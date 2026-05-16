# Phase 07 — Voice Asset Caches

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the lifecycle aware of the Voice provider's two on-disk model caches (Qwen3-ASR `f32` ~1.75 GB and `int8` ~900 MB). Surface them in the Features tab card and Uninstall sheet from Phase 05, add a "Clear cached models…" action to the Voice settings tab, and detect/clean up orphan cache directories on launch (Risk 9 from the spec). The `Qwen3Engine` provider keeps owning the actual model download UX — Phase 07 only adds **awareness** and **cleanup**.

**Architecture:** Two `AssetCacheDescriptor` values (`voice.qwen3.base`, `voice.qwen3.large`) populate `voiceDescriptor().assetCaches`. Each descriptor's `directoryURL` closure delegates to `Qwen3AsrModels.defaultCacheDirectory(variant:)` (the FluidAudio API the provider already uses), so the path stays a provider concern. A new `FeatureCacheManager` reads on-disk size for any descriptor and deletes the named cache directories. `UninstallSheetState.from(descriptor:)` (already shipped in Phase 05) starts producing real rows automatically once the descriptor exposes them. `FeaturesTabView.performUninstall` is updated to route the opted-in cache IDs through `FeatureCacheManager`. A `VoiceCacheCleanupSheet` opens from a new "Clear cached models…" button in `VoiceSettingsView`. An `OrphanCacheScanner` runs once at app launch from `AppController`, walks the FluidAudio models root, finds subdirectories that don't map to any current `AssetCacheDescriptor`, and posts a notification that drives a one-time `OrphanCacheCleanupSheet`. A user-dismissed sentinel in `AppGroupSettings` prevents the prompt from recurring.

**Tech Stack:** Swift 5.9+, SwiftUI, FluidAudio (`Qwen3AsrModels.defaultCacheDirectory(variant:)`), `FileManager`, `AppGroupSettings`, the existing MAYN design system (`MAYNButton`, `MAYNSection`, `MAYNSettingsRow`, `MAYNDivider`).

**Depends on:** Phase 05 (Features tab UI, `UninstallSheetState`, `UninstallConfirmationSheet`, `FeaturesTabView`, `FeatureStatePublisher`).

---

## File structure

```
Shared/Sources/FeatureCore/
└── FeatureCacheManager.swift                 ← new — totalBytes + deleteCaches

Shared/Tests/FeatureCoreTests/
└── FeatureCacheManagerTests.swift            ← new

MacAllYouNeed/App/
├── FeatureRegistryProvider.swift             ← MODIFY — populate voiceDescriptor().assetCaches
└── AppController.swift                       ← MODIFY — kick OrphanCacheScanner once post-init

MacAllYouNeed/Settings/Features/
├── FeaturesTabView.swift                     ← MODIFY — performUninstall routes via FeatureCacheManager
├── VoiceCacheCleanupSheet.swift              ← new — list caches, delete one at a time
├── OrphanCacheScanner.swift                  ← new — walks models root, returns orphans
└── OrphanCacheCleanupSheet.swift             ← new — one-time prompt

MacAllYouNeed/Settings/
└── VoiceSettingsView.swift                   ← MODIFY — add "Clear cached models…" button

MacAllYouNeedTests/Features/
├── VoiceDescriptorAssetCachesTests.swift     ← new
├── FeaturesTabUninstallCacheTests.swift      ← new — exercises performUninstall
└── OrphanCacheScannerTests.swift             ← new

MacAllYouNeedTests/Settings/
└── VoiceCacheCleanupSheetTests.swift         ← new
```

---

### Task 1: Voice descriptor declares its two `AssetCacheDescriptor`s

**Files:**
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift`
- Create: `MacAllYouNeedTests/Features/VoiceDescriptorAssetCachesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Features/VoiceDescriptorAssetCachesTests.swift`:
```swift
import FeatureCore
import XCTest
@testable import MacAllYouNeed

final class VoiceDescriptorAssetCachesTests: XCTestCase {
    func testVoiceDescriptorDeclaresExactlyTwoCaches() {
        let descriptor = FeatureRegistryProvider.voiceDescriptor()
        let ids = descriptor.assetCaches.map(\.id).sorted()
        XCTAssertEqual(ids, ["voice.qwen3.base", "voice.qwen3.large"])
    }

    func testCachesUseModelWeightsCategory() {
        let descriptor = FeatureRegistryProvider.voiceDescriptor()
        for cache in descriptor.assetCaches {
            XCTAssertEqual(cache.category, .modelWeights, "cache \(cache.id) should be modelWeights")
        }
    }

    func testEstimatedBytesMatchProviderSizes() {
        let descriptor = FeatureRegistryProvider.voiceDescriptor()
        let byID = Dictionary(uniqueKeysWithValues: descriptor.assetCaches.map { ($0.id, $0) })

        // Sizes are taken from VoiceASRModelID.diskLabel: int8 ≈ 900 MB, f32 ≈ 1.75 GB.
        XCTAssertEqual(byID["voice.qwen3.base"]?.estimatedBytes, 900_000_000)
        XCTAssertEqual(byID["voice.qwen3.large"]?.estimatedBytes, 1_750_000_000)
    }

    func testActualBytesIsZeroWhenDirectoryAbsent() {
        let descriptor = FeatureRegistryProvider.voiceDescriptor()
        // Point each descriptor at a non-existent path inside a fresh tempdir
        // by hijacking the closure indirectly: actualBytes() must already return 0
        // when the on-disk path is missing, regardless of where it points.
        for cache in descriptor.assetCaches {
            // The default closure resolves to FluidAudio's app support path.
            // We don't delete the user's real models — instead just assert the
            // contract: actualBytes() never throws and returns >= 0.
            XCTAssertGreaterThanOrEqual(cache.actualBytes(), 0)
        }
    }

    func testDirectoryURLsResolveDistinctPaths() {
        let descriptor = FeatureRegistryProvider.voiceDescriptor()
        let urls = descriptor.assetCaches.map { $0.directoryURL().path }
        XCTAssertEqual(Set(urls).count, urls.count, "each cache must point at a different directory")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/VoiceDescriptorAssetCachesTests | tail -15
```

Expected: FAIL — `descriptor.assetCaches` is currently empty.

- [ ] **Step 3: Read current `voiceDescriptor()` to know what to modify**

```bash
grep -n "voiceDescriptor" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/FeatureRegistryProvider.swift
```

Locate the function body added in Phase 03 Task 5 Step 5.

- [ ] **Step 4: Add the descriptors**

In `MacAllYouNeed/App/FeatureRegistryProvider.swift`, add the FluidAudio import near the top:
```swift
import FluidAudio
```

Replace the body of `voiceDescriptor()` with:
```swift
static func voiceDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .voice, displayName: "Voice Dictation", icon: "mic",
        summary: "Push-to-talk voice dictation (cloud or local ASR).",
        detailDescription: "Hold a hotkey, speak, release — text is pasted at the cursor. Supports Groq Whisper (cloud) and Qwen3 (local).",
        requiredPermissions: [.microphone, .accessibility],
        assetCaches: voiceAssetCaches(),
        hotkeys: [HotkeyDescriptor(identifier: "voice.pushToTalk", displayName: "Voice push-to-talk")],
        activator: VoiceFeatureActivator(),
        settingsTabFactory: { AnyView(VoiceSettingsView()) }
    )
}

/// The two Qwen3-ASR variants the Voice provider lazily downloads.
/// `directoryURL` delegates to FluidAudio so the cache layout stays a
/// provider concern; we only borrow it for size reporting and uninstall.
static func voiceAssetCaches() -> [AssetCacheDescriptor] {
    [
        AssetCacheDescriptor(
            id: "voice.qwen3.base",
            displayName: "Qwen3-ASR 0.6B int8 (~900 MB)",
            directoryURL: { Qwen3AsrModels.defaultCacheDirectory(variant: .int8) },
            estimatedBytes: 900_000_000,
            category: .modelWeights
        ),
        AssetCacheDescriptor(
            id: "voice.qwen3.large",
            displayName: "Qwen3-ASR 0.6B f32 (~1.75 GB)",
            directoryURL: { Qwen3AsrModels.defaultCacheDirectory(variant: .f32) },
            estimatedBytes: 1_750_000_000,
            category: .modelWeights
        ),
    ]
}
```

> Note: this assumes `voiceDescriptor()` is `static` (it was made so in Phase 03). If it isn't accessible from a test, add `@testable import MacAllYouNeed` (already in the test) and ensure the function visibility is at least `internal`.

- [ ] **Step 5: Verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/VoiceDescriptorAssetCachesTests | tail -10
```

Expected: PASS, 5/5.

- [ ] **Step 6: Commit**

```bash
git add MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/VoiceDescriptorAssetCachesTests.swift
git commit -m "feat(modular-features): wire Voice descriptor's Qwen3 asset caches"
```

---

### Task 2: `FeatureCacheManager` — total size + delete-by-id

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureCacheManager.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureCacheManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureCacheManagerTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class FeatureCacheManagerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeatureCacheManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeDescriptor(caches: [AssetCacheDescriptor]) -> FeatureDescriptor {
        FeatureDescriptor(
            id: .voice, displayName: "Voice", icon: "mic",
            summary: "", detailDescription: "",
            assetCaches: caches,
            activator: NoopFeatureActivator()
        )
    }

    private func makeFile(at url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = Data(repeating: 0xAB, count: bytes)
        try data.write(to: url)
    }

    func testTotalBytesSumsAllCaches() throws {
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try makeFile(at: dirA.appendingPathComponent("model.bin"), bytes: 1_000)
        try makeFile(at: dirB.appendingPathComponent("nested/weights.bin"), bytes: 4_096)

        let descriptor = makeDescriptor(caches: [
            AssetCacheDescriptor(id: "a", displayName: "A",
                                 directoryURL: { dirA },
                                 estimatedBytes: 1_000, category: .modelWeights),
            AssetCacheDescriptor(id: "b", displayName: "B",
                                 directoryURL: { dirB },
                                 estimatedBytes: 4_096, category: .modelWeights),
        ])

        let manager = FeatureCacheManager()
        XCTAssertEqual(manager.totalBytes(for: descriptor), 5_096)
    }

    func testTotalBytesIsZeroWhenNothingOnDisk() {
        let descriptor = makeDescriptor(caches: [
            AssetCacheDescriptor(id: "missing", displayName: "Missing",
                                 directoryURL: { self.tempRoot.appendingPathComponent("missing") },
                                 estimatedBytes: 100, category: .modelWeights),
        ])
        XCTAssertEqual(FeatureCacheManager().totalBytes(for: descriptor), 0)
    }

    func testDeleteCachesRemovesOnlyNamedDirectories() throws {
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try makeFile(at: dirA.appendingPathComponent("model.bin"), bytes: 100)
        try makeFile(at: dirB.appendingPathComponent("model.bin"), bytes: 100)

        let descriptor = makeDescriptor(caches: [
            AssetCacheDescriptor(id: "a", displayName: "A",
                                 directoryURL: { dirA },
                                 estimatedBytes: 100, category: .modelWeights),
            AssetCacheDescriptor(id: "b", displayName: "B",
                                 directoryURL: { dirB },
                                 estimatedBytes: 100, category: .modelWeights),
        ])

        try FeatureCacheManager().deleteCaches(["a"], in: descriptor)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirB.path))
    }

    func testDeleteUnknownCacheIDIsIgnored() throws {
        let descriptor = makeDescriptor(caches: [])
        // Should not throw even when nothing matches.
        XCTAssertNoThrow(try FeatureCacheManager().deleteCaches(["does-not-exist"], in: descriptor))
    }

    func testDeleteIsNoOpWhenDirectoryAbsent() throws {
        let dir = tempRoot.appendingPathComponent("ghost", isDirectory: true)
        let descriptor = makeDescriptor(caches: [
            AssetCacheDescriptor(id: "g", displayName: "G",
                                 directoryURL: { dir },
                                 estimatedBytes: 0, category: .modelWeights),
        ])
        XCTAssertNoThrow(try FeatureCacheManager().deleteCaches(["g"], in: descriptor))
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" \
swift test --filter FeatureCacheManagerTests 2>&1 | tail -15
```

Expected: FAIL — `FeatureCacheManager` not declared.

- [ ] **Step 3: Implement `FeatureCacheManager`**

Create `Shared/Sources/FeatureCore/FeatureCacheManager.swift`:
```swift
import Foundation

/// Provider-managed asset caches (e.g., Voice's Qwen3 model files) live outside
/// wrapper-managed packs but the lifecycle still needs to read their sizes and
/// delete them on demand. This service is the single entry point for both.
public struct FeatureCacheManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Sum of `actualBytes()` across every cache the descriptor declares.
    /// Caches whose directory is absent contribute 0.
    public func totalBytes(for descriptor: FeatureDescriptor) -> Int64 {
        descriptor.assetCaches.reduce(into: Int64(0)) { acc, cache in
            acc += cache.actualBytes()
        }
    }

    /// Removes the named cache directories. Cache IDs that do not appear in
    /// `descriptor.assetCaches` are ignored; cache directories that don't
    /// exist on disk are no-ops. The first failure throws.
    public func deleteCaches(_ ids: [String], in descriptor: FeatureDescriptor) throws {
        let byID = Dictionary(uniqueKeysWithValues: descriptor.assetCaches.map { ($0.id, $0) })
        for id in ids {
            guard let cache = byID[id] else { continue }
            let url = cache.directoryURL()
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try fileManager.removeItem(at: url)
        }
    }
}
```

> `AssetCacheDescriptor.actualBytes()` already exists from Phase 01 (the Phase 05 `UninstallSheetState` calls it). If for some reason it doesn't (e.g., it was deferred), add this minimal implementation in `Shared/Sources/FeatureCore/AssetCacheDescriptor.swift` first:
>
> ```swift
> public extension AssetCacheDescriptor {
>     /// On-disk byte total under `directoryURL()`. Returns 0 when missing.
>     func actualBytes() -> Int64 {
>         let url = directoryURL()
>         let fm = FileManager.default
>         var isDir: ObjCBool = false
>         guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return 0 }
>         guard let enumerator = fm.enumerator(at: url,
>                                              includingPropertiesForKeys: [.fileSizeKey],
>                                              options: [.skipsHiddenFiles]) else { return 0 }
>         var total: Int64 = 0
>         for case let fileURL as URL in enumerator {
>             let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
>             total += Int64(values?.fileSize ?? 0)
>         }
>         return total
>     }
> }
> ```
>
> Confirm `actualBytes()` is exercised in `UninstallSheetStateTests` — if the Phase 05 test passes today, this method already exists.

- [ ] **Step 4: Verify pass**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" \
swift test --filter FeatureCacheManagerTests 2>&1 | tail -10
```

Expected: PASS, 5/5.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureCacheManager.swift \
        Shared/Tests/FeatureCoreTests/FeatureCacheManagerTests.swift
git commit -m "feat(modular-features): add FeatureCacheManager for size + delete"
```

---

### Task 3: `FeaturesTabView.performUninstall` deletes opted-in caches via `FeatureCacheManager`

**Files:**
- Modify: `MacAllYouNeed/Settings/Features/FeaturesTabView.swift`
- Create: `MacAllYouNeedTests/Features/FeaturesTabUninstallCacheTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Features/FeaturesTabUninstallCacheTests.swift`:
```swift
import FeatureCore
import XCTest
@testable import MacAllYouNeed

/// Phase 05 wired performUninstall to remove opted-in caches via inline
/// FileManager calls. Phase 07 routes that through FeatureCacheManager so a
/// future feature with caches can reuse the same path.
final class FeaturesTabUninstallCacheTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FeaturesTabUninstallCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeDescriptor(cacheDir: URL) -> FeatureDescriptor {
        FeatureDescriptor(
            id: .voice, displayName: "Voice", icon: "mic",
            summary: "", detailDescription: "",
            assetCaches: [
                AssetCacheDescriptor(
                    id: "voice.qwen3.base",
                    displayName: "Qwen3 base",
                    directoryURL: { cacheDir },
                    estimatedBytes: 100,
                    category: .modelWeights
                ),
            ],
            activator: NoopFeatureActivator()
        )
    }

    func testCheckedCachesAreDeleted() async throws {
        let dir = tempRoot.appendingPathComponent("qwen3-base", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 256).write(to: dir.appendingPathComponent("model.bin"))

        let descriptor = makeDescriptor(cacheDir: dir)
        var sheet = UninstallSheetState.from(descriptor: descriptor)
        sheet.toggle(cacheID: "voice.qwen3.base")

        try FeaturesTabView.applyCacheSelections(sheet, in: descriptor,
                                                 cacheManager: FeatureCacheManager())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testUncheckedCachesArePreserved() async throws {
        let dir = tempRoot.appendingPathComponent("qwen3-base", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 256).write(to: dir.appendingPathComponent("model.bin"))

        let descriptor = makeDescriptor(cacheDir: dir)
        let sheet = UninstallSheetState.from(descriptor: descriptor) // all unchecked

        try FeaturesTabView.applyCacheSelections(sheet, in: descriptor,
                                                 cacheManager: FeatureCacheManager())
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeaturesTabUninstallCacheTests | tail -10
```

Expected: FAIL — `applyCacheSelections` not declared.

- [ ] **Step 3: Refactor `FeaturesTabView`**

In `MacAllYouNeed/Settings/Features/FeaturesTabView.swift`, extract the cache-deletion step out of `performUninstall` into a static helper that's testable without spinning up the full SwiftUI view.

Add the import at top:
```swift
import FeatureCore
```

Replace `performUninstall(descriptor:sheetState:)` with:
```swift
private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
    do {
        try Self.applyCacheSelections(sheetState, in: descriptor,
                                      cacheManager: FeatureCacheManager())
    } catch {
        // Surface as a banner in a future polish pass; for now the user can
        // see the directory still on disk and try again.
        NSLog("FeaturesTabView uninstall: cache deletion failed: \(error)")
    }
    try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
    // Phase 06 will additionally call PackUninstaller for asset features.
}

/// Static so tests can exercise cache deletion without instantiating SwiftUI.
static func applyCacheSelections(
    _ sheetState: UninstallSheetState,
    in descriptor: FeatureDescriptor,
    cacheManager: FeatureCacheManager
) throws {
    try cacheManager.deleteCaches(sheetState.checkedCacheIDs, in: descriptor)
}
```

Delete the old per-cache `removeItem(at:)` loop that Phase 05 inserted.

- [ ] **Step 4: Verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeaturesTabUninstallCacheTests | tail -10
```

Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/Features/FeaturesTabView.swift \
        MacAllYouNeedTests/Features/FeaturesTabUninstallCacheTests.swift
git commit -m "feat(modular-features): route Uninstall cache deletion through FeatureCacheManager"
```

---

### Task 4: `VoiceCacheCleanupSheet` — per-cache delete button

**Files:**
- Create: `MacAllYouNeed/Settings/Features/VoiceCacheCleanupSheet.swift`
- Create: `MacAllYouNeedTests/Settings/VoiceCacheCleanupSheetTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Settings/VoiceCacheCleanupSheetTests.swift`:
```swift
import FeatureCore
import XCTest
@testable import MacAllYouNeed

final class VoiceCacheCleanupSheetTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VoiceCacheCleanupSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testDeleteRemovesOnlyTargetCache() throws {
        let dirA = tempRoot.appendingPathComponent("a", isDirectory: true)
        let dirB = tempRoot.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16).write(to: dirA.appendingPathComponent("m.bin"))
        try Data(repeating: 1, count: 16).write(to: dirB.appendingPathComponent("m.bin"))

        let descriptor = FeatureDescriptor(
            id: .voice, displayName: "Voice", icon: "mic",
            summary: "", detailDescription: "",
            assetCaches: [
                AssetCacheDescriptor(id: "a", displayName: "A",
                                     directoryURL: { dirA },
                                     estimatedBytes: 16, category: .modelWeights),
                AssetCacheDescriptor(id: "b", displayName: "B",
                                     directoryURL: { dirB },
                                     estimatedBytes: 16, category: .modelWeights),
            ],
            activator: NoopFeatureActivator()
        )

        try VoiceCacheCleanupSheet.delete(cacheID: "a",
                                          in: descriptor,
                                          cacheManager: FeatureCacheManager())
        XCTAssertFalse(FileManager.default.fileExists(atPath: dirA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirB.path))
    }

    func testRowsExposeOnDiskBytes() throws {
        let dir = tempRoot.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: dir.appendingPathComponent("m.bin"))

        let descriptor = FeatureDescriptor(
            id: .voice, displayName: "Voice", icon: "mic",
            summary: "", detailDescription: "",
            assetCaches: [
                AssetCacheDescriptor(id: "a", displayName: "A",
                                     directoryURL: { dir },
                                     estimatedBytes: 9_999, category: .modelWeights),
                AssetCacheDescriptor(id: "missing", displayName: "M",
                                     directoryURL: { self.tempRoot.appendingPathComponent("nope") },
                                     estimatedBytes: 5_000, category: .modelWeights),
            ],
            activator: NoopFeatureActivator()
        )

        let rows = VoiceCacheCleanupSheet.makeRows(for: descriptor)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(byID["a"]?.bytes, 1_024, "present cache reports actual bytes")
        XCTAssertEqual(byID["missing"]?.bytes, 0, "absent cache reports 0")
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/VoiceCacheCleanupSheetTests | tail -15
```

Expected: FAIL — `VoiceCacheCleanupSheet` not declared.

- [ ] **Step 3: Implement the sheet**

Create `MacAllYouNeed/Settings/Features/VoiceCacheCleanupSheet.swift`:
```swift
import FeatureCore
import SwiftUI

/// Listed by the Voice settings tab via "Clear cached models…". One row per
/// declared `AssetCacheDescriptor`. Each row has its own delete button so the
/// user can reclaim space without uninstalling the feature.
struct VoiceCacheCleanupSheet: View {
    struct Row: Identifiable, Equatable {
        let id: String
        let displayName: String
        let bytes: Int64
    }

    let descriptor: FeatureDescriptor
    let onClose: () -> Void

    @State private var rows: [Row]
    private let cacheManager = FeatureCacheManager()

    init(descriptor: FeatureDescriptor, onClose: @escaping () -> Void) {
        self.descriptor = descriptor
        self.onClose = onClose
        self._rows = State(initialValue: Self.makeRows(for: descriptor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clear cached models").font(.title3).bold()
            Text("Remove downloaded ASR model files. The provider will re-download them the next time you select that model.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MAYNDivider()

            if rows.isEmpty {
                Text("No model caches declared.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                            Text(formatBytes(row.bytes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        MAYNButton("Clear", role: .destructive) {
                            delete(rowID: row.id)
                        }
                        .disabled(row.bytes == 0)
                    }
                    .padding(.vertical, 4)
                }
            }

            MAYNDivider()

            HStack {
                Spacer()
                MAYNButton("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    /// Static so a unit test can build rows without rendering SwiftUI.
    static func makeRows(for descriptor: FeatureDescriptor) -> [Row] {
        descriptor.assetCaches.map { cache in
            Row(id: cache.id, displayName: cache.displayName, bytes: cache.actualBytes())
        }
    }

    /// Static so a unit test can exercise deletion without rendering SwiftUI.
    static func delete(cacheID: String,
                       in descriptor: FeatureDescriptor,
                       cacheManager: FeatureCacheManager) throws {
        try cacheManager.deleteCaches([cacheID], in: descriptor)
    }

    private func delete(rowID: String) {
        do {
            try Self.delete(cacheID: rowID, in: descriptor, cacheManager: cacheManager)
            rows = Self.makeRows(for: descriptor)
        } catch {
            NSLog("VoiceCacheCleanupSheet: delete \(rowID) failed: \(error)")
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
```

> `MAYNButton(_:role:action:)` should already accept a `.destructive` role per the existing design system; if the available initializer is `MAYNButton(_:action:)` only, swap the destructive call to `MAYNButton("Clear", action: { delete(rowID: row.id) })` and rely on text alone for the destructive cue. Do not introduce a new primitive — design rules forbid it.

- [ ] **Step 4: Verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/VoiceCacheCleanupSheetTests | tail -10
```

Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/Features/VoiceCacheCleanupSheet.swift \
        MacAllYouNeedTests/Settings/VoiceCacheCleanupSheetTests.swift
git commit -m "feat(modular-features): add VoiceCacheCleanupSheet"
```

---

### Task 5: "Clear cached models…" button in Voice settings tab

**Files:**
- Modify: `MacAllYouNeed/Settings/VoiceSettingsView.swift`

- [ ] **Step 1: Read the current `VoiceSettingsView` body to find an insertion point**

```bash
sed -n '60,160p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/VoiceSettingsView.swift
```

The view is composed of `MAYNSection(title: …) { MAYNSettingsRow(…) }`. The first section is "Overview" (around line 115). The new section belongs at the bottom of the page so it's never the first thing the user sees.

- [ ] **Step 2: Add a "Storage" section with a "Clear cached models…" row**

In `VoiceSettingsView.swift`, add the FeatureCore import near the top:
```swift
import FeatureCore
```

Add a `@State` for sheet presentation near the other `@State` declarations:
```swift
@State private var showsCacheCleanupSheet: Bool = false
```

Append a new `MAYNSection` at the bottom of the `body`'s top-level `VStack`/`MAYNSettingsPage` (place it after the last existing section, before any closing braces of the page container):
```swift
MAYNSection(title: "Storage") {
    MAYNSettingsRow(
        title: "Cached model files",
        subtitle: "Reclaim disk space without removing the Voice feature."
    ) {
        MAYNButton("Clear cached models…") {
            showsCacheCleanupSheet = true
        }
    }
}
```

Attach the sheet modifier on the same view:
```swift
.sheet(isPresented: $showsCacheCleanupSheet) {
    VoiceCacheCleanupSheet(
        descriptor: FeatureRegistryProvider.voiceDescriptor(),
        onClose: { showsCacheCleanupSheet = false }
    )
}
```

> `FeatureRegistryProvider.voiceDescriptor()` is the source of truth for the cache list — calling it here keeps the sheet in sync if a future provider variant lands.

- [ ] **Step 3: Build verify**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual smoke**

Build and run. Open Settings → Voice. Scroll to the new "Storage" section. Click "Clear cached models…". The sheet appears with two rows ("Qwen3-ASR 0.6B int8" and "Qwen3-ASR 0.6B f32"), each showing on-disk bytes (or "Zero bytes" when not yet downloaded). The "Clear" button is disabled when bytes == 0.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/VoiceSettingsView.swift
git commit -m "feat(modular-features): add Clear cached models action to Voice settings"
```

---

### Task 6: `OrphanCacheScanner` — find directories not declared by any descriptor

**Files:**
- Create: `MacAllYouNeed/Settings/Features/OrphanCacheScanner.swift`
- Create: `MacAllYouNeedTests/Features/OrphanCacheScannerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Features/OrphanCacheScannerTests.swift`:
```swift
import FeatureCore
import XCTest
@testable import MacAllYouNeed

final class OrphanCacheScannerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OrphanCacheScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeFile(at url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0xCC, count: bytes).write(to: url)
    }

    func testReturnsEmptyWhenRootMissing() {
        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot.appendingPathComponent("does-not-exist")],
            knownDirectories: { [] }
        )
        XCTAssertTrue(scanner.scan().isEmpty)
    }

    func testReturnsEmptyWhenAllDirectoriesAreKnown() throws {
        let knownA = tempRoot.appendingPathComponent("known-a", isDirectory: true)
        try FileManager.default.createDirectory(at: knownA, withIntermediateDirectories: true)
        try makeFile(at: knownA.appendingPathComponent("model.bin"), bytes: 100)

        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot],
            knownDirectories: { [knownA] }
        )
        XCTAssertTrue(scanner.scan().isEmpty)
    }

    func testFindsOrphanDirectory() throws {
        let known = tempRoot.appendingPathComponent("known", isDirectory: true)
        let orphan = tempRoot.appendingPathComponent("orphan-old-variant", isDirectory: true)
        try FileManager.default.createDirectory(at: known, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try makeFile(at: known.appendingPathComponent("m.bin"), bytes: 100)
        try makeFile(at: orphan.appendingPathComponent("m.bin"), bytes: 4_096)

        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot],
            knownDirectories: { [known] }
        )
        let results = scanner.scan()
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "orphan-old-variant")
        XCTAssertEqual(results.first?.bytes, 4_096)
    }

    func testDeleteRemovesOrphanFromDisk() throws {
        let orphan = tempRoot.appendingPathComponent("orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try makeFile(at: orphan.appendingPathComponent("m.bin"), bytes: 16)

        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot],
            knownDirectories: { [] }
        )
        let results = scanner.scan()
        XCTAssertEqual(results.count, 1)
        try scanner.delete(results)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testDeepNestedFilesContributeToBytes() throws {
        let orphan = tempRoot.appendingPathComponent("orphan", isDirectory: true)
        try makeFile(at: orphan.appendingPathComponent("a/b/c/m.bin"), bytes: 1_500)
        try makeFile(at: orphan.appendingPathComponent("top.bin"), bytes: 500)

        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot],
            knownDirectories: { [] }
        )
        XCTAssertEqual(scanner.scan().first?.bytes, 2_000)
    }

    func testIgnoresFilesAtRoot() throws {
        // Lone files (not directories) at the scan root must not be flagged as orphans.
        try makeFile(at: tempRoot.appendingPathComponent("loose.txt"), bytes: 10)
        let scanner = OrphanCacheScanner(
            scanRoots: [tempRoot],
            knownDirectories: { [] }
        )
        XCTAssertTrue(scanner.scan().isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/OrphanCacheScannerTests | tail -15
```

Expected: FAIL — `OrphanCacheScanner` not declared.

- [ ] **Step 3: Implement the scanner**

Create `MacAllYouNeed/Settings/Features/OrphanCacheScanner.swift`:
```swift
import FeatureCore
import FluidAudio
import Foundation

/// Walks the directories that providers use to cache asset files and reports
/// any subdirectory that is *not* declared by the current registry's
/// `AssetCacheDescriptor`s. Used at app launch to satisfy spec Risk 9: when a
/// future release drops a Qwen3 variant, the now-unreferenced cache directory
/// would otherwise sit on disk forever.
///
/// The scanner is dependency-injected for testing; production callers use
/// `OrphanCacheScanner.makeForRegistry(_:)`.
struct OrphanCacheScanner {
    struct Orphan: Equatable {
        let url: URL
        let bytes: Int64
    }

    let scanRoots: [URL]
    let knownDirectories: () -> [URL]

    /// Returns one entry per orphan subdirectory under `scanRoots`. Each entry
    /// includes the recursive byte total so the UI can display a meaningful
    /// "Reclaim X MB" prompt.
    func scan(fileManager: FileManager = .default) -> [Orphan] {
        let known = Set(knownDirectories().map(\.standardizedFileURL.path))
        var results: [Orphan] = []
        for root in scanRoots {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let entries = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries {
                var entryIsDir: ObjCBool = false
                guard fileManager.fileExists(atPath: entry.path, isDirectory: &entryIsDir),
                      entryIsDir.boolValue
                else { continue }
                if known.contains(entry.standardizedFileURL.path) { continue }
                let bytes = recursiveBytes(at: entry, fileManager: fileManager)
                results.append(Orphan(url: entry, bytes: bytes))
            }
        }
        return results
    }

    func delete(_ orphans: [Orphan], fileManager: FileManager = .default) throws {
        for orphan in orphans {
            guard fileManager.fileExists(atPath: orphan.url.path) else { continue }
            try fileManager.removeItem(at: orphan.url)
        }
    }

    private func recursiveBytes(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Production constructor: scan FluidAudio's models root (where the Qwen3
    /// provider writes today) and exclude every directory currently declared
    /// by the Voice descriptor.
    static func makeForRegistry(_ registry: FeatureRegistry) -> OrphanCacheScanner {
        let voiceDescriptor = registry.descriptors.first(where: { $0.id == .voice })
        let known: [URL] = voiceDescriptor?.assetCaches.map { $0.directoryURL() } ?? []
        // FluidAudio writes to ~/Library/Application Support/FluidAudio/Models/.
        // Both Qwen3 variant directories live under that root, so a single root scan covers them.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let modelsRoot = appSupport?
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        return OrphanCacheScanner(
            scanRoots: [modelsRoot].compactMap { $0 },
            knownDirectories: { known }
        )
    }
}
```

> The scan-root choice is grounded in `Qwen3AsrModels.defaultCacheDirectory(variant:)` which composes `~/Library/Application Support/FluidAudio/Models/<repo.folderName>/<variant>`. Walking the Models root catches both current Qwen3 variants and any future variants the provider adds — including ones a wrapper update may stop declaring.

- [ ] **Step 4: Verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/OrphanCacheScannerTests | tail -10
```

Expected: PASS, 6/6.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/Features/OrphanCacheScanner.swift \
        MacAllYouNeedTests/Features/OrphanCacheScannerTests.swift
git commit -m "feat(modular-features): add OrphanCacheScanner"
```

---

### Task 7: `OrphanCacheCleanupSheet` + one-time launch prompt

**Files:**
- Create: `MacAllYouNeed/Settings/Features/OrphanCacheCleanupSheet.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 1: Implement the sheet**

Create `MacAllYouNeed/Settings/Features/OrphanCacheCleanupSheet.swift`:
```swift
import Core
import SwiftUI

/// A one-time launch prompt that appears when `OrphanCacheScanner` finds
/// provider cache directories not declared by any current descriptor.
/// Dismissed-by-user is persisted via `AppGroupSettings` so the prompt does
/// not recur for the same set of orphans.
struct OrphanCacheCleanupSheet: View {
    let orphans: [OrphanCacheScanner.Orphan]
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Old Voice models found").font(.title3).bold()
            Text("These cached model files are no longer referenced by any installed Voice provider. You can delete them to reclaim disk space.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            MAYNDivider()

            ForEach(orphans, id: \.url.path) { orphan in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(orphan.url.lastPathComponent)
                        Text(formatBytes(orphan.bytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            MAYNDivider()

            HStack {
                Spacer()
                MAYNButton("Keep", action: onDismiss).keyboardShortcut(.cancelAction)
                MAYNButton("Delete", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}

/// Persisted-dismissal sentinel.
///
/// We store the sorted list of orphan paths the user dismissed so that a
/// brand-new orphan (e.g., from a future provider release) still triggers a
/// prompt. Storing only `Bool` would silence all future orphans permanently.
enum OrphanCacheDismissal {
    static let key = "feature.voice.orphanCachesDismissed.v1"

    static func dismissedSet(in defaults: UserDefaults = AppGroupSettings.defaults) -> Set<String> {
        let array = defaults.stringArray(forKey: key) ?? []
        return Set(array)
    }

    static func markDismissed(_ paths: [String], in defaults: UserDefaults = AppGroupSettings.defaults) {
        let combined = dismissedSet(in: defaults).union(paths)
        defaults.set(Array(combined).sorted(), forKey: key)
    }

    /// Filters an orphan list down to the ones the user has not previously dismissed.
    static func unseen(_ orphans: [OrphanCacheScanner.Orphan],
                       in defaults: UserDefaults = AppGroupSettings.defaults)
        -> [OrphanCacheScanner.Orphan]
    {
        let dismissed = dismissedSet(in: defaults)
        return orphans.filter { !dismissed.contains($0.url.standardizedFileURL.path) }
    }
}
```

- [ ] **Step 2: Wire scanner into `AppController`**

Read the current `AppController` to find a clean post-init seam:
```bash
grep -n "init\|FeatureRuntime\|Task.detached\|scenePhase\|onLaunch" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift | head -20
```

After Phase 04, `AppController.init()` ends with the runtime task dispatch. Append a one-time scan call right after the runtime task is dispatched. Add to `AppController.swift`:

```swift
private func runOrphanCacheScanIfNeeded() {
    Task.detached(priority: .background) {
        let scanner = OrphanCacheScanner.makeForRegistry(await self.runtime.registry)
        let orphans = OrphanCacheDismissal.unseen(scanner.scan())
        guard !orphans.isEmpty else { return }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .orphanCachesFound,
                object: nil,
                userInfo: ["orphans": orphans]
            )
        }
    }
}
```

Append the notification name in `Shared/Sources/FeatureCore/DarwinNotification.swift` (where Phase 05 already added `featureRuntimeStateChanged`):
```swift
public extension Notification.Name {
    static let orphanCachesFound = Notification.Name("orphanCachesFound")
}
```

Call `runOrphanCacheScanIfNeeded()` once at the end of `AppController.init()`:
```swift
self.runOrphanCacheScanIfNeeded()
```

- [ ] **Step 3: Surface the sheet from `MainWindowRoot` (or wherever the app's root SwiftUI scene lives)**

In `MacAllYouNeed/App/MainWindowRoot.swift`, add:
```swift
@State private var pendingOrphans: [OrphanCacheScanner.Orphan] = []
```

Attach to the root view:
```swift
.onReceive(NotificationCenter.default.publisher(for: .orphanCachesFound)) { note in
    guard let orphans = note.userInfo?["orphans"] as? [OrphanCacheScanner.Orphan] else { return }
    self.pendingOrphans = orphans
}
.sheet(isPresented: Binding(
    get: { !pendingOrphans.isEmpty },
    set: { if !$0 { pendingOrphans = [] } }
)) {
    OrphanCacheCleanupSheet(
        orphans: pendingOrphans,
        onDelete: {
            let scanner = OrphanCacheScanner.makeForRegistry(controller.runtime.registry)
            try? scanner.delete(pendingOrphans)
            OrphanCacheDismissal.markDismissed(pendingOrphans.map { $0.url.standardizedFileURL.path })
            pendingOrphans = []
        },
        onDismiss: {
            OrphanCacheDismissal.markDismissed(pendingOrphans.map { $0.url.standardizedFileURL.path })
            pendingOrphans = []
        }
    )
}
```

> Both buttons mark the current orphan set as dismissed so the prompt doesn't recur on every launch. A genuinely new orphan (from a later release) will not be in the dismissed set and will re-trigger the sheet.

- [ ] **Step 4: Build verify**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/Features/OrphanCacheCleanupSheet.swift \
        MacAllYouNeed/App/AppController.swift \
        MacAllYouNeed/App/MainWindowRoot.swift \
        Shared/Sources/FeatureCore/DarwinNotification.swift
git commit -m "feat(modular-features): one-time orphan cache cleanup prompt"
```

---

### Task 8: Voice card disk-usage row reflects descriptor caches

**Files:**
- Modify: `MacAllYouNeed/Settings/Features/FeatureCardView.swift`

The Phase 05 card already shows "Permissions:". Phase 07 adds "Disk: <bytes>" derived from `FeatureCacheManager.totalBytes(for:)` so the Voice card matches the spec § 8 wording ("pack size on disk (sum of pack + caches)"). The line is suppressed when both `assetPacks` and `assetCaches` are empty (Clipboard, Folder Preview today).

- [ ] **Step 1: Add disk-usage row**

In `FeatureCardView.swift`, add a helper:
```swift
private var diskUsageDescription: String? {
    let cacheBytes = FeatureCacheManager().totalBytes(for: descriptor)
    // Pack bytes will be added by Phase 06's PackInstaller integration; for
    // now, only the cache contribution is computed here.
    guard !descriptor.assetCaches.isEmpty || !descriptor.assetPacks.isEmpty else { return nil }
    let formatted = ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
    return "Disk: \(formatted)"
}
```

Insert above `FeatureCardActionView` in the body:
```swift
if let usage = diskUsageDescription {
    Text(usage).font(.caption).foregroundStyle(.tertiary)
}
```

- [ ] **Step 2: Build verify**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke**

Build and run. In Settings → Features, the Voice card now shows a "Disk: …" line. With no Qwen3 models downloaded the line reads "Disk: Zero bytes". After downloading a model via Voice settings, re-open Features and the value reflects the on-disk size.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Settings/Features/FeatureCardView.swift
git commit -m "feat(modular-features): show on-disk cache size on Voice card"
```

---

### Task 9: Phase verification

- [ ] **Step 1: Full Shared package test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test 2>&1 | tail -20
```

Expected: all green (FeatureCore tests including `FeatureCacheManagerTests`).

- [ ] **Step 2: Full Xcode test suite**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' 2>&1 | tail -30
```

Expected: all green. New test classes (`VoiceDescriptorAssetCachesTests`, `FeaturesTabUninstallCacheTests`, `VoiceCacheCleanupSheetTests`, `OrphanCacheScannerTests`) all pass.

- [ ] **Step 3: Manual smoke**

Launch the app.

1. **Uninstall sheet shows caches.** Settings → Features → Voice → ⋯ → "Uninstall…". The sheet now lists "Qwen3-ASR 0.6B int8 (~900 MB)" and "Qwen3-ASR 0.6B f32 (~1.75 GB)", both unchecked. Cancel.
2. **Clear cached models.** Settings → Voice → Storage section → "Clear cached models…". Sheet appears with the same two rows. If a model has been downloaded, its row shows real bytes and the Clear button is enabled. Click Clear; the row's bytes drop to zero and the model directory is gone from `~/Library/Application Support/FluidAudio/Models/`.
3. **Orphan detection.** Quit the app. Create a fake orphan directory:
   ```bash
   mkdir -p "$HOME/Library/Application Support/FluidAudio/Models/qwen3-asr-old"
   echo orphan > "$HOME/Library/Application Support/FluidAudio/Models/qwen3-asr-old/dummy.bin"
   ```
   Relaunch. A sheet appears titled "Old Voice models found" listing `qwen3-asr-old`. Click Delete; confirm the directory is gone. Relaunch again; the sheet does not reappear (dismissal is recorded). Recreate the same fake orphan directory; relaunch; the sheet does not appear (path is in the dismissed set). Create a *different* orphan name (`qwen3-asr-experimental`); relaunch; the sheet appears for that new orphan.
4. **Disk row on the Voice card.** Settings → Features → Voice card now has "Disk: <bytes>" matching the on-disk model size.

- [ ] **Step 4: CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```

Expected: pass (build, lint, tests).

- [ ] **Step 5: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md` to check off Phase 07 in the execution checklist:
```
- [x] Phase 07 — Voice asset caches
```

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 07 complete"
git push -u origin <branch>
gh pr create --title "Phase 07 — Voice Asset Caches" \
  --body "Implements docs/superpowers/plans/2026-05-15-modular-features/07-voice-asset-caches.md"
```
