# Phase 05 — Features Tab UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the user-visible Features tab in Settings: card grid, Enable/Disable toggle wired through `FeatureRuntime`, Uninstall confirmation sheet enumerating asset caches, conditional per-feature tabs, Hotkeys-tab grey-out for disabled features.

**Architecture:** A `FeaturesTabView` reads from `AppController.runtime.registry`, observes `FeatureManager` state via a polling Combine publisher (Phase 10's Darwin-notification observer is daemon-only; main-app updates flow via `@Published` mirror in `AppController`). Each card is a `FeatureCardView`. Uninstall is a `.confirmationDialog` driven by a shared `UninstallSheetState` value type.

**Tech Stack:** SwiftUI, Combine, the existing MAYN design system (`MAYNTheme`, `MAYNControlMetrics`, `FunctionSegmentedTabStrip`, `MAYNDropdown`).

**Depends on:** Phase 04 (`FeatureRuntime`).

---

## File structure

```
MacAllYouNeed/Settings/Features/
├── FeaturesTabView.swift              ← top-level Features tab
├── FeatureCardView.swift              ← one card per descriptor
├── FeatureCardActionView.swift        ← state→control mapping (Install/Enable/Disable/Uninstall)
├── UninstallSheetState.swift          ← value type powering the confirmation
├── UninstallConfirmationSheet.swift   ← sheet view
└── FeatureStatePublisher.swift        ← @Published mirror of FeatureManager state on AppController

MacAllYouNeed/App/
└── AppController.swift                ← MODIFY: add @Published feature-state mirror

MacAllYouNeedTests/Settings/
├── FeatureCardViewTests.swift         ← snapshot tests per state from § 8 of the spec
└── UninstallSheetStateTests.swift
```

---

### Task 1: `FeatureStatePublisher` — `@Published` mirror on `AppController`

**Files:**
- Create: `MacAllYouNeed/Settings/Features/FeatureStatePublisher.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 1: Implement publisher**

Create `MacAllYouNeed/Settings/Features/FeatureStatePublisher.swift`:
```swift
import Combine
import FeatureCore
import Foundation

/// Mirrors FeatureManager state into a Published dict that SwiftUI can observe.
/// FeatureManager is an actor (writes are async); UI needs synchronous reads.
/// This class is the bridge.
@MainActor
final class FeatureStatePublisher: ObservableObject {
    @Published private(set) var states: [FeatureID: FeatureRuntimeState] = [:]
    private let runtime: FeatureRuntime

    init(runtime: FeatureRuntime) {
        self.runtime = runtime
        Task { await self.refresh() }
    }

    func refresh() async {
        let snapshot = await runtime.manager.allStates()
        states = snapshot
    }

    func state(for id: FeatureID) -> FeatureRuntimeState {
        states[id] ?? .initialDefault(assetRequired: false)
    }
}
```

- [ ] **Step 2: Add publisher to AppController**

In `AppController.swift`, add:
```swift
@MainActor
let featureStatePublisher: FeatureStatePublisher

// inside init():
self.featureStatePublisher = FeatureStatePublisher(runtime: runtime)
```

The publisher should refresh after every transition. Modify `FeatureRuntime.applyTransition` to post to `NotificationCenter.default` on completion:
```swift
public func applyTransition(...) async throws {
    try await manager.transition(transition, for: id)
    // ... existing activator side-effects ...
    NotificationCenter.default.post(name: .featureRuntimeStateChanged, object: nil)
}
```

Add the notification name in `Shared/Sources/FeatureCore/DarwinNotification.swift`:
```swift
import Foundation
public extension Notification.Name {
    static let featureRuntimeStateChanged = Notification.Name("featureRuntimeStateChanged")
}
```

In `FeatureStatePublisher.init`, subscribe:
```swift
NotificationCenter.default.addObserver(forName: .featureRuntimeStateChanged, object: nil, queue: .main) { [weak self] _ in
    Task { await self?.refresh() }
}
```

- [ ] **Step 3: Build verify + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

```bash
git add MacAllYouNeed/Settings/Features/FeatureStatePublisher.swift MacAllYouNeed/App/AppController.swift Shared/Sources/FeatureCore/DarwinNotification.swift
git commit -m "feat(modular-features): add FeatureStatePublisher SwiftUI bridge"
```

---

### Task 2: `UninstallSheetState` value type

**Files:**
- Create: `MacAllYouNeed/Settings/Features/UninstallSheetState.swift`
- Create: `MacAllYouNeedTests/Settings/UninstallSheetStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class UninstallSheetStateTests: XCTestCase {
    func testEnumeratesAllCachesAsUnchecked() {
        let cache1 = AssetCacheDescriptor(id: "c1", displayName: "Cache 1",
                                          directoryURL: { URL(fileURLWithPath: "/tmp/c1") },
                                          estimatedBytes: 100_000_000, category: .modelWeights)
        let cache2 = AssetCacheDescriptor(id: "c2", displayName: "Cache 2",
                                          directoryURL: { URL(fileURLWithPath: "/tmp/c2") },
                                          estimatedBytes: 200_000_000, category: .modelWeights)
        let descriptor = FeatureDescriptor(
            id: .voice, displayName: "Voice", icon: "mic",
            summary: "", detailDescription: "",
            assetCaches: [cache1, cache2],
            activator: NoopFeatureActivator()
        )

        let state = UninstallSheetState.from(descriptor: descriptor)
        XCTAssertEqual(state.cacheRows.count, 2)
        for row in state.cacheRows {
            XCTAssertFalse(row.checked, "all caches default unchecked")
        }
    }

    func testTogglingCacheChecksThatCacheOnly() {
        var state = UninstallSheetState(cacheRows: [
            .init(id: "c1", displayName: "C1", bytes: 1, checked: false),
            .init(id: "c2", displayName: "C2", bytes: 2, checked: false),
        ])
        state.toggle(cacheID: "c1")
        XCTAssertTrue(state.cacheRows[0].checked)
        XCTAssertFalse(state.cacheRows[1].checked)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/UninstallSheetStateTests
```

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Settings/Features/UninstallSheetState.swift`:
```swift
import FeatureCore
import Foundation

struct UninstallSheetState {
    struct CacheRow: Identifiable, Equatable {
        let id: String
        let displayName: String
        let bytes: Int64
        var checked: Bool
    }

    var cacheRows: [CacheRow]

    static func from(descriptor: FeatureDescriptor) -> UninstallSheetState {
        UninstallSheetState(cacheRows: descriptor.assetCaches.map { cache in
            CacheRow(
                id: cache.id,
                displayName: cache.displayName,
                bytes: cache.actualBytes() != 0 ? cache.actualBytes() : cache.estimatedBytes,
                checked: false
            )
        })
    }

    mutating func toggle(cacheID: String) {
        guard let idx = cacheRows.firstIndex(where: { $0.id == cacheID }) else { return }
        cacheRows[idx].checked.toggle()
    }

    var checkedCacheIDs: [String] {
        cacheRows.filter(\.checked).map(\.id)
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/UninstallSheetStateTests | tail -10
```
Expected: PASS, 2/2.

```bash
git add MacAllYouNeed/Settings/Features/UninstallSheetState.swift MacAllYouNeedTests/Settings/UninstallSheetStateTests.swift
git commit -m "feat(modular-features): add UninstallSheetState"
```

---

### Task 3: `FeatureCardActionView` — state→control mapping

**Files:**
- Create: `MacAllYouNeed/Settings/Features/FeatureCardActionView.swift`

- [ ] **Step 1: Implement**

```swift
import FeatureCore
import SwiftUI

struct FeatureCardActionView: View {
    let descriptor: FeatureDescriptor
    let state: FeatureRuntimeState
    let onInstall: () -> Void
    let onEnable: () -> Void
    let onDisable: () -> Void
    let onUninstall: () -> Void
    let onCancelDownload: () -> Void
    let onRetryInstall: () -> Void

    var body: some View {
        switch (state.assetState, state.activationState) {
        case (.notRequired, .disabled):
            Button("Enable", action: onEnable).buttonStyle(.borderedProminent)
        case (.notRequired, .enabled):
            HStack {
                Toggle("Enabled", isOn: .init(get: { true }, set: { _ in onDisable() }))
                    .toggleStyle(.switch)
            }
        case (.notDownloaded, _):
            Button("Install", action: onInstall).buttonStyle(.borderedProminent)
        case (.downloading(let progress), _):
            HStack(spacing: 12) {
                ProgressView(value: progress).frame(maxWidth: 200)
                Button("Cancel", action: onCancelDownload).buttonStyle(.bordered)
            }
        case (.downloadFailed(let reason), _):
            HStack {
                Text(reason).font(.caption).foregroundStyle(.red)
                Button("Retry", action: onRetryInstall).buttonStyle(.borderedProminent)
            }
        case (.present, .disabled):
            HStack {
                Button("Enable", action: onEnable).buttonStyle(.borderedProminent)
                Menu("⋯") {
                    Button("Uninstall…", role: .destructive, action: onUninstall)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        case (.present, .enabled):
            HStack {
                Toggle("Enabled", isOn: .init(get: { true }, set: { _ in onDisable() }))
                    .toggleStyle(.switch)
                Menu("⋯") {
                    Button("Uninstall…", role: .destructive, action: onUninstall)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/Settings/Features/FeatureCardActionView.swift
git commit -m "feat(modular-features): add FeatureCardActionView state→control mapping"
```

---

### Task 4: `FeatureCardView`

**Files:**
- Create: `MacAllYouNeed/Settings/Features/FeatureCardView.swift`
- Create: `MacAllYouNeedTests/Settings/FeatureCardViewTests.swift`

- [ ] **Step 1: Write snapshot tests**

```swift
import XCTest
import SwiftUI
import FeatureCore
@testable import MacAllYouNeed

final class FeatureCardViewTests: XCTestCase {
    func testRendersDisplayName() {
        let descriptor = FeatureDescriptor(
            id: .clipboard, displayName: "Clipboard Manager", icon: "doc.on.clipboard",
            summary: "Copy history.", detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let view = FeatureCardView(
            descriptor: descriptor,
            state: .init(assetState: .notRequired, activationState: .disabled),
            onAction: { _ in }
        )
        // Render to host and assert the displayName is present.
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let renderedText = host.descendantText()
        XCTAssertTrue(renderedText.contains("Clipboard Manager"))
        XCTAssertTrue(renderedText.contains("Copy history."))
    }
}

private extension NSView {
    func descendantText() -> String {
        var pieces: [String] = []
        if let textView = self as? NSTextField { pieces.append(textView.stringValue) }
        for sub in subviews { pieces.append(sub.descendantText()) }
        return pieces.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Run to confirm fail**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureCardViewTests
```

- [ ] **Step 3: Implement**

Create `MacAllYouNeed/Settings/Features/FeatureCardView.swift`:
```swift
import FeatureCore
import SwiftUI

struct FeatureCardView: View {
    enum Action {
        case install, enable, disable, uninstall, cancelDownload, retryInstall
    }

    let descriptor: FeatureDescriptor
    let state: FeatureRuntimeState
    let onAction: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: descriptor.icon).font(.title2)
                Text(descriptor.displayName).font(.headline)
                Spacer()
                statusBadge
            }
            Text(descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
            if !descriptor.requiredPermissions.isEmpty {
                Text(permissionsDescription).font(.caption).foregroundStyle(.tertiary)
            }
            FeatureCardActionView(
                descriptor: descriptor,
                state: state,
                onInstall: { onAction(.install) },
                onEnable: { onAction(.enable) },
                onDisable: { onAction(.disable) },
                onUninstall: { onAction(.uninstall) },
                onCancelDownload: { onAction(.cancelDownload) },
                onRetryInstall: { onAction(.retryInstall) }
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(MAYNTheme.cardBackground))
    }

    private var statusBadge: some View {
        switch (state.assetState, state.activationState) {
        case (_, .enabled): return AnyView(Text("Enabled").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.green.opacity(0.2))))
        case (.notDownloaded, _): return AnyView(Text("Not installed").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.gray.opacity(0.2))))
        default: return AnyView(Text("Disabled").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(.gray.opacity(0.2))))
        }
    }

    private var permissionsDescription: String {
        let names = descriptor.requiredPermissions.map { "\($0)" }.joined(separator: ", ")
        return "Permissions: \(names)"
    }
}
```

- [ ] **Step 4: Verify pass + commit**

```bash
xcodebuild test ... -only-testing:MacAllYouNeedTests/FeatureCardViewTests | tail -10
```
Expected: PASS, 1/1.

```bash
git add MacAllYouNeed/Settings/Features/FeatureCardView.swift MacAllYouNeedTests/Settings/FeatureCardViewTests.swift
git commit -m "feat(modular-features): add FeatureCardView"
```

---

### Task 5: `UninstallConfirmationSheet`

**Files:**
- Create: `MacAllYouNeed/Settings/Features/UninstallConfirmationSheet.swift`

- [ ] **Step 1: Implement**

```swift
import FeatureCore
import SwiftUI

struct UninstallConfirmationSheet: View {
    let descriptor: FeatureDescriptor
    @State private var sheetState: UninstallSheetState
    let onCancel: () -> Void
    let onConfirm: (UninstallSheetState) -> Void

    init(descriptor: FeatureDescriptor, onCancel: @escaping () -> Void, onConfirm: @escaping (UninstallSheetState) -> Void) {
        self.descriptor = descriptor
        self._sheetState = State(initialValue: UninstallSheetState.from(descriptor: descriptor))
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall \(descriptor.displayName)?").font(.title3).bold()
            Text("Pack files will be removed.").font(.subheadline).foregroundStyle(.secondary)

            if !sheetState.cacheRows.isEmpty {
                Divider()
                Text("Optional: also remove cached data").font(.caption).foregroundStyle(.secondary)
                ForEach(sheetState.cacheRows) { row in
                    Toggle(isOn: .init(
                        get: { row.checked },
                        set: { _ in sheetState.toggle(cacheID: row.id) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(row.displayName)
                            Text(formatBytes(row.bytes)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()
            Text("User documents (downloaded video files, exported items) are always preserved.")
                .font(.caption).foregroundStyle(.tertiary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Uninstall", role: .destructive) { onConfirm(sheetState) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
    }

    private func formatBytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
}
```

- [ ] **Step 2: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
git add MacAllYouNeed/Settings/Features/UninstallConfirmationSheet.swift
git commit -m "feat(modular-features): add UninstallConfirmationSheet"
```

---

### Task 6: `FeaturesTabView` — replace stub with real grid

**Files:**
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift` (delete the stub `FeaturesTabView` from Phase 04)
- Create: `MacAllYouNeed/Settings/Features/FeaturesTabView.swift`

- [ ] **Step 1: Implement**

```swift
import FeatureCore
import SwiftUI

struct FeaturesTabView: View {
    @ObservedObject var controller: AppController
    @State private var pendingUninstall: FeatureDescriptor?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                ForEach(controller.runtime.registry.descriptors, id: \.id) { descriptor in
                    FeatureCardView(
                        descriptor: descriptor,
                        state: controller.featureStatePublisher.state(for: descriptor.id),
                        onAction: { handle($0, for: descriptor) }
                    )
                }
            }
            .padding(20)
        }
        .sheet(item: $pendingUninstall) { descriptor in
            UninstallConfirmationSheet(
                descriptor: descriptor,
                onCancel: { pendingUninstall = nil },
                onConfirm: { sheet in
                    pendingUninstall = nil
                    Task { await performUninstall(descriptor: descriptor, sheetState: sheet) }
                }
            )
        }
    }

    private func handle(_ action: FeatureCardView.Action, for descriptor: FeatureDescriptor) {
        switch action {
        case .install:
            // Wired in Phase 06 to the real PackDownloader.
            // For Phase 05 (no asset feature in scope yet), no-op except for sample registry slot.
            break
        case .enable:
            Task { try await controller.runtime.applyTransition(.enable, for: descriptor.id) }
        case .disable:
            Task { try await controller.runtime.applyTransition(.disable, for: descriptor.id) }
        case .uninstall:
            pendingUninstall = descriptor
        case .cancelDownload, .retryInstall:
            break  // Phase 06
        }
    }

    private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
        // Asset removal lives in Phase 06's pipeline; cache removal is universal:
        for cacheID in sheetState.checkedCacheIDs {
            if let cache = descriptor.assetCaches.first(where: { $0.id == cacheID }) {
                try? FileManager.default.removeItem(at: cache.directoryURL())
            }
        }
        try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
        // Phase 06 will additionally call PackUninstaller for asset features.
    }
}

extension FeatureDescriptor: Identifiable {}
```

- [ ] **Step 2: Delete the stub `FeaturesTabView` from Phase 04**

In `MacAllYouNeed/Settings/SettingsRoot.swift`, remove the `struct FeaturesTabView` declaration that was added in Phase 04 Task 4 Step 4.

- [ ] **Step 3: Build verify**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Settings/Features/FeaturesTabView.swift MacAllYouNeed/Settings/SettingsRoot.swift
git commit -m "feat(modular-features): real FeaturesTabView replaces Phase 04 stub"
```

---

### Task 7: Conditional per-feature settings tabs

**Files:**
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`

- [ ] **Step 1: Update `featureTabs(registry:)` to accept state**

In `SettingsRoot.swift`:
```swift
static func featureTabs(registry: FeatureRegistry, states: [FeatureID: FeatureRuntimeState]) -> [(FeatureID, AnyView)] {
    registry.descriptors.compactMap { d in
        guard let factory = d.settingsTabFactory else { return nil }
        let state = states[d.id] ?? .initialDefault(assetRequired: d.requiresAsset)
        // Hide the tab when the feature is .notDownloaded (nothing to configure yet).
        if state.assetState == .notDownloaded { return nil }
        return (d.id, factory())
    }
}
```

In `body`, change the `ForEach` to:
```swift
ForEach(Self.featureTabs(registry: controller.runtime.registry,
                          states: controller.featureStatePublisher.states), id: \.0) { (id, view) in
    view
        .tabItem { Label(controller.runtime.registry.descriptor(for: id)!.displayName,
                         systemImage: controller.runtime.registry.descriptor(for: id)!.icon) }
        .tag(SettingsDestination.feature(id))
}
```

- [ ] **Step 2: Add disabled-feature banner inside the per-feature views**

Add a helper:
```swift
struct DisabledFeatureBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "info.circle")
            Text("This feature is disabled. Settings here will apply when you re-enable it.")
            Spacer()
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15))
    }
}
```

Each per-feature settings view (e.g., `ClipboardSettingsView`) should be wrapped with this banner when disabled. A small wrapper helper:
```swift
struct FeatureSettingsContainer<Content: View>: View {
    let id: FeatureID
    @ObservedObject var controller: AppController
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if controller.featureStatePublisher.state(for: id).activationState == .disabled {
                DisabledFeatureBanner()
            }
            content()
        }
    }
}
```

Update each `settingsTabFactory` in `FeatureRegistryProvider` to wrap:
```swift
settingsTabFactory: { AnyView(FeatureSettingsContainer(id: .clipboard, controller: AppController.shared) { ClipboardSettingsView() }) }
```

(Repeat for `.folderPreview`, `.downloader`, `.voice`.)

- [ ] **Step 3: Manual verify**

Build and run. In Settings → Features, disable Clipboard. Switch to Clipboard tab — banner appears. Re-enable — banner disappears.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Settings/SettingsRoot.swift MacAllYouNeed/App/FeatureRegistryProvider.swift
git commit -m "feat(modular-features): conditional per-feature tabs + disabled banner"
```

---

### Task 8: Hotkeys tab grey-out

**Files:**
- Modify: `MacAllYouNeed/Settings/HotkeysSettingsView.swift` (path may vary)

- [ ] **Step 1: Read current view**

```bash
find /Users/mingjie.wang/Documents/personal/mac-all-you-need -name "HotkeysSettingsView.swift"
cat <found-path>
```

- [ ] **Step 2: Refactor to iterate registry, grey-out disabled features**

Replace the hardcoded list with:
```swift
struct HotkeysSettingsView: View {
    @ObservedObject var controller: AppController = .shared

    var body: some View {
        let registry = controller.runtime.registry
        let states = controller.featureStatePublisher.states

        return List {
            ForEach(registry.descriptors, id: \.id) { descriptor in
                Section(descriptor.displayName) {
                    ForEach(descriptor.hotkeys, id: \.identifier) { hotkey in
                        let enabled = states[descriptor.id]?.activationState == .enabled
                        HStack {
                            Text(hotkey.displayName)
                                .foregroundStyle(enabled ? .primary : .tertiary)
                            Spacer()
                            if !enabled {
                                Text("Disabled").font(.caption).foregroundStyle(.tertiary)
                            }
                            ShortcutChip(identifier: hotkey.identifier)
                                .disabled(!enabled)
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Verify build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -5
git add MacAllYouNeed/Settings/HotkeysSettingsView.swift
git commit -m "feat(modular-features): Hotkeys tab grey-out for disabled features"
```

---

### Task 9: Phase verification

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
```
Expected: all green.

- [ ] **Step 2: Manual smoke**

Launch app. In Settings → Features:
- All four cards visible.
- Click Disable on Clipboard. Cmd-Shift-V no longer shows popup. Per-feature Clipboard tab shows "disabled" banner.
- Click Enable on Clipboard. Cmd-Shift-V popup returns; banner gone.
- Click Uninstall… on Voice. Sheet shows (no caches yet — Phase 07). Confirm. Voice deactivates.

- [ ] **Step 3: CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md` to mark Phase 05 complete.

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 05 complete"
git push -u origin <branch>
gh pr create --title "Phase 05 — Features Tab UI" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/05-features-tab-ui.md"
```
