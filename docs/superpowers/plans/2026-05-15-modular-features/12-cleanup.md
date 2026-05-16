# Phase 12 — Cleanup & Polish

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Final cleanup pass before release. Remove the Sync settings surface (Plan 2 deferred indefinitely per CLAUDE.md and design § 13). Add the four Advanced-tab actions from design § 8 ("Re-run onboarding…", "Open feature install directory in Finder", "Install pack from file…", "Reset all features…"). Run a copy pass over every user-facing string introduced in this initiative. Run the manual QA matrix from design § 11. Mark the entire `modular-features` initiative complete.

**Architecture:** No new architecture. This phase deletes UI, adds buttons that call into already-built infrastructure (`FeatureRuntime.applyTransition`, `OnboardingState.reset`, `PackUninstaller`, `SideloadInstaller`), and runs checklists. The "Reset all features…" action is the only piece with non-trivial logic — it iterates the registry and applies the reverse of bootstrap.

**Tech Stack:** SwiftUI, AppKit (`NSWorkspace.activateFileViewerSelecting`, `NSOpenPanel`, `NSAlert`), the existing `FeatureRuntime` (Phase 04), `PackUninstaller` (Phase 02), `SideloadInstaller` (Phase 02), `OnboardingState` (existing), `Migrator` (Phase 11), the MAYN design system (`MAYNButton`, `MAYNSettingsRow`, `MAYNSection`, etc.).

**Depends on:** Phase 11 (Migration). Phase 12 is the last phase in the initiative.

---

## File structure

```
MacAllYouNeed/Settings/
├── AdvancedSettingsView.swift         ← MODIFY: delete Sync section, add 4 new actions
└── AdvancedActions/                   ← NEW directory
    ├── ReRunOnboardingAction.swift    ← NEW: confirmation + reset + reopen wizard
    ├── OpenFeatureDirectoryAction.swift ← NEW: NSWorkspace reveal helper
    ├── SideloadPackAction.swift       ← NEW: NSOpenPanel + SideloadInstaller wrapper
    └── ResetAllFeaturesAction.swift   ← NEW: confirmation + iterate registry + uninstall

MacAllYouNeed/App/
└── AppControllerOnboarding.swift      ← MODIFY: ensure resetOnboarding() reopens wizard window

MacAllYouNeedTests/Settings/
├── ResetAllFeaturesActionTests.swift  ← NEW: integration test for the destructive action
└── OpenFeatureDirectoryActionTests.swift ← NEW: directory-creation fallback test

docs/superpowers/plans/2026-05-15-modular-features/
└── 12-cleanup.md                      ← this file (no edits beyond checkbox progress)

docs/superpowers/plans/
└── 2026-05-15-modular-features.md     ← MODIFY: mark Phase 12 + initiative complete

CLAUDE.md                              ← MODIFY: update Plans Status section
```

The "Sync" section being removed currently lives **inside** `AdvancedSettingsView.swift` (a `MAYNSection(title: "Sync")` block, lines 34–41 of the file as of writing). There is no standalone `SyncSettingsView.swift` file in the current codebase, so there is no file to delete — only the section to remove. Verify this with `grep -rn "SyncSettingsView" MacAllYouNeed/` before starting; if Phase 04 introduced a stub `SyncSettingsView` symbol or `SettingsDestination.sync` case, those go too (Task 1 below covers both possibilities).

---

### Task 1: Remove the Sync settings surface

**Files:**
- Modify: `MacAllYouNeed/Settings/AdvancedSettingsView.swift`
- Possibly modify: `MacAllYouNeed/Settings/SettingsRoot.swift`, `MacAllYouNeed/Settings/SettingsDestination.swift`
- Possibly delete: `MacAllYouNeed/Settings/SyncSettingsView.swift` (if Phase 04 created a stub)

- [ ] **Step 1: Audit the current Sync footprint**

```bash
grep -rn "SyncSettingsView\|\.sync\b\|MAYNSection(title: \"Sync\"" \
  /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/
```

Expected hits (current main, before this task):
- `MacAllYouNeed/Settings/AdvancedSettingsView.swift:34` — the `MAYNSection(title: "Sync")` block.
- Possibly `MacAllYouNeed/Settings/SettingsRoot.swift` if Phase 04 left a `.sync` tab stub.
- Possibly `MacAllYouNeed/Settings/SettingsDestination.swift` if a `case sync` was retained.
- Possibly `MacAllYouNeed/Settings/SyncSettingsView.swift` if it was created as a stub.

Record exact paths and line numbers in a scratch note before editing — Step 2 needs them.

- [ ] **Step 2: Delete the Sync section from `AdvancedSettingsView.swift`**

Open `MacAllYouNeed/Settings/AdvancedSettingsView.swift` and remove the entire `MAYNSection(title: "Sync") { … }` block (the "Multi-device sync / Planned for a future phase. / `StatusPill(text: "Future", kind: .neutral)`" rows). Leave the surrounding sections (`Updates`, `Diagnostics`, `Setup and data`) untouched in this step — Tasks 2–5 modify `Setup and data` separately.

Do **not** touch `resetAllData()`'s `removeObject(forKey: "syncFolderPath")` / `"syncDownloadHistory")` calls. Per the task brief, App Group keys for Sync are inert and removing them risks affecting other code; the UI removal is sufficient.

- [ ] **Step 3: Delete `SyncSettingsView` stub (if it exists)**

If Step 1 found `MacAllYouNeed/Settings/SyncSettingsView.swift`:
```bash
git rm MacAllYouNeed/Settings/SyncSettingsView.swift
```

If Step 1 found a `case sync` in `SettingsDestination`, remove it. If Step 1 found a `.sync` tab item in `SettingsRoot.swift`, remove the corresponding `tabItem` block. Re-run the grep from Step 1 — only the (preserved) `removeObject` references in `resetAllData()` should remain.

- [ ] **Step 4: Build verify**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

If anything else references the removed symbol, the build error names it. Fix it the same way (delete the orphan reference) and rebuild.

- [ ] **Step 5: Commit**

```bash
git add -A MacAllYouNeed/Settings/
git commit -m "feat(modular-features): remove Sync settings surface"
```

---

### Task 2: "Re-run onboarding…" action

**Files:**
- Create: `MacAllYouNeed/Settings/AdvancedActions/ReRunOnboardingAction.swift`
- Modify: `MacAllYouNeed/App/AppControllerOnboarding.swift` (verify `resetOnboarding()` opens the wizard window and closes Settings)
- Modify: `MacAllYouNeed/Settings/AdvancedSettingsView.swift` (replace the existing "Re-run" button)

The current `AdvancedSettingsView.swift` already wires a "Re-run" button to `controller.resetOnboarding()` (line 48). Phase 12 wraps this in a confirmation alert and confirms the underlying `resetOnboarding()` re-opens the wizard window and closes the Settings window.

- [ ] **Step 1: Verify `AppController.resetOnboarding()` does the right thing**

```bash
sed -n '40,80p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/AppControllerOnboarding.swift
```

The function should:
1. Call `OnboardingState.reset()`.
2. Open the onboarding wizard window (`OnboardingWindowController.shared.show()` or equivalent — check the actual symbol used elsewhere for the wizard launch).
3. Close the Settings window (`NSApp.keyWindow?.close()` if it's the Settings window, or the more specific Settings window controller).

If any of those three are missing, add them. Do not alter `OnboardingState.reset()` itself — it's a one-liner that removes the persisted state key, used elsewhere (e.g., `resetAllData()` in `AdvancedSettingsView.swift`).

If Phase 11 introduced `Migrator.resetSentinel(defaults:)`, **do not** call it here — re-running onboarding is not the same as re-running migration; the sentinel staying set is the correct behavior (the user is replaying the wizard, not pretending the upgrade never happened). The task brief explicitly notes this.

- [ ] **Step 2: Implement the action wrapper**

Create `MacAllYouNeed/Settings/AdvancedActions/ReRunOnboardingAction.swift`:
```swift
import AppKit
import SwiftUI

struct ReRunOnboardingAction {
    let controller: AppController

    func perform() {
        let alert = NSAlert()
        alert.messageText = "Restart the setup wizard?"
        alert.informativeText = "This will restart the setup wizard. Your installed features will not be removed."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart Setup")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.resetOnboarding()
    }
}
```

- [ ] **Step 3: Wire it into `AdvancedSettingsView.swift`**

Replace the existing `MAYNButton("Re-run") { controller.resetOnboarding() }` call with:
```swift
MAYNButton("Re-run") { ReRunOnboardingAction(controller: controller).perform() }
```

The confirmation lives in `perform()`, not in the view. Keep the surrounding `MAYNSettingsRow(title: "Onboarding", subtitle: "Show the first-run setup flow again.")` as-is.

- [ ] **Step 4: Manual smoke**

Build and run. Settings → Advanced → "Re-run". Confirm:
1. Confirmation alert appears with the exact copy above.
2. "Cancel" closes the alert and does nothing.
3. "Restart Setup" closes Settings, opens the onboarding wizard at step 1, and `OnboardingState.load()` returns `.notStarted` after.
4. Installed features are still installed (visible in Settings → Features after dismissing the wizard).

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/AdvancedActions/ReRunOnboardingAction.swift \
        MacAllYouNeed/Settings/AdvancedSettingsView.swift \
        MacAllYouNeed/App/AppControllerOnboarding.swift
git commit -m "feat(modular-features): Re-run onboarding action with confirmation"
```

---

### Task 3: "Open feature install directory in Finder" action

**Files:**
- Create: `MacAllYouNeed/Settings/AdvancedActions/OpenFeatureDirectoryAction.swift`
- Create: `MacAllYouNeedTests/Settings/OpenFeatureDirectoryActionTests.swift`
- Modify: `MacAllYouNeed/Settings/AdvancedSettingsView.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Settings/OpenFeatureDirectoryActionTests.swift`:
```swift
import XCTest
@testable import MacAllYouNeed

final class OpenFeatureDirectoryActionTests: XCTestCase {
    func testCreatesFeaturesDirectoryIfMissing() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenFeatureDirectoryActionTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let featuresDir = tempRoot.appendingPathComponent("Features", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: featuresDir.path))

        let url = OpenFeatureDirectoryAction.ensureDirectoryExists(at: featuresDir)
        XCTAssertEqual(url, featuresDir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: featuresDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testReturnsExistingDirectory() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OpenFeatureDirectoryActionTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let url = OpenFeatureDirectoryAction.ensureDirectoryExists(at: tempRoot)
        XCTAssertEqual(url, tempRoot)
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/OpenFeatureDirectoryActionTests | tail -10
```
Expected: compile error — `OpenFeatureDirectoryAction` does not exist yet.

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Settings/AdvancedActions/OpenFeatureDirectoryAction.swift`:
```swift
import AppKit
import Foundation

enum OpenFeatureDirectoryAction {
    /// `~/Library/Application Support/MacAllYouNeed/Features/` per design § 10.
    static func featuresDirectoryURL() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("MacAllYouNeed", isDirectory: true)
            .appendingPathComponent("Features", isDirectory: true)
    }

    /// Creates the directory if missing. Returns the URL either way. Pure helper for testability.
    @discardableResult
    static func ensureDirectoryExists(at url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func perform() {
        let url = ensureDirectoryExists(at: featuresDirectoryURL())
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
```

- [ ] **Step 4: Verify pass**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/OpenFeatureDirectoryActionTests | tail -10
```
Expected: PASS, 2/2.

- [ ] **Step 5: Wire into `AdvancedSettingsView.swift`**

In the "Setup and data" `MAYNSection`, add a new `MAYNSettingsRow` between "Onboarding" and "Reset all data":
```swift
MAYNDivider()
MAYNSettingsRow(
    title: "Feature install directory",
    subtitle: "Reveal `~/Library/Application Support/MacAllYouNeed/Features/` in Finder."
) {
    MAYNButton("Reveal") { OpenFeatureDirectoryAction.perform() }
}
```

- [ ] **Step 6: Manual smoke**

Build and run. Settings → Advanced → "Reveal". Finder opens to `~/Library/Application Support/MacAllYouNeed/Features/` with the directory selected. If the directory was missing, it's created first and then revealed. No errors in console.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/Settings/AdvancedActions/OpenFeatureDirectoryAction.swift \
        MacAllYouNeedTests/Settings/OpenFeatureDirectoryActionTests.swift \
        MacAllYouNeed/Settings/AdvancedSettingsView.swift
git commit -m "feat(modular-features): Open feature install directory action"
```

---

### Task 4: Confirm "Install pack from file…" placement in Advanced

**Files:**
- Possibly create: `MacAllYouNeed/Settings/AdvancedActions/SideloadPackAction.swift`
- Possibly modify: `MacAllYouNeed/Settings/AdvancedSettingsView.swift`

Phase 06 wired the side-load entry point per design § 4. Phase 12 verifies it's in Advanced (per design § 8) and not buried elsewhere; if Phase 06 placed it in the Features tab or somewhere else, move it.

- [ ] **Step 1: Find the existing side-load wiring**

```bash
grep -rn "SideloadInstaller\|Install pack from file\|sideload" \
  /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/
```

Expected: a button or menu item in either `AdvancedSettingsView.swift` or `FeaturesTabView.swift` calls `SideloadInstaller.install(from: pickedURL)`. Note the current location.

- [ ] **Step 2: If already in Advanced — verify and skip to Step 5**

If the side-load button is already in `AdvancedSettingsView.swift`'s "Setup and data" or a dedicated section, no code changes needed. Confirm the row uses standard MAYN copy:
- Title: "Install pack from file…"
- Subtitle: "Side-load a feature pack `.zip` you downloaded manually."
- Button label: "Install…"

If subtle copy differs, align it now.

- [ ] **Step 3: If located elsewhere — extract into `SideloadPackAction`**

Create `MacAllYouNeed/Settings/AdvancedActions/SideloadPackAction.swift`:
```swift
import AppKit
import FeatureCore  // for SideloadInstaller (defined in Phase 02)
import Foundation

@MainActor
struct SideloadPackAction {
    let runtime: FeatureRuntime

    func perform() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a feature pack .zip you downloaded."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                try await SideloadInstaller(runtime: runtime).install(from: url)
                presentSuccess()
            } catch {
                presentFailure(error: error)
            }
        }
    }

    private func presentSuccess() {
        let alert = NSAlert()
        alert.messageText = "Pack installed"
        alert.informativeText = "Open Settings → Features to enable it."
        alert.runModal()
    }

    private func presentFailure(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Install failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
```

The exact `SideloadInstaller` API comes from Phase 02. If Phase 02 named it differently, adjust. If Phase 06 already wraps the call inline, this Task replaces that with the action type.

- [ ] **Step 4: Wire into `AdvancedSettingsView.swift`**

Add a new `MAYNSection(title: "Feature packs")` (or extend "Setup and data" if it reads naturally) with:
```swift
MAYNSettingsRow(
    title: "Install pack from file…",
    subtitle: "Side-load a feature pack `.zip` you downloaded manually."
) {
    MAYNButton("Install…") { SideloadPackAction(runtime: controller.runtime).perform() }
}
```

Remove the original (now-orphan) wiring from wherever Phase 06 placed it.

- [ ] **Step 5: Manual smoke**

Build and run. Settings → Advanced → "Install…". File picker opens limited to `.zip`. Cancel — nothing happens. Pick a known-good pack zip from a Phase 06 fixture — install completes, success alert shows, the corresponding feature card in Features tab moves to `(.present, .disabled)`. Pick a known-bad zip (per Phase 02's security tests) — failure alert shows the reason.

- [ ] **Step 6: Commit (only if changes were made)**

```bash
git add -A MacAllYouNeed/Settings/
git commit -m "feat(modular-features): place sideload action in Advanced tab"
```

If no changes were needed (Phase 06 already placed it correctly), skip the commit.

---

### Task 5: "Reset all features…" destructive action

**Files:**
- Create: `MacAllYouNeed/Settings/AdvancedActions/ResetAllFeaturesAction.swift`
- Create: `MacAllYouNeedTests/Settings/ResetAllFeaturesActionTests.swift`
- Modify: `MacAllYouNeed/Settings/AdvancedSettingsView.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Settings/ResetAllFeaturesActionTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class ResetAllFeaturesActionTests: XCTestCase {
    func testResetReturnsEveryFeatureToBaselineState() async throws {
        let defaults = UserDefaults(suiteName: "ResetAllFeaturesActionTests-\(UUID())")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "") }

        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager, defaults: defaults)

        // Seed every feature into a non-baseline state (enabled, asset present where required).
        for descriptor in registry.descriptors {
            let asset: AssetState = descriptor.requiresAsset ? .present(version: "test") : .notRequired
            try await manager.setState(.init(assetState: asset, activationState: .enabled), for: descriptor.id)
        }

        try await ResetAllFeaturesAction.performWithoutConfirmation(runtime: runtime)

        for descriptor in registry.descriptors {
            let state = await manager.state(for: descriptor.id)
            XCTAssertEqual(state.activationState, .disabled,
                           "\(descriptor.id) must end disabled")
            let expectedAsset: AssetState = descriptor.requiresAsset ? .notDownloaded : .notRequired
            XCTAssertEqual(state.assetState, expectedAsset,
                           "\(descriptor.id) must end at \(expectedAsset)")
        }
    }

    func testResetDoesNotTouchUserDataDirectories() async throws {
        // Synthetic user-data directory under app support that "Reset all features" must NOT touch.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let userDataDir = appSupport.appendingPathComponent("MacAllYouNeed/databases", isDirectory: true)
        try FileManager.default.createDirectory(at: userDataDir, withIntermediateDirectories: true)
        let canary = userDataDir.appendingPathComponent("canary.txt")
        try "canary".write(to: canary, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: canary) }

        let defaults = UserDefaults(suiteName: "ResetAllFeaturesActionTests-\(UUID())")!
        let registry = FeatureRegistryProvider.makeRegistry()
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let runtime = FeatureRuntime(registry: registry, manager: manager, defaults: defaults)

        try await ResetAllFeaturesAction.performWithoutConfirmation(runtime: runtime)

        XCTAssertTrue(FileManager.default.fileExists(atPath: canary.path),
                      "Reset must not delete user data files")
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/ResetAllFeaturesActionTests | tail -10
```
Expected: compile error — `ResetAllFeaturesAction` does not exist yet.

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Settings/AdvancedActions/ResetAllFeaturesAction.swift`:
```swift
import AppKit
import FeatureCore
import Foundation

@MainActor
enum ResetAllFeaturesAction {
    static func perform(runtime: FeatureRuntime) {
        let alert = NSAlert()
        alert.messageText = "Reset all features?"
        alert.informativeText = """
            This will disable every feature and remove all downloaded asset packs. \
            Your user data (clipboard history, downloaded videos, snippets, model caches) \
            will NOT be deleted.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            var removedFeatures: [String] = []
            do {
                try await performWithoutConfirmation(runtime: runtime, removedFeatures: &removedFeatures)
                presentCompletion(removed: removedFeatures)
            } catch {
                presentFailure(error: error)
            }
        }
    }

    /// Test-friendly entry point; no UI.
    static func performWithoutConfirmation(runtime: FeatureRuntime) async throws {
        var ignored: [String] = []
        try await performWithoutConfirmation(runtime: runtime, removedFeatures: &ignored)
    }

    static func performWithoutConfirmation(runtime: FeatureRuntime,
                                           removedFeatures: inout [String]) async throws {
        for descriptor in runtime.registry.descriptors {
            // 1. Disable first so activator tears down workers cleanly.
            try await runtime.applyTransition(.disable, for: descriptor.id)

            // 2. If feature has an installed pack, remove it.
            if descriptor.requiresAsset {
                try await PackUninstaller.uninstall(featureID: descriptor.id, runtime: runtime)
                removedFeatures.append(descriptor.displayName)
            }
            // 3. Asset caches (Voice Qwen3 etc.) are NOT touched here. They are user-installed
            //    model weights; removing them belongs in the per-feature Uninstall sheet, not
            //    in a global "reset features" flow. The task brief calls this out explicitly.
        }
    }

    @MainActor
    private static func presentCompletion(removed: [String]) {
        let alert = NSAlert()
        alert.messageText = "Features reset"
        if removed.isEmpty {
            alert.informativeText = "All features are now disabled. No installed packs were present."
        } else {
            alert.informativeText = "All features are now disabled. Removed packs: \(removed.joined(separator: ", "))."
        }
        alert.runModal()
    }

    @MainActor
    private static func presentFailure(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Reset failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
```

If `PackUninstaller.uninstall(featureID:runtime:)` has a different signature in Phase 02, adjust the call site to match. The contract is: removes `Features/<id>/<version>/` and updates `assetState` to `.notDownloaded`. Asset caches under `Features/<id>/caches/` and user data outside `Features/` must not be touched.

- [ ] **Step 4: Verify tests pass**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/ResetAllFeaturesActionTests | tail -10
```
Expected: PASS, 2/2.

- [ ] **Step 5: Wire into `AdvancedSettingsView.swift`**

Add a new `MAYNSection(title: "Reset")` at the bottom (after "Setup and data"):
```swift
MAYNSection(title: "Reset") {
    MAYNSettingsRow(
        title: "Reset all features",
        subtitle: "Disable every feature and remove downloaded asset packs. User data is preserved."
    ) {
        MAYNButton("Reset…", role: .destructive) {
            ResetAllFeaturesAction.perform(runtime: controller.runtime)
        }
    }
}
```

Note: this is **separate** from the existing "Reset all data" button under "Setup and data" — that one wipes user data (databases, blobs, thumbnails). They have different scopes and both stay.

- [ ] **Step 6: Manual smoke**

Build and run. Pre-state: install Downloader (Phase 06 pack) and enable Voice. Settings → Advanced → "Reset…". Confirm:
1. Confirmation alert with the exact copy.
2. "Cancel" — nothing changes.
3. "Reset" — Settings → Features shows every card at `(.notDownloaded | .notRequired, .disabled)`. `~/Library/Application Support/MacAllYouNeed/Features/downloader/` is gone. `Features/voice/caches/` is **still present**. Clipboard DB and downloaded video files in user folders are untouched.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/Settings/AdvancedActions/ResetAllFeaturesAction.swift \
        MacAllYouNeedTests/Settings/ResetAllFeaturesActionTests.swift \
        MacAllYouNeed/Settings/AdvancedSettingsView.swift
git commit -m "feat(modular-features): Reset all features destructive action"
```

---

### Task 6: Final copy pass

This is a checklist task. No code changes unless a string is clearly wrong (typo, design-token mismatch, contradicts spec). Each item below maps to a file introduced by Phases 05–11. Walk it once, end-to-end, with the running app.

- [ ] **Step 1: Open every surface in turn**

For each item, open the surface in the running app and read the strings aloud. Note any inconsistency.

- `MacAllYouNeed/Settings/Features/FeatureCardActionView.swift` — button labels:
  - `[ Enable ]`, `[● Enabled]`, `[ Install ]`, `[ Cancel ]`, `[ Retry ]`, `Uninstall…`
  - Verify: matches design § 8 table exactly (no "Activate" / "Turn on" / "Add" variants).
- `MacAllYouNeed/Settings/Features/UninstallConfirmationSheet.swift` — sheet text:
  - Title: "Uninstall <displayName>?"
  - Body: matches design § 8 "Uninstall confirmation sheet" layout (pack to remove, opt-in caches, "Not affected" line).
  - Buttons: "Cancel" (default action) and "Uninstall" (destructive).
- `MacAllYouNeed/Onboarding/*` (Phase 09) — wizard copy:
  - Welcome, Picker, Per-feature setup, Done.
  - Verify: button labels are consistent with Features tab ("Install" not "Get", "Skip for now" not "Later").
- `MacAllYouNeed/Migration/WhatsNewSheetView.swift` (Phase 11) — "What's new" copy:
  - Verify: explicitly says nothing was disabled, mentions Hotkeys preserved (per design Risk #13).
- `Shared/Sources/FeaturePack/PackPipelineError.swift` (Phase 02) — error messages:
  - Some are technical (e.g., "per-file SHA mismatch at index 3"). For each, ensure there's a `LocalizedError.errorDescription` user-facing fallback (e.g., "The downloaded pack is corrupted.").
  - If a `PackPipelineError` case has no `errorDescription`, add one. Don't change the technical text — that goes to the log.
- `MacAllYouNeed/Settings/AdvancedSettingsView.swift` — the four new actions added in Tasks 2–5:
  - Verify titles, subtitles, button labels, alert messages all read naturally and consistently.
  - "Re-run", "Reveal", "Install…", "Reset…" — confirm trailing ellipsis convention matches macOS HIG (ellipsis means a follow-up dialog/picker).

- [ ] **Step 2: Record findings**

If everything reads cleanly, note "no changes" and move on. Otherwise, write the smallest possible edits — each one should trace to "this string contradicts the spec" or "this string is inconsistent with another we control".

- [ ] **Step 3: Commit any copy edits**

```bash
git add -A
git commit -m "feat(modular-features): copy pass over user-facing strings"
```

If no edits, skip this step entirely (no empty commit).

---

### Task 7: Manual QA matrix

This is a checklist run by a human. Check off each item only after observing the listed behavior. Each item maps to design § 11 "Manual QA matrix per release". Record the outcome inline (replace the placeholder `[observed: …]` with what you saw).

**Pre-flight:** Build a release-config build of the app; install onto a fresh user account or VM where possible. Tests on the developer machine are acceptable for items not OS-version-specific, but the OS-version sweep needs the matching macOS.

- [ ] **macOS 14 — fresh install**: Wizard runs to completion. Feature picker shows 4 cards, all unchecked. Skip → all features land `.disabled`. [observed: …]
- [ ] **macOS 15 — fresh install**: Same as above. [observed: …]
- [ ] **macOS 26 — fresh install**: Same as above. [observed: …]
- [ ] **Upgrade — Clipboard only prior usage**: "What's new" sheet appears once, says nothing was disabled. Clipboard `(.notRequired, .enabled)`. Downloader `(.notDownloaded, .disabled)` unless prior installs left binaries. [observed: …]
- [ ] **Upgrade — Downloader only prior usage**: Sparkle pre-install script ran; `Features/downloader/<v>/yt-dlp` and `ffmpeg` present; Downloader card `(.present, .enabled)`. [observed: …]
- [ ] **Upgrade — All four features prior usage**: Each feature lands at the right state per migration matrix. No data loss. [observed: …]
- [ ] **Upgrade — None used prior**: All features `.disabled`; "What's new" appears. [observed: …]
- [ ] **Resumability — Install Downloader, kill app mid-download, relaunch**: `URLSession` resume data picks up where it left off; final SHA verifies. [observed: …]
- [ ] **Network failure — Install Downloader, toggle airplane mode mid-download**: clear error UI; "Retry" works after re-enabling network. [observed: …]
- [ ] **SHA verification failure — corrupt the SHA in shipping manifest**: install fails with verification error; live state untouched; no orphan files in `Features/downloader/`. [observed: …]
- [ ] **Side-load symlink rejection**: feed a side-load zip with a symlink injected; `SideloadInstaller` rejects with a clear error before any extraction lands in `Features/`. [observed: …]
- [ ] **Voice disable flow**: Disable Voice → microphone use stops (verify via System Settings → Privacy → Microphone, no active indicator on menu bar); System Settings still lists MAYN as having permission. Re-enable → activator re-prompts only if user manually revoked permission in System Settings. [observed: …]
- [ ] **Downloader uninstall**: Uninstall Downloader → `Features/downloader/<v>/` gone; user's downloaded video files in their chosen output folder preserved. Re-enable Downloader → install prompt shown; install works. [observed: …]
- [ ] **Voice uninstall — caches retained**: Uninstall Voice with both Qwen3 cache checkboxes unchecked → `Features/voice/caches/` directories still present. [observed: …]
- [ ] **Voice uninstall — caches removed**: Uninstall Voice with both Qwen3 cache checkboxes checked → cache directories gone. [observed: …]
- [ ] **Folder Preview disabled placeholder**: Disable Folder Preview → Quick Look on a folder shows the placeholder `NSAttributedString` view. Re-enable → normal HTML preview returns. [observed: …]

- [ ] **Step 1: Record observations in this file**

Edit this Phase 12 plan file in-place: replace each `[observed: …]` with the actual outcome. Keep observations terse ("OK" if pass; otherwise a one-line description of what went wrong). If anything fails, **stop the QA pass** and file the issue. Do not proceed to Task 8 with failing items.

- [ ] **Step 2: Commit the recorded observations**

```bash
git add docs/superpowers/plans/2026-05-15-modular-features/12-cleanup.md
git commit -m "feat(modular-features): record manual QA matrix observations"
```

---

### Task 8: Phase verification

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
```
Expected: all green.

- [ ] **Step 2: SwiftLint strict**

Per `MacAllYouNeed/CLAUDE.md`, the design system is lint-enforced. Confirm:
```bash
swiftlint --strict --quiet --config /Users/mingjie.wang/Documents/personal/mac-all-you-need/.swiftlint.yml \
  /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Settings/ | tail -20
```
Expected: no violations. The new `AdvancedActions/` files use only `MAYNButton` and standard `NSAlert` / `NSOpenPanel` (not styled MAYN controls — both are macOS-native, not product-owned tab/segmented switches), so the design-system rules from `MacAllYouNeed/CLAUDE.md` § "Hard rules" do not apply.

- [ ] **Step 3: CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Manual smoke — every Advanced action one more time**

1. Settings → Advanced → "Re-run" → confirm → wizard reopens.
2. Settings → Advanced → "Reveal" → Finder opens to Features dir.
3. Settings → Advanced → "Install…" → file picker → cancel.
4. Settings → Advanced → "Reset…" → cancel → no state change.

- [ ] **Step 5: Mark Phase 12 complete in the index plan**

Edit `/Users/mingjie.wang/Documents/personal/mac-all-you-need/docs/superpowers/plans/2026-05-15-modular-features.md`:
```
- [x] Phase 12 — Cleanup & polish
```

---

### Task 9: Mark the entire `modular-features` initiative complete

**Files:**
- Modify: `docs/superpowers/plans/2026-05-15-modular-features.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a "Status" header to the index plan**

At the top of `docs/superpowers/plans/2026-05-15-modular-features.md`, immediately after the `# Modular Features — Implementation Plan Index` line, insert:
```markdown
## Status

✅ **Complete** — released in MAYN <version> on <date>.

Replace `<version>` with the release tag this initiative shipped under. Replace `<date>` with the release date (YYYY-MM-DD). If the release is gated behind Plan 7 (Distribution / notarization) and not yet shipped, write "Pending Plan 7 release" instead and update once Plan 7 ships.
```

(Yes, that markdown literally instructs the future editor what to write — keep it; it's the only way to be honest about not knowing the version at planning time.)

- [ ] **Step 2: Update `CLAUDE.md` "Plans Status" section**

Read the current section:
```bash
sed -n '178,188p' /Users/mingjie.wang/Documents/personal/mac-all-you-need/CLAUDE.md
```

Add a new line after `Plan 7`:
```
- Plan 8 ✅ Modular Features (FeatureRegistry, on-demand pack pipeline, conditional activation, Sparkle pre-install migration)
```

The numbering follows the existing pattern in `CLAUDE.md` (Plan 0..7). If by the time this lands a different plan was assigned the number 8, bump to the next free integer and adjust accordingly. Do not renumber existing entries.

Do **not** modify Plan 2's status (`⏳ Sync Engine (skipped indefinitely)`) — Sync staying deferred is the correct state. The Sync UI removal happened in Phase 12, but the Sync engine itself was never built and remains intentionally absent.

- [ ] **Step 3: Verify CLAUDE.md still parses**

```bash
head -200 /Users/mingjie.wang/Documents/personal/mac-all-you-need/CLAUDE.md | tail -25
```
Visual sanity check that the new line is in the right section and the surrounding bullet list is intact.

- [ ] **Step 4: Final commit**

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md \
        docs/superpowers/plans/2026-05-15-modular-features/12-cleanup.md \
        CLAUDE.md
git commit -m "feat(modular-features): mark Phase 12 + initiative complete"
```

- [ ] **Step 5: Open final PR**

```bash
git push -u origin <branch>
gh pr create --title "Phase 12 — Cleanup & polish (modular-features done)" \
  --body "Implements docs/superpowers/plans/2026-05-15-modular-features/12-cleanup.md and closes the modular-features initiative.

- Removes Sync settings surface (Plan 2 deferred indefinitely).
- Adds the four Advanced-tab actions per design § 8 (Re-run onboarding, Open feature install directory, Install pack from file, Reset all features).
- Final copy pass over Features tab, Uninstall sheet, onboarding, What's new, and PackPipelineError messages.
- Manual QA matrix run (per design § 11) — observations recorded in the plan file.
- Marks the entire modular-features initiative complete in the index plan and in CLAUDE.md."
```
