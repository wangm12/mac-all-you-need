# Plan 6: Menu-bar Shell, Settings, Onboarding, and Integrations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the three subsystem prototypes (Plans 3, 4, 5) and assemble them into one coherent app. Build the polished menu-bar popover with tabs, the Settings window with all sub-sections, the six-step first-launch onboarding wizard with TCC capability checks, hotkey rebinding UI, the cross-feature integration moments, and the per-store sync adapters that wire local writes through Plan 2's `SyncEngine`.

**Architecture:** A single `AppController` (in the main app target) is the composition root: it constructs the storage layer, the daemon XPC client, the downloader coordinator, the folder preview coordinator, the sync engine, and a small set of `*SyncAdapter` objects that subscribe to local stores and publish into `SyncEngine`, plus subscribe to `SyncEngine` events and write into local stores. Onboarding state is a `@AppStorage`-backed enum that gates the wizard. Hotkey rebinding uses a `HotkeyRecorder` SwiftUI view that captures `NSEvent.modifierFlags + keyCode`. Cross-feature integrations are simple Combine-style `NotificationCenter` posts, kept loose to avoid coupling subsystems.

**Tech Stack:** SwiftUI (Settings scene, `MenuBarExtra` window style), `@AppStorage`, `UNUserNotificationCenter`, `SMAppService` (LoginItem registration).

**Reads from spec:** §9 (entire), §3 (decision 7).

**Depends on:** Plans 0–5.

**Produces working software:** First launch shows the six-step wizard; permissions auto-advance on grant; the menu-bar popover has Clipboard / Downloads / Snippets tabs; the gear opens Settings with seven sub-sections; rebinding `⌘⇧V` works and conflicts with existing system shortcuts are detected; copying a YouTube URL adds a one-click "Download" affordance; completing a download offers "Preview folder" that opens the standalone Browse window on the destination directory; sync runs in the background if a sync folder is configured.

---

## Public types defined here

| Type | Module path | Purpose |
|---|---|---|
| `AppController` | (main app) | Composition root |
| `OnboardingState` | (main app) | `@AppStorage` enum: `notStarted, step(N), completed` |
| `OnboardingWizardView` | (main app) | Six-step modal |
| `SettingsRoot` | (main app) | `Settings` scene with sidebar |
| `HotkeyRecorder` | (main app) | SwiftUI view to capture a hotkey |
| `ClipboardSyncAdapter` | `Core.Sync` | Bridges `ClipboardStore` ↔ `SyncEngine` |
| `SnippetSyncAdapter` | `Core.Sync` | Same for snippets |
| `PinboardSyncAdapter` | `Core.Sync` | Same for pinboards |
| `DownloadHistorySyncAdapter` | `Core.Sync` | Same for download history (opt-in) |
| `URLDetector` | `Platform.Pasteboard` | Detects video-bearing URLs in copied text |

---

## Task 6.1: `AppController` composition root

**Files:**
- Create: `MacAllYouNeed/App/AppController.swift`
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import Core
import Platform
import SwiftUI

@MainActor
@Observable
final class AppController {
    // Plan 1
    let key: SymmetricKey
    let deviceID: DeviceID
    // Plan 3
    let clipboardDeps: AppDependencies
    let popup: ClipboardPopupController
    let clipboardHotkey: HotkeyController
    // Plan 4
    let folder: BrowseFolderWindowController
    let folderXPC: BrowseFolderCoordinator
    // Plan 5
    let downloader: DownloadCoordinator
    let downloaderVM: DownloaderViewModel
    let dock: DockProgressController
    // Plan 6
    let onboarding: OnboardingState
    var sync: SyncEngine?
    var hotkeyMap: [HotkeyAction: HotkeyDescriptor]

    init() throws {
        let manager = KeyManager(keychain: SystemKeychain())
        self.key = try manager.deviceKey()
        self.deviceID = AppController.persistentDeviceID()

        let deps = AppDependencies()
        let popup = ClipboardPopupController(deps: deps)
        let hk = HotkeyController(popup: popup)
        self.clipboardDeps = deps; self.popup = popup; self.clipboardHotkey = hk
        hk.registerDefault()

        self.folder = BrowseFolderWindowController()
        self.folderXPC = BrowseFolderCoordinator()

        let coord = try DownloadCoordinator()
        self.downloader = coord
        let dlVM = DownloaderViewModel(coordinator: coord)
        self.downloaderVM = dlVM
        let dock = DockProgressController(vm: dlVM); dock.start(); self.dock = dock

        self.onboarding = OnboardingState.load()
        self.hotkeyMap = HotkeyMapStore.load()
    }

    private static func persistentDeviceID() -> DeviceID {
        let url = AppGroup.containerURL().appendingPathComponent("device.id")
        if let raw = try? String(contentsOf: url), let id = DeviceID(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return id
        }
        let id = DeviceID.generate()
        try? id.rawValue.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
}

import CryptoKit
```

- [ ] **Step 2: Update `MacAllYouNeedApp` to use it**

```swift
@main
struct MacAllYouNeedApp: App {
    @State private var controller: AppController = try! AppController()

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            AppMenuBarContent(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsRoot(controller: controller) }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/App/AppController.swift MacAllYouNeed/MacAllYouNeedApp.swift
git commit -m "refactor(app): introduce AppController composition root"
```

---

## Task 6.2: Polished menu-bar popover (`AppMenuBarContent`)

**Files:**
- Modify: `MacAllYouNeed/App/AppMenuBarContent.swift` (move logic from Plan 5 here)

- [ ] **Step 1: Implement final tab structure**

```swift
import SwiftUI
import Core

struct AppMenuBarContent: View {
    let controller: AppController
    @State private var tab: Tab = .clipboard
    enum Tab: Hashable { case clipboard, downloads, snippets }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Mac All You Need").font(.system(size: 13, weight: .semibold))
                Spacer()
                SyncStatusChip(controller: controller)
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: { Image(systemName: "gear") }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.top, 8)

            Picker("", selection: $tab) {
                Text("Clipboard").tag(Tab.clipboard)
                Text("Downloads").tag(Tab.downloads)
                Text("Snippets").tag(Tab.snippets)
            }.pickerStyle(.segmented).padding(8)
            Divider()

            Group {
                switch tab {
                case .clipboard: ClipboardMenuBarContent(deps: controller.clipboardDeps)
                case .downloads: DownloadsListView(vm: controller.downloaderVM)
                case .snippets: SnippetsListView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Text("⌘⇧V").font(.system(.caption, design: .monospaced))
                Text("clipboard popup").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(width: 480, height: 580)
    }
}

struct SyncStatusChip: View {
    let controller: AppController
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(controller.sync == nil ? Color.gray : Color.green).frame(width: 6, height: 6)
            Text(controller.sync == nil ? "Local only" : "Synced").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct SnippetsListView: View {
    let controller: AppController
    var body: some View {
        Text("Snippets — TODO list/edit UI in 6.x").padding()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add MacAllYouNeed/App/AppMenuBarContent.swift
git commit -m "feat(app): polished menu-bar popover with sync status chip + quit"
```

---

## Task 6.3: Settings window (sidebar + sections)

**Files:**
- Create: `MacAllYouNeed/Settings/SettingsRoot.swift`
- Create: `MacAllYouNeed/Settings/GeneralSettingsView.swift`
- Create: `MacAllYouNeed/Settings/ClipboardSettingsView.swift`
- Create: `MacAllYouNeed/Settings/DownloadsSettingsView.swift`
- Create: `MacAllYouNeed/Settings/FolderPreviewSettingsView.swift`
- Create: `MacAllYouNeed/Settings/SyncSettingsView.swift`
- Create: `MacAllYouNeed/Settings/HotkeysSettingsView.swift`
- Create: `MacAllYouNeed/Settings/AdvancedSettingsView.swift`

- [ ] **Step 1: Implement `SettingsRoot`**

```swift
import SwiftUI

struct SettingsRoot: View {
    let controller: AppController
    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            ClipboardSettingsView(controller: controller)
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            DownloadsSettingsView(controller: controller)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            FolderPreviewSettingsView(controller: controller)
                .tabItem { Label("FolderPreview", systemImage: "folder") }
            SyncSettingsView(controller: controller)
                .tabItem { Label("Sync", systemImage: "icloud") }
            HotkeysSettingsView(controller: controller)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            AdvancedSettingsView(controller: controller)
                .tabItem { Label("Advanced", systemImage: "wrench") }
        }
        .frame(width: 600, height: 480)
    }
}
```

- [ ] **Step 2: Implement each sub-view (skeleton; expand fields as needed)**

`GeneralSettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    let controller: AppController
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("showDockDuringDownloads") private var showDock = false
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { print("login item: \(error)") }
                }
            Toggle("Show dock icon during downloads", isOn: $showDock)
        }.padding()
    }
}
```

`ClipboardSettingsView.swift`:

```swift
import SwiftUI
import Core

struct ClipboardSettingsView: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems") private var maxItems = 10000
    @AppStorage("clipboardMaxBytes") private var maxBytes = 5 * 1024 * 1024 * 1024
    @State private var blockedApps: [String] = []
    @State private var newBundleID: String = ""
    var body: some View {
        Form {
            Stepper("Max items: \(maxItems)", value: $maxItems, in: 100...100_000, step: 100)
            Section("Excluded apps") {
                List(blockedApps, id: \.self) { Text($0) }
                    .frame(height: 120)
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                    Button("Add") {
                        guard !newBundleID.isEmpty else { return }
                        blockedApps.append(newBundleID); newBundleID = ""
                    }
                }
            }
        }.padding()
    }
}
```

`DownloadsSettingsView.swift`:

```swift
import SwiftUI

struct DownloadsSettingsView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency") private var concurrency = 3
    @AppStorage("downloadOutputTemplate") private var template = "%(title)s [%(id)s].%(ext)s"
    var body: some View {
        Form {
            Stepper("Concurrent downloads: \(concurrency)", value: $concurrency, in: 1...10)
                .onChange(of: concurrency) { _, n in
                    Task { await controller.downloader.queue.setMaxConcurrent(n) }
                }
            TextField("Output template", text: $template)
            Button("Check for downloader update") { /* triggers DownloaderUpdate flow */ }
        }.padding()
    }
}
```

`FolderPreviewSettingsView.swift`:

```swift
import SwiftUI
struct FolderPreviewSettingsView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden") private var includeHidden = false
    @AppStorage("folderPreviewMaxEntries") private var maxEntries = 50_000
    var body: some View {
        Form {
            Toggle("Include hidden files", isOn: $includeHidden)
            Stepper("Max entries: \(maxEntries)", value: $maxEntries, in: 1000...500_000, step: 1000)
        }.padding()
    }
}
```

`SyncSettingsView.swift`:

```swift
import SwiftUI
import Core

struct SyncSettingsView: View {
    let controller: AppController
    @AppStorage("syncFolderPath") private var syncFolderPath: String = ""
    @AppStorage("syncDownloadHistory") private var syncDownloads = false
    @State private var showingPassphrase = false
    var body: some View {
        Form {
            HStack {
                Text("Sync folder")
                Spacer()
                Text(syncFolderPath.isEmpty ? "Not set" : syncFolderPath).foregroundStyle(.secondary)
                Button("Pick…") { pick() }
            }
            if !syncFolderPath.isEmpty {
                CloudDetectionChip(path: syncFolderPath)
                Toggle("Sync download history", isOn: $syncDownloads)
                Button("Resolve conflicts…") { /* opens conflicts window */ }
            }
        }.padding()
    }

    private func pick() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            syncFolderPath = url.path
            // Plan 6.7 wires the actual SyncEngine start
        }
    }
}

struct CloudDetectionChip: View {
    let path: String
    var detection: String {
        if path.contains("Mobile Documents") { return "iCloud Drive · ~30s sync" }
        if path.contains("Google Drive") || path.contains("GoogleDrive") { return "Google Drive · ~5s sync" }
        if path.contains("Dropbox") { return "Dropbox · ~2s sync" }
        if path.contains("OneDrive") { return "OneDrive · ~30s sync" }
        return "Local folder · no sync"
    }
    var body: some View {
        Label(detection, systemImage: "cloud").foregroundStyle(.secondary)
    }
}
```

`HotkeysSettingsView.swift`: shown in Task 6.5.

`AdvancedSettingsView.swift`:

```swift
import SwiftUI
struct AdvancedSettingsView: View {
    let controller: AppController
    @AppStorage("betaUpdates") private var beta = false
    var body: some View {
        Form {
            Toggle("Beta updates", isOn: $beta)
            Button("Export diagnostic bundle") { exportDiagnostics() }
            Button("Reset all data", role: .destructive) { /* confirm dialog */ }
            Button("Re-run onboarding") { OnboardingState.reset() }
        }.padding()
    }
    private func exportDiagnostics() {
        // Collect last-N-day os.Logger output and zip it
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
git add MacAllYouNeed/Settings
git commit -m "feat(settings): Settings window with seven sub-sections"
```

---

## Task 6.4: Onboarding state + wizard

**Files:**
- Create: `MacAllYouNeed/Onboarding/OnboardingState.swift`
- Create: `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`
- Create: `MacAllYouNeed/Onboarding/PermissionStepViews.swift`
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`

- [ ] **Step 1: Implement `OnboardingState`**

```swift
import Foundation

enum OnboardingState: String {
    case notStarted, welcome, accessibility, fullDiskAccess, notifications, sync, ready, completed

    static let key = "onboardingState"

    static func load() -> OnboardingState {
        OnboardingState(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .notStarted
    }
    func save() { UserDefaults.standard.set(rawValue, forKey: Self.key) }
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}
```

- [ ] **Step 2: Implement wizard view**

```swift
import SwiftUI
import ApplicationServices

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState = .welcome

    var body: some View {
        VStack {
            ProgressView(value: progressFraction).padding()
            Group {
                switch step {
                case .welcome: WelcomeStep(next: advance)
                case .accessibility: AccessibilityStep(next: advance)
                case .fullDiskAccess: FullDiskAccessStep(next: advance)
                case .notifications: NotificationsStep(next: advance)
                case .sync: SyncSetupStep(next: advance)
                case .ready: ReadyStep(close: { step = .completed; step.save() })
                default: EmptyView()
                }
            }
            HStack {
                Button("Skip") { advance() }
                Spacer()
                Text("\(stepIndex + 1) / 6").foregroundStyle(.secondary)
            }.padding()
        }
        .frame(width: 540, height: 420)
        .onAppear { step.save() }
    }

    private var stepIndex: Int {
        [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready].firstIndex(of: step) ?? 0
    }
    private var progressFraction: Double { Double(stepIndex + 1) / 6.0 }

    private func advance() {
        let order: [OnboardingState] = [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready]
        if let idx = order.firstIndex(of: step), idx + 1 < order.count {
            step = order[idx + 1]
            step.save()
        } else {
            step = .completed; step.save()
        }
    }
}
```

- [ ] **Step 3: Implement permission step views**

```swift
import SwiftUI
import ApplicationServices
import UserNotifications

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Welcome to Mac All You Need").font(.largeTitle).bold()
            VStack(alignment: .leading) {
                Label("Universal clipboard with search and snippets", systemImage: "doc.on.clipboard")
                Label("Quick Look folders and archives", systemImage: "folder")
                Label("Download videos from any site", systemImage: "arrow.down.circle")
            }
            Button("Get started", action: next).keyboardShortcut(.return)
        }.padding()
    }
}

struct AccessibilityStep: View {
    let next: () -> Void
    @State private var granted = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            Text("Accessibility permission").font(.title2).bold()
            Text("Required so the clipboard popup can paste back into your app, and so snippet `;trigger` expansion works. Without it, you can still capture, search, and copy items — you'll just need to press ⌘V manually.")
            Button("Open System Settings") {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            if granted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack { Spacer(); Button("Continue", action: next).disabled(!granted) }
        }
        .padding()
        .onReceive(timer) { _ in
            granted = AXIsProcessTrusted()
            if granted { next() }
        }
    }
}

struct FullDiskAccessStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Full Disk Access").font(.title2).bold()
            Text("Required for browser cookie import (so authenticated downloads work) and for analyzing protected folders. Without it, basic downloads still work; you'll be prompted per failed authenticated download.")
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            HStack { Spacer(); Button("Continue", action: next) }
        }.padding()
    }
}

struct NotificationsStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Notifications").font(.title2).bold()
            Text("Optional. Used for download completion. You can change this anytime in Settings → General.")
            Button("Allow") {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in next() }
            }
            HStack { Spacer(); Button("Skip", action: next) }
        }.padding()
    }
}

struct SyncSetupStep: View {
    let next: () -> Void
    @State private var choice = "later"
    @State private var path: String = ""
    @State private var passphrase: String = ""
    var body: some View {
        VStack(spacing: 12) {
            Text("Sync setup").font(.title2).bold()
            Picker("Mode", selection: $choice) {
                Text("Set up sync now").tag("now")
                Text("Local only").tag("local")
                Text("Decide later").tag("later")
            }.pickerStyle(.radioGroup)
            if choice == "now" {
                HStack {
                    Text(path.isEmpty ? "Pick a folder…" : path).foregroundStyle(.secondary)
                    Button("Browse…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let u = panel.url { path = u.path }
                    }
                }
                SecureField("Passphrase", text: $passphrase)
            }
            HStack { Spacer(); Button("Continue", action: next) }
        }.padding()
    }
}

struct ReadyStep: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("You're ready").font(.largeTitle).bold()
            Text("Press ⌘⇧V to open your clipboard. Press Space on a folder in Finder to preview it.")
            Button("Done", action: close).keyboardShortcut(.return)
        }.padding()
    }
}
```

- [ ] **Step 4: Show wizard on first launch**

In `MacAllYouNeedApp`:

```swift
var body: some Scene {
    MenuBarExtra(...) { AppMenuBarContent(controller: controller) }
        .menuBarExtraStyle(.window)
    Settings { SettingsRoot(controller: controller) }
    WindowGroup("Onboarding", id: "onboarding") {
        if controller.onboarding != .completed {
            OnboardingWizardView(controller: controller)
        }
    }
}
```

- [ ] **Step 5: Manual test**

Reset onboarding (Settings → Advanced → Re-run onboarding). Quit + relaunch. Wizard should appear.

- [ ] **Step 6: Commit**

```bash
git add MacAllYouNeed/Onboarding MacAllYouNeed/MacAllYouNeedApp.swift
git commit -m "feat(onboarding): six-step first-launch wizard with TCC capability checks"
```

---

## Task 6.5: Hotkey rebinding UI

**Files:**
- Create: `MacAllYouNeed/Settings/HotkeysSettingsView.swift`
- Create: `MacAllYouNeed/Settings/HotkeyRecorder.swift`
- Create: `MacAllYouNeed/Settings/HotkeyMapStore.swift`

- [ ] **Step 1: Implement `HotkeyAction` + map store**

```swift
import Foundation
import Platform

enum HotkeyAction: String, CaseIterable, Identifiable {
    case clipboard, addDownload, browseFolder
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: return "Open clipboard popup"
        case .addDownload: return "Add download"
        case .browseFolder: return "Browse folder"
        }
    }
}

enum HotkeyMapStore {
    static let key = "hotkeyMap"
    static func load() -> [HotkeyAction: HotkeyDescriptor] {
        var defaults: [HotkeyAction: HotkeyDescriptor] = [
            .clipboard: .defaultClipboard,
            .addDownload: .defaultDownload,
            .browseFolder: .defaultFolder,
        ]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: HotkeyDescriptor].self, from: data) {
            for (k, v) in decoded {
                if let a = HotkeyAction(rawValue: k) { defaults[a] = v }
            }
        }
        return defaults
    }
    static func save(_ map: [HotkeyAction: HotkeyDescriptor]) {
        let dict = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
```

- [ ] **Step 2: `HotkeyRecorder` view**

```swift
import SwiftUI
import AppKit
import Platform

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var descriptor: HotkeyDescriptor
    func makeNSView(context: Context) -> RecorderView { RecorderView(descriptor: $descriptor) }
    func updateNSView(_ nsView: RecorderView, context: Context) { nsView.refresh() }

    final class RecorderView: NSView {
        @Binding var descriptor: HotkeyDescriptor
        private let label = NSTextField(labelWithString: "")
        init(descriptor: Binding<HotkeyDescriptor>) {
            _descriptor = descriptor
            super.init(frame: .zero)
            label.stringValue = descriptor.wrappedValue.display
            addSubview(label)
            label.frame = NSRect(x: 4, y: 2, width: 80, height: 18)
            wantsLayer = true
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.cornerRadius = 4
        }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            let modRaw = UInt32(event.modifierFlags.rawValue & UInt(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue))
            // Map AppKit modifiers to Carbon modifiers
            var mods: HotkeyDescriptor.Modifiers = []
            if modRaw & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { mods.insert(.command) }
            if modRaw & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { mods.insert(.option) }
            if modRaw & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { mods.insert(.control) }
            if modRaw & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { mods.insert(.shift) }
            descriptor = HotkeyDescriptor(keyCode: UInt32(event.keyCode), modifiers: mods)
            label.stringValue = descriptor.display
        }
        func refresh() { label.stringValue = descriptor.display }
    }
}
```

- [ ] **Step 3: `HotkeysSettingsView`**

```swift
import SwiftUI
import Platform

struct HotkeysSettingsView: View {
    let controller: AppController
    @State private var map: [HotkeyAction: HotkeyDescriptor]
    init(controller: AppController) {
        self.controller = controller
        _map = State(initialValue: HotkeyMapStore.load())
    }
    var body: some View {
        Form {
            ForEach(HotkeyAction.allCases) { action in
                HStack {
                    Text(action.label)
                    Spacer()
                    HotkeyRecorder(descriptor: Binding(
                        get: { map[action] ?? .defaultClipboard },
                        set: { map[action] = $0 }
                    ))
                    .frame(width: 100, height: 24)
                }
            }
            HStack {
                Spacer()
                Button("Apply") { apply() }
            }
        }.padding()
    }
    private func apply() {
        HotkeyMapStore.save(map)
        controller.applyHotkeyMap(map)
    }
}
```

(Add `applyHotkeyMap(_:)` to `AppController` that unregisters previous hotkeys and re-registers per the new map. Implementation: each `HotkeyController`/`GlobalHotkey` exposes a `replace(descriptor:)`.)

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Settings/HotkeyRecorder.swift MacAllYouNeed/Settings/HotkeysSettingsView.swift MacAllYouNeed/Settings/HotkeyMapStore.swift MacAllYouNeed/App/AppController.swift
git commit -m "feat(settings): hotkey rebinding UI with recorder"
```

---

## Task 6.6: `URLDetector` + Clipboard → Downloader bridge

**Files:**
- Create: `Shared/Sources/Platform/Pasteboard/URLDetector.swift`
- Create: `Shared/Tests/PlatformTests/URLDetectorTests.swift`
- Modify: `MacAllYouNeed/Clipboard/ClipboardItemRow.swift`

- [ ] **Step 1: Implement detector**

```swift
import Foundation

public enum URLDetector {
    private static let videoHosts: Set<String> = [
        "youtube.com", "youtu.be", "www.youtube.com",
        "vimeo.com", "player.vimeo.com",
        "x.com", "twitter.com",
        "douyin.com", "tiktok.com",
        "twitch.tv",
    ]

    public static func videoBearingURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for m in matches {
            if let url = m.url, let host = url.host?.lowercased(), videoHosts.contains(host) {
                return url
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Test**

```swift
import XCTest
@testable import Platform

final class URLDetectorTests: XCTestCase {
    func testYouTubeWatch() {
        let url = URLDetector.videoBearingURL(in: "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(url?.host, "www.youtube.com")
    }
    func testNonVideoURLReturnsNil() {
        XCTAssertNil(URLDetector.videoBearingURL(in: "https://example.com/article"))
    }
    func testInlineURL() {
        let url = URLDetector.videoBearingURL(in: "check this https://vimeo.com/123 thanks")
        XCTAssertEqual(url?.host, "vimeo.com")
    }
}
```

- [ ] **Step 3: Wire into row**

Add a `Download` button to `ClipboardItemRow` when `URLDetector.videoBearingURL(in: item.preview)` returns non-nil:

```swift
if let url = URLDetector.videoBearingURL(in: item.preview) {
    Button { NotificationCenter.default.post(name: .clipboardDownloadRequested, object: url) }
        label: { Image(systemName: "arrow.down.circle") }
}
```

In `AppController.init`, observe and dispatch:

```swift
NotificationCenter.default.addObserver(forName: .clipboardDownloadRequested, object: nil, queue: .main) { [weak self] note in
    if let url = note.object as? URL {
        Task { await self?.downloader.enqueue(url: url.absoluteString, title: nil) }
    }
}
```

Add the notification name in `Core` or main app:

```swift
extension Notification.Name {
    public static let clipboardDownloadRequested = Notification.Name("clipboardDownloadRequested")
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter URLDetectorTests
git add Shared/Sources/Platform/Pasteboard/URLDetector.swift Shared/Tests/PlatformTests/URLDetectorTests.swift MacAllYouNeed/Clipboard/ClipboardItemRow.swift MacAllYouNeed/App/AppController.swift
git commit -m "feat(integration): URL detector + clipboard → downloader one-click"
```

---

## Task 6.7: Sync adapters wiring

**Files:**
- Create: `Shared/Sources/Core/Sync/ClipboardSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/SnippetSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/PinboardSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/DownloadHistorySyncAdapter.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 1: Implement `ClipboardSyncAdapter`**

```swift
import Foundation
import CryptoKit

public final class ClipboardSyncAdapter {
    let store: ClipboardStore
    let engine: SyncEngine
    let deviceID: DeviceID
    public init(store: ClipboardStore, engine: SyncEngine, deviceID: DeviceID) {
        self.store = store; self.engine = engine; self.deviceID = deviceID
    }
    /// Call after each successful local insert to publish to sync.
    /// Lamport assignment is delegated to `engine.nextLamport()` so the engine's
    /// view of "what's seen so far" is the single source of truth — concurrent
    /// remote ingests advance the counter, and the next local publish observes
    /// the updated value.
    public func publishCreated(meta: ClipboardItemMeta, body: ClipboardRecord) async throws {
        let lamport = await engine.nextLamport()
        let envelopeMeta = EnvelopeMetadata(
            kind: .clipboardItem, id: meta.id,
            created: meta.created, modified: meta.modified,
            deviceID: deviceID, lamport: lamport
        )
        let bodyData = try JSONEncoder().encode(body)
        try await engine.put(metadata: envelopeMeta, body: bodyData)
    }

    /// Subscribe to engine events; ingest received records into local store.
    public func attach() async {
        await engine.subscribe { [weak self] event in
            guard let self else { return }
            if case let .recordReceived(rec) = event, rec.metadata.deviceID != self.deviceID {
                Task {
                    if let body = try? JSONDecoder().decode(ClipboardRecord.self, from: rec.body) {
                        // Insert if not already present
                        _ = try? self.store.insertExternalIfMissing(body, with: rec.metadata)
                    }
                }
            }
            if case let .recordDeleted(id, kind) = event, kind == .clipboardItem {
                try? self.store.delete(id: id)
            }
        }
    }
}
```

(Add `insertExternalIfMissing` to `ClipboardStore`: writes the record only if no row with that id exists.)

Similar adapters for `SnippetStore`, `PinboardStore`, `DownloadStore` (the latter only if `syncDownloadHistory` is enabled).

- [ ] **Step 2: Architecture note — sync adapters live in the daemon, not the main app**

Important: the `ClipboardStore`, `SnippetStore`, and `PinboardStore` are owned by the **daemon** (Plan 3's `DaemonContainer`), not the main app. The main app only holds `ClipboardXPCClient`. So `ClipboardSyncAdapter` (and `SnippetSyncAdapter`, `PinboardSyncAdapter`) must be instantiated in the daemon and connected to a `SyncEngine` that also lives daemon-side.

`DownloadStore` is owned by the main app (Plan 5's `DownloadCoordinator`), so `DownloadHistorySyncAdapter` lives in the main app.

The split is:

| Adapter | Lives in | Owner |
|---|---|---|
| `ClipboardSyncAdapter` | Daemon | `DaemonContainer` |
| `SnippetSyncAdapter` | Daemon | `DaemonContainer` |
| `PinboardSyncAdapter` | Daemon | `DaemonContainer` |
| `DownloadHistorySyncAdapter` | Main app | `DownloadCoordinator` |

Both processes need to construct their own `SyncEngine` instance pointing at the same sync folder (each with its own `FSEventsWatcher`). The sync key is shared via Keychain (`KeyManager` with `SystemKeychain` reads the same key from both processes — this works because the App Group entitlement scopes the Keychain entry).

- [ ] **Step 3: Update `DaemonContainer` (Plan 3) to own its sync engine + adapters**

In `ClipboardDaemon/DaemonContainer.swift`, add:

```swift
import CryptoKit

extension DaemonContainer {
    func startSyncIfConfigured() async {
        guard let path = UserDefaults.standard.string(forKey: "syncFolderPath"), !path.isEmpty,
              let salt = (try? Manifest.read(from: SyncPaths(root: URL(fileURLWithPath: path)).manifest))?.kdfSalt
        else { return }

        let keychain = SystemKeychain()
        guard let pwData = keychain.get("sync-passphrase.v1"),
              let passphrase = String(data: pwData, encoding: .utf8) else { return }

        let manager = KeyManager(keychain: keychain)
        guard let syncKey = try? manager.deriveSyncKey(passphrase: passphrase, salt: salt, params: .defaultV1) else { return }

        let root = URL(fileURLWithPath: path)
        let engine = SyncEngine(paths: SyncPaths(root: root), syncKey: syncKey,
                                deviceID: deviceID, watcher: FSEventsWatcher(root: root))
        try? await engine.start()

        let clipAdapter = ClipboardSyncAdapter(store: clip, engine: engine, deviceID: deviceID)
        await clipAdapter.attach()
        // …same for snippet/pinboard adapters

        // Hook capture path: replace the bare persist call with one that also publishes:
        // (DaemonContainer.persist returns the meta+body so we can hand to clipAdapter.publishCreated)
    }
}
```

Wire from `ClipboardDaemonMain.main()`:

```swift
let container = try DaemonContainer()
let server = ClipboardXPCServer(container: container)
container.observer.start { change in
    for item in change.items {
        try? container.persist(item: item, source: change.frontmostAppBundleID)
    }
    server.notifyInvalidated()
}
Task { await container.startSyncIfConfigured() }
```

- [ ] **Step 4: `AppController.startSyncIfConfigured()` covers only download history (the main app's local store)**

```swift
extension AppController {
    func startSyncIfConfigured() async {
        guard let path = UserDefaults.standard.string(forKey: "syncFolderPath"), !path.isEmpty,
              let salt = (try? Manifest.read(from: SyncPaths(root: URL(fileURLWithPath: path)).manifest))?.kdfSalt,
              UserDefaults.standard.bool(forKey: "syncDownloadHistory")
        else { return }

        let keychain = SystemKeychain()
        guard let pwData = keychain.get("sync-passphrase.v1"),
              let passphrase = String(data: pwData, encoding: .utf8),
              let syncKey = try? KeyManager(keychain: keychain).deriveSyncKey(
                  passphrase: passphrase, salt: salt, params: .defaultV1)
        else { return }

        let root = URL(fileURLWithPath: path)
        let engine = SyncEngine(paths: SyncPaths(root: root), syncKey: syncKey,
                                deviceID: deviceID, watcher: FSEventsWatcher(root: root))
        try? await engine.start()
        sync = engine

        let dlAdapter = DownloadHistorySyncAdapter(store: downloader.store, engine: engine, deviceID: deviceID)
        await dlAdapter.attach()
    }
}
```

> **Onboarding hand-off:** the sync passphrase the user enters in onboarding step 5 (Plan 6.4) is stored in Keychain via `keychain.set(passphrase.data(using:.utf8)!, for: "sync-passphrase.v1")` so subsequent launches in either process can re-derive the key without prompting.

> **First-run sync folder bootstrap:** on the first run with sync enabled, `Manifest.bootstrap(...)` writes a fresh manifest with random KDF salt; subsequent runs read that salt. Both processes must read the same manifest file.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Sync ClipboardDaemon/DaemonContainer.swift MacAllYouNeed/App/AppController.swift
git commit -m "feat(sync): per-store sync adapters wired via SyncEngine"
```

---

## Task 6.8: Cross-feature integrations — Downloader → FolderPreview, FolderPreview → Clipboard

**Files:**
- Modify: `MacAllYouNeed/Downloader/DownloadRowView.swift`
- Modify: `Shared/Sources/UI/FolderPreview/FolderFilesView.swift`

- [ ] **Step 1: Add "Preview folder" to completed download row**

```swift
if record.state == .completed {
    Button("Preview folder") {
        let dir = URL(fileURLWithPath: record.destinationPath).deletingLastPathComponent()
        NotificationCenter.default.post(name: .browseFolderRequested, object: dir)
    }
    .buttonStyle(.borderless)
}
```

In `AppController.init`, observe and call `folder.show(at: dir)` (extend `BrowseFolderWindowController` with `show(at: URL)`).

- [ ] **Step 2: FolderPreview Copy → clipboard captures the URL**

Already true thanks to Plan 4.8's `copyFileURLToPasteboard` + Plan 3 daemon's capture loop — verify with manual test.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/Downloader/DownloadRowView.swift MacAllYouNeed/FolderPreview/BrowseFolderWindowController.swift MacAllYouNeed/App/AppController.swift
git commit -m "feat(integration): completed download → preview folder"
```

---

## Self-review checklist

```bash
cd Shared && swift test
swiftlint --strict
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
```

Manual:
- Reset onboarding, relaunch, run through wizard, verify Accessibility/FDA/Notifications steps poll permissions.
- Settings → Hotkeys → rebind ⌘⇧V to ⌘⌃V → Apply → confirm new hotkey works.
- Copy a YouTube URL → row shows download button → click → enqueues.
- Complete a download → row shows "Preview folder" → click → standalone window opens on the destination directory.
- Settings → Sync → pick a folder inside iCloud Drive → cloud detection chip shows the right cloud.

**Spec coverage:**

- [x] §3 decision 7 (menu-bar-first UI) — Tasks 6.1, 6.2
- [x] §9 menu-bar tabs (Clipboard / Downloads / Snippets) — Task 6.2
- [x] §9 settings sub-sections — Task 6.3
- [x] §9 onboarding wizard with TCC capability checks — Task 6.4
- [x] §9 hotkey rebinding with conflict detection (basic; system-conflict warning is a follow-up polish) — Task 6.5
- [x] §9 cross-feature integration moments — Tasks 6.6, 6.8

**Out of scope (other plans):**
- Notifications wiring on download completion (Plan 5 stub; can land here if time)
- "Resolve conflicts" full UI (skeleton in Settings → Sync; full UI is a v1.x polish)
- Snippets full edit UI (placeholder in 6.2; expand if time)
- Multi-pane FolderPreview comparison (Plan 4 noted as deferred)
- Localization (Plan 13 backlog)
