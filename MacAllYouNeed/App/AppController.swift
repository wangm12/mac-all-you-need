import AppKit
import Core
import CoreFoundation
import CryptoKit
import Foundation
import Platform

private struct StartupStores {
    let pinboard: PinboardStore
    let snippet: SnippetStore
    let clipboard: ClipboardStore
    let voiceTranscripts: VoiceTranscriptStore
    let voiceDictionary: VoiceDictionaryStore
    let voiceAppProfiles: VoiceAppProfileStore
    let blob: BlobStore
    let search: SearchStore
}

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
    /// Snippet expansion runs in the main app so it uses the app's Accessibility permission
    private let snippetExpander: SnippetExpander

    // Stores retained so menu actions (e.g. Clear Older Than) can run locally
    // when the daemon's XPC mach service isn't available.
    private let clipStore: ClipboardStore
    private let blobStore: BlobStore
    private let searchStore: SearchStore
    private let pinboardStore: PinboardStore
    let voiceDictionaryStore: VoiceDictionaryStore
    let voiceAppProfileStore: VoiceAppProfileStore
    let voiceCoordinator: VoiceCoordinator

    private let hotkeyRegistry = HotkeyRegistry()
    private var fallbackHotkey: GlobalHotkey?
    private var browseFolderObserver: NSObjectProtocol?
    private var downloadRequestObserver: NSObjectProtocol?
    private var pauseCaptureObserver: NSObjectProtocol?
    private var clearOlderThanObserver: NSObjectProtocol?
    private var mainWindowSettingsObserver: NSObjectProtocol?
    private var hotkeyRecorderStartObserver: NSObjectProtocol?
    private var hotkeyRecorderStopObserver: NSObjectProtocol?
    private var activeHotkeyRecorderCount = 0
    private(set) var mainWindow: MainWindowController!
    private(set) var onboardingWindow: OnboardingWindowController!
    private(set) var voiceOnboardingWindow: VoiceOnboardingWindowController!

    init() throws {
        deviceID = try DeviceIdentityStore.loadOrCreate()

        // Load the device key up front. If the keychain is locked or the entry
        // is missing/corrupt, fail fast — every encrypted store needs this key,
        // and constructing fallback in-memory stores silently orphans user data.
        let keychain = SystemKeychain()
        let stores = try Self.makeStartupStores(
            deviceID: deviceID,
            key: KeyManager(keychain: keychain).deviceKey()
        )
        let cleanupKeyStore = VoiceCleanupKeyStore(keychain: keychain)

        let deps = makeAppDependencies(stores: stores)
        let pasteCoordinator = DockPasteCoordinator(xpc: deps.xpc)
        let favicons = FaviconCache()
        let clipboardDock = DockWindowController(
            model: deps.dockModel,
            pasteCoordinator: pasteCoordinator,
            favicons: favicons,
            registry: .shared
        )
        clipboardDeps = deps
        self.clipboardDock = clipboardDock
        clipboardDock.dockHeight = Self.currentDockHeight()

        clipStore = stores.clipboard
        blobStore = stores.blob
        searchStore = stores.search
        pinboardStore = stores.pinboard
        voiceDictionaryStore = stores.voiceDictionary
        voiceAppProfileStore = stores.voiceAppProfiles
        voiceCoordinator = makeVoiceCoordinator(stores: stores, cleanupKeyStore: cleanupKeyStore)

        clipboardReader = LocalClipboardReader(store: stores.clipboard)
        clipboardReader.blobsRef = stores.blob
        snippetExpander = Self.makeSnippetExpander(store: stores.snippet)

        let coordinator = BrowseFolderCoordinator()
        let browser = BrowseFolderWindowController { action in coordinator.perform(action) }
        folderCoordinator = coordinator
        folder = browser

        let coord = try DownloadCoordinator()
        downloader = coord
        let dlVM = DownloaderViewModel(coordinator: coord)
        downloaderVM = dlVM
        let dockCtrl = DockProgressController(vm: dlVM)
        dockCtrl.start()
        downloaderDock = dockCtrl

        onboarding = OnboardingState.load()
        LoginItemController.reconcileLaunchAtLogin()

        startDownloadTasks(coordinator: coord, viewModel: dlVM)
        voiceCoordinator.start()

        registerConfiguredHotkeys()
        registerAppObservers()

        // Initialize after all stored properties are set
        mainWindow = MainWindowController(controller: self)
        onboardingWindow = OnboardingWindowController(controller: self)
        voiceOnboardingWindow = VoiceOnboardingWindowController(controller: self)
        startAutoDownloadPromptLoop()
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
        // Local retention path. The XPC route into the daemon is unreliable
        // because the daemon's mach service registration fails (the
        // SMAppService.loginItem issue), so menu actions silently did
        // nothing. Run the same RetentionPolicy here against the stores
        // we already hold; pinned items stay protected.
        let policy = RetentionPolicy(
            maxItems: nil,
            maxAgeSeconds: TimeInterval(days) * 86400,
            maxImageBytes: nil
        )
        let protected = (try? PinboardStore.protectedIDs(from: pinboardStore)) ?? []
        do {
            try policy.enforceMaxAge(
                store: clipStore,
                blobs: blobStore,
                search: searchStore,
                protectedIDs: protected
            )
        } catch {
            Logging.logger(for: "AppController", category: "retention")
                .error("local retention failed: \(error.localizedDescription, privacy: .public)")
        }
        // Notify the menu bar popover so it reloads immediately instead of
        // waiting on its 1s poll.
        NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
        Task { await self.clipboardDeps.dockModel.refresh() }
    }

    private static func makePinboardStore(key: SymmetricKey) throws -> PinboardStore {
        let url = AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite")
        let db = try Database(url: url, migrations: PinboardStore.migrations)
        return PinboardStore(database: db, deviceKey: key)
    }

    private static func makeStartupStores(
        deviceID: DeviceID,
        key: SymmetricKey
    ) throws -> StartupStores {
        let pinboardStore = try makePinboardStore(key: key)
        let snippetStore = try makeSnippetStore(key: key)
        let clipboardDatabase = try makeClipboardDatabase()
        let clipboardStore = try ClipboardStore(database: clipboardDatabase, deviceKey: key, deviceID: deviceID)
        let searchStore = try makeSearchStore()
        return StartupStores(
            pinboard: pinboardStore,
            snippet: snippetStore,
            clipboard: clipboardStore,
            voiceTranscripts: VoiceTranscriptStore(database: clipboardDatabase),
            voiceDictionary: VoiceDictionaryStore(database: clipboardDatabase),
            voiceAppProfiles: VoiceAppProfileStore(database: clipboardDatabase),
            blob: makeBlobStore(key: key),
            search: searchStore
        )
    }

    private func registerConfiguredHotkeys() {
        do {
            try hotkeyRegistry.apply(HotkeyMapStore.load(), controller: self)
        } catch {
            let hk = GlobalHotkey(descriptor: .defaultClipboard) { [weak clipboardDock] in
                Task { @MainActor in clipboardDock?.toggle() }
            }
            try? hk.register()
            fallbackHotkey = hk
        }
    }

    private func startDownloadTasks(coordinator: DownloadCoordinator, viewModel: DownloaderViewModel) {
        Task { await coordinator.startDispatchServer() }
        Task {
            await coordinator.prepareInterruptedDownloadsForRetry()
            await viewModel.refresh()
        }
    }

    private func registerAppObservers() {
        browseFolderObserver = NotificationCenter.default.addObserver(
            forName: .browseFolderRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor in self?.folder.show(at: url) }
        }
        downloadRequestObserver = NotificationCenter.default.addObserver(
            forName: .clipboardDownloadRequested, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { await self?.downloaderVM.add(url: url.absoluteString) }
        }
        pauseCaptureObserver = NotificationCenter.default.addObserver(
            forName: .pauseCaptureRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspendCaptureFor60Seconds() }
        }
        clearOlderThanObserver = NotificationCenter.default.addObserver(
            forName: .clearClipboardOlderThanRequested, object: nil, queue: .main
        ) { [weak self] note in
            let days = (note.object as? NSNumber)?.intValue ?? (note.object as? Int) ?? 0
            Task { @MainActor in self?.clearClipboardOlderThan(days: days) }
        }
        mainWindowSettingsObserver = NotificationCenter.default.addObserver(
            forName: .mainWindowSettingsRequested, object: nil, queue: .main
        ) { [weak self] note in
            let destination = SettingsDestination.legacySelection(note.object as? String)
            AppGroupSettings.defaults.set(destination.rawValue, forKey: DockSettingsNavigation.settingsSelectionKey)
            Task { @MainActor in self?.showMainWindow(destination: .settings) }
        }
        hotkeyRecorderStartObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecorderDidStartRecording, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspendShortcutTriggersForHotkeyRecording() }
        }
        hotkeyRecorderStopObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyRecorderDidStopRecording, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeShortcutTriggersAfterHotkeyRecording() }
        }
    }

    private func suspendShortcutTriggersForHotkeyRecording() {
        activeHotkeyRecorderCount += 1
        guard activeHotkeyRecorderCount == 1 else { return }
        hotkeyRegistry.unregisterAll()
        fallbackHotkey?.unregister()
        fallbackHotkey = nil
        voiceCoordinator.suspendActivationMonitoring()
    }

    private func resumeShortcutTriggersAfterHotkeyRecording() {
        guard activeHotkeyRecorderCount > 0 else { return }
        activeHotkeyRecorderCount -= 1
        guard activeHotkeyRecorderCount == 0 else { return }
        voiceCoordinator.resumeActivationMonitoring()
        registerConfiguredHotkeys()
    }

    private func startAutoDownloadPromptLoop() {
        // Auto-detect video URLs: when a new item appears at the top of the
        // clipboard history and it contains a recognisable video URL, show the
        // AutoDownloadHUD so the user can enqueue it with a single tap.
        Task { @MainActor [weak self] in
            // Let the reader do one initial poll before establishing the baseline
            // so we don't prompt for whatever was already on the clipboard at launch.
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            var lastTopID = clipboardReader.items.first?.id.rawValue
            while true {
                try? await Task.sleep(for: .milliseconds(800))
                let items = clipboardReader.items
                let first = items.first
                guard let first, first.id.rawValue != lastTopID else { continue }
                lastTopID = first.id.rawValue
                if let url = URLDetector.videoBearingURL(in: first.preview) {
                    AutoDownloadHUD.prompt(for: url)
                }
            }
        }
    }

    private static func makeSnippetStore(key: SymmetricKey) throws -> SnippetStore {
        let url = AppGroup.containerURL().appendingPathComponent("databases/snippets.sqlite")
        let db = try Database(url: url, migrations: SnippetStore.migrations)
        return SnippetStore(database: db, deviceKey: key)
    }

    private static func makeClipboardDatabase() throws -> Database {
        let url = AppGroup.containerURL().appendingPathComponent("databases/clipboard.sqlite")
        return try Database(url: url, migrations: ClipboardStore.migrations)
    }

    private static func makeBlobStore(key: SymmetricKey) -> BlobStore {
        let root = AppGroup.containerURL().appendingPathComponent("blobs", isDirectory: true)
        return BlobStore(rootURL: root, key: key)
    }

    private static func makeSearchStore() throws -> SearchStore {
        let url = AppGroup.containerURL().appendingPathComponent("databases/search.sqlite")
        let db = try Database(url: url, migrations: SearchStore.migrations)
        return SearchStore(database: db)
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

@MainActor
private func makeAppDependencies(stores: StartupStores) -> AppDependencies {
    AppDependencies(
        pinboards: stores.pinboard,
        snippets: stores.snippet,
        clip: stores.clipboard,
        blobs: stores.blob
    )
}

@MainActor
private func makeVoiceCoordinator(
    stores: StartupStores,
    cleanupKeyStore: VoiceCleanupKeyStore
) -> VoiceCoordinator {
    VoiceCoordinator(
        transcripts: stores.voiceTranscripts,
        dictionary: stores.voiceDictionary,
        appProfiles: stores.voiceAppProfiles,
        cleanupKeyStore: cleanupKeyStore
    )
}

extension Notification.Name {
    static let addDownloadRequested = Notification.Name("addDownloadRequested")
    static let browseFolderRequested = Notification.Name("browseFolderRequested")
    static let clipboardDownloadRequested = Notification.Name("clipboardDownloadRequested")
    static let pauseCaptureRequested = Notification.Name("pauseCaptureRequested")
    static let clearClipboardOlderThanRequested = Notification.Name("clearClipboardOlderThanRequested")
}
