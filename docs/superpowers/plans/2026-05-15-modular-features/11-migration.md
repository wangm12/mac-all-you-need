# Phase 11 — Migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the upgrade path from a pre-modular MAYN release to the first modular release seamless. Two coordinated mechanisms ship together: (1) a Sparkle pre-install bash script that copies `yt-dlp` + `ffmpeg` out of the old bundle into `Features/downloader/<NEW_VERSION>/` *before* Sparkle swaps the app, and (2) first-launch migration logic in the new app that reads usage signals out of `AppGroupSettings` + the shared GRDB stores, decides each feature's `(assetState, activationState)`, persists them via `FeatureManager`, and surfaces a one-time "What's new" sheet. Migration runs at most once per user, gated by a `migratedToFeatureModel` sentinel in `AppGroupSettings`. If migration ran, `BootstrapDefaults` (Phase 04) is skipped; if it didn't, `BootstrapDefaults` runs as today and onboarding kicks in for fresh installs.

**Architecture:** A new `MacAllYouNeed/Migration/` group holds three independent units. `PriorUsageDetector` is a pure read-only probe over the existing GRDB stores + `AppGroupSettings` keys, returning `[FeatureID: PriorUsageLevel]`. `Migrator` is an actor-friendly type that owns the decision matrix from spec § 7.2: it consumes the detector's output plus on-disk pack-presence checks (per-file SHA against `FeaturePackManifest`), writes per-feature `FeatureRuntimeState` via `FeatureManager.setState`, marks the sentinel, deletes the `.sparkle-migration-pending` marker, sets `OnboardingState` to `.completed`, and returns a structured `MigrationReport` for the UI. `WhatsNewSheetView` is a SwiftUI sheet shown on first launch only when `report.didRun == true`. `AppController` calls `Migrator.migrateIfNeeded(...)` after `FeatureRuntime` is built but before `BootstrapDefaults.seedIfNeeded(...)`. The Sparkle pre-install script lives at `Resources/Migration/pre-install.sh`, ships as a code-signed resource of the main app bundle, and is wired into Sparkle's installer hook in `MacAllYouNeed/App/SparkleUpdater.swift`.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift actors, `FeatureCore`, GRDB (read-only probes for clipboard + download record counts), `AppGroupSettings`, Sparkle 2 installer-arguments hook, `bash` for the pre-install script, `shasum`/`CryptoKit` for SHA verification.

**Depends on:** Phase 06 (Downloader pack landing under `Features/downloader/<version>/`, `FeaturePackManifest.json` shipped, per-file SHAs available for verification), Phase 09 (Onboarding redesign — `OnboardingState.completed` is the terminal state migration sets to skip the wizard).

---

## File structure

```
MacAllYouNeed/Migration/
├── PriorUsageDetector.swift           ← NEW: read-only probes over DB + AppGroupSettings
├── PriorUsageLevel.swift              ← NEW: enum (.directEvidence | .indirectEvidence | .none)
├── MigrationDecisionMatrix.swift      ← NEW: pure function (usage × asset state) -> FeatureRuntimeState
├── MigrationReport.swift              ← NEW: per-feature outcomes for the What's New sheet
├── Migrator.swift                     ← NEW: orchestrator; sentinel + persistence + sheet trigger
├── WhatsNewSheetView.swift            ← NEW: SwiftUI sheet shown on first launch after upgrade
└── MigrationSentinel.swift            ← NEW: thin wrapper around the AppGroupSettings key

MacAllYouNeed/App/
├── AppController.swift                ← MODIFY bootstrap: insert Migrator before BootstrapDefaults
├── BootstrapDefaults.swift            ← MODIFY: skip if sentinel set (no behavior change otherwise)
├── MainWindowRoot.swift               ← MODIFY: present WhatsNewSheetView when migration just ran
└── SparkleUpdater.swift               ← MODIFY (or create): wire the pre-install script

Resources/Migration/
└── pre-install.sh                     ← NEW: Sparkle pre-install bash script (executable)

project.yml                            ← MODIFY: ship Resources/Migration/ as bundle resources
                                        ;            keep the +x bit on pre-install.sh

MacAllYouNeedTests/Migration/
├── PriorUsageDetectorTests.swift
├── MigrationDecisionMatrixTests.swift
├── MigratorTests.swift
├── MigratorEdgeCasesTests.swift
└── PreInstallScriptTests.swift

MacAllYouNeedTests/Fixtures/Migration/
├── empty-old-bundle/                  ← fake old bundle without binaries
└── full-old-bundle/                   ← fake old bundle with yt-dlp + ffmpeg in Resources/
```

Why a new directory instead of folding into `MacAllYouNeed/App/`: migration is a one-time, version-gated subsystem with its own decision matrix, fixture harness, and Sparkle integration. Keeping it separate from the always-on bootstrap code lets us delete it cleanly two releases from now once we're confident no one is upgrading from a pre-modular version.

---

### Task 1: `PriorUsageLevel` and `MigrationReport` value types

**Files:**
- Create: `MacAllYouNeed/Migration/PriorUsageLevel.swift`
- Create: `MacAllYouNeed/Migration/MigrationReport.swift`

- [ ] **Step 1: Implement `PriorUsageLevel`**

Create `MacAllYouNeed/Migration/PriorUsageLevel.swift`:
```swift
import FeatureCore
import Foundation

/// How confident we are that the user actively used a feature on the previous (pre-modular) release.
/// Used by `Migrator` to decide whether to enable or disable the feature post-migration.
enum PriorUsageLevel: Equatable {
    /// State exists in the shared DB (clipboard records, download records, etc.) — strongest signal.
    case directEvidence
    /// Settings tab has at least one non-default persisted value.
    case indirectEvidence
    /// No usage signal at all.
    case none
}
```

- [ ] **Step 2: Implement `MigrationReport`**

Create `MacAllYouNeed/Migration/MigrationReport.swift`:
```swift
import FeatureCore
import Foundation

/// Surface returned by `Migrator.migrateIfNeeded(...)` and consumed by the What's New sheet.
struct MigrationReport: Equatable {
    /// `true` if the migration actually executed in this call (sentinel was unset on entry).
    /// `false` if the sentinel was already set — caller should skip the What's New sheet entirely.
    let didRun: Bool
    /// Per-feature outcome. Empty when `didRun == false`.
    let outcomes: [FeatureID: Outcome]

    struct Outcome: Equatable {
        let resultingState: FeatureRuntimeState
        let assetSource: AssetSource
        let priorUsage: PriorUsageLevel
    }

    enum AssetSource: Equatable {
        /// Pre-install script copied binaries from the old bundle and SHAs match.
        case preInstallScript
        /// Pre-install script copied binaries but per-file SHA didn't match the new manifest.
        /// User will see "Update Downloader" in the What's New sheet.
        case versionMismatch
        /// Feature is Swift-only (no asset pack).
        case notRequired
        /// No binaries on disk; user will see "Install" in the What's New sheet.
        case needsDownload
    }

    static let noop = MigrationReport(didRun: false, outcomes: [:])
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && \
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Migration/PriorUsageLevel.swift MacAllYouNeed/Migration/MigrationReport.swift
git commit -m "feat(modular-features): add PriorUsageLevel and MigrationReport value types"
```

---

### Task 2: `MigrationSentinel` wrapper

**Files:**
- Create: `MacAllYouNeed/Migration/MigrationSentinel.swift`
- Create: `MacAllYouNeedTests/Migration/MigrationSentinelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Migration/MigrationSentinelTests.swift`:
```swift
import XCTest
@testable import MacAllYouNeed

final class MigrationSentinelTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "MigrationSentinelTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsToFalse() {
        XCTAssertFalse(MigrationSentinel.hasMigrated(defaults: defaults))
    }

    func testRoundTrip() {
        MigrationSentinel.markMigrated(defaults: defaults)
        XCTAssertTrue(MigrationSentinel.hasMigrated(defaults: defaults))
    }

    func testKeyIsStable() {
        XCTAssertEqual(MigrationSentinel.key, "migratedToFeatureModel")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/MigrationSentinelTests | tail -15
```
Expected: FAIL ("type 'MigrationSentinel' not in scope").

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Migration/MigrationSentinel.swift`:
```swift
import Core
import Foundation

/// Single source of truth for the "migration ran already" flag. Persists across upgrades.
enum MigrationSentinel {
    static let key = "migratedToFeatureModel"

    static func hasMigrated(defaults: UserDefaults = AppGroupSettings.defaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func markMigrated(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(true, forKey: key)
    }

    /// Test-only / Advanced "Reset all features…" support.
    static func clear(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigrationSentinelTests | tail -15
```
Expected: PASS, 3/3.

```bash
git add MacAllYouNeed/Migration/MigrationSentinel.swift MacAllYouNeedTests/Migration/MigrationSentinelTests.swift
git commit -m "feat(modular-features): add MigrationSentinel for one-time migration gating"
```

---

### Task 3: `PriorUsageDetector` — table-driven probes

**Files:**
- Create: `MacAllYouNeed/Migration/PriorUsageDetector.swift`
- Create: `MacAllYouNeedTests/Migration/PriorUsageDetectorTests.swift`

The detector reads four signals — clipboard records, download records, voice settings, folder-preview settings — without ever opening write transactions or holding state. Each signal can throw; a thrown signal is treated as "unreadable DB" and bubbled up so the caller (Edge case in Task 7) can fall back to "all enabled."

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Migration/PriorUsageDetectorTests.swift`:
```swift
import XCTest
import Core
import FeatureCore
@testable import MacAllYouNeed

final class PriorUsageDetectorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PriorUsageDetectorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNoEvidenceReturnsAllNone() throws {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.clipboard], .none)
        XCTAssertEqual(result[.downloader], .none)
        XCTAssertEqual(result[.voice], .none)
        XCTAssertEqual(result[.folderPreview], .none)
    }

    func testClipboardRecordsAreDirectEvidence() throws {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 12 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.clipboard], .directEvidence)
    }

    func testDownloadRecordsAreDirectEvidence() throws {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 3 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.downloader], .directEvidence)
    }

    func testFolderPreviewRecentInvocationIsDirectEvidence() throws {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { Date() }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.folderPreview], .directEvidence)
    }

    func testVoiceSettingsConfiguredIsDirectEvidence() throws {
        // Voice "configured" = VoiceASRSettings persisted with any non-default value
        let nonDefault = VoiceASRSettings(
            modelID: .qwen3ASR06BInt8,    // not the default .qwen3ASR06BF32
            languageHint: .automatic,
            providerKind: .local
        )
        VoiceASRSettingsStore.save(nonDefault, to: defaults)

        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.voice], .directEvidence)
    }

    func testIndirectEvidenceFromNonDefaultClipboardSetting() throws {
        // Clipboard's indirect signal: non-default `clipboardMaxItems`
        defaults.set(5_000, forKey: "clipboardMaxItems")     // default is 10_000
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.clipboard], .indirectEvidence)
    }

    func testIndirectEvidenceFromNonDefaultFolderPreviewSetting() throws {
        defaults.set(true, forKey: "folderPreviewIncludeHidden")   // default false
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 0 },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.folderPreview], .indirectEvidence)
    }

    func testDirectBeatsIndirect() throws {
        defaults.set(5_000, forKey: "clipboardMaxItems")          // would be indirect
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { 100 },                        // direct wins
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        let result = try detector.detect()
        XCTAssertEqual(result[.clipboard], .directEvidence)
    }

    func testCorruptedDBPropagatesError() {
        struct Boom: Error {}
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { throw Boom() },
            downloadRecordCount: { 0 },
            folderPreviewLastInvoked: { nil }
        )
        XCTAssertThrowsError(try detector.detect())
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/PriorUsageDetectorTests | tail -15
```
Expected: FAIL ("type 'PriorUsageDetector' not in scope").

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Migration/PriorUsageDetector.swift`:
```swift
import Core
import FeatureCore
import Foundation

/// Read-only probe over `AppGroupSettings` + the shared GRDB stores. Returns the strongest
/// usage signal we can find for each feature. Closures injected so tests can drive the matrix
/// without touching real DB files.
struct PriorUsageDetector {
    typealias CountProvider = () throws -> Int
    typealias DateProvider = () -> Date?

    let defaults: UserDefaults
    let clipboardRecordCount: CountProvider
    let downloadRecordCount: CountProvider
    let folderPreviewLastInvoked: DateProvider

    init(
        defaults: UserDefaults = AppGroupSettings.defaults,
        clipboardRecordCount: @escaping CountProvider,
        downloadRecordCount: @escaping CountProvider,
        folderPreviewLastInvoked: @escaping DateProvider = {
            let raw = AppGroupSettings.defaults.object(forKey: PriorUsageDetector.folderPreviewLastInvokedKey) as? Date
            return raw
        }
    ) {
        self.defaults = defaults
        self.clipboardRecordCount = clipboardRecordCount
        self.downloadRecordCount = downloadRecordCount
        self.folderPreviewLastInvoked = folderPreviewLastInvoked
    }

    /// Persisted by FolderPreview extension on each preview render. May be nil for older
    /// installs that pre-date the marker; in that case we fall back to indirect signals.
    static let folderPreviewLastInvokedKey = "folderPreview.lastInvokedAt"

    func detect() throws -> [FeatureID: PriorUsageLevel] {
        var result: [FeatureID: PriorUsageLevel] = [:]
        result[.clipboard] = try detectClipboard()
        result[.downloader] = try detectDownloader()
        result[.voice] = detectVoice()
        result[.folderPreview] = detectFolderPreview()
        return result
    }

    // MARK: Per-feature probes

    private func detectClipboard() throws -> PriorUsageLevel {
        if try clipboardRecordCount() > 0 { return .directEvidence }
        // Indirect: any non-default clipboard setting
        let defaultMaxItems = 10_000
        if defaults.object(forKey: "clipboardMaxItems") != nil,
           defaults.integer(forKey: "clipboardMaxItems") != defaultMaxItems {
            return .indirectEvidence
        }
        if defaults.object(forKey: "capture.sound") != nil { return .indirectEvidence }
        if defaults.object(forKey: "autoPaste.behavior") != nil { return .indirectEvidence }
        if defaults.object(forKey: "autoPaste.delayMs") != nil { return .indirectEvidence }
        return .none
    }

    private func detectDownloader() throws -> PriorUsageLevel {
        if try downloadRecordCount() > 0 { return .directEvidence }
        // Indirect: any non-default Downloads setting
        if defaults.object(forKey: "downloads.outputTemplate") != nil { return .indirectEvidence }
        if defaults.object(forKey: "downloads.outputDirectory") != nil { return .indirectEvidence }
        if defaults.object(forKey: "downloads.format") != nil { return .indirectEvidence }
        return .none
    }

    private func detectVoice() -> PriorUsageLevel {
        // Direct: VoiceASRSettings persisted at all (the store writes only when user changes
        // anything; default is in-memory only).
        if defaults.data(forKey: VoiceASRSettingsStore.key) != nil { return .directEvidence }
        // Indirect: any voice-related setting persisted
        if defaults.object(forKey: "voice.activation.hotkey") != nil { return .indirectEvidence }
        if defaults.object(forKey: "voice.groq.apiKey.present") != nil { return .indirectEvidence }
        return .none
    }

    private func detectFolderPreview() -> PriorUsageLevel {
        if let last = folderPreviewLastInvoked(), last.timeIntervalSinceNow > -60 * 60 * 24 * 90 {
            return .directEvidence    // invoked at least once in the last 90 days
        }
        // Indirect: non-default settings
        if defaults.object(forKey: "folderPreviewIncludeHidden") != nil,
           defaults.bool(forKey: "folderPreviewIncludeHidden") {
            return .indirectEvidence
        }
        if defaults.object(forKey: "folderPreviewMaxEntries") != nil,
           defaults.integer(forKey: "folderPreviewMaxEntries") != 50_000 {
            return .indirectEvidence
        }
        return .none
    }
}
```

> Note: the indirect-evidence keys above must match the actual `@AppStorage` keys used by `ClipboardSettingsView`, `DownloadsSettingsView`, `FolderPreviewSettingsView`, and `VoiceSettingsView`. If those views move or rename a key after this phase, update the detector in lockstep — there is no compiler-enforced linkage.

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/PriorUsageDetectorTests | tail -15
```
Expected: PASS, 9/9.

```bash
git add MacAllYouNeed/Migration/PriorUsageDetector.swift MacAllYouNeedTests/Migration/PriorUsageDetectorTests.swift
git commit -m "feat(modular-features): add PriorUsageDetector for upgrade-time usage probing"
```

---

### Task 4: `MigrationDecisionMatrix` — pure decision function

**Files:**
- Create: `MacAllYouNeed/Migration/MigrationDecisionMatrix.swift`
- Create: `MacAllYouNeedTests/Migration/MigrationDecisionMatrixTests.swift`

The matrix is intentionally a pure function so the entire spec § 7.2 table can be exercised by table-driven unit tests without spinning up `Migrator`, `FeatureManager`, or any disk state.

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Migration/MigrationDecisionMatrixTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class MigrationDecisionMatrixTests: XCTestCase {
    // MARK: Swift-only features

    func testSwiftOnlyEnabledWhenDirectEvidence() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .clipboard,
            requiresAsset: false,
            assetPresence: .swiftOnly,
            priorUsage: .directEvidence
        )
        XCTAssertEqual(outcome.resultingState, .init(assetState: .notRequired, activationState: .enabled))
        XCTAssertEqual(outcome.assetSource, .notRequired)
    }

    func testSwiftOnlyEnabledWhenIndirectEvidence() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .folderPreview,
            requiresAsset: false,
            assetPresence: .swiftOnly,
            priorUsage: .indirectEvidence
        )
        XCTAssertEqual(outcome.resultingState.activationState, .enabled)
    }

    func testSwiftOnlyDisabledWhenNoEvidence() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .voice,
            requiresAsset: false,
            assetPresence: .swiftOnly,
            priorUsage: .none
        )
        XCTAssertEqual(outcome.resultingState, .init(assetState: .notRequired, activationState: .disabled))
    }

    // MARK: Downloader (asset pack)

    func testDownloaderPresentWithEvidenceEnabled() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .downloader,
            requiresAsset: true,
            assetPresence: .presentMatchingSHA(version: "1.0.0"),
            priorUsage: .directEvidence
        )
        XCTAssertEqual(outcome.resultingState,
                       .init(assetState: .present(version: "1.0.0"), activationState: .enabled))
        XCTAssertEqual(outcome.assetSource, .preInstallScript)
    }

    func testDownloaderPresentWithoutEvidenceDisabled() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .downloader,
            requiresAsset: true,
            assetPresence: .presentMatchingSHA(version: "1.0.0"),
            priorUsage: .none
        )
        XCTAssertEqual(outcome.resultingState,
                       .init(assetState: .present(version: "1.0.0"), activationState: .disabled))
        XCTAssertEqual(outcome.assetSource, .preInstallScript)
    }

    func testDownloaderShaMismatchSurfacesAsDownloadFailed() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .downloader,
            requiresAsset: true,
            assetPresence: .shaMismatch(reason: "yt-dlp SHA differs from manifest"),
            priorUsage: .directEvidence
        )
        guard case let .downloadFailed(reason) = outcome.resultingState.assetState else {
            return XCTFail("expected .downloadFailed, got \(outcome.resultingState.assetState)")
        }
        XCTAssertTrue(reason.contains("version mismatch") || reason.contains("SHA differs"))
        XCTAssertEqual(outcome.resultingState.activationState, .disabled,
                       "must not enable when asset is broken")
        XCTAssertEqual(outcome.assetSource, .versionMismatch)
    }

    func testDownloaderAbsentWithEvidenceDisabledNeedsDownload() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .downloader,
            requiresAsset: true,
            assetPresence: .absent,
            priorUsage: .directEvidence
        )
        XCTAssertEqual(outcome.resultingState,
                       .init(assetState: .notDownloaded, activationState: .disabled))
        XCTAssertEqual(outcome.assetSource, .needsDownload)
    }

    func testDownloaderAbsentWithoutEvidenceDisabled() {
        let outcome = MigrationDecisionMatrix.decide(
            feature: .downloader,
            requiresAsset: true,
            assetPresence: .absent,
            priorUsage: .none
        )
        XCTAssertEqual(outcome.resultingState,
                       .init(assetState: .notDownloaded, activationState: .disabled))
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigrationDecisionMatrixTests | tail -15
```
Expected: FAIL ("type 'MigrationDecisionMatrix' not in scope").

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Migration/MigrationDecisionMatrix.swift`:
```swift
import FeatureCore
import Foundation

/// Pure decision function: turns (usage signal × asset presence) into a `(FeatureRuntimeState, AssetSource)`
/// pair. Spec § 7.2.
enum MigrationDecisionMatrix {
    enum AssetPresence: Equatable {
        /// Feature has no asset pack at all.
        case swiftOnly
        /// Pack files on disk, all per-file SHAs matched the manifest.
        case presentMatchingSHA(version: String)
        /// Pack files on disk but at least one per-file SHA failed to match.
        case shaMismatch(reason: String)
        /// No pack files on disk for this feature's expected version directory.
        case absent
    }

    static func decide(
        feature: FeatureID,
        requiresAsset: Bool,
        assetPresence: AssetPresence,
        priorUsage: PriorUsageLevel
    ) -> MigrationReport.Outcome {
        let activation: ActivationState = (priorUsage == .none) ? .disabled : .enabled

        if !requiresAsset {
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notRequired, activationState: activation),
                assetSource: .notRequired,
                priorUsage: priorUsage
            )
        }

        switch assetPresence {
        case .swiftOnly:
            // Defensive: requiresAsset && swiftOnly is contradictory; treat as Swift-only.
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notRequired, activationState: activation),
                assetSource: .notRequired,
                priorUsage: priorUsage
            )
        case .presentMatchingSHA(let version):
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .present(version: version), activationState: activation),
                assetSource: .preInstallScript,
                priorUsage: priorUsage
            )
        case .shaMismatch(let reason):
            return MigrationReport.Outcome(
                resultingState: .init(
                    assetState: .downloadFailed(reason: "version mismatch — \(reason)"),
                    activationState: .disabled            // never enable a broken asset
                ),
                assetSource: .versionMismatch,
                priorUsage: priorUsage
            )
        case .absent:
            return MigrationReport.Outcome(
                resultingState: .init(assetState: .notDownloaded, activationState: .disabled),
                assetSource: .needsDownload,
                priorUsage: priorUsage
            )
        }
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigrationDecisionMatrixTests | tail -15
```
Expected: PASS, 8/8.

```bash
git add MacAllYouNeed/Migration/MigrationDecisionMatrix.swift MacAllYouNeedTests/Migration/MigrationDecisionMatrixTests.swift
git commit -m "feat(modular-features): add MigrationDecisionMatrix (pure decision function)"
```

---

### Task 5: `Migrator` orchestrator

**Files:**
- Create: `MacAllYouNeed/Migration/Migrator.swift`
- Create: `MacAllYouNeedTests/Migration/MigratorTests.swift`

`Migrator` ties the detector + decision matrix + `FeatureManager` together, plus the on-disk asset-presence probe (per-file SHA against the wrapper manifest). It's the only piece in this phase that touches disk for SHA verification; the rest is pure or test-injectable.

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Migration/MigratorTests.swift`:
```swift
import XCTest
import Core
import FeatureCore
@testable import MacAllYouNeed

final class MigratorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        suiteName = "MigratorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigratorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func makeRuntime() async -> FeatureRuntime {
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        return FeatureRuntime(registry: registry, manager: manager)
    }

    func testReturnsNoopWhenSentinelAlreadySet() async throws {
        MigrationSentinel.markMigrated(defaults: defaults)
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 100 },           // would be direct evidence
                downloadRecordCount: { 50 },
                folderPreviewLastInvoked: { Date() }
            ),
            assetProbe: { _, _ in .absent }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertFalse(report.didRun)
        XCTAssertTrue(report.outcomes.isEmpty)
    }

    func testFirstRunSetsSentinel() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertTrue(report.didRun)
        XCTAssertTrue(MigrationSentinel.hasMigrated(defaults: defaults))
    }

    func testWritesPerFeatureStateThroughManager() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 5 },              // clipboard direct
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }              // downloader absent
        )
        _ = try await migrator.migrateIfNeeded(featureRuntime: runtime)

        let manager = await runtime.manager
        let clip = await manager.state(for: .clipboard)
        let dl = await manager.state(for: .downloader)
        XCTAssertEqual(clip.activationState, .enabled, "clipboard had records")
        XCTAssertEqual(dl, .init(assetState: .notDownloaded, activationState: .disabled))
    }

    func testSetsOnboardingStateToCompleted() async throws {
        OnboardingState.notStarted.save()
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }
        )
        _ = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertEqual(OnboardingState.load(), .completed)
    }

    func testDeletesSparkleMigrationPendingMarker() async throws {
        let featuresDir = tmpDir.appendingPathComponent("Features", isDirectory: true)
        try FileManager.default.createDirectory(at: featuresDir, withIntermediateDirectories: true)
        let marker = featuresDir.appendingPathComponent(".sparkle-migration-pending")
        try Data().write(to: marker)

        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent },
            featuresBaseDir: featuresDir
        )
        _ = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testReportContainsOutcomePerRegistryFeature() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertEqual(Set(report.outcomes.keys),
                       Set([.clipboard, .folderPreview, .downloader, .voice]))
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigratorTests | tail -15
```
Expected: FAIL ("type 'Migrator' not in scope").

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Migration/Migrator.swift`:
```swift
import Core
import CryptoKit
import FeatureCore
import Foundation

/// One-time upgrade orchestrator. Idempotent via `MigrationSentinel`.
struct Migrator {
    typealias AssetProbe = (FeatureID, FeatureDescriptor) throws -> MigrationDecisionMatrix.AssetPresence

    let defaults: UserDefaults
    let detector: PriorUsageDetector
    let assetProbe: AssetProbe
    let featuresBaseDir: URL
    let manifestProvider: () throws -> FeaturePackManifest?

    init(
        defaults: UserDefaults = AppGroupSettings.defaults,
        detector: PriorUsageDetector,
        assetProbe: AssetProbe? = nil,
        featuresBaseDir: URL = AppGroup.containerURL().appendingPathComponent("Features", isDirectory: true),
        manifestProvider: (() throws -> FeaturePackManifest?)? = nil
    ) {
        self.defaults = defaults
        self.detector = detector
        self.featuresBaseDir = featuresBaseDir
        self.manifestProvider = manifestProvider ?? Migrator.bundledManifestProvider
        self.assetProbe = assetProbe ?? { id, descriptor in
            try Migrator.probeOnDisk(
                featureID: id,
                descriptor: descriptor,
                featuresBaseDir: featuresBaseDir,
                manifest: try (manifestProvider ?? Migrator.bundledManifestProvider)()
            )
        }
    }

    /// Entry point. Returns immediately with `.noop` if the sentinel is already set.
    func migrateIfNeeded(featureRuntime: FeatureRuntime) async throws -> MigrationReport {
        if MigrationSentinel.hasMigrated(defaults: defaults) {
            return .noop
        }

        let usage = try detector.detect()
        let registry = await featureRuntime.registry
        let manager = await featureRuntime.manager
        var outcomes: [FeatureID: MigrationReport.Outcome] = [:]

        for descriptor in registry.descriptors {
            let presence = descriptor.requiresAsset
                ? (try assetProbe(descriptor.id, descriptor))
                : .swiftOnly
            let outcome = MigrationDecisionMatrix.decide(
                feature: descriptor.id,
                requiresAsset: descriptor.requiresAsset,
                assetPresence: presence,
                priorUsage: usage[descriptor.id] ?? .none
            )
            try await manager.setState(outcome.resultingState, for: descriptor.id)
            outcomes[descriptor.id] = outcome
        }

        // Skip onboarding for upgraders
        OnboardingState.completed.save()

        // Drop the Sparkle marker (if any). Best-effort.
        let marker = featuresBaseDir.appendingPathComponent(".sparkle-migration-pending")
        try? FileManager.default.removeItem(at: marker)

        MigrationSentinel.markMigrated(defaults: defaults)
        return MigrationReport(didRun: true, outcomes: outcomes)
    }

    // MARK: On-disk probing

    /// Looks up the wrapper-bundled `FeaturePackManifest.json`. Returns nil if it can't be
    /// loaded (e.g., test harness without the resource); callers treat that as `.absent`.
    static func bundledManifestProvider() throws -> FeaturePackManifest? {
        guard let url = Bundle.main.url(forResource: "FeaturePackManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try FeaturePackManifest.decode(from: data, expectedSchemaVersion: 1)
    }

    /// Concrete probe used in production: walks `Features/<id>/<currentVersion>/`, hashes each
    /// listed file, and compares to the manifest. Mismatch surfaces a specific reason string
    /// suitable for the What's New sheet.
    static func probeOnDisk(
        featureID: FeatureID,
        descriptor: FeatureDescriptor,
        featuresBaseDir: URL,
        manifest: FeaturePackManifest?
    ) throws -> MigrationDecisionMatrix.AssetPresence {
        guard let pack = descriptor.assetPacks.first,
              let manifest,
              let manifestEntry = manifest.packs[pack.bundledManifestKey]
        else { return .absent }

        let versionDir = featuresBaseDir
            .appendingPathComponent(featureID.rawValue, isDirectory: true)
            .appendingPathComponent(manifestEntry.version, isDirectory: true)

        let fm = FileManager.default
        guard fm.fileExists(atPath: versionDir.path) else { return .absent }

        for (filename, expected) in manifestEntry.files {
            let fileURL = versionDir.appendingPathComponent(filename)
            guard fm.fileExists(atPath: fileURL.path) else {
                return .shaMismatch(reason: "missing \(filename)")
            }
            let actual = try sha256Hex(of: fileURL)
            if actual.lowercased() != expected.sha256.lowercased() {
                return .shaMismatch(reason: "\(filename) SHA differs from manifest")
            }
        }
        return .presentMatchingSHA(version: manifestEntry.version)
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.availableData
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigratorTests | tail -15
```
Expected: PASS, 6/6.

```bash
git add MacAllYouNeed/Migration/Migrator.swift MacAllYouNeedTests/Migration/MigratorTests.swift
git commit -m "feat(modular-features): add Migrator orchestrator (sentinel + per-feature decisions)"
```

---

### Task 6: Wire `PriorUsageDetector` to real `ClipboardStore` / `DownloadStore` counts

**Files:**
- Modify: `MacAllYouNeed/Migration/Migrator.swift` (add a `production` factory)

The unit tests inject closures; in production we need a single helper that constructs the detector with real DB-backed count probes. Keep this thin — the actual stores are already retained on `AppController`.

- [ ] **Step 1: Extend Migrator with a production factory**

Append to `MacAllYouNeed/Migration/Migrator.swift`:
```swift
extension Migrator {
    /// Constructs a Migrator wired to the live ClipboardStore + DownloadStore. Used by
    /// `AppController.bootstrap`. Counts are read inside the closure each call so the DB
    /// handle isn't captured indefinitely.
    static func makeProduction(
        clipboardStore: ClipboardStore,
        downloadStore: DownloadStore,
        defaults: UserDefaults = AppGroupSettings.defaults
    ) -> Migrator {
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { try clipboardStore.recentRecordCount(limit: 1) },
            downloadRecordCount: { try downloadStore.list().count },
            folderPreviewLastInvoked: {
                defaults.object(forKey: PriorUsageDetector.folderPreviewLastInvokedKey) as? Date
            }
        )
        return Migrator(defaults: defaults, detector: detector)
    }
}
```

> If `ClipboardStore` doesn't already expose `recentRecordCount(limit:)`, add a one-liner:
> ```swift
> public func recentRecordCount(limit: Int) throws -> Int {
>     try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM (SELECT id FROM records LIMIT ?)", arguments: [limit]) ?? 0 }
> }
> ```
> The `LIMIT` clause keeps the probe O(1) even on huge tables — we only need to know "≥ 1?" not the exact count.

- [ ] **Step 2: Verify it compiles**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/Migration/Migrator.swift Shared/Sources/Core/Storage/ClipboardStore.swift
git commit -m "feat(modular-features): add Migrator.makeProduction factory wired to live stores"
```

---

### Task 7: Edge-case tests

**Files:**
- Create: `MacAllYouNeedTests/Migration/MigratorEdgeCasesTests.swift`

Cover the four edge cases called out in spec § 7.2 + § 12 Risk 8.

- [ ] **Step 1: Write the tests**

Create `MacAllYouNeedTests/Migration/MigratorEdgeCasesTests.swift`:
```swift
import XCTest
import Core
import FeatureCore
@testable import MacAllYouNeed

final class MigratorEdgeCasesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MigratorEdgeCases-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRuntime() async -> FeatureRuntime {
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        return FeatureRuntime(registry: registry, manager: manager)
    }

    /// Edge: corrupted detection state (e.g., DB file unreadable). Migrator must NOT silently
    /// disable everything — it falls back to "all features enabled" so we don't break workflows.
    func testCorruptedDBFallsBackToAllEnabled() async throws {
        struct DBOpenFailure: Error {}
        let detector = PriorUsageDetector(
            defaults: defaults,
            clipboardRecordCount: { throw DBOpenFailure() },
            downloadRecordCount: { throw DBOpenFailure() },
            folderPreviewLastInvoked: { nil }
        )
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: detector,
            assetProbe: { _, _ in .absent }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)

        XCTAssertTrue(report.didRun)
        let manager = await runtime.manager
        // Swift-only features get .enabled; downloader stays .notDownloaded/.disabled because
        // we can't unilaterally enable a feature whose binaries are missing.
        XCTAssertEqual(await manager.state(for: .clipboard).activationState, .enabled)
        XCTAssertEqual(await manager.state(for: .voice).activationState, .enabled)
        XCTAssertEqual(await manager.state(for: .folderPreview).activationState, .enabled)
        XCTAssertEqual(await manager.state(for: .downloader).activationState, .disabled)
    }

    /// Edge: downgrade then re-upgrade — sentinel persists across the downgrade because
    /// we never clear it on successful migration completion.
    func testRunsAtMostOncePerUser() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }
        )

        let first = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertTrue(first.didRun)

        // Simulate user disabling clipboard, then app re-launching (or being downgraded
        // and re-upgraded). Migration must not run again and must not undo the user's choice.
        let manager = await runtime.manager
        try await manager.transition(.disable, for: .clipboard)

        let second = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertFalse(second.didRun, "sentinel must prevent re-migration")
        XCTAssertEqual(await manager.state(for: .clipboard).activationState, .disabled)
    }

    /// Edge: fresh install where Application Support was wiped — no DB, no sentinel either.
    /// In production, BootstrapDefaults runs (since our sentinel isn't set) and onboarding
    /// kicks in for the truly-empty state. Here we just confirm the migrator does run, and
    /// produces a `.disabled` outcome for everything (no usage signals at all).
    func testFreshInstallNoUsageSignals() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 0 },
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in .absent }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        XCTAssertTrue(report.didRun)
        for outcome in report.outcomes.values {
            XCTAssertEqual(outcome.resultingState.activationState, .disabled,
                           "no signals == nothing enabled")
        }
    }

    /// Edge: Sparkle script wrote binaries for v1.0.0, but the new wrapper's manifest pins
    /// v1.0.1 — per-file SHAs won't match, so migration demotes to .downloadFailed.
    func testVersionMismatchDemotesToDownloadFailed() async throws {
        let runtime = await makeRuntime()
        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 0 },
                downloadRecordCount: { 5 },                  // user actively used downloader
                folderPreviewLastInvoked: { nil }
            ),
            assetProbe: { _, _ in
                .shaMismatch(reason: "yt-dlp from old bundle is v2025.10.03; manifest expects v2026.04.01")
            }
        )
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)
        guard let dl = report.outcomes[.downloader] else {
            return XCTFail("expected downloader outcome")
        }
        guard case let .downloadFailed(reason) = dl.resultingState.assetState else {
            return XCTFail("expected .downloadFailed, got \(dl.resultingState.assetState)")
        }
        XCTAssertTrue(reason.contains("version mismatch"))
        XCTAssertEqual(dl.resultingState.activationState, .disabled)
        XCTAssertEqual(dl.assetSource, .versionMismatch)
    }
}
```

- [ ] **Step 2: Run + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigratorEdgeCasesTests | tail -15
```
Expected: PASS, 4/4.

```bash
git add MacAllYouNeedTests/Migration/MigratorEdgeCasesTests.swift
git commit -m "test(modular-features): add Migrator edge-case coverage (corruption, re-upgrade, fresh install, version mismatch)"
```

> The "corrupted DB falls back to all enabled" behavior is implemented via the per-feature usage probes — when `clipboardRecordCount()` throws, the detector propagates. To match the spec § 7.2 "assume all four enabled" rule, the `Migrator` itself catches `detector.detect()` errors:
>
> Edit `MacAllYouNeed/Migration/Migrator.swift`'s `migrateIfNeeded` to wrap the detect call:
> ```swift
> let usage: [FeatureID: PriorUsageLevel]
> do {
>     usage = try detector.detect()
> } catch {
>     NSLog("Migrator: detection failed (\(error)); falling back to all-enabled per spec § 7.2")
>     usage = Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, .directEvidence) })
> }
> ```
> Re-run `MigratorEdgeCasesTests/testCorruptedDBFallsBackToAllEnabled` to confirm it now passes.

---

### Task 8: `WhatsNewSheetView`

**Files:**
- Create: `MacAllYouNeed/Migration/WhatsNewSheetView.swift`
- Create: `MacAllYouNeedTests/Migration/WhatsNewSheetViewTests.swift`

The sheet renders the `MigrationReport` produced in Task 5. UI rules: use `MAYNTheme`, `MAYNButton`, `MAYNSection`, and `StatusPill` per `MacAllYouNeed/CLAUDE.md`. Single primary "Open Features Settings" action, single secondary "Dismiss" action.

- [ ] **Step 1: Implement the view**

Create `MacAllYouNeed/Migration/WhatsNewSheetView.swift`:
```swift
import FeatureCore
import SwiftUI

/// Shown once after a pre-modular → modular upgrade, courtesy of `Migrator`.
/// Lists each feature's outcome and routes the user to Settings → Features.
struct WhatsNewSheetView: View {
    let report: MigrationReport
    let registry: FeatureRegistry
    let onDismiss: () -> Void
    let onOpenFeaturesSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mac All You Need is now modular")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("You can pick which features to use. Nothing was disabled — you can change anything in Settings → Features.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(orderedOutcomes(), id: \.0) { (id, outcome) in
                    if let descriptor = registry.descriptor(for: id) {
                        FeatureOutcomeRow(descriptor: descriptor, outcome: outcome)
                    }
                }
            }

            HStack {
                Spacer()
                MAYNButton.secondary(title: "Dismiss", action: onDismiss)
                MAYNButton.primary(title: "Open Features Settings", action: {
                    onOpenFeaturesSettings()
                    onDismiss()
                })
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 520)
    }

    private func orderedOutcomes() -> [(FeatureID, MigrationReport.Outcome)] {
        // Render in registry order so the same feature is always in the same place.
        registry.descriptors.compactMap { d in
            guard let outcome = report.outcomes[d.id] else { return nil }
            return (d.id, outcome)
        }
    }
}

private struct FeatureOutcomeRow: View {
    let descriptor: FeatureDescriptor
    let outcome: MigrationReport.Outcome

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: descriptor.icon)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName).font(.body)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: badgeText, kind: badgeKind)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(MAYNTheme.surfaceSubtle)
        .cornerRadius(8)
    }

    private var statusText: String {
        switch outcome.assetSource {
        case .preInstallScript:
            return "Kept active — your binaries were carried over from the old version."
        case .versionMismatch:
            return "Needs an update — the binaries from the old version don't match this release."
        case .needsDownload:
            return outcome.resultingState.activationState == .enabled
                ? "Active but needs binaries — install when convenient."
                : "Available — install if you want it back."
        case .notRequired:
            return outcome.resultingState.activationState == .enabled
                ? "Kept active."
                : "Available — enable in Settings → Features."
        }
    }

    private var badgeText: String {
        switch (outcome.assetSource, outcome.resultingState.activationState) {
        case (.versionMismatch, _): return "Update needed"
        case (.needsDownload, _):    return "Install"
        case (_, .enabled):          return "Enabled"
        case (_, .disabled):         return "Disabled"
        }
    }

    private var badgeKind: StatusPill.Kind {
        switch (outcome.assetSource, outcome.resultingState.activationState) {
        case (.versionMismatch, _): return .warning
        case (.needsDownload, _):    return .neutral
        case (_, .enabled):          return .success
        case (_, .disabled):         return .neutral
        }
    }
}
```

> If `MAYNButton.primary` / `.secondary` don't accept a trailing-closure shape exactly like above, adapt to the actual signatures in `Settings/MAYNSettingsUI.swift`. The constraint is "use the design-system primitives" — not the exact call shape.

- [ ] **Step 2: Smoke-test view rendering**

Create `MacAllYouNeedTests/Migration/WhatsNewSheetViewTests.swift`:
```swift
import XCTest
import SwiftUI
import FeatureCore
@testable import MacAllYouNeed

final class WhatsNewSheetViewTests: XCTestCase {
    func testRendersOneRowPerOutcome() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let outcomes: [FeatureID: MigrationReport.Outcome] = [
            .clipboard: .init(
                resultingState: .init(assetState: .notRequired, activationState: .enabled),
                assetSource: .notRequired,
                priorUsage: .directEvidence
            ),
            .downloader: .init(
                resultingState: .init(assetState: .present(version: "1.0.0"), activationState: .enabled),
                assetSource: .preInstallScript,
                priorUsage: .directEvidence
            ),
        ]
        let report = MigrationReport(didRun: true, outcomes: outcomes)
        let view = WhatsNewSheetView(report: report, registry: registry, onDismiss: {}, onOpenFeaturesSettings: {})
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.bounds.width, 0)   // smoke: instantiates without crashing
    }
}
```

- [ ] **Step 3: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/WhatsNewSheetViewTests | tail -15
```
Expected: PASS, 1/1.

```bash
git add MacAllYouNeed/Migration/WhatsNewSheetView.swift MacAllYouNeedTests/Migration/WhatsNewSheetViewTests.swift
git commit -m "feat(modular-features): add WhatsNewSheetView for first-launch upgrade messaging"
```

---

### Task 9: Wire `Migrator` into `AppController` bootstrap

**Files:**
- Modify: `MacAllYouNeed/App/AppController.swift`
- Modify: `MacAllYouNeed/App/BootstrapDefaults.swift`
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`

The order of operations on app launch is now:
1. Build `FeatureRuntime`.
2. Run `Migrator.migrateIfNeeded(...)`.
3. If migration ran (`report.didRun == true`): stash the report and present `WhatsNewSheetView` on first window appearance. Skip `BootstrapDefaults`.
4. If migration didn't run (sentinel was already set, OR fresh install): run `BootstrapDefaults.seedIfNeeded(...)` exactly as Phase 04 wired it.
5. `runtime.activateAllEnabled()`.

- [ ] **Step 1: Modify `AppController` bootstrap**

In `AppController.swift`, locate the bootstrap `Task` block (added in Phase 04) and replace with:

```swift
Task { [manager, runtime, weak self] in
    let migrator = Migrator.makeProduction(
        clipboardStore: stores.clipboard,
        downloadStore: stores.downloads,        // verify the actual property name on stores
        defaults: AppGroupSettings.defaults
    )
    let report = (try? await migrator.migrateIfNeeded(featureRuntime: runtime)) ?? .noop

    if !report.didRun {
        // Either the sentinel is already set (subsequent launch) or this is a fresh install
        // where we want the standard first-launch seed + onboarding to kick in.
        try? await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: AppGroupSettings.defaults)
    }
    await runtime.activateAllEnabled()

    // Hand the report to the main window so it can present the sheet on first appearance.
    await MainActor.run { self?.pendingMigrationReport = report.didRun ? report : nil }
}
```

Add a property:
```swift
@MainActor private(set) var pendingMigrationReport: MigrationReport?
```

> If `AppController` is `@Observable`, omit `@MainActor`. Match the existing access patterns; this property must be readable from `MainWindowRoot` without causing a Sendable warning.

- [ ] **Step 2: Modify `BootstrapDefaults` to no-op when migration ran**

In `MacAllYouNeed/App/BootstrapDefaults.swift`, prepend a sentinel check inside `seedIfNeeded`:

```swift
static func seedIfNeeded(manager: FeatureManager, defaults: UserDefaults) async throws {
    if MigrationSentinel.hasMigrated(defaults: defaults) {
        // Migration already populated state; do not overwrite.
        defaults.set(true, forKey: seededKey)
        return
    }
    guard !defaults.bool(forKey: seededKey) else { return }
    // ...existing logic unchanged below this point
}
```

The `defaults.set(true, forKey: seededKey)` line ensures the seeded flag is consistent for any future code that might query it.

- [ ] **Step 3: Present `WhatsNewSheetView` from `MainWindowRoot`**

In `MacAllYouNeed/App/MainWindowRoot.swift`, add:

```swift
@State private var showWhatsNew: Bool = false
@State private var whatsNewReport: MigrationReport? = nil
```

In the body (or whichever container `MainWindowRoot` mounts at startup), append:
```swift
.onAppear {
    if let report = controller.pendingMigrationReport {
        whatsNewReport = report
        showWhatsNew = true
        // Clear so it doesn't reappear on subsequent appearances.
        controller.pendingMigrationReport = nil
    }
}
.sheet(isPresented: $showWhatsNew) {
    if let report = whatsNewReport {
        WhatsNewSheetView(
            report: report,
            registry: controller.runtime.registry,
            onDismiss: { showWhatsNew = false },
            onOpenFeaturesSettings: {
                NSApp.sendAction(Selector(("openFeaturesSettings:")), to: nil, from: nil)
            }
        )
    }
}
```

> The "open Features settings" wiring uses whatever helper Phase 05 introduced; if there's no responder selector, replace with `controller.openSettings(destination: .features)` or the equivalent helper.

- [ ] **Step 4: Build + smoke**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: `BUILD SUCCEEDED`.

Run the app once with the sentinel cleared:
```bash
defaults delete group.com.macallyouneed.shared migratedToFeatureModel 2>/dev/null || true
defaults delete group.com.macallyouneed.shared feature.bootstrap.seeded 2>/dev/null || true
open -a "Mac All You Need.app"
```
Expected: app launches, the What's New sheet appears once, dismissing it does NOT cause it to reappear on the next launch.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/AppController.swift MacAllYouNeed/App/BootstrapDefaults.swift MacAllYouNeed/App/MainWindowRoot.swift
git commit -m "feat(modular-features): wire Migrator and What's New sheet into AppController bootstrap"
```

---

### Task 10: Sparkle pre-install script

**Files:**
- Create: `Resources/Migration/pre-install.sh`
- Modify: `project.yml` (ship `Resources/Migration/` as bundle resources for the main app target)

- [ ] **Step 1: Verify `Resources/` directory layout**

```bash
ls /Users/mingjie.wang/Documents/personal/mac-all-you-need/Resources/ 2>/dev/null || mkdir -p /Users/mingjie.wang/Documents/personal/mac-all-you-need/Resources/Migration
```

- [ ] **Step 2: Write the script**

Create `Resources/Migration/pre-install.sh`:
```bash
#!/bin/bash
# pre-install.sh — runs from inside the NEW MAYN bundle before Sparkle swaps in the new app.
# Best-effort: copies yt-dlp + ffmpeg from the OLD bundle's Resources/ into the App Group's
# Features/downloader/<NEW_VERSION>/ directory so the new (small) wrapper finds them already
# in place — no re-download for upgraders.
#
# Arguments:
#   $1  Path to the currently-installed (OLD) MAYN app bundle.
#   $2  Marketing version of the NEW bundle (e.g. "2.0.0").
#
# Exits 0 unconditionally so a failure here cannot block the Sparkle install. The new app's
# Migrator will see no binaries on disk and fall back to "needs download" via the What's New
# sheet — that's the documented graceful-degradation path (spec § 12 Risk 8).
set -euo pipefail

OLD_APP="${1:-}"
NEW_VERSION="${2:-}"

if [ -z "$OLD_APP" ] || [ -z "$NEW_VERSION" ]; then
    echo "pre-install: missing arguments (OLD_APP=$OLD_APP, NEW_VERSION=$NEW_VERSION); skipping" >&2
    exit 0
fi

APPGROUP_BASE="$HOME/Library/Application Support/MacAllYouNeed"
DST="$APPGROUP_BASE/Features/downloader/$NEW_VERSION"

mkdir -p "$DST" || exit 0
mkdir -p "$APPGROUP_BASE/Features" || exit 0

for bin in yt-dlp ffmpeg; do
    src="$OLD_APP/Contents/Resources/$bin"
    if [ -f "$src" ]; then
        cp -p "$src" "$DST/$bin" || true
        chmod +x "$DST/$bin" 2>/dev/null || true
    fi
done

# Marker tells the new app's Migrator that the script ran (for diagnostics + cleanup).
touch "$APPGROUP_BASE/Features/.sparkle-migration-pending" || true

exit 0
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x /Users/mingjie.wang/Documents/personal/mac-all-you-need/Resources/Migration/pre-install.sh
```

- [ ] **Step 4: Add to `project.yml` so it ships in the bundle**

Read the current `project.yml`:
```bash
grep -n "Resources\|preserveExistingFile\|sources:" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -40
```

In the `MacAllYouNeed` target's `sources:` (or `resources:`) section, add:
```yaml
      - path: Resources/Migration
        type: folder
```

> `type: folder` ensures the directory ships as `MacAllYouNeed.app/Contents/Resources/Migration/pre-install.sh` (preserving the +x bit). If your xcodegen layout uses `buildPhase: resources` explicitly, mirror the existing pattern.

- [ ] **Step 5: Regenerate the project + verify the script lands in the bundle**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
# Find the just-built bundle and confirm the script is there
find ~/Library/Developer/Xcode/DerivedData -name "Mac All You Need.app" -type d -path "*Build/Products*" 2>/dev/null \
  | head -1 | xargs -I {} ls -l "{}/Contents/Resources/Migration/pre-install.sh"
```
Expected: `-rwxr-xr-x ... pre-install.sh`.

- [ ] **Step 6: Commit**

```bash
git add Resources/Migration/pre-install.sh project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): ship Sparkle pre-install script in app bundle"
```

---

### Task 11: Sparkle integration

**Files:**
- Modify (or create): `MacAllYouNeed/App/SparkleUpdater.swift`

Sparkle 2 supports an installer hook via `SPUUpdaterDelegate.installerArguments(for:)` and `SPUUserDriverDelegate`, plus the `SUEnableInstallerLauncherService` Info.plist key for spawning the installer service. The exact wiring depends on what's already in the project (currently nothing — there is no `SparkleUpdater.swift`, since Plan 7 distribution is still pending).

The **shape** of the integration must:
1. Resolve the path to the bundled `pre-install.sh` (`Bundle.main.url(forResource: "pre-install", withExtension: "sh", subdirectory: "Migration")`).
2. Resolve the OLD app's bundle path (Sparkle provides the currently-running bundle path).
3. Resolve the NEW marketing version (Sparkle provides this from the appcast item).
4. Run the script via `Process` with stdout/stderr captured, after the new bundle has been downloaded and verified by Sparkle but before Sparkle swaps it in.
5. Never block the install on a non-zero exit (the script itself exits 0 unconditionally; this is a defense-in-depth guard).

- [ ] **Step 1: Confirm Sparkle 2 is or will be a dependency**

```bash
grep -n "Sparkle" /Users/mingjie.wang/Documents/personal/mac-all-you-need/Package.swift /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Package.swift /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml 2>/dev/null
```

If Sparkle is not yet wired (Plan 7 territory), add a stub TODO file that's a no-op until Plan 7 lands the actual SPM dependency. The migration logic itself is independent of Sparkle — first-launch migration runs whether or not the pre-install script ran.

- [ ] **Step 2: Verify the Sparkle 2 installer-hook API name**

Run (only after Sparkle is added as a dependency):
```bash
find ~/Library/Developer/Xcode/DerivedData -path "*SourcePackages*Sparkle*" -name "*.h" 2>/dev/null \
  | head -5 | xargs grep -l "installerArguments\|preInstall\|InstallationHook" 2>/dev/null
```

Sparkle 2's documented hook is `SPUUpdaterDelegate.installerArguments(for:)` (passes args TO Sparkle's installer) plus the Info.plist key `SUEnableInstallerLauncherService`. For running our own script, the simplest pattern is to invoke the script from a `SPUUpdaterDelegate.updater(_:didDownloadUpdate:)` callback (after download, before install) — the delegate is given the update item, from which we extract `displayVersionString` (= NEW_VERSION) and we already know the OLD app path is `Bundle.main.bundlePath` because we're still running.

If the exact callback name has shifted between Sparkle 2 minor versions, consult `SPUUpdaterDelegate.h` in the resolved package and adapt accordingly. The contract is fixed — *invoke the script with `(oldAppPath, newVersionString)` after download and before install* — only the binding to Sparkle's hook may change.

- [ ] **Step 3: Implement the wiring**

Create `MacAllYouNeed/App/SparkleUpdater.swift`:
```swift
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// Wrapper around Sparkle 2 that runs our pre-install migration script after Sparkle has
/// downloaded and verified the new bundle but before it swaps it in. Best-effort: any failure
/// in the script is swallowed and surfaced via the `Migrator`'s "needs download" fallback path.
final class SparkleUpdater: NSObject {
    static let shared = SparkleUpdater()

    private override init() { super.init() }

    #if canImport(Sparkle)
    private(set) lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()
    #endif

    /// Public for direct invocation from tests (Task 12) and from the Sparkle delegate.
    @discardableResult
    func runPreInstallScript(oldAppPath: String, newVersion: String) -> Int32 {
        guard let scriptURL = Bundle.main.url(forResource: "pre-install", withExtension: "sh", subdirectory: "Migration") else {
            NSLog("SparkleUpdater: pre-install.sh not found in bundle; skipping")
            return -1
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, oldAppPath, newVersion]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            NSLog("SparkleUpdater: pre-install script failed to launch: \(error)")
            return -1
        }
    }
}

#if canImport(Sparkle)
extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let oldPath = Bundle.main.bundlePath
        let newVersion = item.displayVersionString ?? item.versionString
        _ = runPreInstallScript(oldAppPath: oldPath, newVersion: newVersion)
    }
}
#endif
```

- [ ] **Step 4: Initialize in `AppController`**

In `AppController.init` (after the existing setup), reference `SparkleUpdater.shared.controller` so it's instantiated. The Sparkle-2 SPM dependency itself lands in Plan 7; until then the `#if canImport(Sparkle)` guard makes this a no-op.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/SparkleUpdater.swift MacAllYouNeed/App/AppController.swift
git commit -m "feat(modular-features): wire Sparkle pre-install script via SparkleUpdater delegate"
```

---

### Task 12: Pre-install script harness test

**Files:**
- Create: `MacAllYouNeedTests/Migration/PreInstallScriptTests.swift`

Black-box test that runs the script via `bash`, asserts it copies binaries and writes the marker. Doesn't require Sparkle.

- [ ] **Step 1: Write the test**

Create `MacAllYouNeedTests/Migration/PreInstallScriptTests.swift`:
```swift
import XCTest

final class PreInstallScriptTests: XCTestCase {
    private var sandbox: URL!
    private var fakeOldBundle: URL!

    override func setUp() {
        super.setUp()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreInstallScriptTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        // Build a fake old bundle layout with yt-dlp + ffmpeg in Contents/Resources/
        fakeOldBundle = sandbox.appendingPathComponent("OldMAYN.app", isDirectory: true)
        let resources = fakeOldBundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try? "fake yt-dlp body".write(to: resources.appendingPathComponent("yt-dlp"),
                                      atomically: true, encoding: .utf8)
        try? "fake ffmpeg body".write(to: resources.appendingPathComponent("ffmpeg"),
                                      atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sandbox)
        super.tearDown()
    }

    private func runScript(env: [String: String]) -> Int32 {
        let scriptURL = Bundle(for: PreInstallScriptTests.self)
            .url(forResource: "pre-install", withExtension: "sh", subdirectory: "Migration")
            ?? Bundle.main.url(forResource: "pre-install", withExtension: "sh", subdirectory: "Migration")!
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path, fakeOldBundle.path, "9.9.9"]
        task.environment = env
        try! task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }

    func testCopiesBothBinariesAndWritesMarker() throws {
        // Redirect HOME so the script writes inside the sandbox.
        let env = ["HOME": sandbox.path]
        XCTAssertEqual(runScript(env: env), 0)

        let dst = sandbox
            .appendingPathComponent("Library/Application Support/MacAllYouNeed/Features/downloader/9.9.9", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("yt-dlp").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("ffmpeg").path))

        let marker = sandbox
            .appendingPathComponent("Library/Application Support/MacAllYouNeed/Features/.sparkle-migration-pending")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testTolerantOfMissingBinaries() throws {
        // Empty old bundle (no Resources/yt-dlp). Script must still exit 0 + write the marker.
        try FileManager.default.removeItem(at: fakeOldBundle.appendingPathComponent("Contents/Resources/yt-dlp"))
        try FileManager.default.removeItem(at: fakeOldBundle.appendingPathComponent("Contents/Resources/ffmpeg"))
        let env = ["HOME": sandbox.path]
        XCTAssertEqual(runScript(env: env), 0)

        let marker = sandbox
            .appendingPathComponent("Library/Application Support/MacAllYouNeed/Features/.sparkle-migration-pending")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testPreservesExecutableBit() throws {
        let env = ["HOME": sandbox.path]
        _ = runScript(env: env)
        let dst = sandbox
            .appendingPathComponent("Library/Application Support/MacAllYouNeed/Features/downloader/9.9.9/yt-dlp")
        let attrs = try FileManager.default.attributesOfItem(atPath: dst.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        XCTAssertNotEqual(perms & 0o111, 0, "yt-dlp must be executable after the copy")
    }
}
```

- [ ] **Step 2: Run + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/PreInstallScriptTests | tail -15
```
Expected: PASS, 3/3.

```bash
git add MacAllYouNeedTests/Migration/PreInstallScriptTests.swift
git commit -m "test(modular-features): add pre-install script harness tests"
```

---

### Task 13: End-to-end migration integration test

**Files:**
- Create: `MacAllYouNeedTests/Migration/MigratorEndToEndTests.swift`

Simulates a "user upgrading from pre-modular":
1. Write fake legacy state (clipboard records via direct `ClipboardStore.insert`, download records via `DownloadStore.insert`, voice settings via `VoiceASRSettingsStore.save`).
2. Run the pre-install script against a fake old bundle.
3. Construct `Migrator`, run `migrateIfNeeded`.
4. Assert per-feature outcomes match the spec § 7.2 matrix.

- [ ] **Step 1: Write the test**

Create `MacAllYouNeedTests/Migration/MigratorEndToEndTests.swift`:
```swift
import XCTest
import Core
import FeatureCore
@testable import MacAllYouNeed

final class MigratorEndToEndTests: XCTestCase {
    private var sandbox: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigratorE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        suiteName = "MigratorE2E-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sandbox)
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testUpgradeWithClipboardAndDownloaderUsage() async throws {
        // Arrange: simulate prior usage signals
        let nonDefaultVoice = VoiceASRSettings(modelID: .qwen3ASR06BInt8, languageHint: .automatic, providerKind: .local)
        VoiceASRSettingsStore.save(nonDefaultVoice, to: defaults)

        let featuresDir = sandbox.appendingPathComponent("Features", isDirectory: true)
        try FileManager.default.createDirectory(at: featuresDir, withIntermediateDirectories: true)
        // Drop the Sparkle marker as if the script ran
        try Data().write(to: featuresDir.appendingPathComponent(".sparkle-migration-pending"))

        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager)

        let migrator = Migrator(
            defaults: defaults,
            detector: PriorUsageDetector(
                defaults: defaults,
                clipboardRecordCount: { 42 },        // direct evidence
                downloadRecordCount: { 7 },          // direct evidence
                folderPreviewLastInvoked: { nil }    // no folder preview signal
            ),
            assetProbe: { _, _ in .presentMatchingSHA(version: "1.0.0") },
            featuresBaseDir: featuresDir
        )

        // Act
        let report = try await migrator.migrateIfNeeded(featureRuntime: runtime)

        // Assert
        XCTAssertTrue(report.didRun)
        XCTAssertEqual(report.outcomes[.clipboard]?.resultingState.activationState, .enabled)
        XCTAssertEqual(report.outcomes[.downloader]?.resultingState,
                       .init(assetState: .present(version: "1.0.0"), activationState: .enabled))
        XCTAssertEqual(report.outcomes[.voice]?.resultingState.activationState, .enabled)
        XCTAssertEqual(report.outcomes[.folderPreview]?.resultingState.activationState, .disabled)

        // Sentinel set, marker removed, onboarding completed.
        XCTAssertTrue(MigrationSentinel.hasMigrated(defaults: defaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            featuresDir.appendingPathComponent(".sparkle-migration-pending").path))
        XCTAssertEqual(OnboardingState.load(), .completed)
    }
}
```

- [ ] **Step 2: Run + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/MigratorEndToEndTests | tail -15
```
Expected: PASS, 1/1.

```bash
git add MacAllYouNeedTests/Migration/MigratorEndToEndTests.swift
git commit -m "test(modular-features): end-to-end migration integration test"
```

---

### Task 14: Phase verification

- [ ] **Step 1: Full test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/MigrationSentinelTests \
  -only-testing:MacAllYouNeedTests/PriorUsageDetectorTests \
  -only-testing:MacAllYouNeedTests/MigrationDecisionMatrixTests \
  -only-testing:MacAllYouNeedTests/MigratorTests \
  -only-testing:MacAllYouNeedTests/MigratorEdgeCasesTests \
  -only-testing:MacAllYouNeedTests/PreInstallScriptTests \
  -only-testing:MacAllYouNeedTests/MigratorEndToEndTests \
  -only-testing:MacAllYouNeedTests/WhatsNewSheetViewTests | tail -30
```
Expected: all green.

- [ ] **Step 2: Manual upgrade simulation**

Reset state to look like a pre-modular install:
```bash
APPGROUP=group.com.macallyouneed.shared
defaults delete $APPGROUP migratedToFeatureModel 2>/dev/null || true
defaults delete $APPGROUP feature.bootstrap.seeded 2>/dev/null || true
# Simulate "user had clipboard + downloader history"
defaults write $APPGROUP clipboardMaxItems -int 5000           # non-default → indirect
defaults write $APPGROUP "downloads.outputTemplate" -string "%(title)s.%(ext)s"
defaults write $APPGROUP voice.asr.settings.v1 -data "$(echo '{"modelID":"qwen3-asr-0.6b-int8","languageHint":"automatic","providerKind":"local"}' | xxd -p)"
# Drop the Sparkle marker as if the pre-install script had run
mkdir -p "$HOME/Library/Application Support/MacAllYouNeed/Features"
touch "$HOME/Library/Application Support/MacAllYouNeed/Features/.sparkle-migration-pending"
```

Launch the app. Verify:
- The What's New sheet appears.
- It lists each feature with the expected verdict.
- Clicking "Open Features Settings" opens Settings → Features.
- Quit and relaunch the app — sheet does NOT reappear.
- `defaults read $APPGROUP migratedToFeatureModel` returns `1`.
- The `.sparkle-migration-pending` marker is gone.

- [ ] **Step 3: Run CI**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Mark phase complete in index plan**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md`, change:
```markdown
- [ ] Phase 11 — Migration
```
to:
```markdown
- [x] Phase 11 — Migration
```

- [ ] **Step 5: Commit + open PR**

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 11 complete"
git push -u origin <branch>
gh pr create --title "Phase 11 — Migration: Sparkle pre-install + first-launch logic + What's New sheet" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/11-migration.md"
```
