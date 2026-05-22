import AppKit
import Combine
import Core
import CoreFoundation
import CryptoKit
import FeatureCore
import Foundation
import PackPipeline
import Platform

@MainActor
@Observable
final class AppController {
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

    // MARK: - Feature system (Phase 04)
    /// Registry-driven feature lifecycle. Seeded by BootstrapDefaults on first launch.
    let runtime: FeatureRuntime
    private let featureManager: FeatureManager
    /// SwiftUI-observable mirror of FeatureManager state (Phase 05).
    let featureStatePublisher: FeatureStatePublisher
    /// Phase 06: orchestrates pack download + install + asset state writes.
    let packInstallController: PackInstallController
    /// Phase 06: Advanced-tab side-load affordance.
    let sideloadController: SideloadController

    /// Report from one-time upgrade migration. Non-nil only on the first launch after
    /// upgrading from a pre-modular release. Consumed by `MainWindowRoot` to present
    /// the What's New sheet, then cleared so it never reappears.
    var pendingMigrationReport: MigrationReport?

    // Phase 7 W1: encrypted stores live in AppStoreContainer; AppController
    // retains the container reference and exposes the voice stores publicly
    // because they are read by SwiftUI screens that took the legacy direct
    // properties.
    private let stores: AppStoreContainer

    var deviceID: DeviceID { stores.deviceID }
    var voiceTranscriptStore: VoiceTranscriptStore { stores.voiceTranscripts }
    var voiceDictionaryStore: VoiceDictionaryStore { stores.voiceDictionary }
    var voicePersonalizationStore: VoicePersonalizationStore { stores.voicePersonalization }
    var voiceTrainingExampleStore: VoiceTrainingExampleStore { stores.voiceTrainingExamples }

    let voiceCoordinator: VoiceCoordinator
    let voiceRetentionRunner: VoiceTranscriptRetentionRunner
    let windowControl: WindowControlCoordinator
    private let windowControlAccessibilityTrustMonitor: WindowControlAccessibilityTrustMonitor

    // Phase 7 W1: hotkey registry + action dispatch table extracted to
    // HotkeyOrchestrator. AppController forwards `performHotkeyAction` to it.
    private let hotkeys: HotkeyOrchestrator

    // Phase 7 W1: NotificationCenter observers extracted to a typed-publisher
    // adapter. AppController owns the adapter + the Combine subscription that
    // dispatches each AppEvent to the same handler the inline observer used.
    private let appEventObservers: AppNotificationObservers
    private var appEventCancellable: AnyCancellable?

    private var activeHotkeyRecorderCount = 0

    // Phase 7 W1: window controllers live in AppWindowsCoordinator.
    // The three legacy properties are computed forwards so external callers
    // (`AdvancedSettingsView`, `AppControllerOnboarding`, etc.) keep working
    // unchanged. Implicitly-unwrapped because the controllers must be
    // constructed AFTER `self` is fully initialized (they take `controller: self`).
    private(set) var windows: AppWindowsCoordinator!

    var mainWindow: MainWindowController {
        guard let ctrl = windows.main as? MainWindowController else {
            preconditionFailure("AppWindowsCoordinator.main is not a MainWindowController")
        }
        return ctrl
    }
    var onboardingWindow: OnboardingWindowController {
        guard let ctrl = windows.onboarding as? OnboardingWindowController else {
            preconditionFailure("AppWindowsCoordinator.onboarding is not an OnboardingWindowController")
        }
        return ctrl
    }
    var voiceOnboardingWindow: VoiceOnboardingWindowController {
        guard let ctrl = windows.voiceOnboarding as? VoiceOnboardingWindowController else {
            preconditionFailure("AppWindowsCoordinator.voiceOnboarding is not a VoiceOnboardingWindowController")
        }
        return ctrl
    }

    var hasVisibleAuxiliarySurface: Bool {
        clipboardDock.isVisible
    }

    init() throws {
        let deviceID = try DeviceIdentityStore.loadOrCreate()

        // Load the device key up front. If the keychain is locked or the entry
        // is missing/corrupt, fail fast — every encrypted store needs this key,
        // and constructing fallback in-memory stores silently orphans user data.
        let keychain = SystemKeychain()
        let stores = try AppStoreContainer.makeProductionStores(
            deviceID: deviceID,
            key: KeyManager(keychain: keychain).deviceKey()
        )
        self.stores = stores
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

        voiceCoordinator = makeVoiceCoordinator(stores: stores, cleanupKeyStore: cleanupKeyStore)
        voiceRetentionRunner = VoiceTranscriptRetentionRunner(
            transcriptStore: stores.voiceTranscripts,
            trainingExampleStore: stores.voiceTrainingExamples,
            audioRoot: AppGroup.containerURL().appendingPathComponent("voice-training-audio", isDirectory: true),
            historySettings: { VoiceHistorySettings.load(from: AppGroupSettings.defaults) }
        )
        let windowControl = WindowControlCoordinator()
        self.windowControl = windowControl
        windowControlAccessibilityTrustMonitor = WindowControlAccessibilityTrustMonitor(
            onTrustChanged: { [windowControl] trusted in
                windowControl.refreshAccessibilityTrust(trusted)
            },
            shouldPoll: { [windowControl] in
                windowControl.shouldPollAccessibilityTrust
            }
        )

        clipboardReader = LocalClipboardReader(store: stores.clipboard)
        clipboardReader.blobsRef = stores.blob
        snippetExpander = Self.makeSnippetExpander(store: stores.snippet)

        let coordinator = BrowseFolderCoordinator()
        let browser = BrowseFolderWindowController { action in coordinator.perform(action) }
        folderCoordinator = coordinator
        folder = browser

        let coord = try DownloadCoordinator(binaries: LegacyBundleLocator(binaries: BinaryManager(bundleResources: Bundle.main.resourceURL!)))
        downloader = coord
        let dlVM = DownloaderViewModel(coordinator: coord)
        downloaderVM = dlVM
        let dockCtrl = DockProgressController(vm: dlVM)
        dockCtrl.start()
        downloaderDock = dockCtrl

        onboarding = OnboardingState.load()
        LoginItemController.reconcileLaunchAtLogin()
        AppAppearanceMode.applyStoredPreference()

        // Feature system (Phase 04) — initialized before first self-method calls
        let featureRegistry = FeatureRegistryProvider.makeRegistry()
        let fm = FeatureManager(registry: featureRegistry, defaults: AppGroupSettings.defaults)
        let rt = FeatureRuntime(registry: featureRegistry, manager: fm)
        featureManager = fm
        runtime = rt
        featureStatePublisher = FeatureStatePublisher(manager: fm)

        // Phase 06: Pack install + side-load controllers.
        let manifestLoader = FeatureManifestLoader.bundled() ?? FeatureManifestLoader(
            manifestURL: AppGroup.containerURL().appendingPathComponent("FeaturePackManifest.fallback.json")
        )
        packInstallController = PackInstallController(
            manager: fm,
            registry: featureRegistry,
            manifestLoader: manifestLoader
        )
        sideloadController = SideloadController(manager: fm, manifestLoader: manifestLoader)

        // Hotkey orchestrator owns the registry + the action dispatch table.
        // Closures capture the runtime collaborators directly so the
        // orchestrator does not need a back-reference to AppController.
        hotkeys = HotkeyOrchestrator(
            onClipboardToggle: { [weak clipboardDock] in clipboardDock?.toggle() },
            onBrowseFolder: { [weak browser] in browser?.openPanelAndBrowse() },
            onWindowAction: { [weak windowControl] action in windowControl?.perform(action: action) }
        )

        // Notification adapter — registers all 9 NC observers and surfaces
        // them as typed AppEvent values on a Combine publisher.
        appEventObservers = AppNotificationObservers()

        windowControl.setHotkeyRegistrationNeedsRefresh { [weak self] in
            self?.registerConfiguredHotkeys()
        }

        startDownloadTasks(coordinator: coord, viewModel: dlVM)
        voiceCoordinator.start()
        voiceRetentionRunner.start()
        windowControl.start()
        windowControlAccessibilityTrustMonitor.start()

        registerConfiguredHotkeys()

        // Window controllers must be built after all stored properties are
        // initialized because each takes `controller: self`.
        let main = MainWindowController(controller: self)
        let onb = OnboardingWindowController(controller: self)
        let voiceOnb = VoiceOnboardingWindowController(controller: self)
        windows = AppWindowsCoordinator(
            main: main,
            onboarding: onb,
            voiceOnboarding: voiceOnb
        )

        // Subscribe to the typed AppEvent publisher AFTER `self` is fully
        // initialized so handlers can dispatch back through `self`.
        //
        // The original inline observers each wrapped their handler in
        // `Task { @MainActor in self?.foo() }`, deferring execution to the
        // next run-loop tick so notification posts couldn't recurse into
        // AppController. Preserve that hop here so dispatch timing is
        // identical to pre-extraction behavior.
        appEventCancellable = appEventObservers.events.sink { [weak self] event in
            Task { @MainActor in self?.handle(event: event) }
        }

        startAutoDownloadPromptLoop()

        Task { [weak self] in
            // Phase 11: run one-time migration for upgraders from pre-modular releases.
            // If migration ran, skip BootstrapDefaults (migration already seeded state).
            // If not (fresh install or subsequent launch), run BootstrapDefaults as before.
            let migrator = Migrator.makeProduction(
                clipboardStore: stores.clipboard,
                downloadStore: coord.store,
                defaults: AppGroupSettings.defaults
            )
            let report = (try? await migrator.migrateIfNeeded(featureRuntime: rt)) ?? .noop

            if !report.didRun {
                // Sentinel already set (subsequent launch) or fresh install — run normal seed.
                try? await BootstrapDefaults.seedIfNeeded(manager: fm, defaults: AppGroupSettings.defaults)
                // Phase 06: run legacy migration once so pre-modular installs stay enabled.
                _ = try? await DownloaderFeatureActivator.migrateLegacyAssetStateIfNeeded(
                    manager: fm, loader: manifestLoader
                )
            }
            if let self {
                await self.refreshWindowControlFeatureAvailability()
            }
            await rt.activateAllEnabled()

            // Surface the What's New sheet on first window appearance (upgrade only).
            if report.didRun {
                await MainActor.run { self?.pendingMigrationReport = report }
            }
        }

        runOrphanCacheScanIfNeeded()
    }

    private func runOrphanCacheScanIfNeeded() {
        let registry = runtime.registry
        Task.detached(priority: .background) {
            let scanner = OrphanCacheScanner.makeForRegistry(registry)
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

    func applyHotkeyMap(_ map: [HotkeyAction: [Platform.HotkeyDescriptor]]) throws {
        try hotkeys.applyMap(
            map,
            controller: self,
            windowControlEnabled: windowControl.settings.enabled,
            windowActionPerformerAvailable: windowControl.windowActionPerformerAvailable
        )
    }

    func performHotkeyAction(_ action: HotkeyAction) {
        hotkeys.performAction(action)
    }

    func applyWindowControlSettings(_ settings: WindowControlSettings) {
        windowControl.applySettings(settings)
        registerConfiguredHotkeys()
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
        let protected = (try? PinboardStore.protectedIDs(from: stores.pinboard)) ?? []
        do {
            try policy.enforceMaxAge(
                store: stores.clipboard,
                blobs: stores.blob,
                search: stores.search,
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

    func clearAllClipboardHistory() {
        do {
            let deleted = try ClipboardHistoryClearer.clearAll(
                store: stores.clipboard,
                blobs: stores.blob,
                search: stores.search,
                pinboards: stores.pinboard
            )
            NotificationCenter.default.post(name: .clipboardStoreDidChange, object: nil)
            Task { await self.clipboardDeps.dockModel.refresh() }
            CopyHUD.show(deleted == 1 ? "Deleted 1 item" : "Deleted \(deleted) items", symbol: "trash.fill")
        } catch {
            Logging.logger(for: "AppController", category: "retention")
                .error("clear all clipboard history failed: \(error.localizedDescription, privacy: .public)")
            CopyHUD.show("Clear failed", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func registerConfiguredHotkeys() {
        do {
            try hotkeys.applyMap(
                HotkeyMapStore.load(),
                controller: self,
                windowControlEnabled: windowControl.settings.enabled,
                windowActionPerformerAvailable: windowControl.windowActionPerformerAvailable
            )
        } catch {
            let hk = GlobalHotkey(descriptor: .defaultClipboard) { [weak clipboardDock] in
                Task { @MainActor in clipboardDock?.toggle() }
            }
            try? hk.register()
            hotkeys.installFallbackHotkey(hk)
        }
    }

    private func startDownloadTasks(coordinator: DownloadCoordinator, viewModel: DownloaderViewModel) {
        Task { await coordinator.startDispatchServer() }
        Task {
            await coordinator.prepareInterruptedDownloadsForRetry()
            await viewModel.refresh()
        }
    }

    /// Dispatch a typed AppEvent surfaced by `AppNotificationObservers`.
    /// Mirrors the inline closures the controller previously installed
    /// directly with NotificationCenter.
    private func handle(event: AppEvent) {
        switch event {
        case let .browseFolder(url):
            folder.show(at: url)
        case let .clipboardDownloadRequested(url):
            Task { await self.downloaderVM.add(url: url.absoluteString) }
        case .pauseCaptureRequested:
            suspendCaptureFor60Seconds()
        case let .clearClipboardOlderThan(days):
            clearClipboardOlderThan(days: days)
        case .clearAllClipboardHistory:
            clearAllClipboardHistory()
        case let .mainWindowSettings(route):
            if DockSettingsNavigation.isClipboardRulesRoute(route) {
                AppGroupSettings.defaults.set(ClipboardFunctionTab.rules.rawValue, forKey: ClipboardFunctionTab.storageKey)
                showMainWindow(destination: .clipboard)
                return
            }
            let destination = SettingsDestination.legacySelection(route)
            AppGroupSettings.defaults.set(destination.rawValue, forKey: DockSettingsNavigation.settingsSelectionKey)
            showMainWindow(destination: .settings)
        case .featureRuntimeStateChanged:
            Task { await self.refreshWindowControlFeatureAvailability() }
        case .hotkeyRecordingStarted:
            suspendShortcutTriggersForHotkeyRecording()
        case .hotkeyRecordingStopped:
            resumeShortcutTriggersAfterHotkeyRecording()
        }
    }

    private func refreshWindowControlFeatureAvailability() async {
        let layoutsState = await featureManager.state(for: .windowLayouts)
        let grabState = await featureManager.state(for: .windowGrab)
        windowControl.applyFeatureAvailability(WindowControlFeatureAvailability(
            windowLayoutsEnabled: layoutsState.activationState == .enabled,
            windowGrabEnabled: grabState.activationState == .enabled
        ))
    }

    private func suspendShortcutTriggersForHotkeyRecording() {
        activeHotkeyRecorderCount += 1
        guard activeHotkeyRecorderCount == 1 else { return }
        hotkeys.unregisterAll()
        voiceCoordinator.suspendActivationMonitoring()
        windowControl.suspendForHotkeyRecording()
    }

    private func resumeShortcutTriggersAfterHotkeyRecording() {
        guard activeHotkeyRecorderCount > 0 else { return }
        activeHotkeyRecorderCount -= 1
        guard activeHotkeyRecorderCount == 0 else { return }
        voiceCoordinator.resumeActivationMonitoring()
        windowControl.resumeAfterHotkeyRecording()
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

    private static func makeSnippetExpander(store: SnippetStore) -> SnippetExpander {
        let expander = SnippetExpander { trigger in try? store.find(trigger: trigger)?.body }
        expander.start()
        return expander
    }

    private static func currentDockHeight() -> CGFloat {
        CGFloat(ClipboardDockHeightSetting.load())
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

enum ClipboardHistoryClearer {
    @discardableResult
    static func clearAll(
        store: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore,
        pinboards: PinboardStore,
        batchSize: Int = 500
    ) throws -> Int {
        let limit = max(1, batchSize)
        var deleted = 0

        while true {
            let batch = try store.list(limit: limit)
            guard !batch.isEmpty else { break }

            for meta in batch {
                try deleteRecord(meta.id, store: store, blobs: blobs, search: search)
                deleted += 1
            }
        }

        try clearPinboardReferences(pinboards)
        return deleted
    }

    private static func deleteRecord(
        _ id: RecordID,
        store: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore
    ) throws {
        if let body = try? store.body(for: id), case let .image(blobID, _, _) = body {
            try? blobs.delete(id: blobID)
        }
        try? search.remove(kind: .clipboardItem, id: id)
        try store.delete(id: id)
    }

    private static func clearPinboardReferences(_ pinboards: PinboardStore) throws {
        for board in try pinboards.list() where !board.itemIDs.isEmpty {
            try pinboards.mutate(id: board.id) { pinboard in
                pinboard.itemIDs.removeAll()
            }
        }
    }
}

@MainActor
private func makeAppDependencies(stores: AppStoreContainer) -> AppDependencies {
    AppDependencies(
        pinboards: stores.pinboard,
        snippets: stores.snippet,
        clip: stores.clipboard,
        blobs: stores.blob
    )
}

@MainActor
private func makeVoiceCoordinator(
    stores: AppStoreContainer,
    cleanupKeyStore: VoiceCleanupKeyStore
) -> VoiceCoordinator {
    let keychain = SystemKeychain()
    let summarizer = VoicePersonalizationSummarizer(
        store: stores.voicePersonalization,
        settings: { VoicePersonalizationSettingsStore.load() },
        makeProvider: {
            let settings = VoiceCleanupSettingsStore.load()
            return try VoiceCleanupProviderFactory.makeTextGenerationProvider(settings: settings, keyStore: cleanupKeyStore)
        }
    )

    let asrSettings = VoiceASRSettingsStore.load()
    let cloudKeyStore = VoiceCloudASRKeyStore(keychain: keychain)
    // Fall back to local if cloud ASR is selected but no API key is configured,
    // so the coordinator starts in a usable state instead of failing on first use.
    let resolvedProviderKind: VoiceASRProviderKind
    if asrSettings.providerKind.isCloud, (try? cloudKeyStore.apiKey(for: asrSettings.providerKind)) == nil {
        resolvedProviderKind = .local
    } else {
        resolvedProviderKind = asrSettings.providerKind
    }
    let engine: any VoiceTranscriptionEngine = switch resolvedProviderKind {
    case .local:
        VoiceLocalASREngine()
    case .groq:
        GroqASREngine(
            settings: { GroqASRSettingsStore.load() },
            keyStore: GroqASRKeyStore(keychain: keychain)
        )
    case .elevenLabs, .openAITranscribe, .deepgram:
        VoiceCloudASREngine(
            providerKind: resolvedProviderKind,
            settings: { VoiceCloudASRSettingsStore.load() },
            keyStore: cloudKeyStore
        )
    }

    return VoiceCoordinator(
        transcripts: stores.voiceTranscripts,
        dictionary: stores.voiceDictionary,
        personalizationStore: stores.voicePersonalization,
        trainingExampleStore: stores.voiceTrainingExamples,
        personalizationSettings: { VoicePersonalizationSettingsStore.load() },
        engine: engine,
        cleanupKeyStore: cleanupKeyStore,
        summarizer: summarizer,
        historySettings: { VoiceHistorySettings.load(from: AppGroupSettings.defaults) }
    )
}

extension Notification.Name {
    static let addDownloadRequested = Notification.Name("addDownloadRequested")
    static let browseFolderRequested = Notification.Name("browseFolderRequested")
    static let clipboardDownloadRequested = Notification.Name("clipboardDownloadRequested")
    static let pauseCaptureRequested = Notification.Name("pauseCaptureRequested")
    static let clearClipboardOlderThanRequested = Notification.Name("clearClipboardOlderThanRequested")
    static let clearAllClipboardHistoryRequested = Notification.Name("clearAllClipboardHistoryRequested")
}
