import AppKit
import Core
import Foundation
import Platform

@MainActor
@Observable
final class AppController {
    let deviceID: DeviceID
    let clipboardDeps: AppDependencies
    let clipboardReader: LocalClipboardReader
    let popup: ClipboardPopupController
    let folder: BrowseFolderWindowController
    let folderCoordinator: BrowseFolderCoordinator
    let downloader: DownloadCoordinator
    let downloaderVM: DownloaderViewModel
    let dock: DockProgressController
    var onboarding: OnboardingState

    private let hotkeyRegistry = HotkeyRegistry()
    private var fallbackHotkey: GlobalHotkey?
    private var browseFolderObserver: NSObjectProtocol?
    private var downloadRequestObserver: NSObjectProtocol?
    private(set) var onboardingWindow: OnboardingWindowController!

    init() throws {
        self.deviceID = try DeviceIdentityStore.loadOrCreate()

        let deps = AppDependencies()
        let popup = ClipboardPopupController(deps: deps)
        self.clipboardDeps = deps
        self.popup = popup

        let clipKey = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let clipDBURL = AppGroup.containerURL()
            .appendingPathComponent("databases/clipboard.sqlite")
        let clipDB = try Database(url: clipDBURL, migrations: ClipboardStore.migrations)
        let clipStore = try ClipboardStore(database: clipDB, deviceKey: clipKey, deviceID: self.deviceID)
        self.clipboardReader = LocalClipboardReader(store: clipStore)

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
        self.dock = dockCtrl

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
            let hk = GlobalHotkey(descriptor: .defaultClipboard) { [weak popup] in
                Task { @MainActor in popup?.show() }
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

    func applyHotkeyMap(_ map: [HotkeyAction: HotkeyDescriptor]) throws {
        fallbackHotkey = nil
        try hotkeyRegistry.apply(map, controller: self)
    }

    func performHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .clipboard: popup.show()
        case .addDownload: NotificationCenter.default.post(name: .addDownloadRequested, object: nil)
        case .browseFolder: folder.openPanelAndBrowse()
        }
    }

    func startSyncIfConfigured() async {
        // Plan 2 (SyncEngine) is deferred — stub for now
    }
}

extension Notification.Name {
    static let addDownloadRequested = Notification.Name("addDownloadRequested")
    static let browseFolderRequested = Notification.Name("browseFolderRequested")
    static let clipboardDownloadRequested = Notification.Name("clipboardDownloadRequested")
}
