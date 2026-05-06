# Plan 6: Menu-bar Shell, Settings, Onboarding, and Integrations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the three subsystem prototypes (Plans 3, 4, 5) and assemble them into one coherent app. Build the polished menu-bar popover with tabs, the Settings window with all sub-sections, the six-step first-launch onboarding wizard with TCC capability checks, hotkey rebinding UI, the cross-feature integration moments, and the per-store sync adapters that wire local writes through Plan 2's `SyncEngine`.

**Architecture:** A single `AppController` (in the main app target) is the composition root: it constructs the storage layer, the daemon XPC client, the downloader coordinator, the folder preview coordinator, the sync engine, and a small set of `*SyncAdapter` objects that subscribe to local stores and publish into `SyncEngine`, plus subscribe to `SyncEngine` events and write into local stores. Settings and onboarding state live in an App Group `UserDefaults` suite so the main app and daemon agree on sync configuration. Hotkey rebinding uses a `HotkeyRecorder` SwiftUI view plus a `HotkeyRegistry` that atomically re-registers Carbon hotkeys and reports registration conflicts. Cross-feature integrations are simple `NotificationCenter` posts, kept loose to avoid coupling subsystems.

**Tech Stack:** SwiftUI (Settings scene, `MenuBarExtra` window style), `@AppStorage`, `UNUserNotificationCenter`, `SMAppService` (LoginItem registration).

**Reads from spec:** §9 (entire), §3 (decision 7).

**Depends on:** Plans 0–5.

**Produces working software:** First launch shows the six-step wizard; permissions auto-advance on grant; the menu-bar popover has Clipboard / Downloads / Snippets tabs; the gear opens Settings with seven sub-sections; rebinding `⌘⇧V` works and conflicts with existing system shortcuts are detected; copying a YouTube URL adds a one-click "Download" affordance; completing a download offers "Preview folder" that opens the standalone Browse window on the destination directory; sync runs in the background if a sync folder is configured.

---

## Public types defined here

| Type | Module path | Purpose |
|---|---|---|
| `AppController` | (main app) | Composition root |
| `OnboardingState` | (main app) | App Group persisted enum: `notStarted, welcome, accessibility, fullDiskAccess, notifications, sync, ready, completed` |
| `OnboardingWizardView` | (main app) | Six-step modal |
| `SettingsRoot` | (main app) | `Settings` scene with sidebar |
| `HotkeyRecorder` | (main app) | SwiftUI view to capture a hotkey |
| `HotkeyRegistry` | (main app) | Owns all global hotkey registrations and conflict rollback |
| `AppGroupSettings` | `Core` | Shared `UserDefaults` suite for app + daemon settings |
| `DeviceIdentityStore` | `Core` | Single persisted device ID helper used by app + daemon |
| `SyncConfigurationStore` | `Core.Sync` | Persists sync folder/passphrase bootstrap handoff |
| `ClipboardSyncAdapter` | `Core.Sync` | Bridges `ClipboardStore` ↔ `SyncEngine` |
| `SnippetSyncAdapter` | `Core.Sync` | Same for snippets |
| `PinboardSyncAdapter` | `Core.Sync` | Same for pinboards |
| `DownloadHistorySyncAdapter` | `Core.Sync` | Same for download history (opt-in) |
| `URLDetector` | `Platform.Pasteboard` | Detects video-bearing URLs in copied text |

---

## Task 6.1: `AppController` composition root

**Files:**
- Create: `Shared/Sources/Core/AppGroupSettings.swift`
- Create: `Shared/Sources/Core/DeviceIdentityStore.swift`
- Create: `MacAllYouNeed/App/AppController.swift`
- Create: `MacAllYouNeed/App/LoginItemController.swift`
- Create: `MacAllYouNeed/Onboarding/OnboardingState.swift`
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`
- Modify: `ClipboardDaemon/DaemonContainer.swift` (use shared `DeviceIdentityStore`)

- [ ] **Step 1: Add shared settings + device identity helpers**

`Shared/Sources/Core/AppGroupSettings.swift`:

```swift
import Foundation

public enum AppGroupSettings {
    public static let defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
}
```

`Shared/Sources/Core/DeviceIdentityStore.swift`:

```swift
import Foundation

public enum DeviceIdentityStore {
    public static func loadOrCreate(root: URL = AppGroup.containerURL()) throws -> DeviceID {
        let url = root.appendingPathComponent("device-id.txt")
        if let raw = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let id = DeviceID(rawValue: raw) {
            return id
        }
        let id = DeviceID.generate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try id.rawValue.write(to: url, atomically: true, encoding: .utf8)
        return id
    }
}
```

In `ClipboardDaemon/DaemonContainer.swift`, delete the daemon-local `DeviceIdentityStore` enum from Plan 3 and keep:

```swift
self.deviceID = try DeviceIdentityStore.loadOrCreate(root: AppGroup.containerURL())
```

- [ ] **Step 2: Implement `OnboardingState`**

`MacAllYouNeed/Onboarding/OnboardingState.swift`:

```swift
import Foundation
import Core

enum OnboardingState: String {
    case notStarted, welcome, accessibility, fullDiskAccess, notifications, sync, ready, completed

    static let key = "onboardingState"

    static func load() -> OnboardingState {
        OnboardingState(rawValue: AppGroupSettings.defaults.string(forKey: key) ?? "") ?? .notStarted
    }

    func save() {
        AppGroupSettings.defaults.set(rawValue, forKey: Self.key)
    }

    static func reset() {
        AppGroupSettings.defaults.removeObject(forKey: key)
    }
}
```

- [ ] **Step 3: Implement `AppController`**

`MacAllYouNeed/App/LoginItemController.swift`:

```swift
import Foundation
import ServiceManagement
import Core

enum LoginItemController {
    static let daemonIdentifier = "com.macallyouneed.app.daemon"

    static func reconcileLaunchAtLogin() {
        let enabled = AppGroupSettings.defaults.object(forKey: "launchAtLogin") as? Bool ?? true
        setLaunchAtLogin(enabled)
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            let item = SMAppService.loginItem(identifier: daemonIdentifier)
            if enabled { try item.register() }
            else { try item.unregister() }
            AppGroupSettings.defaults.set(enabled, forKey: "launchAtLogin")
        } catch {
            Logging.logger(for: "app", category: "login-item")
                .error("Login item update failed: \(error.localizedDescription)")
        }
    }
}
```

```swift
import Foundation
import Core
import Platform
import SwiftUI
import CryptoKit

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
    var onboarding: OnboardingState
    var sync: SyncEngine?
    var downloadHistorySync: DownloadHistorySyncAdapter?
    lazy var onboardingWindow = OnboardingWindowController(controller: self)

    init() throws {
        let manager = KeyManager(keychain: SystemKeychain())
        self.key = try manager.deviceKey()
        self.deviceID = try DeviceIdentityStore.loadOrCreate(root: AppGroup.containerURL())

        let deps = AppDependencies()
        let popup = ClipboardPopupController(deps: deps)
        let hk = HotkeyController(popup: popup)
        self.clipboardDeps = deps; self.popup = popup; self.clipboardHotkey = hk
        // Hotkey registration is performed at the end of init via HotkeyRegistry
        // (Task 6.5). The fallback `hk.registerDefault()` only fires if the
        // registry can't claim every hotkey atomically — preventing
        // double-registration of ⌘⇧V.

        self.folder = BrowseFolderWindowController()
        self.folderXPC = BrowseFolderCoordinator()

        let coord = try DownloadCoordinator()
        self.downloader = coord
        let dlVM = DownloaderViewModel(coordinator: coord)
        self.downloaderVM = dlVM
        let dock = DockProgressController(vm: dlVM); dock.start(); self.dock = dock

        self.onboarding = OnboardingState.load()

        LoginItemController.reconcileLaunchAtLogin()
        Task { await coord.startDispatchServer() }
        Task { await coord.recoverInFlight() }
    }

    func setOnboarding(_ state: OnboardingState) {
        onboarding = state
        state.save()
    }

    func resetOnboarding() {
        setOnboarding(.notStarted)
    }

    func startSyncIfConfigured() async {
        // Task 6.7 adds the engine startup body.
    }

    func showOnboardingIfNeeded() {
        guard onboarding != .completed else { return }
        onboardingWindow.show()
    }
}
```

- [ ] **Step 4: Update `MacAllYouNeedApp` to use it**

```swift
@main
struct MacAllYouNeedApp: App {
    @State private var controller: AppController

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            Text("Mac All You Need")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/AppGroupSettings.swift Shared/Sources/Core/DeviceIdentityStore.swift MacAllYouNeed/App/AppController.swift MacAllYouNeed/App/LoginItemController.swift MacAllYouNeed/Onboarding/OnboardingState.swift MacAllYouNeed/MacAllYouNeedApp.swift ClipboardDaemon/DaemonContainer.swift
git commit -m "refactor(app): introduce AppController composition root"
```

---

## Task 6.2: Polished menu-bar popover (`AppMenuBarContent`)

**Files:**
- Modify: `MacAllYouNeed/App/AppMenuBarContent.swift` (move logic from Plan 5 here)
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift` (snippet list DTO + API)
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift` (serve snippets from daemon-owned store)

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

// Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift
@objc public class SnippetXPCDTO: NSObject, NSSecureCoding, Identifiable {
    public static var supportsSecureCoding: Bool { true }
    @objc public let id: String
    @objc public let name: String
    @objc public let trigger: String?

    public init(id: String, name: String, trigger: String?) {
        self.id = id
        self.name = name
        self.trigger = trigger
    }

    public required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let name = coder.decodeObject(of: NSString.self, forKey: "name") as String? else { return nil }
        self.id = id
        self.name = name
        self.trigger = coder.decodeObject(of: NSString.self, forKey: "trigger") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(name as NSString, forKey: "name")
        if let trigger { coder.encode(trigger as NSString, forKey: "trigger") }
    }
}

// Add to ClipboardXPCProtocol in Plan 3:
// func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void)
// Add `SnippetXPCDTO` and `NSArray` to the allowed classes for this reply on
// both ClipboardXPCClient and ClipboardXPCServer.
//
// In ClipboardXPCServer:
// func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
//     let rows = (try? container.snippets.list()) ?? []
//     reply(rows.map { SnippetXPCDTO(id: $0.id.rawValue, name: $0.name, trigger: $0.trigger) })
// }

struct SnippetsListView: View {
    let controller: AppController
    @State private var snippets: [SnippetXPCDTO] = []
    var body: some View {
        List(snippets) { snippet in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.name)
                    if let trigger = snippet.trigger {
                        Text(trigger).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .overlay {
            if snippets.isEmpty { Text("No snippets yet").foregroundStyle(.secondary) }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        guard let proxy = controller.clipboardDeps.xpc.proxy() else { return }
        let rows: [SnippetXPCDTO] = await withCheckedContinuation { cont in
            proxy.listSnippets { cont.resume(returning: $0) }
        }
        snippets = rows
    }
}
```

- [ ] **Step 2: Commit**

Update `MacAllYouNeedApp` to render the final popover:

```swift
MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
    AppMenuBarContent(controller: controller)
}
.menuBarExtraStyle(.window)
```

```bash
git add MacAllYouNeed/App/AppMenuBarContent.swift MacAllYouNeed/MacAllYouNeedApp.swift Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift ClipboardDaemon/ClipboardXPCServer.swift
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
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`
- Modify: `MacAllYouNeed/Downloader/DownloadCoordinator.swift`
- Modify: `ClipboardDaemon/DaemonContainer.swift`
- Modify: `Shared/Sources/UI/FolderPreview/FolderPreviewView.swift`

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

Update `MacAllYouNeedApp`:

```swift
Settings { SettingsRoot(controller: controller) }
```

- [ ] **Step 2: Implement each sub-view with persistent backing**

`GeneralSettingsView.swift`:

```swift
import SwiftUI
import AppKit
import Core

struct GeneralSettingsView: View {
    let controller: AppController
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true
    @AppStorage("showDockDuringDownloads", store: AppGroupSettings.defaults) private var showDock = false
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LoginItemController.setLaunchAtLogin(on)
                }
            Toggle("Show dock icon during downloads", isOn: $showDock)
                .onChange(of: showDock) { _, visible in
                    DockVisibilityController.setDockIconVisible(visible)
                }
        }.padding()
    }
}

enum DockVisibilityController {
    static func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
```

`ClipboardSettingsView.swift`:

```swift
import SwiftUI
import Core

struct ClipboardSettingsView: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems", store: AppGroupSettings.defaults) private var maxItems = 10000
    @AppStorage("clipboardMaxBytes", store: AppGroupSettings.defaults) private var maxBytes = 5 * 1024 * 1024 * 1024
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var newBundleID: String = ""
    var body: some View {
        Form {
            Stepper("Max items: \(maxItems)", value: $maxItems, in: 100...100_000, step: 100)
            Section("Excluded apps") {
                List {
                    ForEach(blockedApps, id: \.self) { Text($0) }
                    .onDelete { offsets in
                        blockedApps.remove(atOffsets: offsets)
                        ExcludedAppsStore.save(blockedApps)
                    }
                }
                    .frame(height: 120)
                HStack {
                    TextField("com.example.app", text: $newBundleID)
                    Button("Add") {
                        guard !newBundleID.isEmpty else { return }
                        blockedApps.append(newBundleID)
                        ExcludedAppsStore.save(blockedApps)
                        newBundleID = ""
                    }
                }
            }
        }.padding()
    }
}

enum ExcludedAppsStore {
    private static let key = "clipboardExcludedBundleIDs"
    static func load() -> [String] {
        AppGroupSettings.defaults.stringArray(forKey: key) ?? []
    }
    static func save(_ ids: [String]) {
        AppGroupSettings.defaults.set(Array(Set(ids)).sorted(), forKey: key)
    }
}
```

Update `DaemonContainer` from Plan 3 so capture uses the shared exclusion list:

```swift
let blocked = Set(AppGroupSettings.defaults.stringArray(forKey: "clipboardExcludedBundleIDs") ?? [])
self.observer = PasteboardObserver(reader: SystemPasteboardReader(),
                                   rules: ExclusionRules(blockedBundleIDs: blocked))
```

`DownloadsSettingsView.swift`:

```swift
import SwiftUI
import Core

struct DownloadsSettingsView: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    var body: some View {
        Form {
            Stepper("Concurrent downloads: \(concurrency)", value: $concurrency, in: 1...10)
                .onChange(of: concurrency) { _, n in
                    Task { await controller.downloader.queue.setMaxConcurrent(n) }
                }
            TextField("Output template", text: $template)
            Button("Check for downloader update") {
                Task { await controller.downloader.checkForDownloaderUpdate() }
            }
        }.padding()
    }
}
```

Add this wrapper to `DownloadCoordinator` if Plan 5 has only the lower-level `DownloaderUpdate` verifier:

```swift
extension DownloadCoordinator {
    func checkForDownloaderUpdate() async {
        // Plan 7 owns network/appcast delivery; Plan 6 exposes the command surface
        // and keeps this path observable rather than leaving the Settings control inert.
        NotificationCenter.default.post(name: .downloaderUpdateRequested, object: nil)
    }
}

extension Notification.Name {
    public static let downloaderUpdateRequested = Notification.Name("downloaderUpdateRequested")
}
```

Also replace the hard-coded destination template in `DownloadCoordinator.enqueue(url:title:)`:

```swift
let template = AppGroupSettings.defaults.string(forKey: "downloadOutputTemplate")
    ?? "%(title)s [%(id)s].%(ext)s"
let dest = (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    ?? URL(fileURLWithPath: "/tmp")).appendingPathComponent(template)
```

`FolderPreviewSettingsView.swift`:

```swift
import SwiftUI
import Core
struct FolderPreviewSettingsView: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    var body: some View {
        Form {
            Toggle("Include hidden files", isOn: $includeHidden)
            Stepper("Max entries: \(maxEntries)", value: $maxEntries, in: 1000...500_000, step: 1000)
        }.padding()
    }
}
```

Update `FolderPreviewView` from Plan 4 to consume those settings:

```swift
let maxEntries = AppGroupSettings.defaults.integer(forKey: "folderPreviewMaxEntries")
let includeHidden = AppGroupSettings.defaults.bool(forKey: "folderPreviewIncludeHidden")
inventory = try? await FolderEnumerator.enumerate(
    url: currentURL,
    maxEntries: maxEntries == 0 ? 50_000 : maxEntries,
    includeHidden: includeHidden
)
```

`SyncSettingsView.swift`:

```swift
import SwiftUI
import Core

struct SyncSettingsView: View {
    let controller: AppController
    @AppStorage("syncFolderPath", store: AppGroupSettings.defaults) private var syncFolderPath: String = ""
    @AppStorage("syncDownloadHistory", store: AppGroupSettings.defaults) private var syncDownloads = false
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
            Task { await controller.startSyncIfConfigured() }
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
import AppKit
import Foundation
import Core
struct AdvancedSettingsView: View {
    let controller: AppController
    @AppStorage("betaUpdates", store: AppGroupSettings.defaults) private var beta = false
    @State private var confirmingReset = false
    var body: some View {
        Form {
            Toggle("Beta updates", isOn: $beta)
            Button("Export diagnostic bundle") { exportDiagnostics() }
            Button("Reset all data", role: .destructive) { confirmingReset = true }
            Button("Re-run onboarding") { controller.resetOnboarding() }
        }
        .confirmationDialog("Reset all local data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local databases, blobs, thumbnails, and downloader checkpoints. Synced cloud files are not deleted.")
        }
        .padding()
    }
    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacAllYouNeed-Diagnostics.zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task.detached {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("mayn-diagnostics-\(UUID())", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let settings = AppGroupSettings.defaults.dictionaryRepresentation()
                .filter { !$0.key.lowercased().contains("passphrase") }
            let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: temp.appendingPathComponent("settings.json"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", destination.path, "."]
            process.currentDirectoryURL = temp
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: temp)
        }
    }
    private func resetAllData() {
        let root = AppGroup.containerURL()
        for name in ["databases", "blobs", "thumbnails", "downloader-updates", "dispatch.token"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        OnboardingState.reset()
        AppGroupSettings.defaults.removeObject(forKey: "syncFolderPath")
        AppGroupSettings.defaults.removeObject(forKey: "syncDownloadHistory")
    }
}
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
git add MacAllYouNeed/Settings MacAllYouNeed/MacAllYouNeedApp.swift MacAllYouNeed/Downloader/DownloadCoordinator.swift ClipboardDaemon/DaemonContainer.swift Shared/Sources/UI/FolderPreview/FolderPreviewView.swift
git commit -m "feat(settings): Settings window with seven sub-sections"
```

---

## Task 6.4: Onboarding state + wizard

**Files:**
- Create: `Shared/Sources/Core/Sync/SyncConfigurationStore.swift`
- Modify: `MacAllYouNeed/Onboarding/OnboardingState.swift`
- Create: `MacAllYouNeed/Onboarding/OnboardingWindowController.swift`
- Create: `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`
- Create: `MacAllYouNeed/Onboarding/PermissionStepViews.swift`
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift`

- [ ] **Step 1: Verify `OnboardingState` uses the App Group settings suite**

```swift
import Foundation
import Core

enum OnboardingState: String {
    case notStarted, welcome, accessibility, fullDiskAccess, notifications, sync, ready, completed

    static let key = "onboardingState"

    static func load() -> OnboardingState {
        OnboardingState(rawValue: AppGroupSettings.defaults.string(forKey: key) ?? "") ?? .notStarted
    }
    func save() { AppGroupSettings.defaults.set(rawValue, forKey: Self.key) }
    static func reset() { AppGroupSettings.defaults.removeObject(forKey: key) }
}
```

- [ ] **Step 2: Implement sync configuration handoff**

`Shared/Sources/Core/Sync/SyncConfigurationStore.swift`:

```swift
import Foundation

public enum SyncConfigurationStore {
    public static let folderKey = "syncFolderPath"
    public static let syncDownloadHistoryKey = "syncDownloadHistory"
    public static let passphraseAccount = "sync-passphrase.v1"

    public static func syncFolderURL() -> URL? {
        guard let path = AppGroupSettings.defaults.string(forKey: folderKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    public static func configure(folder: URL, passphrase: String, deviceID: DeviceID,
                                 keychain: KeychainBackend = SystemKeychain()) throws {
        let paths = SyncPaths(root: folder)
        try paths.createIfNeeded()
        if !FileManager.default.fileExists(atPath: paths.manifest.path) {
            let deviceName = Host.current().localizedName ?? "Mac"
            try Manifest.bootstrap(deviceID: deviceID, deviceName: deviceName).write(to: paths.manifest)
        }
        AppGroupSettings.defaults.set(folder.path, forKey: folderKey)
        if !passphrase.isEmpty {
            try keychain.set(Data(passphrase.utf8), for: passphraseAccount)
        }
    }

    public static func passphrase(keychain: KeychainBackend = SystemKeychain()) throws -> String? {
        guard let data = try keychain.get(passphraseAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Implement wizard view**

```swift
import SwiftUI
import ApplicationServices

struct OnboardingWizardView: View {
    let controller: AppController
    @State private var step: OnboardingState

    init(controller: AppController) {
        self.controller = controller
        let loaded = controller.onboarding
        _step = State(initialValue: loaded == .notStarted ? .welcome : loaded)
    }

    var body: some View {
        VStack {
            ProgressView(value: progressFraction).padding()
            Group {
                switch step {
                case .welcome: WelcomeStep(next: advance)
                case .accessibility: AccessibilityStep(next: advance)
                case .fullDiskAccess: FullDiskAccessStep(next: advance)
                case .notifications: NotificationsStep(next: advance)
                case .sync: SyncSetupStep(controller: controller, next: advance)
                case .ready: ReadyStep(close: { setStep(.completed) })
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
        .onAppear { setStep(step) }
    }

    private var stepIndex: Int {
        [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready].firstIndex(of: step) ?? 0
    }
    private var progressFraction: Double { Double(stepIndex + 1) / 6.0 }

    private func advance() {
        let order: [OnboardingState] = [.welcome, .accessibility, .fullDiskAccess, .notifications, .sync, .ready]
        if let idx = order.firstIndex(of: step), idx + 1 < order.count {
            setStep(order[idx + 1])
        } else {
            setStep(.completed)
        }
    }

    private func setStep(_ newValue: OnboardingState) {
        step = newValue
        controller.setOnboarding(newValue)
    }
}
```

- [ ] **Step 4: Implement permission step views**

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
    @State private var granted = FullDiskAccessProbe.hasUsefulAccess()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            Text("Full Disk Access").font(.title2).bold()
            Text("Required for browser cookie import (so authenticated downloads work) and for analyzing protected folders. Without it, basic downloads still work; you'll be prompted per failed authenticated download.")
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            if granted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack { Spacer(); Button("Continue", action: next) }
        }
        .padding()
        .onReceive(timer) { _ in
            let nowGranted = FullDiskAccessProbe.hasUsefulAccess()
            if nowGranted && !granted { next() }
            granted = nowGranted
        }
    }
}

enum FullDiskAccessProbe {
    static func hasUsefulAccess() -> Bool {
        let chromeCookies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        let safariCookies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        return FileManager.default.isReadableFile(atPath: chromeCookies.path)
            || FileManager.default.isReadableFile(atPath: safariCookies.path)
    }
}

struct NotificationsStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Notifications").font(.title2).bold()
            Text("Optional. Used for download completion. You can change this anytime in Settings → General.")
            Button("Allow") {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async { next() }
                }
            }
            HStack { Spacer(); Button("Skip", action: next) }
        }.padding()
    }
}

struct SyncSetupStep: View {
    let controller: AppController
    let next: () -> Void
    @State private var choice = "later"
    @State private var path: String = ""
    @State private var passphrase: String = ""
    @State private var errorMessage: String?
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
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Continue") { continueTapped() }
                    .disabled(choice == "now" && (path.isEmpty || passphrase.isEmpty))
            }
        }.padding()
    }

    private func continueTapped() {
        if choice == "now" {
            do {
                try SyncConfigurationStore.configure(folder: URL(fileURLWithPath: path),
                                                    passphrase: passphrase,
                                                    deviceID: controller.deviceID)
                Task { await controller.startSyncIfConfigured() }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        next()
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

- [ ] **Step 5: Show wizard on first launch**

Use an explicit AppKit window controller. Do not mount the launcher inside `MenuBarExtra` content — that content may not be constructed until the user clicks the menu-bar icon, which can suppress first-launch onboarding.

`MacAllYouNeed/Onboarding/OnboardingWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private weak var controller: AppController?
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    func show() {
        guard let controller, controller.onboarding != .completed else { return }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Mac All You Need Setup"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingWizardView(controller: controller))
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

In `MacAllYouNeedApp`, schedule the window after the app has entered the run loop:

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

    init() {
        let controller = try! AppController()
        _controller = State(initialValue: controller)
        Task { @MainActor in
            await Task.yield()
            controller.showOnboardingIfNeeded()
        }
    }
}
```

- [ ] **Step 6: Manual test**

Reset onboarding (Settings → Advanced → Re-run onboarding). Quit + relaunch. Wizard should appear.

- [ ] **Step 7: Commit**

```bash
git add Shared/Sources/Core/Sync/SyncConfigurationStore.swift MacAllYouNeed/Onboarding MacAllYouNeed/MacAllYouNeedApp.swift
git commit -m "feat(onboarding): six-step first-launch wizard with TCC capability checks"
```

---

## Task 6.5: Hotkey rebinding UI

**Files:**
- Create: `MacAllYouNeed/Settings/HotkeysSettingsView.swift`
- Create: `MacAllYouNeed/Settings/HotkeyRecorder.swift`
- Create: `MacAllYouNeed/Settings/HotkeyMapStore.swift`
- Create: `MacAllYouNeed/App/HotkeyRegistry.swift`

- [ ] **Step 1: Implement `HotkeyAction` + map store**

```swift
import Foundation
import Platform
import Core

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
        if let data = AppGroupSettings.defaults.data(forKey: key),
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
            AppGroupSettings.defaults.set(data, forKey: key)
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
        @available(*, unavailable)
        required init?(coder: NSCoder) { return nil }
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
    @State private var errorMessage: String?
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
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }.padding()
    }
    private func apply() {
        do {
            try controller.applyHotkeyMap(map)
            HotkeyMapStore.save(map)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Implement `HotkeyRegistry` and wire `AppController.applyHotkeyMap`**

`MacAllYouNeed/App/HotkeyRegistry.swift`:

```swift
import Foundation
import Platform

enum HotkeyRegistryError: LocalizedError {
    case duplicate(HotkeyDescriptor)
    case registrationFailed(HotkeyAction, Error)

    var errorDescription: String? {
        switch self {
        case .duplicate(let descriptor):
            return "Duplicate hotkey \(descriptor.display). Pick a unique shortcut."
        case .registrationFailed(let action, let error):
            return "Could not register \(action.label): \(error.localizedDescription)"
        }
    }
}

@MainActor
final class HotkeyRegistry {
    private var handles: [HotkeyAction: GlobalHotkey] = [:]

    func apply(_ map: [HotkeyAction: HotkeyDescriptor], controller: AppController) throws {
        var seen: [HotkeyDescriptor: HotkeyAction] = [:]
        for (action, descriptor) in map {
            if seen[descriptor] != nil { throw HotkeyRegistryError.duplicate(descriptor) }
            seen[descriptor] = action
        }

        var next: [HotkeyAction: GlobalHotkey] = [:]
        do {
            for (action, descriptor) in map {
                let handle = GlobalHotkey(descriptor: descriptor) { [weak controller] in
                    Task { @MainActor in controller?.performHotkeyAction(action) }
                }
                try handle.register()
                next[action] = handle
            }
        } catch {
            next.values.forEach { $0.unregister() }
            let failed = map.first { next[$0.key] == nil }?.key ?? .clipboard
            throw HotkeyRegistryError.registrationFailed(failed, error)
        }

        handles.values.forEach { $0.unregister() }
        handles = next
    }
}
```

In `AppController.swift`, add:

```swift
private let hotkeyRegistry = HotkeyRegistry()

func applyHotkeyMap(_ map: [HotkeyAction: HotkeyDescriptor]) throws {
    clipboardHotkey.unregister()
    try hotkeyRegistry.apply(map, controller: self)
}

func performHotkeyAction(_ action: HotkeyAction) {
    switch action {
    case .clipboard:
        popup.show()
    case .addDownload:
        NotificationCenter.default.post(name: .addDownloadRequested, object: nil)
    case .browseFolder:
        folder.openPanelAndBrowse()
    }
}
```

In the same file at file scope, add:

```swift
extension Notification.Name {
    public static let addDownloadRequested = Notification.Name("addDownloadRequested")
}
```

In `DownloadsListView` from Plan 5, listen for the hotkey:

```swift
.onReceive(NotificationCenter.default.publisher(for: .addDownloadRequested)) { _ in
    showAdd = true
}
```

At the end of `AppController.init`, after all properties are initialized, replace `hk.registerDefault()` with:

```swift
do {
    try hotkeyRegistry.apply(HotkeyMapStore.load(), controller: self)
} catch {
    hk.registerDefault()
}
```

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/HotkeyRecorder.swift MacAllYouNeed/Settings/HotkeysSettingsView.swift MacAllYouNeed/Settings/HotkeyMapStore.swift MacAllYouNeed/App/HotkeyRegistry.swift MacAllYouNeed/App/AppController.swift
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
- Modify: `Shared/Sources/Core/Sync/SyncConfigurationStore.swift`
- Create: `Shared/Sources/Core/Sync/ClipboardSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/SnippetSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/PinboardSyncAdapter.swift`
- Create: `Shared/Sources/Core/Sync/DownloadHistorySyncAdapter.swift`
- Modify: `Shared/Sources/Core/Storage/ClipboardStore.swift`
- Modify: `Shared/Sources/Core/Storage/SnippetStore.swift`
- Modify: `Shared/Sources/Core/Storage/PinboardStore.swift`
- Modify: `Shared/Sources/Core/Storage/DownloadStore.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 0: Ensure stores preserve sync metadata**

Before wiring adapters, add idempotent external-write APIs and metadata columns to every synced store. The local write path and the remote ingest path must both persist `deviceID` and `lamport`; otherwise a record re-emitted from local storage loses its causal identity.

```swift
// ClipboardStore: base table already has device_id from Plan 1 after the review patch.
func insertExternalIfMissing(_ body: ClipboardRecord, with metadata: EnvelopeMetadata) throws {
    // If id exists, return without changing local data.
    // Else insert id/created/modified/device_id/lamport/kind/preview/envelope using metadata.
}

// SnippetStore / PinboardStore / DownloadStore:
// Add device_id TEXT and lamport INTEGER NOT NULL DEFAULT 0 if not present.
// For remote inserts, copy metadata.modified, metadata.deviceID, and metadata.lamport.
func insertExternalIfMissing(_ value: Snippet, with metadata: EnvelopeMetadata) throws
func insertExternalIfMissing(_ value: Pinboard, with metadata: EnvelopeMetadata) throws
func insertExternalIfMissing(_ value: DownloadRecord, with metadata: EnvelopeMetadata) throws
```

Add store tests for duplicate external insert (no overwrite), remote `modified` preservation, remote `deviceID` preservation, and remote `lamport` preservation.

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

(The Step 0 `insertExternalIfMissing` implementation writes the record only if no row with that id exists.)

- [ ] **Step 2: Implement the remaining adapters explicitly**

`Shared/Sources/Core/Sync/SnippetSyncAdapter.swift`:

```swift
import Foundation

public final class SnippetSyncAdapter {
    let store: SnippetStore
    let engine: SyncEngine
    let deviceID: DeviceID

    public init(store: SnippetStore, engine: SyncEngine, deviceID: DeviceID) {
        self.store = store; self.engine = engine; self.deviceID = deviceID
    }

    public func publishCreated(_ snippet: Snippet, modified: Date) async throws {
        let meta = EnvelopeMetadata(kind: .snippet, id: snippet.id, created: modified, modified: modified,
                                    deviceID: deviceID, lamport: await engine.nextLamport())
        try await engine.put(metadata: meta, body: JSONEncoder().encode(snippet))
    }

    public func attach() async {
        await engine.subscribe { [weak self] event in
            guard let self else { return }
            if case let .recordReceived(rec) = event,
               rec.metadata.kind == .snippet,
               rec.metadata.deviceID != self.deviceID,
               let snippet = try? JSONDecoder().decode(Snippet.self, from: rec.body) {
                try? self.store.insertExternalIfMissing(snippet, with: rec.metadata)
            }
            if case let .recordDeleted(id, kind) = event, kind == .snippet {
                try? self.store.delete(id: id)
            }
        }
    }
}
```

`Shared/Sources/Core/Sync/PinboardSyncAdapter.swift`:

```swift
import Foundation

public final class PinboardSyncAdapter {
    let store: PinboardStore
    let engine: SyncEngine
    let deviceID: DeviceID

    public init(store: PinboardStore, engine: SyncEngine, deviceID: DeviceID) {
        self.store = store; self.engine = engine; self.deviceID = deviceID
    }

    public func publishChanged(_ pinboard: Pinboard, modified: Date) async throws {
        let meta = EnvelopeMetadata(kind: .pinboard, id: pinboard.id, created: modified, modified: modified,
                                    deviceID: deviceID, lamport: await engine.nextLamport())
        try await engine.put(metadata: meta, body: JSONEncoder().encode(pinboard))
    }

    public func attach() async {
        await engine.subscribe { [weak self] event in
            guard let self else { return }
            if case let .recordReceived(rec) = event,
               rec.metadata.kind == .pinboard,
               rec.metadata.deviceID != self.deviceID,
               let pinboard = try? JSONDecoder().decode(Pinboard.self, from: rec.body) {
                try? self.store.insertExternalIfMissing(pinboard, with: rec.metadata)
            }
            if case let .recordDeleted(id, kind) = event, kind == .pinboard {
                try? self.store.delete(id: id)
            }
        }
    }
}
```

`Shared/Sources/Core/Sync/DownloadHistorySyncAdapter.swift`:

```swift
import Foundation

public final class DownloadHistorySyncAdapter {
    let store: DownloadStore
    let engine: SyncEngine
    let deviceID: DeviceID

    public init(store: DownloadStore, engine: SyncEngine, deviceID: DeviceID) {
        self.store = store; self.engine = engine; self.deviceID = deviceID
    }

    public func publishChanged(_ record: DownloadRecord) async throws {
        let modified = Date()
        let meta = EnvelopeMetadata(kind: .downloadHistory, id: record.id, created: modified, modified: modified,
                                    deviceID: deviceID, lamport: await engine.nextLamport())
        try await engine.put(metadata: meta, body: JSONEncoder().encode(record))
    }

    public func attach() async {
        await engine.subscribe { [weak self] event in
            guard let self else { return }
            if case let .recordReceived(rec) = event,
               rec.metadata.kind == .downloadHistory,
               rec.metadata.deviceID != self.deviceID,
               let record = try? JSONDecoder().decode(DownloadRecord.self, from: rec.body) {
                try? self.store.insertExternalIfMissing(record, with: rec.metadata)
            }
            if case let .recordDeleted(id, kind) = event, kind == .downloadHistory {
                try? self.store.delete(id: id)
            }
        }
    }
}
```

The same Step 0 idempotency and metadata-preservation rules apply to `SnippetStore`, `PinboardStore`, and `DownloadStore`.

- [ ] **Step 3: Architecture note — sync adapters live in the daemon, not the main app**

Important: the `ClipboardStore`, `SnippetStore`, and `PinboardStore` are owned by the **daemon** (Plan 3's `DaemonContainer`), not the main app. The main app only holds `ClipboardXPCClient`. So `ClipboardSyncAdapter` (and `SnippetSyncAdapter`, `PinboardSyncAdapter`) must be instantiated in the daemon and connected to a `SyncEngine` that also lives daemon-side.

`DownloadStore` is owned by the main app (Plan 5's `DownloadCoordinator`), so `DownloadHistorySyncAdapter` lives in the main app.

The split is:

| Adapter | Lives in | Owner |
|---|---|---|
| `ClipboardSyncAdapter` | Daemon | `DaemonContainer` |
| `SnippetSyncAdapter` | Daemon | `DaemonContainer` |
| `PinboardSyncAdapter` | Daemon | `DaemonContainer` |
| `DownloadHistorySyncAdapter` | Main app | `DownloadCoordinator` |

Both processes need to construct their own `SyncEngine` instance pointing at the same sync folder (each with its own watcher). The sync key is shared via Keychain (`KeyManager` with `SystemKeychain` reads the same key from both processes because Plan 0 gives the main app and daemon the same `keychain-access-groups` entitlement and `MAYNKeychainAccessGroup` Info.plist value). App Groups only share files/defaults; they do not share Keychain rows.

- [ ] **Step 4: Update `DaemonContainer` (Plan 3) to own its sync engine + adapters**

In `ClipboardDaemon/DaemonContainer.swift`, add:

```swift
import CryptoKit

extension DaemonContainer {
    func startSyncIfConfigured() async {
        guard let root = SyncConfigurationStore.syncFolderURL() else { return }
        let paths = SyncPaths(root: root)
        guard let manifest = try? Manifest.read(from: paths.manifest) else { return }

        let keychain = SystemKeychain()
        guard let passphrase = try? SyncConfigurationStore.passphrase(keychain: keychain) else { return }

        let manager = KeyManager(keychain: keychain)
        guard let syncKey = try? manager.deriveSyncKey(passphrase: passphrase, salt: manifest.kdfSalt, params: manifest.kdfParams) else { return }

        let watcher: FolderWatcher = root.path.contains("Mobile Documents")
            ? MetadataQueryWatcher(root: root)
            : FSEventsWatcher(root: root)
        let hydrationQueue = HydrationQueue(maxConcurrent: 3) { url in
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        let engine = SyncEngine(paths: paths, syncKey: syncKey, deviceID: deviceID,
                                watcher: watcher,
                                hydrationQueue: root.path.contains("Mobile Documents") ? hydrationQueue : nil)
        try? await engine.start()

        let clipAdapter = ClipboardSyncAdapter(store: clip, engine: engine, deviceID: deviceID)
        await clipAdapter.attach()
        let snippetAdapter = SnippetSyncAdapter(store: snippets, engine: engine, deviceID: deviceID)
        await snippetAdapter.attach()
        let pinboardAdapter = PinboardSyncAdapter(store: pinboards, engine: engine, deviceID: deviceID)
        await pinboardAdapter.attach()
        self.syncEngine = engine
        self.clipboardSync = clipAdapter
        self.snippetSync = snippetAdapter
        self.pinboardSync = pinboardAdapter
    }
}
```

Retain sync state in `DaemonContainer`:

```swift
var syncEngine: SyncEngine?
var clipboardSync: ClipboardSyncAdapter?
var snippetSync: SnippetSyncAdapter?
var pinboardSync: PinboardSyncAdapter?
```

`DaemonContainer` must own `snippets: SnippetStore` and `pinboards: PinboardStore` instances (alongside `clip: ClipboardStore`). If Plan 3 hasn't constructed them yet, add them here using the same encrypted-store pattern as `clip`. The engine subscribers above only fire while the adapter objects are alive — store them as instance properties, not local lets.

Update `DaemonContainer.persist` to return the local record it wrote:

```swift
@discardableResult
func persist(item: PasteboardItem, source: String?) throws -> (ClipboardItemMeta, ClipboardRecord)? {
    // Existing Plan 3 switch body remains; each successful append returns `(meta, body)`.
    // Example text branch:
    if case .text(let s) = item {
        let body = ClipboardRecord.text(s)
        let meta = try clip.append(body, sourceAppBundleID: source)
        try search.upsert(kind: .clipboardItem, id: meta.id, text: s)
        return (meta, body)
    }
    return nil
}
```

Wire from `ClipboardDaemonMain.main()`:

```swift
let container = try DaemonContainer()
let server = ClipboardXPCServer(container: container)
container.observer.start { change in
    for item in change.items {
        if let persisted = try? container.persist(item: item, source: change.frontmostAppBundleID) {
            Task { try? await container.clipboardSync?.publishCreated(meta: persisted.0, body: persisted.1) }
        }
    }
    server.notifyInvalidated()
}
Task { await container.startSyncIfConfigured() }
```

- [ ] **Step 5: Replace `AppController.startSyncIfConfigured()` with download-history sync**

In `AppController.swift`, replace the Task 6.1 method body with:

```swift
func startSyncIfConfigured() async {
    guard let root = SyncConfigurationStore.syncFolderURL(),
          AppGroupSettings.defaults.bool(forKey: SyncConfigurationStore.syncDownloadHistoryKey)
    else { sync = nil; downloadHistorySync = nil; return }
    let paths = SyncPaths(root: root)
    guard let manifest = try? Manifest.read(from: paths.manifest) else { sync = nil; downloadHistorySync = nil; return }

    let keychain = SystemKeychain()
    guard let passphrase = try? SyncConfigurationStore.passphrase(keychain: keychain),
          let syncKey = try? KeyManager(keychain: keychain).deriveSyncKey(
              passphrase: passphrase, salt: manifest.kdfSalt, params: manifest.kdfParams)
    else { sync = nil; downloadHistorySync = nil; return }

    let watcher: FolderWatcher = root.path.contains("Mobile Documents")
        ? MetadataQueryWatcher(root: root)
        : FSEventsWatcher(root: root)
    let hydrationQueue = HydrationQueue(maxConcurrent: 3) { url in
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
    let engine = SyncEngine(paths: paths, syncKey: syncKey, deviceID: deviceID,
                            watcher: watcher,
                            hydrationQueue: root.path.contains("Mobile Documents") ? hydrationQueue : nil)
    try? await engine.start()
    sync = engine

    let dlAdapter = DownloadHistorySyncAdapter(store: downloader.store, engine: engine, deviceID: deviceID)
    await dlAdapter.attach()
    downloadHistorySync = dlAdapter   // retain so the engine's [weak self] subscriber stays live
}
```

At the end of `AppController.init`, keep the startup tasks together:

```swift
Task { await coord.startDispatchServer() }
Task { await coord.recoverInFlight() }
Task { [weak self] in await self?.startSyncIfConfigured() }
```

> **Onboarding hand-off:** the sync passphrase the user enters in onboarding step 5 (Plan 6.4) is stored in Keychain via `SyncConfigurationStore.configure(...)` so subsequent launches in either process can re-derive the key without prompting.

> **First-run sync folder bootstrap:** on the first run with sync enabled, `Manifest.bootstrap(...)` writes a fresh manifest with random KDF salt; subsequent runs read that salt. Both processes must read the same manifest file.

- [ ] **Step 6: Commit**

```bash
git add Shared/Sources/Core/Sync Shared/Sources/Core/Storage/ClipboardStore.swift Shared/Sources/Core/Storage/SnippetStore.swift Shared/Sources/Core/Storage/PinboardStore.swift Shared/Sources/Core/Storage/DownloadStore.swift ClipboardDaemon/DaemonContainer.swift MacAllYouNeed/App/AppController.swift
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

In `AppController.init`, observe and call `folder.show(at: dir)`. First extend `BrowseFolderWindowController` with `show(at: URL)`:

```swift
extension BrowseFolderWindowController {
    func show(at url: URL) {
        self.url = url   // existing private property; promote to internal if it was private
        show()
    }
}
```

Then in `AppController.init` (after all properties are initialized), add the observer and retain the token:

```swift
private var browseFolderObserver: NSObjectProtocol?

// inside init():
browseFolderObserver = NotificationCenter.default.addObserver(
    forName: .browseFolderRequested, object: nil, queue: .main
) { [weak self] note in
    guard let url = note.object as? URL else { return }
    self?.folder.show(at: url)
}

deinit {
    if let token = browseFolderObserver {
        NotificationCenter.default.removeObserver(token)
    }
}
```

Add the notification name next to the other app-level integration notifications:

```swift
extension Notification.Name {
    public static let browseFolderRequested = Notification.Name("browseFolderRequested")
}
```

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
- [x] §9 hotkey rebinding with conflict detection — Task 6.5 detects duplicate assignments and reports Carbon registration failures when macOS rejects a reserved/in-use shortcut
- [x] §9 cross-feature integration moments — Tasks 6.6, 6.8

**Deferred to dedicated follow-up plans:**
- Notifications wiring on download completion
- Full conflict-resolution browser beyond the Settings entry point
- Rich Snippets authoring UI beyond the menu-bar empty/list state
- Multi-pane FolderPreview comparison (Plan 4 noted as deferred)
- Localization (Plan 13 backlog)
