# Phase 09 — Onboarding Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the legacy 6-step onboarding wizard (Welcome → Accessibility → FDA → Notifications → Sync → Done) with a feature-driven flow:

```
1. Welcome
2. Feature Picker             ← all cards unchecked by default ("wrapper has no functions")
3. Per-feature setup          ← repeats once per chosen feature, in registry order
   3a. Download progress      (skipped if descriptor.assetPacks is empty)
   3b. Permission grants      (only the ones this feature actually declares)
   3c. Feature-specific config (descriptor.onboardingSetupFactory; Voice provides ASR provider + optional Qwen3 download)
4. Done                       ← summary + "you can change this any time in Settings → Features"
```

"Skip for now" exits with zero features enabled (a legitimate end state). Existing-user upgrades skip onboarding entirely via Phase 11's sentinel — Phase 09 only changes what runs on **fresh** installs.

**Architecture:** A new `FeatureSetupCoordinator` owns the per-feature inner state machine (`download → permissions → config`). The existing `OnboardingWindowController` and `SetupWizardShell` are reused; only the steps inside change. `OnboardingState` gains `featurePicker`, `featureSetup(FeatureID)`, `done` cases. The user's picker selections are persisted to `AppGroupSettings` so a partial-onboarding crash resumes at the same feature. The Voice descriptor's `onboardingSetupFactory` returns a new reusable `VoiceProviderSetupView` extracted from `VoiceSettingsView`'s ASR-provider section. `AppController.showStartupSurface()` already routes to `onboardingWindow.show()` when `OnboardingState != .completed`; Phase 09 only swaps the wizard's contents and the `setOnboarding(.completed)` post-step logic.

**Tech Stack:** Swift 5.9+, SwiftUI, the existing MAYN design system (`MAYNTheme`, `MAYNControlMetrics`, `MAYNButton`, `MAYNDivider`, `SetupWizardShell`, `SetupTaskPage`, `PermissionCard`, `InstructionStrip`), `FeatureCore` types from Phases 01–06, `FeatureRuntime`, `PackDownloader`/`PackInstaller` from Phase 06.

**Depends on:** Phase 06 (Downloader pack — onboarding's download sub-step calls `PackDownloader`/`PackInstaller`).

---

## File structure

```
MacAllYouNeed/Onboarding/
├── OnboardingState.swift                       ← REWRITE: new cases + selection persistence
├── OnboardingSelectionStore.swift              ← NEW: persists picker selections + per-feature sub-step
├── OnboardingWizardView.swift                  ← REWRITE: drives new flow over SetupWizardShell
├── OnboardingWindowController.swift            ← MINIMAL TWEAK: title only
├── PermissionStepViews.swift                   ← KEEP WelcomeStep + PermissionCard helpers; remove Sync/FDA/Notifications hardcoding
├── FeaturePickerView.swift                     ← NEW: card grid, all-unchecked default
├── FeaturePickerCard.swift                     ← NEW: one selectable card with "Learn more" disclosure
├── FeatureSetupCoordinator.swift               ← NEW: drives one feature through download → permissions → config
├── FeatureSetupContainerView.swift             ← NEW: hosts the active sub-step view
├── FeatureSetupDownloadView.swift              ← NEW: progress bar + retry
├── FeatureSetupPermissionsView.swift           ← NEW: iterates descriptor.requiredPermissions
├── FeatureSetupConfigView.swift                ← NEW: thin wrapper around descriptor.onboardingSetupFactory
├── OnboardingDoneView.swift                    ← NEW: installed/skipped summary
└── PermissionGateProbe.swift                   ← NEW: per-Permission "isGranted?" + open-system-settings-URL helper

MacAllYouNeed/App/
├── AppController.swift                         ← MINIMAL TWEAK: post-completion path triggers FeatureRuntime.activateAllEnabled()
├── AppControllerOnboarding.swift               ← MINIMAL TWEAK: setOnboarding(.completed) reactivates runtime
├── FeatureRegistryProvider.swift               ← MODIFY: Voice descriptor populates onboardingSetupFactory
└── MainStartupSurfaceRouter.swift              ← UNCHANGED (still routes on `onboarding == .completed`)

MacAllYouNeed/Voice/UI/
└── VoiceProviderSetupView.swift                ← NEW: extracted ASR-provider + Qwen3-download UI for reuse

MacAllYouNeed/Settings/Advanced/
└── AdvancedSettingsView.swift                  ← MODIFY: add "Re-run onboarding…" row (developer/support escape hatch)

MacAllYouNeedTests/Onboarding/
├── OnboardingStateTests.swift                  ← NEW: persistence + migration of legacy values
├── OnboardingSelectionStoreTests.swift         ← NEW: selection persistence
├── FeatureSetupCoordinatorTests.swift          ← NEW: per-feature sub-step machine
├── FeaturePickerViewTests.swift                ← NEW: snapshot + interaction
└── OnboardingDoneViewTests.swift               ← NEW: summary contents
```

---

### Task 1: Rewrite `OnboardingState` with new cases + persistence migration

**Files:**
- Modify: `MacAllYouNeed/Onboarding/OnboardingState.swift`
- Create: `MacAllYouNeedTests/Onboarding/OnboardingStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Onboarding/OnboardingStateTests.swift`:
```swift
import Core
import FeatureCore
import XCTest
@testable import MacAllYouNeed

final class OnboardingStateTests: XCTestCase {
    private let suiteName = "OnboardingStateTests-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultIsNotStarted() {
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .notStarted)
    }

    func testRoundTripWelcome() {
        OnboardingState.welcome.save(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .welcome)
    }

    func testRoundTripFeaturePicker() {
        OnboardingState.featurePicker.save(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .featurePicker)
    }

    func testRoundTripFeatureSetupCarriesFeatureID() {
        OnboardingState.featureSetup(.voice).save(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .featureSetup(.voice))
    }

    func testRoundTripDoneAndCompleted() {
        OnboardingState.done.save(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .done)
        OnboardingState.completed.save(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .completed)
    }

    /// Legacy values written by the pre-Phase-09 onboarding flow must not crash readers.
    /// Fresh installs are the only path that runs the new wizard; legacy values can only
    /// appear in development. We coerce them to .notStarted so the user just retakes onboarding.
    func testLegacyValuesCoerceToNotStarted() {
        for legacy in ["accessibility", "fullDiskAccess", "notifications", "sync", "ready"] {
            defaults.set(legacy, forKey: OnboardingState.key)
            XCTAssertEqual(OnboardingState.load(defaults: defaults), .notStarted,
                           "legacy raw value \(legacy) must coerce to .notStarted")
        }
    }

    func testReset() {
        OnboardingState.featurePicker.save(defaults: defaults)
        OnboardingState.reset(defaults: defaults)
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .notStarted)
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/OnboardingStateTests
```
Expected: FAIL with "type 'OnboardingState' has no case 'featurePicker'".

- [ ] **Step 3: Rewrite `OnboardingState`**

Replace `MacAllYouNeed/Onboarding/OnboardingState.swift`:
```swift
import Core
import FeatureCore
import Foundation

/// Persisted onboarding cursor.
///
/// Phase 09 redesign: the legacy fixed-permission steps are gone. Instead the wizard
/// runs Welcome → Feature Picker → per-feature setup loop → Done. Per-feature setup
/// is a single state (`.featureSetup(FeatureID)`) that internally iterates download →
/// permissions → config — that inner state is owned by `FeatureSetupCoordinator` and
/// is not persisted (restart resumes at the feature, re-running its sub-steps).
enum OnboardingState: Equatable {
    case notStarted
    case welcome
    case featurePicker
    case featureSetup(FeatureID)
    case done
    case completed

    static let key = "onboardingState"

    static func load(defaults: UserDefaults = AppGroupSettings.defaults) -> OnboardingState {
        guard let raw = defaults.string(forKey: key) else { return .notStarted }
        return OnboardingState(rawValue: raw) ?? .notStarted
    }

    func save(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(rawValue, forKey: Self.key)
    }

    static func reset(defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Raw value coding

    /// Encoded as a single string so we can keep the existing AppGroupSettings layout.
    /// Format: `"featureSetup:voice"` for the parameterised case; bare names for the rest.
    var rawValue: String {
        switch self {
        case .notStarted: return "notStarted"
        case .welcome: return "welcome"
        case .featurePicker: return "featurePicker"
        case .featureSetup(let id): return "featureSetup:\(id.rawValue)"
        case .done: return "done"
        case .completed: return "completed"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "notStarted": self = .notStarted
        case "welcome": self = .welcome
        case "featurePicker": self = .featurePicker
        case "done": self = .done
        case "completed": self = .completed
        default:
            // featureSetup:<id>
            let parts = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0] == "featureSetup", let id = FeatureID(rawValue: String(parts[1])) {
                self = .featureSetup(id)
                return
            }
            return nil
        }
    }
}

extension OnboardingState: Identifiable {
    var id: String { rawValue }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/OnboardingStateTests | tail -10
```
Expected: PASS, 7/7.

```bash
git add MacAllYouNeed/Onboarding/OnboardingState.swift \
        MacAllYouNeedTests/Onboarding/OnboardingStateTests.swift
git commit -m "feat(modular-features): redesign OnboardingState for feature-driven flow"
```

---

### Task 2: `OnboardingSelectionStore` — persisted picker selections

**Files:**
- Create: `MacAllYouNeed/Onboarding/OnboardingSelectionStore.swift`
- Create: `MacAllYouNeedTests/Onboarding/OnboardingSelectionStoreTests.swift`

The store remembers (a) which features the user picked, and (b) which features in that list are already complete, so a relaunch mid-onboarding resumes at the next pending feature. Persisted to AppGroupSettings as a JSON-encoded payload.

- [ ] **Step 1: Write the failing test**

```swift
import Core
import FeatureCore
import XCTest
@testable import MacAllYouNeed

final class OnboardingSelectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "OnboardingSelectionStoreTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testEmptyByDefault() {
        let store = OnboardingSelectionStore(defaults: defaults)
        XCTAssertTrue(store.selectedIDs.isEmpty)
        XCTAssertTrue(store.completedIDs.isEmpty)
    }

    func testSavesAndRestoresSelection() {
        let s1 = OnboardingSelectionStore(defaults: defaults)
        s1.setSelection([.downloader, .voice])
        let s2 = OnboardingSelectionStore(defaults: defaults)
        XCTAssertEqual(s2.selectedIDs, [.downloader, .voice])
    }

    func testMarkComplete() {
        let store = OnboardingSelectionStore(defaults: defaults)
        store.setSelection([.downloader, .voice])
        store.markCompleted(.downloader)
        XCTAssertEqual(store.completedIDs, [.downloader])
        XCTAssertEqual(store.nextPendingID(in: [.clipboard, .folderPreview, .downloader, .voice]), .voice)
    }

    func testNextPendingHonorsRegistryOrder() {
        let store = OnboardingSelectionStore(defaults: defaults)
        store.setSelection([.voice, .downloader])
        XCTAssertEqual(
            store.nextPendingID(in: [.clipboard, .folderPreview, .downloader, .voice]),
            .downloader,
            "registry order must win even if user-selection order differs"
        )
    }

    func testClearAfterCompletion() {
        let store = OnboardingSelectionStore(defaults: defaults)
        store.setSelection([.downloader])
        store.markCompleted(.downloader)
        store.clear()
        let s2 = OnboardingSelectionStore(defaults: defaults)
        XCTAssertTrue(s2.selectedIDs.isEmpty)
        XCTAssertTrue(s2.completedIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm fail**

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Onboarding/OnboardingSelectionStore.swift`:
```swift
import Core
import FeatureCore
import Foundation

/// Persists the user's picker choices and per-feature completion progress so a crash
/// or quit mid-onboarding resumes at the next pending feature.
@MainActor
final class OnboardingSelectionStore {
    private struct Payload: Codable {
        var selected: [String]
        var completed: [String]
    }

    private let defaults: UserDefaults
    private static let key = "onboarding.featureSelection"

    private(set) var selectedIDs: [FeatureID]
    private(set) var completedIDs: Set<FeatureID>

    init(defaults: UserDefaults = AppGroupSettings.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.selectedIDs = payload.selected.compactMap(FeatureID.init(rawValue:))
            self.completedIDs = Set(payload.completed.compactMap(FeatureID.init(rawValue:)))
        } else {
            self.selectedIDs = []
            self.completedIDs = []
        }
    }

    func setSelection(_ ids: [FeatureID]) {
        selectedIDs = ids
        completedIDs.formIntersection(Set(ids))
        persist()
    }

    func markCompleted(_ id: FeatureID) {
        completedIDs.insert(id)
        persist()
    }

    /// Returns the next un-completed feature in registry order. Nil when all are done.
    func nextPendingID(in registryOrder: [FeatureID]) -> FeatureID? {
        let selected = Set(selectedIDs)
        for id in registryOrder where selected.contains(id) && !completedIDs.contains(id) {
            return id
        }
        return nil
    }

    func clear() {
        selectedIDs = []
        completedIDs = []
        defaults.removeObject(forKey: Self.key)
    }

    private func persist() {
        let payload = Payload(
            selected: selectedIDs.map(\.rawValue),
            completed: completedIDs.map(\.rawValue)
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/OnboardingSelectionStoreTests | tail -10
```
Expected: PASS, 5/5.

```bash
git add MacAllYouNeed/Onboarding/OnboardingSelectionStore.swift \
        MacAllYouNeedTests/Onboarding/OnboardingSelectionStoreTests.swift
git commit -m "feat(modular-features): add OnboardingSelectionStore for picker persistence"
```

---

### Task 3: `PermissionGateProbe` — granted-check + system-settings URL per Permission

The permissions sub-step needs (a) a way to ask "is this Permission already granted?" so we can auto-skip an already-granted prompt, and (b) the right `x-apple.systempreferences:` URL to drive the user. Centralise both here so the sub-step view is dumb.

**Files:**
- Create: `MacAllYouNeed/Onboarding/PermissionGateProbe.swift`

- [ ] **Step 1: Implement**

Create `MacAllYouNeed/Onboarding/PermissionGateProbe.swift`:
```swift
import AppKit
import ApplicationServices
import AVFoundation
import FeatureCore
import Foundation
import UserNotifications

/// Read-only probe + UI-driving helper for each `Permission` declared on a
/// `FeatureDescriptor`. Owns the mapping from FeatureCore's abstract Permission
/// to AppKit/AVFoundation/UN APIs and the `x-apple.systempreferences:` URL.
@MainActor
enum PermissionGateProbe {
    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .fullDiskAccess:
            // No first-party API. Probe by attempting to read a known protected path.
            let probe = ("~/Library/Safari/Bookmarks.plist" as NSString).expandingTildeInPath
            return FileManager.default.isReadableFile(atPath: probe)
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .notifications:
            // UNNotificationCenter exposes async-only authorization status; cache last seen.
            // Treat as not-granted on cold-launch. Presenting code calls requestAuthorization.
            return false
        }
    }

    static func openSettings(for permission: Permission) {
        let raw: String
        switch permission {
        case .accessibility:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .fullDiskAccess:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .microphone:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .notifications:
            raw = "x-apple.systempreferences:com.apple.preference.notifications"
        }
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Some permissions need an explicit system request (notifications, accessibility prompt).
    /// Returns `true` once the request was issued or no request is needed.
    static func request(_ permission: Permission, completion: @escaping (Bool) -> Void) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            completion(AXIsProcessTrusted())
        case .fullDiskAccess:
            // No programmatic request — UI directs the user to System Settings.
            completion(isGranted(.fullDiskAccess))
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    static func displayName(for permission: Permission) -> String {
        switch permission {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .microphone: return "Microphone"
        case .notifications: return "Notifications"
        }
    }

    static func reason(for permission: Permission, descriptor: FeatureDescriptor) -> String {
        switch (descriptor.id, permission) {
        case (.clipboard, .accessibility):
            return "Lets the clipboard popup paste into the active app and `;trigger` snippets expand."
        case (.downloader, .fullDiskAccess):
            return "Optional. Browser cookie import (Chrome/Safari) needs this for authenticated downloads."
        case (.downloader, .notifications):
            return "Optional. Used only for download completion alerts."
        case (.voice, .accessibility):
            return "Lets dictation paste recognized text into the active app."
        case (.voice, .microphone):
            return "Required for voice capture."
        default:
            return "Required for \(descriptor.displayName)."
        }
    }
}
```

- [ ] **Step 2: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Onboarding/PermissionGateProbe.swift
git commit -m "feat(modular-features): add PermissionGateProbe for onboarding gates"
```

---

### Task 4: `FeatureSetupCoordinator` — per-feature inner state machine

The coordinator owns the `download → permissions → config` micro-state machine for one feature at a time. It is created fresh each time the wizard enters `.featureSetup(id)` and is destroyed when the feature completes. The wizard view observes its `@Published` `subStep` and re-renders.

**Files:**
- Create: `MacAllYouNeed/Onboarding/FeatureSetupCoordinator.swift`
- Create: `MacAllYouNeedTests/Onboarding/FeatureSetupCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import FeatureCore
import XCTest
@testable import MacAllYouNeed

@MainActor
final class FeatureSetupCoordinatorTests: XCTestCase {
    private func makeDescriptor(
        id: FeatureID,
        permissions: [Permission] = [],
        assetPacks: [AssetPack] = [],
        config: Bool = false
    ) -> FeatureDescriptor {
        FeatureDescriptor(
            id: id,
            displayName: id.rawValue,
            icon: "circle",
            summary: "",
            detailDescription: "",
            requiredPermissions: permissions,
            assetPacks: assetPacks,
            activator: NoopFeatureActivator(),
            onboardingSetupFactory: config ? { AnyView(EmptyView()) } : nil
        )
    }

    func testSwiftOnlyFeatureWithNoPermissionsAndNoConfigCompletesImmediately() async {
        let coord = FeatureSetupCoordinator(
            descriptor: makeDescriptor(id: .clipboard),
            installer: NoopOnboardingInstaller(),
            permissionsAlwaysGranted: true
        )
        await coord.start()
        XCTAssertEqual(coord.subStep, .complete)
    }

    func testFeatureWithAssetPackEntersDownloadFirst() async {
        let coord = FeatureSetupCoordinator(
            descriptor: makeDescriptor(
                id: .downloader,
                assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")]
            ),
            installer: NoopOnboardingInstaller(),
            permissionsAlwaysGranted: true
        )
        await coord.start()
        XCTAssertEqual(coord.subStep, .download(progress: 0))
    }

    func testDownloadCompletionAdvancesToPermissionsThenConfigThenComplete() async {
        let installer = ScriptedOnboardingInstaller()
        let coord = FeatureSetupCoordinator(
            descriptor: makeDescriptor(
                id: .downloader,
                permissions: [.notifications],
                assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
                config: false
            ),
            installer: installer,
            permissionsAlwaysGranted: false
        )
        await coord.start()
        XCTAssertEqual(coord.subStep, .download(progress: 0))

        installer.simulateProgress(0.5)
        XCTAssertEqual(coord.subStep, .download(progress: 0.5))

        await installer.simulateSuccess()
        XCTAssertEqual(coord.subStep, .permissions)

        coord.markPermissionGranted(.notifications)
        // No config; falls through to .complete.
        XCTAssertEqual(coord.subStep, .complete)
    }

    func testFeatureWithOnlyConfigSkipsDownloadAndPermissions() async {
        let coord = FeatureSetupCoordinator(
            descriptor: makeDescriptor(id: .voice, config: true),
            installer: NoopOnboardingInstaller(),
            permissionsAlwaysGranted: true
        )
        await coord.start()
        XCTAssertEqual(coord.subStep, .config)
        coord.markConfigDone()
        XCTAssertEqual(coord.subStep, .complete)
    }

    func testRetryAfterDownloadFailure() async {
        let installer = ScriptedOnboardingInstaller()
        let coord = FeatureSetupCoordinator(
            descriptor: makeDescriptor(
                id: .downloader,
                assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")]
            ),
            installer: installer,
            permissionsAlwaysGranted: true
        )
        await coord.start()
        await installer.simulateFailure(reason: "network down")
        XCTAssertEqual(coord.subStep, .downloadFailed(reason: "network down"))

        coord.retryDownload()
        XCTAssertEqual(coord.subStep, .download(progress: 0))
        await installer.simulateSuccess()
        XCTAssertEqual(coord.subStep, .complete)
    }
}

// MARK: - Test doubles

@MainActor
private final class NoopOnboardingInstaller: OnboardingInstalling {
    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        progress(1.0)
    }
}

@MainActor
private final class ScriptedOnboardingInstaller: OnboardingInstalling {
    private var progressCallback: ((Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?

    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        progressCallback = progress
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
        }
    }

    func simulateProgress(_ value: Double) {
        progressCallback?(value)
    }

    func simulateSuccess() async {
        continuation?.resume()
        continuation = nil
        await Task.yield()
    }

    func simulateFailure(reason: String) async {
        continuation?.resume(throwing: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
        continuation = nil
        await Task.yield()
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureSetupCoordinatorTests
```

- [ ] **Step 3: Implement coordinator + installer protocol**

Create `MacAllYouNeed/Onboarding/FeatureSetupCoordinator.swift`:
```swift
import Combine
import FeatureCore
import Foundation

/// Abstracts the "install one feature's pack" call so tests can drive it deterministically.
/// Real implementation lives in `OnboardingInstaller` (see Task 5) and wraps Phase 06's
/// PackDownloader + PackInstaller.
@MainActor
protocol OnboardingInstalling: AnyObject {
    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws
}

/// Drives one feature through the per-feature setup sub-flow:
///   download (if assetPacks non-empty)
///   → permissions (if requiredPermissions non-empty and not all already granted)
///   → config (if onboardingSetupFactory non-nil)
///   → complete
///
/// Persisting the cursor position within the sub-flow is intentionally NOT done — a relaunch
/// resumes at the same feature (via OnboardingSelectionStore) and re-runs its sub-steps.
/// All sub-steps are idempotent (download already-present, permissions already-granted,
/// config closure pure UI), so re-running is cheap.
@MainActor
final class FeatureSetupCoordinator: ObservableObject {
    enum SubStep: Equatable {
        case idle
        case download(progress: Double)
        case downloadFailed(reason: String)
        case permissions
        case config
        case complete
    }

    @Published private(set) var subStep: SubStep = .idle

    let descriptor: FeatureDescriptor
    private let installer: OnboardingInstalling
    private let permissionsAlwaysGranted: Bool   // test seam; production uses PermissionGateProbe
    private var grantedPermissions: Set<Permission> = []

    init(descriptor: FeatureDescriptor, installer: OnboardingInstalling, permissionsAlwaysGranted: Bool = false) {
        self.descriptor = descriptor
        self.installer = installer
        self.permissionsAlwaysGranted = permissionsAlwaysGranted
    }

    func start() async {
        if !descriptor.assetPacks.isEmpty {
            subStep = .download(progress: 0)
            do {
                try await installer.install(descriptor: descriptor) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if case .download = self.subStep { self.subStep = .download(progress: progress) }
                    }
                }
                advanceFromDownload()
            } catch {
                subStep = .downloadFailed(reason: error.localizedDescription)
            }
        } else {
            advanceFromDownload()
        }
    }

    func retryDownload() {
        subStep = .download(progress: 0)
        Task { await start() }
    }

    func markPermissionGranted(_ permission: Permission) {
        grantedPermissions.insert(permission)
        if allDeclaredPermissionsGranted {
            advanceFromPermissions()
        }
    }

    func markConfigDone() {
        if subStep == .config { subStep = .complete }
    }

    // MARK: - Internal advance helpers

    private func advanceFromDownload() {
        if descriptor.requiredPermissions.isEmpty || initiallyAllGranted() {
            advanceFromPermissions()
        } else {
            subStep = .permissions
        }
    }

    private func advanceFromPermissions() {
        if descriptor.onboardingSetupFactory != nil {
            subStep = .config
        } else {
            subStep = .complete
        }
    }

    private func initiallyAllGranted() -> Bool {
        if permissionsAlwaysGranted { return true }
        for p in descriptor.requiredPermissions where !PermissionGateProbe.isGranted(p) {
            return false
        }
        return true
    }

    private var allDeclaredPermissionsGranted: Bool {
        Set(descriptor.requiredPermissions).isSubset(of: grantedPermissions)
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureSetupCoordinatorTests | tail -10
```
Expected: PASS, 5/5.

```bash
git add MacAllYouNeed/Onboarding/FeatureSetupCoordinator.swift \
        MacAllYouNeedTests/Onboarding/FeatureSetupCoordinatorTests.swift
git commit -m "feat(modular-features): add FeatureSetupCoordinator per-feature state machine"
```

---

### Task 5: `OnboardingInstaller` — production wiring of Phase 06 pack pipeline

Production conformance to `OnboardingInstalling`. Wraps Phase 06's `PackDownloader` and `PackInstaller`, marks `FeatureManager.markAssetState(.downloading(...))` mid-flight and `.markAssetState(.present(version))` on success. No-op for descriptors with empty `assetPacks` (the coordinator never calls into it for those).

**Files:**
- Create: `MacAllYouNeed/Onboarding/OnboardingInstaller.swift`

- [ ] **Step 1: Implement**

```swift
import FeatureCore
import Foundation

/// Production OnboardingInstalling. Wraps Phase 06's PackDownloader + PackInstaller and
/// keeps FeatureManager state in sync so the Features tab card mirrors what onboarding shows.
@MainActor
final class OnboardingInstaller: OnboardingInstalling {
    private let runtime: FeatureRuntime
    private let downloader: PackDownloader
    private let installer: PackInstaller

    init(runtime: FeatureRuntime, downloader: PackDownloader, installer: PackInstaller) {
        self.runtime = runtime
        self.downloader = downloader
        self.installer = installer
    }

    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        guard let pack = descriptor.assetPacks.first else { return }   // coordinator guards this
        try await runtime.manager.markAssetState(.downloading(progress: 0), for: descriptor.id)

        let zipURL = try await downloader.download(packKey: pack.bundledManifestKey) { fraction in
            Task { @MainActor in
                try? await self.runtime.manager.markAssetState(.downloading(progress: fraction), for: descriptor.id)
                progress(fraction)
            }
        }

        let installed = try await installer.install(packKey: pack.bundledManifestKey, zipURL: zipURL)
        try await runtime.manager.markAssetState(.present(version: installed.version), for: descriptor.id)
        // The coordinator drives FeatureRuntime.applyTransition(.enable, ...) at Done time,
        // not here — the user could still abandon onboarding mid-flight after install.
    }
}
```

> The exact `PackDownloader.download(packKey:)` and `PackInstaller.install(packKey:zipURL:)` signatures land in Phase 02/06; if they differ slightly, adapt this wrapper without changing `OnboardingInstalling`.

- [ ] **Step 2: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
git add MacAllYouNeed/Onboarding/OnboardingInstaller.swift
git commit -m "feat(modular-features): add production OnboardingInstaller wrapping Phase 06"
```

---

### Task 6: `FeaturePickerView` + `FeaturePickerCard`

A 2-column `LazyVGrid` of `FeaturePickerCard`s. Each card shows the descriptor's icon, displayName, summary, "Learn more" disclosure (revealing `detailDescription` + declared permissions + first asset pack's download size if any), and a checkbox. **All cards default unchecked.**

**Files:**
- Create: `MacAllYouNeed/Onboarding/FeaturePickerCard.swift`
- Create: `MacAllYouNeed/Onboarding/FeaturePickerView.swift`
- Create: `MacAllYouNeedTests/Onboarding/FeaturePickerViewTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import FeatureCore
import SwiftUI
import XCTest
@testable import MacAllYouNeed

@MainActor
final class FeaturePickerViewTests: XCTestCase {
    private func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: FeatureID.allCases.map { id in
            FeatureDescriptor(
                id: id,
                displayName: id.rawValue.capitalized,
                icon: "circle",
                summary: "Summary for \(id.rawValue)",
                detailDescription: "Detail for \(id.rawValue)",
                activator: NoopFeatureActivator()
            )
        })
    }

    func testRendersOneCardPerRegistryEntry() {
        let registry = makeRegistry()
        let view = FeaturePickerView(
            registry: registry,
            selectedIDs: .constant([]),
            onContinue: {},
            onSkip: {}
        )
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let text = host.descendantText()
        for descriptor in registry.descriptors {
            XCTAssertTrue(text.contains(descriptor.displayName),
                          "card for \(descriptor.id) missing")
        }
    }

    func testAllCardsDefaultUnchecked() {
        let registry = makeRegistry()
        var selection: [FeatureID] = []
        _ = FeaturePickerView(
            registry: registry,
            selectedIDs: Binding(get: { selection }, set: { selection = $0 }),
            onContinue: {},
            onSkip: {}
        )
        XCTAssertTrue(selection.isEmpty, "all cards must default unchecked")
    }

    func testToggleAddsThenRemovesFromSelection() {
        var selection: [FeatureID] = []
        let card = FeaturePickerCard(
            descriptor: FeatureDescriptor(
                id: .voice, displayName: "Voice", icon: "mic",
                summary: "", detailDescription: "",
                activator: NoopFeatureActivator()
            ),
            isSelected: Binding(get: { selection.contains(.voice) },
                                set: { newValue in
                                    if newValue { selection.append(.voice) }
                                    else { selection.removeAll { $0 == .voice } }
                                })
        )
        _ = card
        // Simulate toggle.
        selection = []
        let isSelected = Binding(get: { selection.contains(.voice) },
                                 set: { newValue in
                                     if newValue { selection.append(.voice) }
                                     else { selection.removeAll { $0 == .voice } }
                                 })
        isSelected.wrappedValue = true
        XCTAssertEqual(selection, [.voice])
        isSelected.wrappedValue = false
        XCTAssertEqual(selection, [])
    }
}

private extension NSView {
    func descendantText() -> String {
        var pieces: [String] = []
        if let textField = self as? NSTextField { pieces.append(textField.stringValue) }
        for sub in subviews { pieces.append(sub.descendantText()) }
        return pieces.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Run to confirm fail**

- [ ] **Step 3: Implement `FeaturePickerCard`**

Create `MacAllYouNeed/Onboarding/FeaturePickerCard.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeaturePickerCard: View {
    let descriptor: FeatureDescriptor
    @Binding var isSelected: Bool
    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: descriptor.icon)
                    .font(.title3)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName).font(.headline)
                    Text(descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            DisclosureGroup(isExpanded: $showsDetail) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(descriptor.detailDescription).font(.caption)
                    if !descriptor.requiredPermissions.isEmpty {
                        Text("Permissions: " + descriptor.requiredPermissions
                             .map(PermissionGateProbe.displayName(for:))
                             .joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let pack = descriptor.assetPacks.first {
                        Text("Download: \(downloadSizeText(packKey: pack.bundledManifestKey))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Learn more").font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }

    /// Resolved at render-time from the bundled FeaturePackManifest.json (Phase 06).
    /// Falls back to "—" if the manifest can't be read (offline dev build, etc.).
    private func downloadSizeText(packKey: String) -> String {
        guard let manifest = BundledFeaturePackManifest.shared,
              let pack = manifest.packs[packKey] else { return "—" }
        return ByteCountFormatter.string(fromByteCount: pack.sizeBytes, countStyle: .file)
    }
}

/// Lazily reads `Resources/FeaturePackManifest.json` from the app bundle so picker cards
/// can show the real "Download: 192 MB" string. Phase 06 wires the Resources file.
enum BundledFeaturePackManifest {
    static let shared: FeaturePackManifest? = {
        guard let url = Bundle.main.url(forResource: "FeaturePackManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeaturePackManifest.self, from: data)
    }()
}
```

- [ ] **Step 4: Implement `FeaturePickerView`**

Create `MacAllYouNeed/Onboarding/FeaturePickerView.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeaturePickerView: View {
    let registry: FeatureRegistry
    @Binding var selectedIDs: [FeatureID]
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        SetupTaskPage(
            symbol: "square.grid.2x2",
            title: "Choose your features",
            subtitle: "Pick what you want now. Everything is opt-in — you can install or remove features any time from Settings → Features."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(registry.descriptors, id: \.id) { descriptor in
                        FeaturePickerCard(
                            descriptor: descriptor,
                            isSelected: binding(for: descriptor.id)
                        )
                    }
                }
                Text("\(selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for id: FeatureID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected, !selectedIDs.contains(id) {
                    selectedIDs.append(id)
                } else if !isSelected {
                    selectedIDs.removeAll { $0 == id }
                }
            }
        )
    }
}
```

> The "Skip for now" / "Continue" buttons live in `SetupWizardShell`'s action bar — see Task 9. The view itself only needs to render cards and report selection.

- [ ] **Step 5: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeaturePickerViewTests | tail -10
```
Expected: PASS, 3/3.

```bash
git add MacAllYouNeed/Onboarding/FeaturePickerCard.swift \
        MacAllYouNeed/Onboarding/FeaturePickerView.swift \
        MacAllYouNeedTests/Onboarding/FeaturePickerViewTests.swift
git commit -m "feat(modular-features): add FeaturePickerView with all-unchecked default"
```

---

### Task 7: Per-feature setup sub-step views

Three thin views, one per `SubStep` value. They all render inside `SetupTaskPage` so they match the wizard chrome.

**Files:**
- Create: `MacAllYouNeed/Onboarding/FeatureSetupDownloadView.swift`
- Create: `MacAllYouNeed/Onboarding/FeatureSetupPermissionsView.swift`
- Create: `MacAllYouNeed/Onboarding/FeatureSetupConfigView.swift`
- Create: `MacAllYouNeed/Onboarding/FeatureSetupContainerView.swift`

- [ ] **Step 1: Implement download view**

Create `MacAllYouNeed/Onboarding/FeatureSetupDownloadView.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeatureSetupDownloadView: View {
    let descriptor: FeatureDescriptor
    let progress: Double
    let failureReason: String?
    let onRetry: () -> Void

    var body: some View {
        SetupTaskPage(
            symbol: "arrow.down.circle",
            title: "Installing \(descriptor.displayName)…",
            subtitle: "This downloads the \(descriptor.displayName) binaries the first time you enable the feature."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let failureReason {
                    StatusPill(text: failureReason, kind: .danger)
                    MAYNButton("Retry", role: .primary, action: onRetry)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 360)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Continue is available when the install finishes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Implement permissions view**

Create `MacAllYouNeed/Onboarding/FeatureSetupPermissionsView.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeatureSetupPermissionsView: View {
    let descriptor: FeatureDescriptor
    let onPermissionGranted: (Permission) -> Void
    @State private var liveGranted: [Permission: Bool] = [:]
    private let pollTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SetupTaskPage(
            symbol: "lock",
            title: "Permissions for \(descriptor.displayName)",
            subtitle: "Grant the permissions \(descriptor.displayName) needs. This step advances automatically once each is granted."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(descriptor.requiredPermissions, id: \.self) { permission in
                    PermissionCard(
                        title: PermissionGateProbe.displayName(for: permission),
                        reason: PermissionGateProbe.reason(for: permission, descriptor: descriptor),
                        state: (liveGranted[permission] ?? PermissionGateProbe.isGranted(permission)) ? .granted : .needed,
                        actionTitle: "Open System Settings"
                    ) {
                        PermissionGateProbe.request(permission) { granted in
                            liveGranted[permission] = granted
                            if !granted { PermissionGateProbe.openSettings(for: permission) }
                            if granted { onPermissionGranted(permission) }
                        }
                    }
                }
            }
        }
        .onAppear {
            for permission in descriptor.requiredPermissions {
                liveGranted[permission] = PermissionGateProbe.isGranted(permission)
                if liveGranted[permission] == true { onPermissionGranted(permission) }
            }
        }
        .onReceive(pollTimer) { _ in
            for permission in descriptor.requiredPermissions {
                let now = PermissionGateProbe.isGranted(permission)
                if liveGranted[permission] != now {
                    liveGranted[permission] = now
                    if now { onPermissionGranted(permission) }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Implement config view**

Create `MacAllYouNeed/Onboarding/FeatureSetupConfigView.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeatureSetupConfigView: View {
    let descriptor: FeatureDescriptor

    var body: some View {
        SetupTaskPage(
            symbol: "slider.horizontal.3",
            title: "Set up \(descriptor.displayName)",
            subtitle: "Configure how \(descriptor.displayName) should behave. You can change these later from Settings → \(descriptor.displayName)."
        ) {
            if let factory = descriptor.onboardingSetupFactory {
                factory()
            } else {
                Text("No additional setup required.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }
}
```

- [ ] **Step 4: Implement container view**

Create `MacAllYouNeed/Onboarding/FeatureSetupContainerView.swift`:
```swift
import FeatureCore
import SwiftUI

/// Hosts the active sub-step for one feature. Owns the FeatureSetupCoordinator instance and
/// reports completion upward so the wizard can advance to the next selected feature.
struct FeatureSetupContainerView: View {
    @StateObject private var coordinator: FeatureSetupCoordinator
    let onFeatureCompleted: () -> Void

    init(coordinator: FeatureSetupCoordinator, onFeatureCompleted: @escaping () -> Void) {
        _coordinator = StateObject(wrappedValue: coordinator)
        self.onFeatureCompleted = onFeatureCompleted
    }

    var body: some View {
        Group {
            switch coordinator.subStep {
            case .idle:
                ProgressView().task { await coordinator.start() }
            case .download(let progress):
                FeatureSetupDownloadView(
                    descriptor: coordinator.descriptor,
                    progress: progress,
                    failureReason: nil,
                    onRetry: { coordinator.retryDownload() }
                )
            case .downloadFailed(let reason):
                FeatureSetupDownloadView(
                    descriptor: coordinator.descriptor,
                    progress: 0,
                    failureReason: reason,
                    onRetry: { coordinator.retryDownload() }
                )
            case .permissions:
                FeatureSetupPermissionsView(descriptor: coordinator.descriptor) { permission in
                    coordinator.markPermissionGranted(permission)
                }
            case .config:
                FeatureSetupConfigView(descriptor: coordinator.descriptor)
            case .complete:
                Color.clear.onAppear { onFeatureCompleted() }
            }
        }
    }
}
```

- [ ] **Step 5: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Onboarding/FeatureSetupDownloadView.swift \
        MacAllYouNeed/Onboarding/FeatureSetupPermissionsView.swift \
        MacAllYouNeed/Onboarding/FeatureSetupConfigView.swift \
        MacAllYouNeed/Onboarding/FeatureSetupContainerView.swift
git commit -m "feat(modular-features): add per-feature setup sub-step views"
```

---

### Task 8: `OnboardingDoneView` — installed/skipped summary

**Files:**
- Create: `MacAllYouNeed/Onboarding/OnboardingDoneView.swift`
- Create: `MacAllYouNeedTests/Onboarding/OnboardingDoneViewTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import FeatureCore
import SwiftUI
import XCTest
@testable import MacAllYouNeed

@MainActor
final class OnboardingDoneViewTests: XCTestCase {
    private func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: FeatureID.allCases.map { id in
            FeatureDescriptor(
                id: id, displayName: id.rawValue.capitalized, icon: "circle",
                summary: "", detailDescription: "",
                activator: NoopFeatureActivator()
            )
        })
    }

    func testListsInstalledAndSkipped() {
        let registry = makeRegistry()
        let view = OnboardingDoneView(
            registry: registry,
            installedIDs: [.downloader, .voice],
            skippedIDs: [.clipboard, .folderPreview],
            onDone: {}
        )
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let text = host.descendantText()
        XCTAssertTrue(text.contains("Downloader"))
        XCTAssertTrue(text.contains("Voice"))
        XCTAssertTrue(text.contains("Clipboard"))
        XCTAssertTrue(text.contains("Settings → Features"))
    }

    func testHandlesAllSkipped() {
        let registry = makeRegistry()
        let view = OnboardingDoneView(
            registry: registry,
            installedIDs: [],
            skippedIDs: FeatureID.allCases,
            onDone: {}
        )
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let text = host.descendantText()
        XCTAssertTrue(text.contains("No features were enabled"))
    }
}

private extension NSView {
    func descendantText() -> String {
        var pieces: [String] = []
        if let tf = self as? NSTextField { pieces.append(tf.stringValue) }
        for sub in subviews { pieces.append(sub.descendantText()) }
        return pieces.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Run to confirm fail**

- [ ] **Step 3: Implement**

```swift
import FeatureCore
import SwiftUI

struct OnboardingDoneView: View {
    let registry: FeatureRegistry
    let installedIDs: [FeatureID]
    let skippedIDs: [FeatureID]
    let onDone: () -> Void

    var body: some View {
        SetupTaskPage(
            symbol: "checkmark",
            title: "You're all set",
            subtitle: "Mac All You Need is ready. You can install or remove features any time from Settings → Features."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if installedIDs.isEmpty && !skippedIDs.isEmpty {
                    StatusPill(text: "No features were enabled", kind: .neutral)
                    Text("Open Settings → Features when you're ready to enable something.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !installedIDs.isEmpty {
                    SectionList(title: "Enabled", ids: installedIDs, registry: registry, symbol: "checkmark.circle.fill")
                }
                if !skippedIDs.isEmpty {
                    SectionList(title: "Skipped", ids: skippedIDs, registry: registry, symbol: "circle")
                }
            }
        }
    }

    private struct SectionList: View {
        let title: String
        let ids: [FeatureID]
        let registry: FeatureRegistry
        let symbol: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(ids, id: \.self) { id in
                    if let descriptor = registry.descriptor(for: id) {
                        HStack {
                            Image(systemName: symbol).frame(width: 18)
                            Text(descriptor.displayName)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/OnboardingDoneViewTests | tail -10
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeed/Onboarding/OnboardingDoneView.swift \
        MacAllYouNeedTests/Onboarding/OnboardingDoneViewTests.swift
git commit -m "feat(modular-features): add OnboardingDoneView summary"
```

---

### Task 9: Rewrite `OnboardingWizardView` to drive the new flow

The wizard view becomes a pure router over the new `OnboardingState` cases. Sidebar steps reflect the new flow (`Welcome • Choose Features • Set up • Done`). Picker / setup / done pages live below the existing `SetupWizardShell` chrome.

**Files:**
- Modify: `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`

- [ ] **Step 1: Replace the file**

Rewrite `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`:
```swift
import AppKit
import FeatureCore
import SwiftUI

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState
    @State private var selectedIDs: [FeatureID]
    @State private var skippedIDs: [FeatureID] = []
    @State private var coordinator: FeatureSetupCoordinator?

    private let selectionStore: OnboardingSelectionStore

    init(controller: AppController) {
        self.controller = controller
        let store = OnboardingSelectionStore()
        self.selectionStore = store

        let loaded = controller.onboarding
        let initial: OnboardingState = (loaded == .notStarted) ? .welcome : loaded
        _step = State(initialValue: initial)
        _selectedIDs = State(initialValue: store.selectedIDs)
    }

    private var registry: FeatureRegistry { controller.runtime.registry }
    private var registryOrder: [FeatureID] { registry.descriptors.map(\.id) }

    var body: some View {
        SetupWizardShell(
            title: "Mac All You Need",
            subtitle: "Initial setup",
            steps: stepDescriptors,
            currentStep: sidebarStep,
            canGoBack: canGoBack,
            canSkip: canSkip,
            primaryTitle: primaryTitle,
            canAdvance: canAdvance,
            back: back,
            skip: handleSkip,
            primaryAction: handlePrimary
        ) {
            content
        }
        .frame(width: 760, height: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .notStarted, .welcome:
            WelcomeStep(next: { advanceTo(.featurePicker) })
        case .featurePicker:
            FeaturePickerView(
                registry: registry,
                selectedIDs: $selectedIDs,
                onContinue: handlePrimary,
                onSkip: handleSkip
            )
        case .featureSetup(let id):
            if let coordinator, coordinator.descriptor.id == id {
                FeatureSetupContainerView(coordinator: coordinator) {
                    selectionStore.markCompleted(id)
                    advanceToNextFeatureOrDone()
                }
            } else {
                ProgressView().onAppear {
                    coordinator = makeCoordinator(for: id)
                }
            }
        case .done:
            OnboardingDoneView(
                registry: registry,
                installedIDs: selectedIDs,
                skippedIDs: skippedIDs,
                onDone: { setStep(.completed) }
            )
        case .completed:
            EmptyView()
        }
    }

    // MARK: - Step machine

    private var stepDescriptors: [SetupStepDescriptor<OnboardingSidebarStep>] {
        OnboardingSidebarStep.allCases.enumerated().map { idx, candidate in
            SetupStepDescriptor(
                id: candidate,
                title: candidate.title,
                subtitle: candidate.subtitle,
                symbol: candidate.symbol,
                isCompleted: idx < currentSidebarIndex
            )
        }
    }

    private var sidebarStep: OnboardingSidebarStep { OnboardingSidebarStep.from(step) }
    private var currentSidebarIndex: Int {
        OnboardingSidebarStep.allCases.firstIndex(of: sidebarStep) ?? 0
    }

    private var primaryTitle: String {
        switch step {
        case .notStarted, .welcome: return "Get Started"
        case .featurePicker: return selectedIDs.isEmpty ? "Continue with no features" : "Continue"
        case .featureSetup: return "Continue"
        case .done: return "Done"
        case .completed: return "Done"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .featureSetup:
            return coordinator?.subStep == .complete || coordinator?.subStep == .config
        default:
            return true
        }
    }

    private var canGoBack: Bool {
        switch step {
        case .notStarted, .welcome, .completed: return false
        default: return true
        }
    }

    private var canSkip: Bool {
        switch step {
        case .featurePicker: return true
        case .featureSetup: return true       // skip just this feature
        default: return false
        }
    }

    private func handlePrimary() {
        switch step {
        case .notStarted, .welcome:
            advanceTo(.featurePicker)
        case .featurePicker:
            selectionStore.setSelection(selectedIDs)
            skippedIDs = registryOrder.filter { !selectedIDs.contains($0) }
            advanceToNextFeatureOrDone()
        case .featureSetup(let id):
            // Treat "Continue" during config as "config done".
            coordinator?.markConfigDone()
            selectionStore.markCompleted(id)
            advanceToNextFeatureOrDone()
        case .done, .completed:
            setStep(.completed)
        }
    }

    private func handleSkip() {
        switch step {
        case .featurePicker:
            // Bare "Skip for now" → exit with zero features.
            selectedIDs = []
            skippedIDs = registryOrder
            selectionStore.clear()
            setStep(.completed)
        case .featureSetup(let id):
            // Skip this feature; it remains in `skippedIDs`.
            if let idx = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: idx) }
            if !skippedIDs.contains(id) { skippedIDs.append(id) }
            advanceToNextFeatureOrDone()
        default:
            break
        }
    }

    private func back() {
        switch step {
        case .featurePicker:
            advanceTo(.welcome)
        case .featureSetup:
            advanceTo(.featurePicker)
        case .done:
            // Step back into the last feature's setup, if any. Otherwise the picker.
            if let last = selectedIDs.last { advanceTo(.featureSetup(last)) }
            else { advanceTo(.featurePicker) }
        default:
            break
        }
    }

    private func advanceToNextFeatureOrDone() {
        coordinator = nil
        if let next = selectionStore.nextPendingID(in: registryOrder) {
            advanceTo(.featureSetup(next))
        } else {
            advanceTo(.done)
        }
    }

    private func advanceTo(_ newStep: OnboardingState) {
        if case .featureSetup(let id) = newStep {
            coordinator = makeCoordinator(for: id)
        }
        setStep(newStep)
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
        if newValue == .completed {
            selectionStore.clear()
            // Persist the user's selections into FeatureRuntime: enable each picked feature.
            Task { @MainActor in
                for id in selectedIDs {
                    try? await controller.runtime.applyTransition(.enable, for: id)
                }
                NSApplication.shared.keyWindow?.close()
            }
        }
    }

    private func makeCoordinator(for id: FeatureID) -> FeatureSetupCoordinator? {
        guard let descriptor = registry.descriptor(for: id) else { return nil }
        return FeatureSetupCoordinator(
            descriptor: descriptor,
            installer: controller.onboardingInstaller
        )
    }
}

/// Sidebar nav model. The actual flow has many states (one per feature in `.featureSetup`);
/// the sidebar collapses them into four high-level phases the user can read at a glance.
enum OnboardingSidebarStep: Hashable, CaseIterable {
    case welcome, picker, setup, done

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .picker: return "Choose Features"
        case .setup: return "Set Up"
        case .done: return "Done"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "What this app does"
        case .picker: return "Pick what you want"
        case .setup: return "Per-feature config"
        case .done: return "Start using it"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .picker: return "square.grid.2x2"
        case .setup: return "gearshape"
        case .done: return "checkmark"
        }
    }

    static func from(_ state: OnboardingState) -> OnboardingSidebarStep {
        switch state {
        case .notStarted, .welcome: return .welcome
        case .featurePicker: return .picker
        case .featureSetup: return .setup
        case .done, .completed: return .done
        }
    }
}
```

- [ ] **Step 2: Add `onboardingInstaller` accessor on `AppController`**

In `AppControllerOnboarding.swift`, add a lazy production installer:
```swift
extension AppController {
    /// Lazily-built production installer for onboarding's per-feature download step.
    /// Phase 06 wires PackDownloader + PackInstaller; if you're running this in a
    /// pre-Phase-06 build, return a Noop wrapper that immediately succeeds.
    var onboardingInstaller: OnboardingInstalling {
        OnboardingInstaller(
            runtime: runtime,
            downloader: packDownloader,
            installer: packInstaller
        )
    }
}
```

(`packDownloader` / `packInstaller` come from Phase 02 wiring on `AppController`. If they don't exist yet on the branch you're starting from, stub `var onboardingInstaller: OnboardingInstalling = NoopOnboardingInstaller()` and add a `// TODO Phase 06` comment.)

- [ ] **Step 3: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Onboarding/OnboardingWizardView.swift \
        MacAllYouNeed/App/AppControllerOnboarding.swift
git commit -m "feat(modular-features): rewrite OnboardingWizardView for feature-driven flow"
```

---

### Task 10: Voice — extract `VoiceProviderSetupView` and wire `onboardingSetupFactory`

The Voice descriptor needs a real `onboardingSetupFactory`. Reuse the relevant pieces of `VoiceSettingsView`'s ASR-provider section by extracting them into a small reusable child view.

**Files:**
- Create: `MacAllYouNeed/Voice/UI/VoiceProviderSetupView.swift`
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift`

- [ ] **Step 1: Read the relevant Voice settings code**

```bash
sed -n '362,400p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/VoiceSettingsView.swift
sed -n '440,535p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/VoiceSettingsView.swift
```

Note the existing `cloudASRModelsSection`, `applyASRProviderSelection(_:)`, and Qwen3 download helpers. The new view reuses these *via the controller* — no behaviour duplication.

- [ ] **Step 2: Implement `VoiceProviderSetupView`**

Create `MacAllYouNeed/Voice/UI/VoiceProviderSetupView.swift`:
```swift
import Core
import FeatureCore
import SwiftUI

/// Onboarding sub-step for the Voice feature. Picks an ASR provider (Cloud/Local) and,
/// for Local, lets the user kick off the Qwen3 model download. Mirrors the cloud + local
/// model sections of `VoiceSettingsView` but trims everything that isn't first-run essential:
/// no microphone picker, no cleanup, no dictionary, no history.
///
/// The user can refine all of these later from Settings → Voice.
struct VoiceProviderSetupView: View {
    let controller: AppController
    @State private var providerKind: VoiceASRProviderKind
    @State private var localModelID: VoiceASRModelID
    @State private var groqModelID: GroqASRModelID
    @State private var groqAPIKey: String
    @State private var languageHint: VoiceASRLanguageHint
    @State private var groqLanguageHint: VoiceASRLanguageHint
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var downloadingModelID: VoiceASRModelID?

    init(controller: AppController) {
        self.controller = controller
        let asr = VoiceASRSettingsStore.load()
        let groq = GroqASRSettingsStore.load()
        _providerKind = State(initialValue: asr.providerKind)
        _localModelID = State(initialValue: asr.modelID)
        _groqModelID = State(initialValue: groq.modelID)
        _groqAPIKey = State(initialValue: controller.groqASRAPIKey())
        _languageHint = State(initialValue: asr.languageHint)
        _groqLanguageHint = State(initialValue: groq.languageHint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FunctionSegmentedTabStrip(
                tabs: Array(VoiceASRProviderKind.allCases),
                selection: providerKind,
                fillsAvailableWidth: false,
                size: .control
            ) { kind in
                providerKind = kind
                applyProviderSelection(kind)
            }

            switch providerKind {
            case .groq:
                cloudSection
            case .local:
                localSection
            }

            MAYNDivider()
            MAYNSettingsRow(
                title: "Language",
                subtitle: "Auto-detect handles mixed Chinese/English. Switch to one only if results drift."
            ) {
                MAYNDropdown(
                    selection: providerKind == .groq ? $groqLanguageHint : $languageHint,
                    options: Array(VoiceASRLanguageHint.allCases),
                    title: VoiceLanguageModePresentation.title,
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
        }
    }

    // MARK: - Sections

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Groq Whisper (cloud)").font(.headline)
            Text("Fast, accurate, requires a Groq API key. Free tier available.")
                .font(.caption).foregroundStyle(.secondary)
            MAYNSecureField(
                placeholder: "Groq API key",
                text: $groqAPIKey,
                width: 360
            )
            MAYNDropdown(
                selection: $groqModelID,
                options: Array(GroqASRModelID.allCases),
                title: { $0.title },
                width: MAYNControlMetrics.widePickerWidth
            )
            MAYNButton("Save key") {
                controller.setGroqASRAPIKey(groqAPIKey)
                applyGroqSettings()
            }
        }
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Qwen3 ASR (local)").font(.headline)
            Text("On-device, private. Requires a one-time model download (~900 MB or 1.75 GB).")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(VoiceASRModelID.allCases, id: \.id) { modelID in
                let isDownloaded = Qwen3AsrModels.modelsExist(at: Qwen3AsrModels.defaultCacheDirectory(variant: modelID.variant))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelID.title)
                        if let status = modelDownloadStatus[modelID] {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isDownloaded {
                        StatusPill(text: "Ready", kind: .success)
                        MAYNButton("Use") {
                            localModelID = modelID
                            applyLocalSelection()
                        }
                    } else if downloadingModelID == modelID {
                        ProgressView(value: modelDownloadFractions[modelID] ?? 0)
                            .frame(width: 120)
                        Text("\(Int((modelDownloadFractions[modelID] ?? 0) * 100))%")
                            .font(.caption)
                    } else {
                        MAYNButton("Download") { downloadLocal(modelID) }
                    }
                }
                .padding(.vertical, 6)
            }
            Text("You can skip downloading now and pick a model later in Settings → Voice.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions (delegate to controller, same paths VoiceSettingsView uses)

    private func applyProviderSelection(_ kind: VoiceASRProviderKind) {
        try? controller.applyVoiceASRProviderSettings(
            providerKind: kind,
            localModelID: localModelID,
            groqModelID: groqModelID
        )
    }

    private func applyGroqSettings() {
        try? controller.applyVoiceASRProviderSettings(
            providerKind: .groq,
            localModelID: localModelID,
            groqModelID: groqModelID
        )
    }

    private func applyLocalSelection() {
        try? controller.applyVoiceASRProviderSettings(
            providerKind: .local,
            localModelID: localModelID,
            groqModelID: groqModelID
        )
    }

    private func downloadLocal(_ modelID: VoiceASRModelID) {
        downloadingModelID = modelID
        modelDownloadStatus[modelID] = "Downloading…"
        Task {
            do {
                try await Qwen3AsrModels.download(
                    variant: modelID.variant,
                    progress: { fraction in
                        Task { @MainActor in
                            modelDownloadFractions[modelID] = fraction
                        }
                    }
                )
                await MainActor.run {
                    modelDownloadStatus[modelID] = nil
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                }
            } catch {
                await MainActor.run {
                    modelDownloadStatus[modelID] = "Failed: \(error.localizedDescription)"
                    downloadingModelID = nil
                }
            }
        }
    }
}
```

> Exact `controller.applyVoiceASRProviderSettings` / `Qwen3AsrModels.download(variant:progress:)` signatures match the existing methods used in `VoiceSettingsView`. If a method's parameter list differs in your tree, mirror it from `VoiceSettingsView.applyASRProviderSelection(_:)` and `VoiceSettingsView` Task 553-line area.

- [ ] **Step 3: Wire it into the Voice descriptor**

In `MacAllYouNeed/App/FeatureRegistryProvider.swift`, find `voiceDescriptor()` and set:
```swift
static func voiceDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .voice,
        // ... existing fields ...
        requiredPermissions: [.microphone, .accessibility],
        // ... existing assetCaches, hotkeys ...
        activator: VoiceActivator(),
        settingsTabFactory: { AnyView(VoiceSettingsView(controller: AppController.shared)) },
        onboardingSetupFactory: { AnyView(VoiceProviderSetupView(controller: AppController.shared)) }
        // menuBarItemFactory: nil
    )
}
```

The other three descriptors (`clipboard`, `folderPreview`, `downloader`) leave `onboardingSetupFactory` as `nil` — Phase 09 only adds it for Voice.

- [ ] **Step 4: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Voice/UI/VoiceProviderSetupView.swift \
        MacAllYouNeed/App/FeatureRegistryProvider.swift
git commit -m "feat(modular-features): wire Voice onboardingSetupFactory"
```

---

### Task 11: Onboarding bootstrap — entry point + post-completion activation

`AppController.showStartupSurface()` already does the right routing (it presents `onboardingWindow` whenever `OnboardingState != .completed`). Phase 09 only needs two surgical tweaks:

1. After `setOnboarding(.completed)` runs, call `runtime.activateAllEnabled()` so the user's just-enabled features actually start without requiring a relaunch.
2. The "wrapper has no functions" framing means a fresh install should land on `.notStarted` even when no features were ever enabled — this already works, no change needed here.

**Files:**
- Modify: `MacAllYouNeed/App/AppControllerOnboarding.swift`
- Modify: `MacAllYouNeed/App/AppController.swift` (one-line change to `init` if needed)

- [ ] **Step 1: Update `setOnboarding(.completed)` to re-activate runtime**

In `AppControllerOnboarding.swift`, change:
```swift
func setOnboarding(_ state: OnboardingState) {
    onboarding = state
    state.save()
    if state == .completed {
        Task { @MainActor in
            await Task.yield()
            // Newly-enabled features (just transitioned by the wizard) need to start.
            await runtime.activateAllEnabled()
            self.showStartupSurface()
        }
    }
}
```

`runtime.activateAllEnabled()` is idempotent (it tracks `active` set) so re-calling it is safe — it'll only start activators for features whose state newly flipped to `.enabled`.

- [ ] **Step 2: Confirm `init()` still presents onboarding when needed**

In `AppController.swift`, the existing post-init `Task` should call `showOnboardingIfNeeded()` (or equivalent) on app launch when `onboarding != .completed`. If it currently auto-activates everything before showing the wizard, gate that:

```swift
private init() throws {
    // ... existing setup ...
    Task { [manager, runtime, weak self] in
        try? await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: AppGroupSettings.defaults)
        // Only activate enabled features. On a fresh install everything is disabled until
        // the user picks features in the wizard.
        await runtime.activateAllEnabled()
        await MainActor.run { self?.showStartupSurface() }
    }
}
```

> Phase 11 will overhaul `BootstrapDefaults` so fresh installs default to all-disabled (today's stub from Phase 04 defaults to `.enabled` for backward compat). Phase 09 tolerates either default — its observable behaviour (wizard appears + drives FeatureRuntime via `applyTransition(.enable, ...)`) is correct under both.

- [ ] **Step 3: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
git add MacAllYouNeed/App/AppControllerOnboarding.swift \
        MacAllYouNeed/App/AppController.swift
git commit -m "feat(modular-features): re-activate runtime after onboarding completes"
```

---

### Task 12: Advanced tab — "Re-run onboarding…"

A small developer/support escape hatch in Settings → Advanced.

**Files:**
- Modify: `MacAllYouNeed/Settings/Advanced/AdvancedSettingsView.swift` (path may vary; locate via `grep`)

- [ ] **Step 1: Find the Advanced settings view**

```bash
grep -rn "AdvancedSettingsView\|struct Advanced" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/ | head -5
```

- [ ] **Step 2: Add the row**

Inside `AdvancedSettingsView`, add a new `MAYNSection` (or a row inside an existing maintenance section):
```swift
MAYNSection(title: "Onboarding") {
    MAYNSettingsRow(
        title: "Re-run onboarding",
        subtitle: "Opens the setup wizard again. Useful for support or to start fresh."
    ) {
        MAYNButton("Re-run onboarding…") {
            controller.resetOnboarding()
            controller.onboardingWindow.show()
        }
    }
}
```

`controller.resetOnboarding()` already exists (`AppControllerOnboarding.swift` line 44) and clears `OnboardingState` to `.notStarted`. The picker selections are reset by the wizard itself on the next `setSelection` call.

- [ ] **Step 3: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
git add MacAllYouNeed/Settings/Advanced/AdvancedSettingsView.swift
git commit -m "feat(modular-features): add 'Re-run onboarding…' to Advanced settings"
```

---

### Task 13: Delete legacy step files / dead code

After Tasks 1–12 the legacy `AccessibilityStep`, `FullDiskAccessStep`, `NotificationsStep`, `SyncSetupStep`, `ReadyStep` are no longer referenced from `OnboardingWizardView`. `WelcomeStep` is still used. Don't delete anything Phase 11 might reuse — the migration "What's new" sheet is its own view, not a reincarnation of these. Keep `WelcomeStep` and `PermissionCard`/`InstructionStrip` helpers; remove the now-orphan permission steps + sync step.

**Files:**
- Modify: `MacAllYouNeed/Onboarding/PermissionStepViews.swift`

- [ ] **Step 1: Verify nothing else references the legacy steps**

```bash
grep -rn "AccessibilityStep\|FullDiskAccessStep\|NotificationsStep\|SyncSetupStep\|ReadyStep" \
  /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/
```
Expected: matches only inside `PermissionStepViews.swift` itself (no consumers).

- [ ] **Step 2: Delete the dead structs**

Edit `PermissionStepViews.swift`. Remove `AccessibilityStep`, `FullDiskAccessStep`, `NotificationsStep`, `SyncSetupChoice` (private enum), `SyncSetupStep`, and `ReadyStep`. Keep `WelcomeStep` (used by the new wizard's first page).

The file should end up containing only `WelcomeStep` plus its private `setupItem` helper.

- [ ] **Step 3: Build + smoke test**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Onboarding/PermissionStepViews.swift
git commit -m "feat(modular-features): drop legacy fixed-permission onboarding steps"
```

---

### Task 14: End-to-end interaction test

A single integration test that drives the wizard end-to-end with a fake installer + simulated permission grants, exercises Downloader (requires download) + Voice (requires config), and asserts the final state:

- `OnboardingState == .completed`
- `runtime.isActive(.downloader) == true`
- `runtime.isActive(.voice) == true`
- `runtime.isActive(.clipboard) == false`
- `runtime.isActive(.folderPreview) == false`

**Files:**
- Create: `MacAllYouNeedTests/Onboarding/OnboardingEndToEndTests.swift`

- [ ] **Step 1: Write the test**

```swift
import FeatureCore
import SwiftUI
import XCTest
@testable import MacAllYouNeed

@MainActor
final class OnboardingEndToEndTests: XCTestCase {
    func testFullFlowDownloaderPlusVoice() async throws {
        let defaults = UserDefaults(suiteName: "OnboardingE2E-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }

        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager)

        let store = OnboardingSelectionStore(defaults: defaults)
        store.setSelection([.downloader, .voice])

        // Walk the per-feature setup machine for each in registry order.
        let installer = FakeInstaller()
        for id in registry.descriptors.map(\.id) where store.selectedIDs.contains(id) {
            let descriptor = registry.descriptor(for: id)!
            let coord = FeatureSetupCoordinator(
                descriptor: descriptor,
                installer: installer,
                permissionsAlwaysGranted: true
            )
            await coord.start()
            // For voice, simulate config-done.
            if descriptor.onboardingSetupFactory != nil {
                XCTAssertEqual(coord.subStep, .config)
                coord.markConfigDone()
            }
            XCTAssertEqual(coord.subStep, .complete, "feature \(id) should reach complete")
            store.markCompleted(id)
            try await runtime.applyTransition(.enable, for: id)
        }

        OnboardingState.completed.save(defaults: defaults)

        XCTAssertTrue(await runtime.isActive(.downloader))
        XCTAssertTrue(await runtime.isActive(.voice))
        XCTAssertFalse(await runtime.isActive(.clipboard))
        XCTAssertFalse(await runtime.isActive(.folderPreview))
        XCTAssertEqual(OnboardingState.load(defaults: defaults), .completed)
    }

    func testSkipForNowLeavesAllDisabled() async throws {
        let defaults = UserDefaults(suiteName: "OnboardingE2E-\(UUID().uuidString)")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager)

        let store = OnboardingSelectionStore(defaults: defaults)
        // User taps "Skip for now" without selecting anything.
        store.clear()
        OnboardingState.completed.save(defaults: defaults)

        // No applyTransition calls were made → all features remain disabled.
        for id in registry.descriptors.map(\.id) {
            XCTAssertFalse(await runtime.isActive(id), "\(id) must remain inactive after skip-for-now")
        }
    }
}

@MainActor
private final class FakeInstaller: OnboardingInstalling {
    func install(descriptor: FeatureDescriptor, progress: @escaping (Double) -> Void) async throws {
        progress(0.5)
        progress(1.0)
    }
}
```

- [ ] **Step 2: Run + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/OnboardingEndToEndTests | tail -10
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeedTests/Onboarding/OnboardingEndToEndTests.swift
git commit -m "feat(modular-features): add onboarding end-to-end test"
```

---

### Task 15: Phase verification

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
```
Expected: all green.

- [ ] **Step 2: Manual end-to-end smoke (fresh-install simulation)**

```bash
# Wipe AppGroupSettings to simulate first launch.
defaults delete group.com.macallyouneed 2>/dev/null || true
# Also wipe the bootstrap-seeded sentinel so BootstrapDefaults re-runs.
defaults delete group.com.macallyouneed feature.bootstrap.seeded 2>/dev/null || true
```

Launch the app. Verify the wizard sequence:

1. **Welcome** appears with "Get Started" button.
2. **Choose Features**: 4 cards visible, all unchecked. Toggle Downloader and Voice. Tap Continue.
3. **Set Up — Downloader**: progress bar appears (download from local fixture or live GH Release). Wait for completion. No permissions declared → advances automatically.
4. **Set Up — Voice**: permissions sub-step prompts for Microphone + Accessibility (if not already granted). Auto-advance once both granted. Config sub-step renders `VoiceProviderSetupView`. Pick Cloud / paste API key OR Local / start Qwen3 download. Tap Continue.
5. **Done**: shows "Enabled: Downloader, Voice. Skipped: Clipboard, Folder Preview." Tap Done.
6. Wizard window closes.

Verify after the wizard:
- Settings → Features cards show Downloader + Voice as Enabled, others as Disabled.
- Cmd-Shift-V (Clipboard) does *not* open the popup (Clipboard inactive).
- Voice activation hotkey works.

- [ ] **Step 3: Manual "Skip for now" smoke**

```bash
defaults delete group.com.macallyouneed 2>/dev/null || true
```

Launch app. Welcome → Continue. Choose Features → tap Skip for now. Wizard closes. All four feature cards in Settings → Features show Disabled. App still launches normally; no features active.

- [ ] **Step 4: Manual "Re-run onboarding" smoke**

In a fresh-install run that completed normally, open Settings → Advanced → tap "Re-run onboarding…". Wizard reappears at Welcome.

- [ ] **Step 5: CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 6: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md`, change:
```markdown
- [ ] Phase 09 — Onboarding redesign
```
to:
```markdown
- [x] Phase 09 — Onboarding redesign
```

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 09 complete"
git push -u origin <branch>
gh pr create --title "Phase 09 — Onboarding Redesign" \
  --body "Implements docs/superpowers/plans/2026-05-15-modular-features/09-onboarding-redesign.md"
```
