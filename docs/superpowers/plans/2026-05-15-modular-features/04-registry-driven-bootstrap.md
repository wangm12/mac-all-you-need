# Phase 04 — Registry-Driven Bootstrap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop hardcoding per-feature initialization in `AppController`, `SettingsRoot`, `MenuBarHost`, and `HotkeyRegistry`. Each becomes a loop over the `FeatureRegistry`, calling activator/factory methods on each descriptor. Backward-compatible: every feature defaults to `activationState == .enabled` so the app behaves the same as today after this phase ships.

**Architecture:** A new singleton `FeatureRuntime` (composition of `FeatureRegistry` + `FeatureManager` + a long-lived `Task` per active feature) replaces the per-subsystem properties on `AppController`. UI shells (`SettingsRoot`, `MenuBarHost`, `HotkeyRegistry`) read directly from the registry and call descriptor factories.

**Tech Stack:** Swift, SwiftUI, the existing `AppController` shape (refactored, not rewritten).

**Depends on:** Phase 01 (`FeatureManager`), Phase 03 (all four activators + `FeatureRegistryProvider`).

---

## File structure

```
MacAllYouNeed/App/
├── AppController.swift                ← REWRITE bootstrap to iterate registry
├── FeatureRuntime.swift               ← NEW: holds FeatureRegistry + FeatureManager + activation Task map
├── FeatureRegistryProvider.swift      ← already exists from Phase 03
└── BootstrapDefaults.swift            ← NEW: seeds first-launch FeatureManager state

MacAllYouNeed/Settings/
├── SettingsRoot.swift                 ← REWRITE tab list to iterate registry's settingsTabFactory
└── SettingsDestination.swift          ← REWRITE to be FeatureID-keyed
MacAllYouNeed/App/
└── MainWindowRoot.swift               ← MODIFY menu bar items to iterate registry.menuBarItemFactory

Shared/Sources/Core/HotkeyRegistry.swift  ← MODIFY to iterate registry.hotkeys

MacAllYouNeedTests/
├── FeatureRuntimeTests.swift
└── BootstrapDefaultsTests.swift
```

---

### Task 1: `BootstrapDefaults` — first-launch seeding

**Files:**
- Create: `MacAllYouNeed/App/BootstrapDefaults.swift`
- Create: `MacAllYouNeedTests/BootstrapDefaultsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class BootstrapDefaultsTests: XCTestCase {
    func testSeedsAllFeaturesEnabledOnFirstLaunch() async throws {
        let defaults = UserDefaults(suiteName: "BootstrapDefaultsTests-\(UUID())")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            XCTAssertEqual(state.activationState, .enabled,
                           "first-launch must default \(descriptor.id) to enabled for backward compat")
        }
        XCTAssertTrue(defaults.bool(forKey: BootstrapDefaults.seededKey))
    }

    func testIsIdempotent() async throws {
        let defaults = UserDefaults(suiteName: "BootstrapDefaultsTests-\(UUID())")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)

        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        try await manager.transition(.disable, for: .clipboard)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        let state = await manager.state(for: .clipboard)
        XCTAssertEqual(state.activationState, .disabled, "second seed must not undo user changes")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/BootstrapDefaultsTests
```

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/App/BootstrapDefaults.swift`:
```swift
import FeatureCore
import Foundation

enum BootstrapDefaults {
    static let seededKey = "feature.bootstrap.seeded"

    /// Runs once. Seeds every feature to (asset-appropriate, .enabled) so the app behaves
    /// like the pre-modular release until Phase 11's migration overrides this for upgraders.
    /// New installs *after Phase 11* will not call this — onboarding writes intent first and
    /// sets the seeded flag itself.
    static func seedIfNeeded(manager: FeatureManager, defaults: UserDefaults) async throws {
        guard !defaults.bool(forKey: seededKey) else { return }
        for descriptor in await manager.registry.descriptors {
            let asset: AssetState = descriptor.requiresAsset
                ? .present(version: "legacy")  // Phase 06 will replace 'legacy' with real pack version detection
                : .notRequired
            try await manager.setState(.init(assetState: asset, activationState: .enabled), for: descriptor.id)
        }
        defaults.set(true, forKey: seededKey)
    }
}
```

> The `"legacy"` placeholder version unblocks Phase 04's standalone landing — at Phase 04 the Downloader still uses bundled `Resources/yt-dlp`, so it's "present" in spirit. Phase 06 will detect the real pack and rewrite this state.

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/BootstrapDefaultsTests | tail -15
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeed/App/BootstrapDefaults.swift MacAllYouNeedTests/BootstrapDefaultsTests.swift
git commit -m "feat(modular-features): add BootstrapDefaults for first-launch seeding"
```

---

### Task 2: `FeatureRuntime` (composition root)

**Files:**
- Create: `MacAllYouNeed/App/FeatureRuntime.swift`
- Create: `MacAllYouNeedTests/FeatureRuntimeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FeatureRuntimeTests: XCTestCase {
    func testActivatesEnabledFeaturesOnBoot() async throws {
        let defaults = UserDefaults(suiteName: "FeatureRuntimeTests-\(UUID())")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        let runtime = FeatureRuntime(registry: registry, manager: manager)
        await runtime.activateAllEnabled()

        for descriptor in registry.descriptors {
            XCTAssertTrue(await runtime.isActive(descriptor.id), "\(descriptor.id) should be active after boot")
        }
    }

    func testSkipsDisabledFeatures() async throws {
        let defaults = UserDefaults(suiteName: "FeatureRuntimeTests-\(UUID())")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
        try await manager.transition(.disable, for: .clipboard)

        let runtime = FeatureRuntime(registry: registry, manager: manager)
        await runtime.activateAllEnabled()

        XCTAssertFalse(await runtime.isActive(.clipboard))
        XCTAssertTrue(await runtime.isActive(.voice))
    }

    func testDeactivateOne() async throws {
        let defaults = UserDefaults(suiteName: "FeatureRuntimeTests-\(UUID())")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)

        let runtime = FeatureRuntime(registry: registry, manager: manager)
        await runtime.activateAllEnabled()
        try await runtime.applyTransition(.disable, for: .voice)

        XCTAssertFalse(await runtime.isActive(.voice))
        let state = await manager.state(for: .voice)
        XCTAssertEqual(state.activationState, .disabled)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureRuntimeTests
```

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/App/FeatureRuntime.swift`:
```swift
import FeatureCore
import Foundation

/// Composition root for the modular feature system. Single instance lives on AppController.
public actor FeatureRuntime {
    public let registry: FeatureRegistry
    public let manager: FeatureManager
    private var active: Set<FeatureID> = []

    public init(registry: FeatureRegistry, manager: FeatureManager) {
        self.registry = registry
        self.manager = manager
    }

    public func isActive(_ id: FeatureID) -> Bool { active.contains(id) }

    /// Called once on app launch.
    public func activateAllEnabled() async {
        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            guard state.activationState == .enabled else { continue }
            do {
                try await descriptor.activator.activate()
                active.insert(descriptor.id)
            } catch {
                // On failure, demote to disabled but keep asset state intact.
                try? await manager.transition(.disable, for: descriptor.id)
                NSLog("Feature \(descriptor.id) activation failed: \(error)")
            }
        }
    }

    /// Called on app quit.
    public func deactivateAll() async {
        for descriptor in registry.descriptors where active.contains(descriptor.id) {
            try? await descriptor.activator.deactivate()
            active.remove(descriptor.id)
        }
    }

    /// Drives a user-initiated state change. Persists state AND drives activator side-effects.
    public func applyTransition(_ transition: FeatureManager.Transition, for id: FeatureID) async throws {
        try await manager.transition(transition, for: id)
        guard let descriptor = registry.descriptor(for: id) else { return }
        switch transition {
        case .enable:
            if !active.contains(id) {
                try await descriptor.activator.activate()
                active.insert(id)
            }
        case .disable:
            if active.contains(id) {
                try await descriptor.activator.deactivate()
                active.remove(id)
            }
        }
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureRuntimeTests | tail -15
```
Expected: PASS, 3/3.

```bash
git add MacAllYouNeed/App/FeatureRuntime.swift MacAllYouNeedTests/FeatureRuntimeTests.swift
git commit -m "feat(modular-features): add FeatureRuntime composition root"
```

---

### Task 3: Replace `AppController` boot path

**Files:**
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 1: Read current AppController to identify what to remove**

```bash
sed -n '1,200p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppController.swift
```

Identify each per-feature property (e.g., `clipboardCoordinator`, `downloadCoordinator`, `voiceCoordinator`, `dispatchServer`, hotkey registrations) and its init point.

- [ ] **Step 2: Refactor AppController to delegate to FeatureRuntime**

Edit `AppController.swift`. Replace the per-feature properties + their init with:

```swift
final class AppController: ObservableObject {
    static let shared: AppController = { try! AppController() }()  // existing pattern from CLAUDE.md

    let runtime: FeatureRuntime
    private let manager: FeatureManager

    private init() throws {
        let defaults = AppGroupSettings.defaults
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        self.manager = manager
        self.runtime = FeatureRuntime(registry: registry, manager: manager)

        Task { [manager, runtime] in
            try await BootstrapDefaults.seedIfNeeded(manager: manager, defaults: defaults)
            await runtime.activateAllEnabled()
        }
    }

    func shutdown() async {
        await runtime.deactivateAll()
    }
}
```

Move any AppController code that wasn't actually feature-specific (e.g., onboarding bootstrap, app-quit hooks, dock controller setup, log directory init) into a new helper called from `init()` after the runtime task is dispatched.

> Delete the now-unused per-feature properties and init code. The activators own that state now (per Phase 03).

- [ ] **Step 3: Verify the app still launches and behaves identically**

Build and run. All four features should work as before (clipboard popup, downloader queue, folder preview, voice dictation).

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/App/AppController.swift
git commit -m "feat(modular-features): replace AppController bootstrap with FeatureRuntime"
```

---

### Task 4: `SettingsRoot` iterates registry for tabs

**Files:**
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`
- Modify: `MacAllYouNeed/Settings/SettingsDestination.swift`
- Create: `MacAllYouNeedTests/SettingsRegistryDrivenTests.swift`

- [ ] **Step 1: Read current SettingsRoot and SettingsDestination**

```bash
cat /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/SettingsRoot.swift
cat /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/SettingsDestination.swift
```

- [ ] **Step 2: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class SettingsRegistryDrivenTests: XCTestCase {
    func testTabListIncludesAllFeaturesWithFactories() {
        let registry = FeatureRegistryProvider.makeRegistry()
        let tabs = SettingsRoot.featureTabs(registry: registry)
        let ids = tabs.map(\.0)
        XCTAssertEqual(ids, [.clipboard, .folderPreview, .downloader, .voice],
                       "feature tabs must follow registry order")
    }
}
```

- [ ] **Step 3: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/SettingsRegistryDrivenTests
```

- [ ] **Step 4: Refactor SettingsRoot to iterate registry**

In `SettingsRoot.swift`, replace the hardcoded tab list with:

```swift
import SwiftUI
import FeatureCore

struct SettingsRoot: View {
    @ObservedObject var controller: AppController
    @State private var selection: SettingsDestination = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsDestination.general)

            FeaturesTabView(controller: controller)   // landing in Phase 05; for now stub
                .tabItem { Label("Features", systemImage: "puzzlepiece") }
                .tag(SettingsDestination.features)

            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(SettingsDestination.hotkeys)

            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench") }
                .tag(SettingsDestination.advanced)

            ForEach(Self.featureTabs(registry: controller.runtime.registry), id: \.0) { (id, view) in
                view
                    .tabItem { Label(controller.runtime.registry.descriptor(for: id)!.displayName,
                                     systemImage: controller.runtime.registry.descriptor(for: id)!.icon) }
                    .tag(SettingsDestination.feature(id))
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    /// Used by tests and by `body`.
    static func featureTabs(registry: FeatureRegistry) -> [(FeatureID, AnyView)] {
        registry.descriptors.compactMap { d in
            guard let factory = d.settingsTabFactory else { return nil }
            return (d.id, factory())
        }
    }
}

/// Stub for Phase 04. Phase 05 fully implements this view.
struct FeaturesTabView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        Text("Features tab — implemented in Phase 05.").padding()
    }
}
```

In `SettingsDestination.swift`, change to:
```swift
import FeatureCore

enum SettingsDestination: Hashable {
    case general, features, hotkeys, advanced
    case feature(FeatureID)
}
```

> If the existing settings file references removed cases by name (e.g., `.clipboard`, `.downloads`), search-and-replace those to `.feature(.clipboard)`, `.feature(.downloader)`, etc.

- [ ] **Step 5: Sync removal**

The current `SettingsDestination` likely has `.sync`. Remove it (Sync subsystem is being deleted in Phase 12; for Phase 04 just stop referencing it from the tab list — file removal happens in Phase 12).

```bash
grep -rn "\.sync\|SyncSettingsView" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/
```
Comment-out or stub each reference; leave a `// TODO Phase 12: remove` next to the stubs.

- [ ] **Step 6: Verify tests pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/SettingsRegistryDrivenTests | tail -15
```
Expected: PASS, 1/1.

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Settings/SettingsRoot.swift MacAllYouNeed/Settings/SettingsDestination.swift MacAllYouNeedTests/SettingsRegistryDrivenTests.swift
git commit -m "feat(modular-features): SettingsRoot iterates FeatureRegistry"
```

---

### Task 5: `MainWindowRoot` (menu bar) iterates registry

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift`

- [ ] **Step 1: Read current menu bar layout**

```bash
sed -n '1,150p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/MainWindowRoot.swift
```

- [ ] **Step 2: Refactor menu items to iterate registry**

In `MainWindowRoot.swift`, find the section building the `MenuBarExtra` body. Replace hardcoded per-feature menu items with:
```swift
ForEach(controller.runtime.registry.descriptors, id: \.id) { descriptor in
    if let factory = descriptor.menuBarItemFactory {
        factory()
    }
}
```

> Existing menu item code (3-tab popover with Clipboard/Downloads/Snippets) should move into one of the descriptors' `menuBarItemFactory`. For Phase 04, the simplest move: Clipboard owns the popover; set `clipboardDescriptor()`'s `menuBarItemFactory` to a closure returning the existing popover view.

Update `FeatureRegistryProvider.clipboardDescriptor()`:
```swift
static func clipboardDescriptor() -> FeatureDescriptor {
    FeatureDescriptor(
        // ... existing ...
        menuBarItemFactory: { AnyView(MenuBarPopoverView()) },
        settingsTabFactory: { AnyView(ClipboardSettingsView()) }
    )
}
```

(Other features may not have menu bar items today; their `menuBarItemFactory` stays `nil`.)

- [ ] **Step 3: Manual verify**

Build and run. The menu bar icon should still show the popover when clicked, with the same content as before.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/App/MainWindowRoot.swift MacAllYouNeed/App/FeatureRegistryProvider.swift
git commit -m "feat(modular-features): menu bar iterates FeatureRegistry"
```

---

### Task 6: `HotkeyRegistry` iterates `descriptor.hotkeys`

**Files:**
- Modify: `Shared/Sources/Core/HotkeyRegistry.swift` (assuming it lives there; if it lives in `MacAllYouNeed/`, modify there)

- [ ] **Step 1: Read current HotkeyRegistry**

```bash
grep -rn "class HotkeyRegistry\|struct HotkeyRegistry" /Users/mingjie.wang/Documents/personal/mac-all-you-need
```

- [ ] **Step 2: Add registry-driven enumeration helper**

Add this method to `HotkeyRegistry`:
```swift
public func declaredHotkeys(from registry: FeatureRegistry) -> [(FeatureID, HotkeyDescriptor)] {
    registry.descriptors.flatMap { d in
        d.hotkeys.map { (d.id, $0) }
    }
}
```

This is consumed by Phase 05's HotkeysSettingsView. For Phase 04 the actual hotkey registration still happens inside each activator (per Phase 03). This task only adds the enumerator.

- [ ] **Step 3: Smoke test build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Shared/Sources/Core/HotkeyRegistry.swift
git commit -m "feat(modular-features): add HotkeyRegistry.declaredHotkeys(from:) enumerator"
```

---

### Task 7: Phase verification

- [ ] **Step 1: Full test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
```
Expected: all green.

- [ ] **Step 2: Manual smoke**

Launch the app fresh (after `defaults delete <appgroup>` to simulate a first-launch). All four features should be active. Disable one in Settings → Features (the stub view in Phase 04 doesn't have UI yet — bypass via:
```bash
defaults write <appgroup> feature.voice.runtimeState '{"assetState":{"kind":"notRequired"},"activationState":"disabled"}'
```
Restart the app. Voice should not be active (microphone permission not requested, no hotkey registered).

- [ ] **Step 3: Run CI**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md` to mark Phase 04 complete.

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 04 complete"
git push -u origin <branch>
gh pr create --title "Phase 04 — Registry-Driven Bootstrap" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/04-registry-driven-bootstrap.md"
```
