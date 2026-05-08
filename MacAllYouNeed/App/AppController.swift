import AppKit
import Core
import CryptoKit
import Foundation
import CoreFoundation
import Platform

@MainActor
@Observable
final class AppController {
    let deviceID: DeviceID
    let clipboardDeps: AppDependencies
    let clipboardReader: LocalClipboardReader
    let clipboardDock: DockWindowController
    let folder: BrowseFolderWindowController
    let folderCoordinator: BrowseFolderCoordinator
    let downloader: DownloadCoordinator
    let downloaderVM: DownloaderViewModel
    let downloaderDock: DockProgressController
    var onboarding: OnboardingState
    // Snippet expansion runs in the main app so it uses the app's Accessibility permission
    private let snippetExpander: SnippetExpander

    private let hotkeyRegistry = HotkeyRegistry()
    private var fallbackHotkey: GlobalHotkey?
    private var browseFolderObserver: NSObjectProtocol?
    private var downloadRequestObserver: NSObjectProtocol?
    private var pauseCaptureObserver: NSObjectProtocol?
    private var clearOlderThanObserver: NSObjectProtocol?
    private(set) var onboardingWindow: OnboardingWindowController!

    init() throws {
        self.deviceID = try DeviceIdentityStore.loadOrCreate()

        // Load the device key up front. If the keychain is locked or the entry
        // is missing/corrupt, fail fast — every encrypted store needs this key,
        // and constructing fallback in-memory stores silently orphans user data.
        let clipKey = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let pinboardStore = try Self.makePinboardStore(key: clipKey)
        // One SnippetStore per process — both the dock UI and the CGEventTap
        // expander must share it. Two GRDB DatabaseQueues to the same SQLite
        // file race on writes and contend for locks.
        let snippetStore = try Self.makeSnippetStore(key: clipKey)

        let deps = AppDependencies(pinboards: pinboardStore, snippets: snippetStore)
        let pasteCoordinator = DockPasteCoordinator(xpc: deps.xpc)
        let favicons = FaviconCache()
        let clipboardDock = DockWindowController(
            model: deps.dockModel,
            pasteCoordinator: pasteCoordinator,
            favicons: favicons,
            registry: .shared
        )
        self.clipboardDeps = deps
        self.clipboardDock = clipboardDock
        clipboardDock.dockHeight = Self.currentDockHeight()

        self.clipboardReader = try Self.makeClipboardReader(deviceID: deviceID, key: clipKey)
        self.snippetExpander = Self.makeSnippetExpander(store: snippetStore)

        let coordinator = BrowseFolderCoordinator()
        let browser = BrowseFolderWindowController { action in coordinator.perform(action) }
        self.folderCoordinator = coordinator
        self.folder = browser

        let coord = try DownloadCoordinator()
        self.downloader = coord
        let dlVM = DownloaderViewModel(coordinator: coord)
        self.downloaderVM = dlVM
        let dockCtrl = DockProgressController(vm: dlVM)
        dockCtrl.start()
        self.downloaderDock = dockCtrl

        self.onboarding = OnboardingState.load()
        LoginItemController.reconcileLaunchAtLogin()

        Task { await coord.startDispatchServer() }
        Task {
            await coord.prepareInterruptedDownloadsForRetry()
            await dlVM.refresh()
        }

        // Register hotkeys from stored map; fall back to clipboard-only default on failure
        do {
            try hotkeyRegistry.apply(HotkeyMapStore.load(), controller: self)
        } catch {
            let hk = GlobalHotkey(descriptor: .defaultClipboard) { [weak clipboardDock] in
                Task { @MainActor in clipboardDock?.toggle() }
            }
            try? hk.register()
            fallbackHotkey = hk
        }

        browseFolderObserver = NotificationCenter.default.addObserver(
            forName: .browseFolderRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            self?.folder.show(at: url)
        }
        downloadRequestObserver = NotificationCenter.default.addObserver(
            forName: .clipboardDownloadRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { await self?.downloader.enqueue(url: url.absoluteString, title: nil) }
        }
        pauseCaptureObserver = NotificationCenter.default.addObserver(
            forName: .pauseCaptureRequested, object: nil, queue: .main
        ) { [weak self] _ in
            self?.suspendCaptureFor60Seconds()
        }
        clearOlderThanObserver = NotificationCenter.default.addObserver(
            forName: .clearClipboardOlderThanRequested, object: nil, queue: .main
        ) { [weak self] note in
            let days = (note.object as? NSNumber)?.intValue ?? (note.object as? Int) ?? 0
            self?.clearClipboardOlderThan(days: days)
        }

        // Initialize after all stored properties are set
        onboardingWindow = OnboardingWindowController(controller: self)
    }

    func setOnboarding(_ state: OnboardingState) {
        onboarding = state
        state.save()
    }

    func resetOnboarding() { setOnboarding(.notStarted) }

    func showOnboardingIfNeeded() {
        guard onboarding != .completed else { return }
        onboardingWindow.show()
    }

    func applyHotkeyMap(_ map: [HotkeyAction: [HotkeyDescriptor]]) throws {
        fallbackHotkey = nil
        try hotkeyRegistry.apply(map, controller: self)
    }

    func performHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .clipboard: clipboardDock.toggle()
        case .addDownload: NotificationCenter.default.post(name: .addDownloadRequested, object: nil)
        case .browseFolder: folder.openPanelAndBrowse()
        }
    }

    func startSyncIfConfigured() async {
        // Plan 2 (SyncEngine) is deferred — stub for now
    }

    func suspendCaptureFor60Seconds() {
        AppGroupSettings.defaults.set(
            Date().addingTimeInterval(60).timeIntervalSince1970,
            forKey: "captureSuspendUntil"
        )
        Self.postSettingsChangedDarwin()
    }

    func clearClipboardOlderThan(days: Int) {
        guard days > 0 else { return }
        // Route through XPC so the daemon (writer of these SQLite files) owns
        // the deletion. Opening competing DatabaseQueue instances here racing
        // against the daemon caused intermittent BUSY errors and bypassed the
        // FTS cleanup path.
        Task {
            _ = await self.clipboardDeps.xpc.runRetention(maxAgeDays: days)
            await self.clipboardDeps.dockModel.refresh()
        }
    }

    private static func makePinboardStore(key: SymmetricKey) throws -> PinboardStore {
        let url = AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite")
        let db = try Database(url: url, migrations: PinboardStore.migrations)
        return PinboardStore(database: db, deviceKey: key)
    }

    private static func makeSnippetStore(key: SymmetricKey) throws -> SnippetStore {
        let url = AppGroup.containerURL().appendingPathComponent("databases/snippets.sqlite")
        let db = try Database(url: url, migrations: SnippetStore.migrations)
        return SnippetStore(database: db, deviceKey: key)
    }

    private static func makeClipboardReader(deviceID: DeviceID, key: SymmetricKey) throws -> LocalClipboardReader {
        let url = AppGroup.containerURL().appendingPathComponent("databases/clipboard.sqlite")
        let db = try Database(url: url, migrations: ClipboardStore.migrations)
        let store = try ClipboardStore(database: db, deviceKey: key, deviceID: deviceID)
        return LocalClipboardReader(store: store)
    }

    private static func makeSnippetExpander(store: SnippetStore) -> SnippetExpander {
        let expander = SnippetExpander { trigger in try? store.find(trigger: trigger)?.body }
        expander.start()
        return expander
    }

    private static func currentDockHeight() -> CGFloat {
        let value = AppGroupSettings.defaults.double(forKey: "dock.height")
        return value == 0 ? 360 : CGFloat(value)
    }

    private static func postSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}

extension Notification.Name {
    static let addDownloadRequested = Notification.Name("addDownloadRequested")
    static let browseFolderRequested = Notification.Name("browseFolderRequested")
    static let clipboardDownloadRequested = Notification.Name("clipboardDownloadRequested")
    static let pauseCaptureRequested = Notification.Name("pauseCaptureRequested")
    static let clearClipboardOlderThanRequested = Notification.Name("clearClipboardOlderThanRequested")
}
