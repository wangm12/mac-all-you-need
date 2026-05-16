# Phase 03 — Feature Activators

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **The four activator tasks (Tasks 2–5) are mutually independent and SHOULD be dispatched as parallel sub-agents** after Task 1 (the shared protocol scaffolding) lands.

**Goal:** Wrap each of the four existing subsystems (Clipboard, Folder Preview, Downloader, Voice) in a `FeatureActivator` so that they can be started and stopped on demand. Build the corresponding `FeatureDescriptor` for each, but do not yet wire the descriptors into a registry-driven bootstrap (that's Phase 04). The existing `AppController` continues to call into each subsystem as it does today; the activators are an additive, parallel surface that Phase 04 will start using.

**Architecture:** Each subsystem already has an init/teardown shape inside `AppController` (e.g., `clipboardCoordinator`, `voiceCoordinator`). The activator wraps that shape: `activate()` does what `AppController` does today on launch; `deactivate()` is the inverse. The wrappers live next to their subsystems in `MacAllYouNeed/<Subsystem>/`, not in `App/`. State that previously lived in `AppController` properties moves into the activators (private mutable state inside the activator instance).

**Tech Stack:** Swift 5.9+, Swift actors (each activator is an actor for thread safety), existing subsystem code (no rewrites — only extraction).

**Depends on:** Phase 01 (`FeatureActivator`, `FeatureDescriptor`, `FeatureID`, `Permission`, `HotkeyDescriptor`, `OSExtensionPolicy`).

---

## File structure

```
MacAllYouNeed/Clipboard/
└── ClipboardFeatureActivator.swift          ← new
MacAllYouNeed/FolderPreview/
└── FolderPreviewFeatureActivator.swift      ← new
MacAllYouNeed/Downloader/
└── DownloaderFeatureActivator.swift         ← new
MacAllYouNeed/Voice/
└── VoiceFeatureActivator.swift              ← new

MacAllYouNeed/App/
└── FeatureRegistryProvider.swift            ← new — vends a fully-populated FeatureRegistry

MacAllYouNeedTests/Features/
├── ClipboardFeatureActivatorTests.swift
├── FolderPreviewFeatureActivatorTests.swift
├── DownloaderFeatureActivatorTests.swift
└── VoiceFeatureActivatorTests.swift
```

`FeatureRegistryProvider` is the single point where descriptors are assembled. Phase 04 will move bootstrap to read this provider; until then it's just declared and tested.

---

### Task 1: `FeatureRegistryProvider` skeleton (shared scaffolding for the 4 parallel tasks)

**Files:**
- Create: `MacAllYouNeed/App/FeatureRegistryProvider.swift`
- Create: `MacAllYouNeedTests/Features/FeatureRegistryProviderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FeatureRegistryProviderTests: XCTestCase {
    func testProviderReturnsAllFourFeatures() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let ids = registry.descriptors.map(\.id)
        XCTAssertEqual(ids, [.clipboard, .folderPreview, .downloader, .voice],
                       "Registry order is contractual; UI iterates this order.")
    }

    func testEachDescriptorHasDisplayMetadata() {
        let registry = FeatureRegistryProvider.makeRegistry()
        for descriptor in registry.descriptors {
            XCTAssertFalse(descriptor.displayName.isEmpty, "\(descriptor.id) missing displayName")
            XCTAssertFalse(descriptor.icon.isEmpty, "\(descriptor.id) missing icon")
            XCTAssertFalse(descriptor.summary.isEmpty, "\(descriptor.id) missing summary")
        }
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeatureRegistryProviderTests | tail -15
```
Expected: FAIL — `FeatureRegistryProvider` not declared.

- [ ] **Step 3: Implement skeleton (with NoopFeatureActivator placeholders the four sub-tasks will replace)**

Create `MacAllYouNeed/App/FeatureRegistryProvider.swift`:
```swift
import FeatureCore
import SwiftUI

enum FeatureRegistryProvider {
    static func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(descriptors: [
            clipboardDescriptor(),
            folderPreviewDescriptor(),
            downloaderDescriptor(),
            voiceDescriptor(),
        ])
    }

    // Each of these is replaced in Tasks 2–5 with the real activator + factories.
    static func clipboardDescriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .clipboard, displayName: "Clipboard Manager", icon: "doc.on.clipboard",
            summary: "Copy history, snippets, ⌘⇧V popup.",
            detailDescription: "Captures everything you copy and lets you paste any past clip with ⌘⇧V. Includes snippet expansion (type `;email` to expand a saved snippet).",
            requiredPermissions: [.accessibility],
            activator: NoopFeatureActivator()
        )
    }

    static func folderPreviewDescriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .folderPreview, displayName: "Folder Preview", icon: "folder",
            summary: "Quick Look HTML preview of folders and archives.",
            detailDescription: "Press space on any folder or archive to see a browsable preview without opening Finder.",
            activator: NoopFeatureActivator()
        )
    }

    static func downloaderDescriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .downloader, displayName: "Video Downloader", icon: "arrow.down.circle",
            summary: "Universal video downloader (yt-dlp + ffmpeg).",
            detailDescription: "Paste any video URL and the downloader handles formats, fragments, cookies, and re-encoding.",
            assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
            activator: NoopFeatureActivator()
        )
    }

    static func voiceDescriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .voice, displayName: "Voice Dictation", icon: "mic",
            summary: "Push-to-talk voice dictation (cloud or local ASR).",
            detailDescription: "Hold a hotkey, speak, release — text is pasted at the cursor. Supports Groq Whisper (cloud) and Qwen3 (local).",
            requiredPermissions: [.microphone, .accessibility],
            activator: NoopFeatureActivator()
        )
    }
}
```

- [ ] **Step 4: Run to verify pass**

Same xcodebuild command as Step 2. Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/FeatureRegistryProvider.swift MacAllYouNeedTests/Features/FeatureRegistryProviderTests.swift
git commit -m "feat(modular-features): scaffold FeatureRegistryProvider with stub descriptors"
```

---

### Task 2 (PARALLELIZABLE): `ClipboardFeatureActivator`

> Owner: a sub-agent. Touches only Clipboard files.

**Files:**
- Create: `MacAllYouNeed/Clipboard/ClipboardFeatureActivator.swift`
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift` (replace the noop activator + add `settingsTabFactory`/`hotkeys`)
- Create: `MacAllYouNeedTests/Features/ClipboardFeatureActivatorTests.swift`

- [ ] **Step 1: Read `AppController` to identify what currently boots Clipboard**

```bash
grep -n "Clipboard\|clipboard" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift | head -30
```
Identify: which properties hold clipboard state, what init code runs on launch, what hotkeys are registered.

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class ClipboardFeatureActivatorTests: XCTestCase {
    func testActivateStartsClipboardPolling() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(activator.isPolling, "activate should start the pasteboard poller")
        try await activator.deactivate()
        XCTAssertFalse(activator.isPolling)
    }

    func testActivateIsIdempotent() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()  // second call must not crash or double-register
        XCTAssertTrue(activator.isPolling)
        try await activator.deactivate()
    }

    func testDeactivateIsIdempotent() async throws {
        let activator = ClipboardFeatureActivator(testMode: true)
        try await activator.deactivate()  // already inactive
        XCTAssertFalse(activator.isPolling)
    }
}
```

- [ ] **Step 3: Run to confirm it fails**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/ClipboardFeatureActivatorTests | tail -15
```

- [ ] **Step 4: Implement the activator (move boot code out of `AppController`)**

Create `MacAllYouNeed/Clipboard/ClipboardFeatureActivator.swift`:
```swift
import FeatureCore
import Foundation

/// Owns the Clipboard subsystem's lifecycle. Wraps init code that previously lived in AppController.
public actor ClipboardFeatureActivator: FeatureActivator {
    private var reader: LocalClipboardReader?
    private var hotkey: GlobalHotkey?
    private var snippetExpander: SnippetExpander?
    private let testMode: Bool

    public var isPolling: Bool { reader?.isRunning ?? false }

    public init(testMode: Bool = false) {
        self.testMode = testMode
    }

    public func activate() async throws {
        guard reader == nil else { return }   // idempotent
        let reader = LocalClipboardReader()
        if !testMode {
            reader.start()
        } else {
            reader.startInTestMode()
        }
        self.reader = reader

        if !testMode {
            hotkey = try GlobalHotkey.register(.clipboardPopup) { [weak self] in
                Task { await self?.showPopup() }
            }
            snippetExpander = try SnippetExpander.start()
        }
    }

    public func deactivate() async throws {
        reader?.stop()
        reader = nil
        hotkey?.unregister()
        hotkey = nil
        snippetExpander?.stop()
        snippetExpander = nil
    }

    private func showPopup() async {
        ClipboardPopupController.shared.show()
    }
}
```

> If `LocalClipboardReader` doesn't already have a `startInTestMode()` (one that doesn't actually poll the system pasteboard), add one in this same task: a public method that sets `isRunning = true` and returns immediately, used for unit tests where the global pasteboard would be flaky.

- [ ] **Step 5: Update `FeatureRegistryProvider.clipboardDescriptor()`**

In `MacAllYouNeed/App/FeatureRegistryProvider.swift`, replace `clipboardDescriptor()` with:
```swift
static func clipboardDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .clipboard, displayName: "Clipboard Manager", icon: "doc.on.clipboard",
        summary: "Copy history, snippets, ⌘⇧V popup.",
        detailDescription: "Captures everything you copy and lets you paste any past clip with ⌘⇧V. Includes snippet expansion (type `;email` to expand a saved snippet).",
        requiredPermissions: [.accessibility],
        hotkeys: [HotkeyDescriptor(identifier: "clipboard.popup", displayName: "Show clipboard popup")],
        activator: ClipboardFeatureActivator(),
        settingsTabFactory: { AnyView(ClipboardSettingsView()) }
    )
}
```

- [ ] **Step 6: Run tests to verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/ClipboardFeatureActivatorTests | tail -15
```
Expected: PASS, 3/3.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/Clipboard/ClipboardFeatureActivator.swift \
        MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/ClipboardFeatureActivatorTests.swift
git commit -m "feat(modular-features): add ClipboardFeatureActivator"
```

---

### Task 3 (PARALLELIZABLE): `FolderPreviewFeatureActivator`

> Owner: a sub-agent. Touches only Folder Preview files.

**Files:**
- Create: `MacAllYouNeed/FolderPreview/FolderPreviewFeatureActivator.swift`
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift` (replace folder-preview noop)
- Create: `MacAllYouNeedTests/Features/FolderPreviewFeatureActivatorTests.swift`

- [ ] **Step 1: Read `AppController` for current Folder Preview init**

```bash
grep -n "FolderPreview\|folderPreview\|browseFolder" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift | head -20
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FolderPreviewFeatureActivatorTests: XCTestCase {
    func testActivateRegistersBrowseFolderHotkey() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(activator.isHotkeyRegistered)
        try await activator.deactivate()
        XCTAssertFalse(activator.isHotkeyRegistered)
    }

    func testIdempotency() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()
        XCTAssertTrue(activator.isHotkeyRegistered)
        try await activator.deactivate()
        try await activator.deactivate()
        XCTAssertFalse(activator.isHotkeyRegistered)
    }
}
```

- [ ] **Step 3: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderPreviewFeatureActivatorTests
```

- [ ] **Step 4: Implement**

Create `MacAllYouNeed/FolderPreview/FolderPreviewFeatureActivator.swift`:
```swift
import FeatureCore
import Foundation

public actor FolderPreviewFeatureActivator: FeatureActivator {
    private var browseFolderHotkey: GlobalHotkey?
    private let testMode: Bool

    public var isHotkeyRegistered: Bool { browseFolderHotkey != nil }

    public init(testMode: Bool = false) { self.testMode = testMode }

    public func activate() async throws {
        guard browseFolderHotkey == nil else { return }
        if !testMode {
            browseFolderHotkey = try GlobalHotkey.register(.browseFolder) {
                Task { @MainActor in BrowseFolderWindow.shared.show() }
            }
        } else {
            browseFolderHotkey = GlobalHotkey.testStub()
        }
    }

    public func deactivate() async throws {
        browseFolderHotkey?.unregister()
        browseFolderHotkey = nil
    }
}
```

(If `GlobalHotkey.testStub()` doesn't exist, add it as a static returning a `GlobalHotkey` whose `unregister()` is a no-op. Used only in tests.)

- [ ] **Step 5: Update `FeatureRegistryProvider.folderPreviewDescriptor()`**

```swift
static func folderPreviewDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .folderPreview, displayName: "Folder Preview", icon: "folder",
        summary: "Quick Look HTML preview of folders and archives.",
        detailDescription: "Press space on any folder or archive to see a browsable preview without opening Finder.",
        hotkeys: [HotkeyDescriptor(identifier: "folderPreview.browse", displayName: "Browse folder")],
        osExtensionPolicy: .staticBundleExtension(StaticExtensionConfig(
            extensionBundleID: "FolderPreview",
            runsRegardlessOfFeatureState: true,
            respectsFeatureFlag: true
        )),
        activator: FolderPreviewFeatureActivator(),
        settingsTabFactory: { AnyView(FolderPreviewSettingsView()) }
    )
}
```

- [ ] **Step 6: Verify tests pass**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderPreviewFeatureActivatorTests | tail -15
```
Expected: PASS, 2/2.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/FolderPreview/FolderPreviewFeatureActivator.swift \
        MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/FolderPreviewFeatureActivatorTests.swift
git commit -m "feat(modular-features): add FolderPreviewFeatureActivator"
```

---

### Task 4 (PARALLELIZABLE): `DownloaderFeatureActivator`

> Owner: a sub-agent. Touches only Downloader files.

**Files:**
- Create: `MacAllYouNeed/Downloader/DownloaderFeatureActivator.swift`
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift`
- Create: `MacAllYouNeedTests/Features/DownloaderFeatureActivatorTests.swift`

- [ ] **Step 1: Read AppController for current Downloader init**

```bash
grep -n "Download\|downloader\|DispatchServer" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift | head -30
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class DownloaderFeatureActivatorTests: XCTestCase {
    func testActivateStartsCoordinatorAndDispatchServer() async throws {
        let activator = DownloaderFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(activator.isCoordinatorRunning)
        XCTAssertTrue(activator.isDispatchServerRunning)
        try await activator.deactivate()
        XCTAssertFalse(activator.isCoordinatorRunning)
        XCTAssertFalse(activator.isDispatchServerRunning)
    }

    func testActivateRequiresAssetPackInProduction() async {
        // In testMode the activator skips the asset-pack probe; in production it would throw.
        // This test asserts the pre-check helper independently.
        let result = DownloaderFeatureActivator.assetPackProbe(packDir: URL(fileURLWithPath: "/nonexistent"))
        XCTAssertFalse(result, "missing pack must fail probe")
    }
}
```

- [ ] **Step 3: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/DownloaderFeatureActivatorTests
```

- [ ] **Step 4: Implement**

Create `MacAllYouNeed/Downloader/DownloaderFeatureActivator.swift`:
```swift
import FeatureCore
import Foundation

public actor DownloaderFeatureActivator: FeatureActivator {
    private var coordinator: DownloadCoordinator?
    private var dispatchServer: DispatchServer?
    private let testMode: Bool

    public var isCoordinatorRunning: Bool { coordinator != nil }
    public var isDispatchServerRunning: Bool { dispatchServer?.isRunning == true }

    public init(testMode: Bool = false) { self.testMode = testMode }

    public func activate() async throws {
        guard coordinator == nil else { return }
        if !testMode {
            // Pack must be present (Phase 06 ties this to FeatureManager.state).
            // Until Phase 06 lands, AppController still prevalidates — so keep this advisory.
        }
        coordinator = DownloadCoordinator()
        let server = DispatchServer()
        try server.start()
        dispatchServer = server
    }

    public func deactivate() async throws {
        await coordinator?.shutdown()
        coordinator = nil
        dispatchServer?.stop()
        dispatchServer = nil
    }

    /// Used by Phase 06 to verify the pack is on disk before transitioning to enabled.
    public static func assetPackProbe(packDir: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: packDir.appendingPathComponent("yt-dlp").path)
            && fm.fileExists(atPath: packDir.appendingPathComponent("ffmpeg").path)
    }
}
```

- [ ] **Step 5: Update `FeatureRegistryProvider.downloaderDescriptor()`**

```swift
static func downloaderDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .downloader, displayName: "Video Downloader", icon: "arrow.down.circle",
        summary: "Universal video downloader (yt-dlp + ffmpeg).",
        detailDescription: "Paste any video URL and the downloader handles formats, fragments, cookies, and re-encoding.",
        assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
        activator: DownloaderFeatureActivator(),
        settingsTabFactory: { AnyView(DownloadsSettingsView()) }
    )
}
```

- [ ] **Step 6: Verify tests pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/DownloaderFeatureActivatorTests | tail -15
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeed/Downloader/DownloaderFeatureActivator.swift \
        MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/DownloaderFeatureActivatorTests.swift
git commit -m "feat(modular-features): add DownloaderFeatureActivator"
```

---

### Task 5 (PARALLELIZABLE): `VoiceFeatureActivator`

> Owner: a sub-agent. Touches only Voice files.

**Files:**
- Create: `MacAllYouNeed/Voice/VoiceFeatureActivator.swift`
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift`
- Create: `MacAllYouNeedTests/Features/VoiceFeatureActivatorTests.swift`

- [ ] **Step 1: Read existing Voice boot path**

```bash
grep -n "Voice\|voice" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift | head -20
grep -n "VoiceCoordinator" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppControllerVoice.swift | head -20
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class VoiceFeatureActivatorTests: XCTestCase {
    func testActivateStartsVoiceCoordinator() async throws {
        let activator = VoiceFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(activator.isCoordinatorRunning)
        try await activator.deactivate()
        XCTAssertFalse(activator.isCoordinatorRunning)
    }

    func testIdempotency() async throws {
        let activator = VoiceFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()
        try await activator.deactivate()
        try await activator.deactivate()
        XCTAssertFalse(activator.isCoordinatorRunning)
    }
}
```

- [ ] **Step 3: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/VoiceFeatureActivatorTests
```

- [ ] **Step 4: Implement**

Create `MacAllYouNeed/Voice/VoiceFeatureActivator.swift`:
```swift
import FeatureCore
import Foundation

public actor VoiceFeatureActivator: FeatureActivator {
    private var coordinator: VoiceCoordinator?
    private let testMode: Bool

    public var isCoordinatorRunning: Bool { coordinator != nil }

    public init(testMode: Bool = false) { self.testMode = testMode }

    public func activate() async throws {
        guard coordinator == nil else { return }
        coordinator = try VoiceCoordinator(testMode: testMode)
        try await coordinator?.start()
    }

    public func deactivate() async throws {
        await coordinator?.stop()
        coordinator = nil
    }
}
```

> `VoiceCoordinator(testMode:)` and `start()`/`stop()` may not exist exactly today. If `start()` is implicit (constructor-driven), refactor `VoiceCoordinator` to lazy-start in this same task: extract the side effects from `init` into a new `start()` method. Keep the existing `init()` signature working by having it call `start()` synchronously (no behavior change for current callers); add a `testMode` parameter that skips microphone setup.

- [ ] **Step 5: Update `FeatureRegistryProvider.voiceDescriptor()`**

```swift
static func voiceDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        id: .voice, displayName: "Voice Dictation", icon: "mic",
        summary: "Push-to-talk voice dictation (cloud or local ASR).",
        detailDescription: "Hold a hotkey, speak, release — text is pasted at the cursor. Supports Groq Whisper (cloud) and Qwen3 (local).",
        requiredPermissions: [.microphone, .accessibility],
        // Asset caches for Qwen3 models land in Phase 07.
        hotkeys: [HotkeyDescriptor(identifier: "voice.pushToTalk", displayName: "Voice push-to-talk")],
        activator: VoiceFeatureActivator(),
        settingsTabFactory: { AnyView(VoiceSettingsView()) }
    )
}
```

- [ ] **Step 6: Verify tests pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/VoiceFeatureActivatorTests | tail -15
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeed/Voice/VoiceFeatureActivator.swift \
        MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/VoiceFeatureActivatorTests.swift
git commit -m "feat(modular-features): add VoiceFeatureActivator"
```

---

### Task 6: Phase verification

This task runs after all four parallel sub-tasks merge.

- [ ] **Step 1: Run all activator tests**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/ClipboardFeatureActivatorTests \
  -only-testing:MacAllYouNeedTests/FolderPreviewFeatureActivatorTests \
  -only-testing:MacAllYouNeedTests/DownloaderFeatureActivatorTests \
  -only-testing:MacAllYouNeedTests/VoiceFeatureActivatorTests \
  -only-testing:MacAllYouNeedTests/FeatureRegistryProviderTests | tail -20
```
Expected: all pass.

- [ ] **Step 2: Manual smoke**

Build and run MAYN. The app behavior should be unchanged (AppController still drives boot today). Confirm clipboard, folder preview, downloader, and voice all work.

- [ ] **Step 3: Run CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md` to mark Phase 03 complete.

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 03 complete"
git push -u origin <branch>
gh pr create --title "Phase 03 — Feature Activators" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/03-activators.md"
```
