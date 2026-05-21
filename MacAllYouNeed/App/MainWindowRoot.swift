import AppKit
import ApplicationServices
import AVFoundation
import Core
import FeatureCore
import FluidAudio
import Platform
import SwiftUI
import UniformTypeIdentifiers

private typealias HotkeyDescriptor = Platform.HotkeyDescriptor

struct MainWindowRoot: View {
    let controller: AppController
    private var statePublisher: FeatureStatePublisher
    @AppStorage(MainAppDestination.storageKey, store: AppGroupSettings.defaults)
    private var selectedRaw = MainAppDestination.dashboard.rawValue
    @State private var pendingOrphans: [OrphanCacheScanner.Orphan] = []
    @State private var showWhatsNew = false
    @State private var whatsNewReport: MigrationReport?

    init(controller: AppController) {
        self.controller = controller
        self.statePublisher = controller.featureStatePublisher
    }

    private var selection: Binding<MainAppDestination> {
        Binding {
            MainAppDestination.storedSelection(selectedRaw)
        } set: { destination in
            selectedRaw = destination.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .frame(height: 34)

                ForEach(MainSidebarDestinationPresentation.renderedDestinations()) { destination in
                    let isDisabled = isFeatureDisabled(for: destination)
                    MainSidebarButton(
                        destination: destination,
                        isSelected: selection.wrappedValue == destination,
                        isDisabled: isDisabled,
                        badge: MainSidebarBadgePresentation.badgeText(
                            for: destination,
                            records: controller.downloaderVM.rows
                        )
                    ) {
                        selection.wrappedValue = destination
                    }
                }

                Spacer(minLength: 0)

                Divider()
                    .padding(.vertical, 6)

                MainSidebarSettingsButton {
                    openSettingsInMain()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .background(MAYNTheme.panel)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MAYNTheme.window)
        }
        .tint(MAYNTheme.controlTint)
        .accentColor(.gray)
        .maynDismissTextFocusOnOutsideClick()
        .onReceive(NotificationCenter.default.publisher(for: .globalSettingsOpenRequested)) { note in
            if DockSettingsNavigation.isClipboardRulesRoute(note.object as? String) {
                openClipboardRulesInMain()
                return
            }
            let destination = SettingsDestination.legacySelection(note.object as? String)
            openSettingsInMain(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .orphanCachesFound)) { note in
            guard let orphans = note.userInfo?["orphans"] as? [OrphanCacheScanner.Orphan] else { return }
            pendingOrphans = orphans
        }
        .sheet(isPresented: Binding(
            get: { !pendingOrphans.isEmpty },
            set: { if !$0 { pendingOrphans = [] } }
        )) {
            OrphanCacheCleanupSheet(
                orphans: pendingOrphans,
                onDelete: {
                    let scanner = OrphanCacheScanner.makeForRegistry(controller.runtime.registry)
                    try? scanner.delete(pendingOrphans)
                    OrphanCacheDismissal.markDismissed(pendingOrphans.map { $0.url.standardizedFileURL.path })
                    pendingOrphans = []
                },
                onDismiss: {
                    OrphanCacheDismissal.markDismissed(pendingOrphans.map { $0.url.standardizedFileURL.path })
                    pendingOrphans = []
                }
            )
        }
        .onAppear {
            if let report = controller.pendingMigrationReport {
                whatsNewReport = report
                showWhatsNew = true
                controller.pendingMigrationReport = nil
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            if let report = whatsNewReport {
                WhatsNewSheetView(
                    report: report,
                    registry: controller.runtime.registry,
                    onDismiss: { showWhatsNew = false },
                    onOpenFeaturesSettings: {
                        AppGroupSettings.defaults.set(
                            SettingsDestination.general.rawValue,
                            forKey: DockSettingsNavigation.settingsSelectionKey
                        )
                        selectedRaw = MainAppDestination.settings.rawValue
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
        }
    }

    private var detailView: AnyView {
        switch MainAppDestination.storedSelection(selectedRaw) {
        case .dashboard:
            AnyView(DashboardMainPage(
                controller: controller,
                openDestination: openMainDestination
            ))
        case .clipboard:
            AnyView(ClipboardMainPage(controller: controller))
        case .voice:
            AnyView(VoiceMainPage(controller: controller))
        case .downloads:
            AnyView(DownloadsMainPage(controller: controller))
        case .folderPreview:
            AnyView(FolderPreviewMainPage(controller: controller))
        case .snippets:
            AnyView(SnippetsMainPage(controller: controller))
        case .windowLayouts:
            AnyView(WindowLayoutsMainPage(controller: controller))
        case .grabAnywhere:
            AnyView(GrabAnywhereMainPage(controller: controller))
        case .settings:
            AnyView(EmbeddedSettingsView(controller: controller))
        }
    }

    private func openSettingsInMain(_ destination: SettingsDestination = .general) {
        AppGroupSettings.defaults.set(destination.rawValue, forKey: DockSettingsNavigation.settingsSelectionKey)
        openMainDestination(.settings)
    }

    private func openClipboardRulesInMain() {
        guard !isFeatureDisabled(for: .clipboard) else {
            openMainDestination(.dashboard)
            return
        }
        AppGroupSettings.defaults.set(ClipboardFunctionTab.rules.rawValue, forKey: ClipboardFunctionTab.storageKey)
        openMainDestination(.clipboard)
    }

    private func openMainDestination(_ destination: MainAppDestination) {
        selectedRaw = destination.rawValue
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Feature gating helpers

    private func isFeatureDisabled(for destination: MainAppDestination) -> Bool {
        guard let fid = MainSidebarDestinationPresentation.featureID(for: destination) else { return false }
        return statePublisher.state(for: fid).activationState != .enabled
    }
}

enum MainWindowRootPresentation {
    static let usesTypeErasedDetailViews = true
    static let observesFeatureStatePublisher = true
    static let disabledSidebarItemsAreNonClickable = true
    static let disabledSidebarItemsIgnoreHover = true
}

private struct MainSidebarButton: View {
    let destination: MainAppDestination
    let isSelected: Bool
    let isDisabled: Bool
    let badge: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: destination.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 16)
                    if isDisabled {
                        Image(systemName: "slash.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .offset(x: 5, y: -5)
                    }
                }
                Text(destination.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(MAYNTheme.progress, in: Capsule())
                        .accessibilityLabel("\(badge) downloads in progress")
                }
            }
            .foregroundStyle(isSelected && !isDisabled ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isDisabled { return .clear }
        if isSelected && !isDisabled { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct MainSidebarSettingsButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @AppStorage(MainAppDestination.storageKey, store: AppGroupSettings.defaults)
    private var selectedRaw = MainAppDestination.dashboard.rawValue

    var body: some View {
        Button(action: action) {
            Label("Settings", systemImage: "gearshape")
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var isSelected: Bool {
        MainAppDestination.storedSelection(selectedRaw) == .settings
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct DashboardMainPage: View {
    let controller: AppController
    let openDestination: (MainAppDestination) -> Void
    private var statePublisher: FeatureStatePublisher
    @State private var pendingFeatureIDs: Set<FeatureID> = []
    @State private var showingUninstallFor: FeatureDescriptor?

    init(controller: AppController, openDestination: @escaping (MainAppDestination) -> Void) {
        self.controller = controller
        self.openDestination = openDestination
        self.statePublisher = controller.featureStatePublisher
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dashboardHeader
                toolGrid
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
        }
        .task {
            await controller.downloaderVM.refresh()
        }
        .sheet(
            isPresented: Binding(
                get: { showingUninstallFor != nil },
                set: { isPresented in
                    if !isPresented {
                        showingUninstallFor = nil
                    }
                }
            )
        ) {
            if let descriptor = showingUninstallFor {
                UninstallConfirmationSheet(
                    descriptor: descriptor,
                    onCancel: { showingUninstallFor = nil },
                    onConfirm: { sheet in
                        showingUninstallFor = nil
                        Task { await performUninstall(descriptor: descriptor, sheetState: sheet) }
                    }
                )
            }
        }
    }

    private var dashboardHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Dashboard")
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                Text("Local tools, shortcuts, and current activity.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(dashboardTiles) { tile in
                FeatureToolCard(
                    title: tile.title,
                    subtitle: tile.detail,
                    symbolName: tile.symbolName,
                    accent: accent(for: tile.destination),
                    fixedHeight: DashboardRenderingPresentation.toolCardHeight,
                    state: state(for: tile),
                    descriptor: descriptor(for: tile),
                    isPending: (tile.proxiesFeatureID ?? tile.featureID).map { pendingFeatureIDs.contains($0) } ?? false,
                    onOpen: { openTile(tile) },
                    onEnable: { Task { await handleAction(.enable, for: tile) } },
                    onDisable: { Task { await handleAction(.disable, for: tile) } },
                    onInstall: { Task { await handleAction(.install, for: tile) } },
                    onCancelDownload: { Task { await handleAction(.cancelDownload, for: tile) } },
                    onRetryInstall: { Task { await handleAction(.retryInstall, for: tile) } },
                    onUninstall: { Task { await handleAction(.uninstall, for: tile) } }
                ) {
                    DashboardToolCardFooter(
                        tile: tile,
                        voiceStatus: voiceStatus
                    )
                }
            }
        }
    }

    private var dashboardTiles: [DashboardToolTileItem] {
        DashboardToolTilePresentation.dashboardTiles(
            clipboardCount: controller.clipboardReader.items.count,
            downloadsQueueCount: DashboardDownloadSummaryPresentation.activeQueueCount(in: controller.downloaderVM.rows),
            hotkeys: HotkeyMapStore.load(),
            voiceSettings: VoiceActivationSettingsStore.load()
        )
    }

    private func openTile(_ tile: DashboardToolTileItem) {
        let effectiveID = tile.proxiesFeatureID ?? tile.featureID
        if let effectiveID,
           statePublisher.state(for: effectiveID).activationState != .enabled {
            return
        }
        let route = DashboardToolOpenNavigation.route(for: tile.destination)
        if let tabStorageKey = route.tabStorageKey, let tabRawValue = route.tabRawValue {
            AppGroupSettings.defaults.set(tabRawValue, forKey: tabStorageKey)
        }
        openDestination(route.destination)
    }

    // MARK: Feature helpers

    private func descriptor(for tile: DashboardToolTileItem) -> FeatureDescriptor? {
        guard let featureID = tile.featureID else { return nil }
        return controller.runtime.registry.descriptor(for: featureID)
    }

    private func state(for tile: DashboardToolTileItem) -> FeatureRuntimeState? {
        guard let featureID = tile.featureID else { return nil }
        return statePublisher.state(for: featureID)
    }

    // MARK: Action dispatch

    private enum DashboardFeatureAction {
        case enable, disable, install, cancelDownload, retryInstall, uninstall
    }

    private func handleAction(_ action: DashboardFeatureAction, for tile: DashboardToolTileItem) async {
        guard let targetID = tile.proxiesFeatureID ?? tile.featureID else { return }
        pendingFeatureIDs.insert(targetID)
        defer { pendingFeatureIDs.remove(targetID) }

        switch action {
        case .enable:
            try? await controller.runtime.applyTransition(.enable, for: targetID)
        case .disable:
            try? await controller.runtime.applyTransition(.disable, for: targetID)
        case .install:
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .cancelDownload:
            await controller.packInstallController.cancel(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .retryInstall:
            try? await controller.packInstallController.install(featureID: targetID)
            await controller.featureStatePublisher.refresh()
        case .uninstall:
            guard let desc = controller.runtime.registry.descriptor(for: targetID) else { return }
            showingUninstallFor = desc
        }
    }

    private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
        do {
            try FeatureCacheManager().deleteCaches(sheetState.checkedCacheIDs, in: descriptor)
        } catch {
            NSLog("DashboardMainPage uninstall: cache deletion failed: \(error)")
        }
        try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
        if descriptor.requiresAsset {
            try? await controller.packInstallController.uninstall(featureID: descriptor.id)
        }
        await controller.featureStatePublisher.refresh()
    }

    // MARK: Voice status

    private var voiceStatus: DashboardVoiceStatusPresentation.Status? {
        DashboardVoiceStatusPresentation.footerStatus(for: controller.voiceCoordinator.state)
    }

    private func accent(for destination: MainAppDestination) -> Color {
        switch destination {
        case .clipboard:
            Color(red: 0.10, green: 0.42, blue: 0.92)
        case .voice:
            Color(red: 0.64, green: 0.22, blue: 0.88)
        case .downloads:
            Color(red: 0.02, green: 0.58, blue: 0.42)
        case .folderPreview:
            Color(red: 0.86, green: 0.46, blue: 0.12)
        case .snippets:
            Color(red: 0.82, green: 0.18, blue: 0.36)
        case .windowLayouts:
            Color(red: 0.20, green: 0.48, blue: 0.72)
        case .grabAnywhere:
            Color(red: 0.24, green: 0.46, blue: 0.36)
        case .dashboard, .settings:
            .secondary
        }
    }
}

enum DashboardHeaderPresentation {
    static let trailingActionTitle: String? = nil
}

enum DashboardRenderingPresentation {
    static let usesStaticStartupSummary = false
    static let usesToolCards = true
    static let usesPlainRows = false
    static let toolCardHeight: CGFloat = 156
}

private struct DashboardToolCardFooter: View {
    let tile: DashboardToolTileItem
    let voiceStatus: DashboardVoiceStatusPresentation.Status?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let metric = tile.metric {
                Text(metric)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } else if tile.destination == .voice, let voiceStatus {
                StatusPill(text: voiceStatus.text, kind: voiceStatus.kind)
            } else if let statusText = tile.statusText, let statusKind = tile.statusKind {
                StatusPill(text: statusText, kind: statusKind)
            }

            Spacer(minLength: 8)

            if let shortcutDisplay = tile.shortcutDisplay {
                ShortcutChip(text: shortcutDisplay, height: HotkeyChipPresentation.compactHeight)
            }
        }
        .frame(height: 34, alignment: .center)
    }
}

private struct ClipboardMainPage: View {
    let controller: AppController
    @AppStorage("clipboardMaxItems", store: AppGroupSettings.defaults) private var maxItems = 10000
    @AppStorage("capture.sound", store: AppGroupSettings.defaults) private var captureSound = false
    @AppStorage("autoPaste.behavior", store: AppGroupSettings.defaults) private var pasteBehavior = "pasteIntoFocused"
    @AppStorage("autoPaste.delayMs", store: AppGroupSettings.defaults) private var pasteDelay = 150
    @AppStorage(ClipboardFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = ClipboardFunctionTab.history.rawValue
    @State private var blockedApps: [String] = ExcludedAppsStore.load()
    @State private var hotkeyMap: [HotkeyAction: [HotkeyDescriptor]] = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var historyItems: [ClipboardItemMeta] = []
    @State private var historySearch = ""
    @State private var historyPage = 0
    @State private var isHistoryLoading = false
    private static let historyPageSize = 20

    private var selectedTab: Binding<ClipboardFunctionTab> {
        Binding {
            ClipboardFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Clipboard",
            subtitle: "History, ignored apps, and paste behavior for local clipboard memory.",
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainToolHeaderShortcutModel.display(
                        for: .clipboard,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    )
                )
            }
        ) {
            switch ClipboardFunctionTab.storedSelection(selectedTabRaw) {
            case .history:
                FunctionPageScrollContent {
                    clipboardHistorySection
                }
            case .rules:
                FunctionPageScrollContent {
                    clipboardRulesSection
                }
            case .settings:
                FunctionPageScrollContent {
                    clipboardSettingsSection
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
            blockedApps = ExcludedAppsStore.load()
            reloadClipboardHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardStoreDidChange)) { _ in
            reloadClipboardHistory()
        }
        .onChange(of: controller.clipboardReader.items.map(\.id.rawValue)) { _, _ in
            reloadClipboardHistory()
        }
        .onChange(of: historySearch) { _, _ in
            historyPage = 0
        }
        .onChange(of: historyItems.map(\.id.rawValue)) { _, _ in
            clampClipboardHistoryPage()
        }
        .onChange(of: maxItems) { _, _ in
            reloadClipboardHistory()
        }
    }

    private var clipboardHistorySection: some View {
        Group {
            MAYNSection(title: "All items", subtitle: "Search and page through the full local clipboard history.") {
                let state = clipboardHistoryState
                ClipboardHistorySearchBar(
                    query: $historySearch,
                    resultText: state.totalItems == 1 ? "1 item" : "\(state.totalItems) items"
                )

                MAYNDivider()

                if isHistoryLoading, historyItems.isEmpty {
                    MAYNSettingsRow(title: "Loading history", subtitle: "Reading local clipboard metadata.") {
                        ProgressView()
                            .controlSize(.small)
                    }
                } else if historyItems.isEmpty {
                    MAYNSettingsRow(title: "No items yet", subtitle: "Copy text, images, links, or files to start history capture.") {
                        EmptyView()
                    }
                } else if state.totalItems == 0 {
                    MAYNSettingsRow(title: "No matching items", subtitle: "Clear the search field or try a different term.") {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(state.visibleItems.enumerated()), id: \.element.id.rawValue) { index, item in
                        if index > 0 { MAYNDivider() }
                        MainClipboardRecentRow(
                            item: item,
                            imageLoader: controller.clipboardDeps.imageLoader,
                            appIcons: controller.clipboardDeps.appIcons,
                            isSelected: controller.clipboardReader.selectedIDs.contains(item.id.rawValue),
                            onSelect: {
                                selectClipboardHistoryItem(item)
                            },
                            onCopy: {
                                copyClipboardHistoryItems(ids: [item.id.rawValue])
                            }
                        )
                    }

                    MAYNDivider()
                    ClipboardHistoryPaginationFooter(
                        state: state,
                        previous: { historyPage = max(0, historyPage - 1) },
                        next: { historyPage = min(state.totalPages - 1, historyPage + 1) }
                    )
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress { keyPress in
                handleClipboardHistoryKeyPress(keyPress)
            }
        }
    }

    private var clipboardHistoryState: MainClipboardHistoryPageState {
        MainClipboardHistoryPresentation.state(
            items: historyItems,
            query: historySearch,
            requestedPage: historyPage,
            pageSize: Self.historyPageSize
        )
    }

    private var filteredClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.filteredItems
    }

    private var visibleClipboardHistoryItems: [ClipboardItemMeta] {
        clipboardHistoryState.visibleItems
    }

    private var clipboardRulesSection: some View {
        MAYNSection(
            title: "Ignored Apps",
            subtitle: "Clipboard content copied from these apps will never be saved to history."
        ) {
            BundleIDExclusionEditor(bundleIDs: $blockedApps) { ExcludedAppsStore.save($0) }
        }
    }

    private var clipboardSettingsSection: some View {
        Group {
            MAYNSection(title: "Shortcut") {
                MAYNSettingsRow(
                    title: "Clipboard shortcut",
                    subtitle: "Global trigger for opening the clipboard dock."
                ) {
                    HotkeyRecorderControl(
                        descriptor: hotkeyBinding(for: .clipboard),
                        issueMessage: hotkeyIssueMessage(for: .clipboard),
                        candidateIssueMessage: { hotkeyCandidateIssueMessage($0, for: .clipboard) },
                        defaultDescriptor: HotkeyAction.clipboard.primaryDefaultDescriptor,
                        recorderWidth: 112,
                        errorWidth: 260,
                        reset: {
                            if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                                setHotkey(descriptor, for: .clipboard)
                            }
                        }
                    )
                }
            }

            MAYNSection(title: "Capture") {
                MAYNSettingsRow(
                    title: "Maximum items",
                    subtitle: "Upper bound for searchable clipboard history before retention cleanup."
                ) {
                    MAYNNumericStepper(
                        text: "\(maxItems)",
                        value: $maxItems,
                        range: 100...100_000,
                        step: 100,
                        presets: [1_000, 5_000, 10_000, 50_000, 100_000]
                    )
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Play sound on capture",
                    subtitle: "Audible feedback when a new clipboard item is recorded."
                ) {
                    Toggle("", isOn: $captureSound)
                        .labelsHidden()
                }
            }

            MAYNSection(title: "Paste behavior") {
                MAYNSettingsRow(
                    title: "When picking an item",
                    subtitle: "Choose whether the clipboard dock inserts into the focused app or only copies."
                ) {
                    MAYNDropdown(
                        selection: $pasteBehavior,
                        options: pasteBehaviorOptions,
                        title: pasteBehaviorTitle,
                        width: MAYNControlMetrics.widePickerWidth
                    )
                }

                if pasteBehavior == "copyThenPaste" {
                    MAYNDivider()
                    MAYNSettingsRow(
                        title: "Paste delay",
                        subtitle: "Wait after copying before sending Command-V."
                    ) {
                        MAYNNumericStepper(
                        text: "\(pasteDelay) ms",
                        value: $pasteDelay,
                        range: 50...2000,
                        step: 50,
                        presets: [50, 100, 150, 250, 500, 1000, 2000],
                        suffix: "ms"
                    )
                }
            }
            }

            ClipboardDockHeightSection(controller: controller)

            SearchPreferencesSection()
        }
    }

    private let pasteBehaviorOptions = ["pasteIntoFocused", "copyOnly", "copyThenPaste"]

    private func pasteBehaviorTitle(_ behavior: String) -> String {
        switch behavior {
        case "pasteIntoFocused":
            "Paste into focused app"
        case "copyOnly":
            "Just copy"
        case "copyThenPaste":
            "Copy, then paste"
        default:
            behavior
        }
    }

    private func hotkeyBinding(for action: HotkeyAction) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = action.primaryDefaultDescriptor ?? .defaultClipboard
                let descriptors = hotkeyMap[action] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { descriptor in
                setHotkey(descriptor, for: action)
            }
        )
    }

    private func setHotkey(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) {
        var descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[action] = descriptors
        autoApplyHotkeys(next, changedAction: action)
    }

    private func hotkeyIssueMessage(for action: HotkeyAction) -> String? {
        let descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        guard let descriptor = descriptors.first ?? action.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: action
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [HotkeyDescriptor]], changedAction: HotkeyAction) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: changedAction
            )
        }
    }

    private func reloadClipboardHistory() {
        guard let store = controller.clipboardReader.store else {
            historyItems = controller.clipboardReader.items
            return
        }

        let limit = max(1, maxItems)
        isHistoryLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try store.list(limit: limit) }
            }.value

            switch result {
            case let .success(fetched):
                historyItems = LocalClipboardReader.deduplicate(fetched, limit: limit)
            case .failure:
                historyItems = controller.clipboardReader.items
            }
            isHistoryLoading = false
            clampClipboardHistoryPage()
        }
    }

    private func clampClipboardHistoryPage() {
        let state = clipboardHistoryState
        historyPage = state.currentPage
    }

    private func selectClipboardHistoryItem(_ item: ClipboardItemMeta) {
        let reader = controller.clipboardReader
        let id = item.id.rawValue
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let items = filteredClipboardHistoryItems

        if modifiers.contains(.command) {
            if reader.selectedIDs.contains(id) {
                reader.selectedIDs.remove(id)
            } else {
                reader.selectedIDs.insert(id)
            }
            reader.anchorID = id
            return
        }

        if modifiers.contains(.shift),
           let anchorID = reader.anchorID,
           let anchorIndex = items.firstIndex(where: { $0.id.rawValue == anchorID }),
           let targetIndex = items.firstIndex(where: { $0.id == item.id })
        {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            for row in items[lower...upper] {
                reader.selectedIDs.insert(row.id.rawValue)
            }
            return
        }

        reader.selectedIDs = [id]
        reader.anchorID = id
    }

    private func handleClipboardHistoryKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let raw = keyPress.key.character
        let reader = controller.clipboardReader

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "a" {
            reader.selectedIDs = Set(filteredClipboardHistoryItems.map { $0.id.rawValue })
            reader.anchorID = filteredClipboardHistoryItems.first?.id.rawValue
            return .handled
        }

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "c" {
            copyClipboardHistoryItems(ids: effectiveClipboardHistoryIDs())
            return .handled
        }

        switch raw {
        case " ":
            if ClipboardSystemQuickLookCoordinator.shared.isVisible {
                ClipboardSystemQuickLookCoordinator.shared.dismiss()
            } else {
                previewClipboardHistoryItem(id: effectiveClipboardHistoryIDs().first)
            }
            return .handled
        case Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveClipboardHistorySelection(delta: 1)
            return .handled
        case Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveClipboardHistorySelection(delta: -1)
            return .handled
        default:
            return .ignored
        }
    }

    private func moveClipboardHistorySelection(delta: Int) {
        let reader = controller.clipboardReader
        let items = visibleClipboardHistoryItems
        guard !items.isEmpty else { return }
        let currentIndex = reader.anchorID.flatMap { id in
            items.firstIndex { $0.id.rawValue == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        let nextID = items[nextIndex].id.rawValue
        reader.selectedIDs = [nextID]
        reader.anchorID = nextID
        if ClipboardSystemQuickLookCoordinator.shared.isVisible {
            previewClipboardHistoryItem(id: nextID)
        }
    }

    private func effectiveClipboardHistoryIDs() -> [String] {
        let reader = controller.clipboardReader
        let items = filteredClipboardHistoryItems
        if !reader.selectedIDs.isEmpty {
            return items.map(\.id.rawValue).filter { reader.selectedIDs.contains($0) }
        }
        if let anchorID = reader.anchorID {
            return [anchorID]
        }
        return items.first.map { [$0.id.rawValue] } ?? []
    }

    private func copyClipboardHistoryItems(ids: [String]) {
        guard let store = controller.clipboardReader.store,
              !ids.isEmpty
        else { return }

        if ids.count == 1,
           let id = ids.first,
           let recordID = RecordID(rawValue: id),
           let body = try? store.body(for: recordID)
        {
            ClipboardXPCService.restoreToPasteboard(
                body: body,
                blobs: controller.clipboardDeps.blobs,
                pasteboard: .general
            )
            NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
            CopyHUD.show("Copied")
            return
        }

        let strings = ids.compactMap { id -> String? in
            guard let recordID = RecordID(rawValue: id),
                  let body = try? store.body(for: recordID)
            else { return nil }
            return plainClipboardHistoryText(from: body)
        }
        guard !strings.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        CopyHUD.show(strings.count == 1 ? "Copied" : "Copied \(strings.count)")
    }

    private func previewClipboardHistoryItem(id: String?) {
        guard let id,
              let recordID = RecordID(rawValue: id),
              let store = controller.clipboardReader.store,
              let body = try? store.body(for: recordID)
        else { return }

        let itemTitle = visibleClipboardHistoryItems
            .first { $0.id.rawValue == id }
            .map { $0.customLabel ?? $0.preview }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = itemTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Clipboard Preview"
        ClipboardSystemQuickLookCoordinator.shared.show(
            record: body,
            title: title,
            blobs: controller.clipboardDeps.blobs
        )
    }

    private func plainClipboardHistoryText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(text):
            return text
        case let .html(html):
            return plainHTMLString(html)
        case let .rtf(data):
            return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls):
            return urls.map(\.path).joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private func plainHTMLString(_ html: String) -> String {
        if let data = html.data(using: .utf8),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .newlines)
        }
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

}

enum MainClipboardPreviewKind: Equatable {
    case imageThumbnail(recordID: String)
    case symbol(String)
}

enum ClipboardHistoryIconKind: Equatable {
    case sourceApp(bundleID: String, fallbackSymbol: String)
    case symbol(String)
}

enum ClipboardHistoryIconPresentation {
    static func iconKind(
        for item: ClipboardItemMeta,
        fallbackSymbol: String
    ) -> ClipboardHistoryIconKind {
        let bundleID = item.sourceAppBundleID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bundleID, !bundleID.isEmpty else {
            return .symbol(fallbackSymbol)
        }
        return .sourceApp(bundleID: bundleID, fallbackSymbol: fallbackSymbol)
    }

    static func hasSourceApp(_ item: ClipboardItemMeta) -> Bool {
        if case .sourceApp = iconKind(for: item, fallbackSymbol: "") {
            return true
        }
        return false
    }
}

enum MainClipboardItemPresentation {
    static func previewKind(for item: ClipboardItemMeta) -> MainClipboardPreviewKind {
        if item.preview.hasPrefix("(image ") {
            return .imageThumbnail(recordID: item.id.rawValue)
        }
        if item.preview.hasPrefix("http") {
            return .symbol("link")
        }
        if item.preview.hasPrefix("("), item.preview.contains("file") {
            return .symbol("doc")
        }
        return .symbol("doc.plaintext")
    }
}

enum DashboardClipboardPreviewPresentation {
    static func displayTitle(customLabel: String?, preview: String) -> String {
        if let customLabel, !customLabel.isEmpty {
            return customLabel
        }

        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPreview.range(
            of: #"(?i)(token|secret|password|passwd|api[_-]?key|auth[_-]?key|bearer)\s*[=:]"#,
            options: .regularExpression
        ) != nil {
            return "Sensitive text captured"
        }

        return trimmedPreview
    }
}

struct MainClipboardHistoryPageState: Equatable {
    let filteredItems: [ClipboardItemMeta]
    let visibleItems: [ClipboardItemMeta]
    let currentPage: Int
    let totalPages: Int
    let totalItems: Int
    let pageSize: Int

    var canGoPrevious: Bool { currentPage > 0 }
    var canGoNext: Bool { currentPage < totalPages - 1 }

    var rangeText: String {
        guard totalItems > 0 else { return "0 of 0" }
        let start = currentPage * pageSize + 1
        let end = min(start + visibleItems.count - 1, totalItems)
        return "\(start)-\(end) of \(totalItems)"
    }
}

enum MainClipboardHistoryPresentation {
    static func state(
        items: [ClipboardItemMeta],
        query: String,
        requestedPage: Int,
        pageSize requestedPageSize: Int
    ) -> MainClipboardHistoryPageState {
        let pageSize = max(1, requestedPageSize)
        let filteredItems = filter(items, query: query)
        let totalItems = filteredItems.count
        let totalPages = max(1, Int(ceil(Double(totalItems) / Double(pageSize))))
        let currentPage = min(max(0, requestedPage), totalPages - 1)
        let start = currentPage * pageSize
        let end = min(start + pageSize, totalItems)
        let visibleItems = start < end ? Array(filteredItems[start ..< end]) : []

        return MainClipboardHistoryPageState(
            filteredItems: filteredItems,
            visibleItems: visibleItems,
            currentPage: currentPage,
            totalPages: totalPages,
            totalItems: totalItems,
            pageSize: pageSize
        )
    }

    private static func filter(_ items: [ClipboardItemMeta], query: String) -> [ClipboardItemMeta] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let lower = trimmed.lowercased()

        return items.filter { item in
            item.preview.lowercased().contains(lower)
                || (item.customLabel?.lowercased().contains(lower) ?? false)
        }
    }
}

struct VoiceTranscriptHistorySelectionState: Equatable {
    let selectedIDs: Set<String>
    let anchorID: String?
}

enum MainVoiceTranscriptHistoryPresentation {
    static func displayText(_ transcript: VoiceTranscript) -> String {
        let cleaned = transcript.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return transcript.cleanedText
        }

        let raw = transcript.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Empty transcript" : transcript.rawText
    }

    static func selection(
        afterClicking targetID: String,
        orderedIDs: [String],
        selectedIDs: Set<String>,
        anchorID: String?,
        command: Bool,
        shift: Bool
    ) -> VoiceTranscriptHistorySelectionState {
        guard orderedIDs.contains(targetID) else {
            return VoiceTranscriptHistorySelectionState(selectedIDs: selectedIDs, anchorID: anchorID)
        }

        if command {
            var next = selectedIDs
            if next.contains(targetID) {
                next.remove(targetID)
            } else {
                next.insert(targetID)
            }
            return VoiceTranscriptHistorySelectionState(selectedIDs: next, anchorID: targetID)
        }

        if shift,
           let anchorID,
           let anchorIndex = orderedIDs.firstIndex(of: anchorID),
           let targetIndex = orderedIDs.firstIndex(of: targetID)
        {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            var next = selectedIDs
            next.formUnion(orderedIDs[lower...upper])
            return VoiceTranscriptHistorySelectionState(selectedIDs: next, anchorID: anchorID)
        }

        return VoiceTranscriptHistorySelectionState(selectedIDs: [targetID], anchorID: targetID)
    }

    static func selection(
        afterMovingFrom anchorID: String?,
        orderedIDs: [String],
        delta: Int
    ) -> VoiceTranscriptHistorySelectionState {
        guard !orderedIDs.isEmpty else {
            return VoiceTranscriptHistorySelectionState(selectedIDs: [], anchorID: nil)
        }

        let currentIndex = anchorID.flatMap { orderedIDs.firstIndex(of: $0) } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), orderedIDs.count - 1)
        let nextID = orderedIDs[nextIndex]
        return VoiceTranscriptHistorySelectionState(selectedIDs: [nextID], anchorID: nextID)
    }

    static func effectiveIDs(
        selectedIDs: Set<String>,
        anchorID: String?,
        orderedIDs: [String]
    ) -> [String] {
        if !selectedIDs.isEmpty {
            return orderedIDs.filter { selectedIDs.contains($0) }
        }

        if let anchorID, orderedIDs.contains(anchorID) {
            return [anchorID]
        }

        return orderedIDs.first.map { [$0] } ?? []
    }
}

private struct ClipboardHistorySearchBar: View {
    @Binding var query: String
    let resultText: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search all clipboard items", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(resultText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClipboardHistoryPaginationFooter: View {
    let state: MainClipboardHistoryPageState
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(state.rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            MAYNButton("Previous", action: previous)
                .disabled(!state.canGoPrevious)

            Text("Page \(state.currentPage + 1) of \(state.totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 86)

            MAYNButton("Next", action: next)
                .disabled(!state.canGoNext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VoiceTranscriptPaginationFooter: View {
    let rangeText: String
    let currentPage: Int
    let totalPages: Int
    let canGoPrevious: Bool
    let canGoNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(rangeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            MAYNButton("Previous", action: previous)
                .disabled(!canGoPrevious)

            Text("Page \(currentPage + 1) of \(totalPages)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 86)

            MAYNButton("Next", action: next)
                .disabled(!canGoNext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MainClipboardRecentRow: View {
    let item: ClipboardItemMeta
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void

    var body: some View {
        switch MainClipboardItemPresentation.previewKind(for: item) {
        case let .imageThumbnail(recordID):
            MainClipboardImageRecentRow(
                item: item,
                recordID: recordID,
                imageLoader: imageLoader,
                appIcons: appIcons,
                isSelected: isSelected,
                onSelect: onSelect,
                onCopy: onCopy
            )
        case let .symbol(symbol):
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.customLabel ?? item.preview)
                        .font(.callout)
                        .lineLimit(2)
                    Text(CompactTimestamp.format(item.modified))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ClipboardHistoryIconView(
                    item: item,
                    fallbackSymbol: symbol,
                    appIcons: appIcons,
                    size: 28,
                    symbolFontSize: 15,
                    cornerRadius: 7
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    onCopy()
                }
            )
        }
    }

    private var rowBackground: Color {
        isSelected ? Color.primary.opacity(0.10) : Color.clear
    }
}

private struct MainClipboardImageRecentRow: View {
    let item: ClipboardItemMeta
    let recordID: String
    let imageLoader: ImageBlobLoader
    let appIcons: AppIconResolver
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            MainClipboardThumbnailView(
                recordID: recordID,
                imageLoader: imageLoader,
                width: 92,
                height: 62,
                maxDim: 192
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.customLabel ?? "Image")
                    .font(.callout)
                Text("\(item.preview) - \(CompactTimestamp.format(item.modified))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ClipboardHistoryIconPresentation.hasSourceApp(item) {
                ClipboardHistoryIconView(
                    item: item,
                    fallbackSymbol: "photo",
                    appIcons: appIcons,
                    size: 28,
                    symbolFontSize: 15,
                    cornerRadius: 7
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 82)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onCopy()
            }
        )
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

struct ClipboardHistoryIconView: View {
    let item: ClipboardItemMeta
    let fallbackSymbol: String
    let appIcons: AppIconResolver
    let size: CGFloat
    let symbolFontSize: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        switch ClipboardHistoryIconPresentation.iconKind(for: item, fallbackSymbol: fallbackSymbol) {
        case let .sourceApp(bundleID, fallbackSymbol):
            if let icon = appIcons.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 0.5)
                    )
                    .help(appIcons.displayName(for: bundleID))
            } else {
                fallbackIcon(fallbackSymbol)
            }
        case let .symbol(symbol):
            fallbackIcon(symbol)
        }
    }

    private func fallbackIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: symbolFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

private struct MainClipboardThumbnailView: View {
    let recordID: String
    let imageLoader: ImageBlobLoader
    let width: CGFloat
    let height: CGFloat
    let maxDim: Int
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            } else if failed {
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .task(id: "\(recordID)-\(maxDim)") {
            image = nil
            failed = false
            let loadedImage = await imageLoader.thumbnail(recordID: recordID, maxDim: maxDim)
            await MainActor.run {
                image = loadedImage
                failed = loadedImage == nil
            }
        }
    }
}

private struct MainHeaderToolbar<ShortcutControl: View>: View {
    let buttonTitle: String
    var buttonDisabled = false
    let action: () -> Void
    let shortcutControl: ShortcutControl

    init(
        buttonTitle: String,
        buttonDisabled: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder shortcutControl: () -> ShortcutControl
    ) {
        self.buttonTitle = buttonTitle
        self.buttonDisabled = buttonDisabled
        self.action = action
        self.shortcutControl = shortcutControl()
    }

    var body: some View {
        HStack(spacing: 8) {
            shortcutControl
            MAYNButton(buttonTitle, action: action)
                .disabled(buttonDisabled)
        }
    }
}

private struct MainHeaderShortcutDisplay: View {
    let text: String?
    var issueMessage: String?

    var body: some View {
        if let text {
            HStack(spacing: 6) {
                MAYNHotkeyDisplay(text: text)
                if let issueMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MAYNTheme.warning)
                        .accessibilityLabel(issueMessage)
                }
            }
            .accessibilityLabel("Current shortcut \(text)")
            .help(issueMessage ?? "Change this shortcut in Settings")
        }
    }
}

private struct VoiceMainPage: View {
    let controller: AppController
    @AppStorage(VoiceFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = VoiceFunctionTab.dictate.rawValue
    @AppStorage(VoiceAudioSettings.microphoneIDKey, store: AppGroupSettings.defaults) private var preferredMicrophoneID = VoiceAudioSettings.systemMicrophoneID
    @AppStorage("voice.audio.interactionSounds", store: AppGroupSettings.defaults) private var interactionSounds = true
    @AppStorage("voice.audio.muteWhenDictating", store: AppGroupSettings.defaults) private var muteWhenDictating = false
    @AppStorage("voice.asr.groq.apiSetupExpanded", store: AppGroupSettings.defaults) private var isCloudAPISetupExpanded = false
    @State private var shortcut: HotkeyDescriptor
    @State private var mode: VoiceActivationMode
    @State private var selectedASRModelID: VoiceASRModelID
    @State private var languageHint: VoiceASRLanguageHint
    @State private var asrProviderKind: VoiceASRProviderKind
    @State private var cloudModelID: VoiceCloudASRModelID
    @State private var cloudLanguageHint: VoiceASRLanguageHint
    @State private var cloudAPIKeys: [VoiceASRProviderKind: String]
    @State private var cloudSetupProviderKind: VoiceASRProviderKind
    @State private var cloudStatusMessage: String?
    @State private var isTestingCloud = false
    @State private var cleanupEnabled: Bool
    @State private var cleanupProvider: VoiceCleanupProviderKind
    @State private var cleanupModel: String
    @State private var cleanupBaseURLString: String
    @State private var cleanupAPIKey: String
    @State private var cleanupTimeoutSeconds: Int
    @State private var cleanupLatencyPolicy: VoiceCleanupLatencyPolicy
    @State private var cleanupStatusMessage: String?
    @State private var onboardingProgress: VoiceOnboardingProgress
    @State private var errorMessage: String?
    @State private var transcripts: [VoiceTranscript] = []
    @State private var transcriptPage = 0
    @State private var selectedTranscriptIDs: Set<String> = []
    @State private var voiceHistorySettings = VoiceHistorySettings()
    @State private var historyToast: VoiceHistoryUndoToken?
    @State private var toastClearTask: Task<Void, Never>?
    @State private var transcriptAnchorID: String?
    @State private var microphoneOptions = VoiceMicrophoneOptionDescriptor.available()
    @State private var modelDownloadStatus: [VoiceASRModelID: String] = [:]
    @State private var modelDownloadFractions: [VoiceASRModelID: Double] = [:]
    @State private var downloadingModelID: VoiceASRModelID?
    private let microphoneRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controller: AppController) {
        self.controller = controller
        let activationSettings = VoiceActivationSettingsStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cloudSettings = VoiceCloudASRSettingsStore.load()
        let cleanupSettings = controller.voiceCleanupSettings()
        let recognitionLanguageHint = asrSettings.providerKind.isCloud
            ? cloudSettings.languageHint
            : asrSettings.languageHint
        _shortcut = State(initialValue: activationSettings.shortcut)
        _mode = State(initialValue: activationSettings.mode)
        _selectedASRModelID = State(initialValue: asrSettings.modelID)
        _languageHint = State(initialValue: recognitionLanguageHint)
        _asrProviderKind = State(initialValue: asrSettings.providerKind)
        _cloudModelID = State(
            initialValue: asrSettings.providerKind.isCloud
                ? cloudSettings.modelID(for: asrSettings.providerKind)
                : cloudSettings.modelID
        )
        _cloudLanguageHint = State(initialValue: recognitionLanguageHint)
        let cloudKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        _cloudAPIKeys = State(initialValue: cloudKeys)
        _cloudSetupProviderKind = State(initialValue: asrSettings.providerKind.isCloud ? asrSettings.providerKind : cloudSettings.modelID.providerKind)
        _cleanupEnabled = State(initialValue: cleanupSettings.isEnabled)
        _cleanupProvider = State(initialValue: cleanupSettings.provider)
        _cleanupModel = State(initialValue: cleanupSettings.model)
        _cleanupBaseURLString = State(initialValue: cleanupSettings.baseURLString)
        _cleanupAPIKey = State(initialValue: controller.voiceCleanupAPIKey(for: cleanupSettings.provider))
        _cleanupTimeoutSeconds = State(initialValue: cleanupSettings.timeoutSeconds)
        _cleanupLatencyPolicy = State(initialValue: cleanupSettings.latencyPolicy)
        _onboardingProgress = State(initialValue: VoiceOnboardingProgressStore.load())
    }

    private var selectedTab: Binding<VoiceFunctionTab> {
        Binding {
            VoiceFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Voice",
            subtitle: "Dictation, transcript history, dictionary, app profiles, and voice settings.",
            selection: selectedTab,
            toolbar: {
                if VoiceMainPagePresentation.showsHeaderShortcut {
                    MainHeaderShortcutDisplay(
                        text: MainToolHeaderShortcutModel.display(
                            for: .voice,
                            hotkeys: HotkeyMapStore.load(),
                            voiceSettings: VoiceActivationSettings(shortcut: shortcut, mode: mode)
                        )
                    )
                }
            }
        ) {
            switch VoiceFunctionTab.storedSelection(selectedTabRaw) {
            case .dictate:
                FunctionPageScrollContent {
                    voiceDictateSection
                    voiceSetupSection
                }
            case .models:
                FunctionPageScrollContent {
                    voiceRecognitionModelsSection
                    voiceCleanupSection
                }
            case .history:
                FunctionPageScrollContent {
                    voiceHistorySection
                }
            case .dictionary:
                VoiceDictionaryPage(controller: controller, showsHeader: false)
            case .personalization:
                FunctionPageScrollContent {
                    VoicePersonalizationPage(controller: controller)
                }
            case .settings:
                FunctionPageScrollContent {
                    voiceActivationSection
                    voiceModelSummarySection
                    voiceAudioSection
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            refreshMicrophoneOptions()
        }
        .onReceive(microphoneRefreshTimer) { _ in
            refreshMicrophoneOptions()
        }
        .onChange(of: cleanupProvider) { _, provider in
            cleanupModel = provider.defaultModel
            cleanupBaseURLString = provider.defaultBaseURLString
            cleanupAPIKey = controller.voiceCleanupAPIKey(for: provider)
        }
        .onChange(of: languageHint) { _, hint in
            cloudLanguageHint = hint
            controller.applyVoiceASRSettings(currentAppliedASRSettings.updating(languageHint: hint))
            controller.applyCloudASRSettings(VoiceCloudASRSettings(modelID: cloudModelID, languageHint: hint))
        }
        .onChange(of: asrProviderKind) { _, providerKind in
            applyASRProviderSelection(providerKind)
        }
        .onChange(of: cloudModelID) { _, newModelID in
            cloudSetupProviderKind = newModelID.providerKind
            applyCloudDropdownSettings()
        }
    }

    private var voiceDictateSection: some View {
        MAYNSection(title: "Dictate") {
            MAYNSettingsRow(
                title: "State",
                subtitle: voiceStateTitle
            ) {
                StatusPill(text: voiceStatusText, kind: voiceStatusKind)
            }
        }
    }

    private var voiceSetupSection: some View {
        MAYNSection(title: "Setup") {
            MAYNSettingsRow(
                title: "Voice onboarding",
                subtitle: "Checks microphone, Accessibility, ASR, cleanup, shortcut, languages, and a try-it pass."
            ) {
                StatusPill(
                    text: onboardingProgress.isCompleted ? "Completed" : onboardingProgress.currentStep.title,
                    kind: onboardingProgress.isCompleted ? .success : .progress
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Setup actions") {
                HStack(spacing: 8) {
                    MAYNButton(onboardingProgress.isCompleted ? "Open setup" : "Continue setup") {
                        controller.showVoiceOnboarding()
                        reload()
                    }
                    MAYNButton("Restart") {
                        controller.restartVoiceOnboarding()
                        reload()
                    }
                }
            }
        }
    }

    private var voiceRecognitionModelsSection: some View {
        MAYNSection(
            title: "Recognition model",
            subtitle: "Choose the local or BYOK cloud recognizer used for dictation."
        ) {
            MAYNSettingsRow(
                title: "Dictation language",
                subtitle: "Auto-detect is best for mixed Chinese and English; switch to one language only when results drift."
            ) {
                MAYNDropdown(
                    selection: $languageHint,
                    options: Array(VoiceASRLanguageHint.allCases),
                    title: VoiceLanguageModePresentation.title,
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            VoiceCloudASRSetupDrawer(
                isExpanded: $isCloudAPISetupExpanded,
                providerKind: cloudSetupProviderKind,
                apiKey: cloudAPIKeyBinding,
                isTesting: isTestingCloud,
                statusMessage: cloudStatusMessage,
                testConnection: testCloudConnection
            )
            MAYNDivider()
            ForEach(Array(VoiceModelCatalog.cloudASRModels.enumerated()), id: \.element.id) { index, descriptor in
                let modelID = descriptor.cloudASRModelID!
                if index > 0 { MAYNDivider() }
                VoiceCloudASRModelRow(
                    modelID: modelID,
                    isSelected: VoiceASRModelSelectionState.isCloudModelSelected(
                        providerKind: asrProviderKind,
                        selectedModelID: cloudModelID,
                        modelID: modelID,
                        hasUsableAPIKey: hasUsableCloudAPIKey(for: modelID.providerKind)
                    ),
                    hasUsableAPIKey: hasUsableCloudAPIKey(for: modelID.providerKind),
                    action: { selectCloudModel(modelID) }
                )
            }
            MAYNDivider()
            ForEach(Array(VoiceModelCatalog.localASRModels.enumerated()), id: \.element.id) { index, descriptor in
                if index > 0 { MAYNDivider() }
                if let modelID = descriptor.localASRModelID {
                    VoiceASRModelRow(
                        modelID: modelID,
                        isSelected: VoiceASRModelSelectionState.isLocalModelSelected(
                            providerKind: asrProviderKind,
                            selectedModelID: selectedASRModelID,
                            modelID: modelID
                        ),
                        isDownloaded: isDownloaded(modelID),
                        statusMessage: modelDownloadStatus[modelID],
                        downloadFraction: modelDownloadFractions[modelID],
                        isDownloading: downloadingModelID == modelID,
                        onSelect: { selectModel(modelID) },
                        onShowInFinder: { showModelInFinder(modelID) },
                        onDelete: { deleteModel(modelID) }
                    )
                } else {
                    VoiceUnsupportedASRModelRow(descriptor: descriptor)
                }
            }
        }
    }

    private var voiceHistorySection: some View {
        let page = voiceTranscriptPageState
        return VStack(spacing: 12) {
            MAYNSection(title: "Recent transcripts") {
                if transcripts.isEmpty {
                    MAYNSettingsRow(
                        title: "No transcripts yet",
                        subtitle: "Completed voice dictations appear here after transcription and paste."
                    ) {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(page.visible.enumerated()), id: \.element.id) { index, transcript in
                        if index > 0 { MAYNDivider() }
                        VoiceTranscriptHistoryRow(
                            transcript: transcript,
                            isSelected: selectedTranscriptIDs.contains(transcript.id),
                            onSelect: { selectVoiceTranscript(transcript) },
                            onCopy: { copyVoiceTranscripts(ids: [transcript.id]) },
                            onRetry: { retryTranscript(transcript) },
                            onDownload: { downloadTranscript(transcript) },
                            onDelete: { deleteTranscriptWithUndo(transcript) }
                        )
                    }

                    if page.totalPages > 1 {
                        MAYNDivider()
                        VoiceTranscriptPaginationFooter(
                            rangeText: page.rangeText,
                            currentPage: page.currentPage,
                            totalPages: page.totalPages,
                            canGoPrevious: page.canGoPrevious,
                            canGoNext: page.canGoNext,
                            previous: { transcriptPage = max(0, transcriptPage - 1) },
                            next: { transcriptPage = min(page.totalPages - 1, transcriptPage + 1) }
                        )
                    }
                }
            }

            VoiceHistoryStorageHeader(settings: $voiceHistorySettings)
                .onChange(of: voiceHistorySettings) { _, new in
                    controller.saveVoiceHistorySettings(new)
                }
        }
        .overlay(alignment: .bottom) {
            if let toast = historyToast {
                VoiceHistoryToastView(message: toast.message) {
                    toast.undo()
                    toastClearTask?.cancel()
                    historyToast = nil
                    reload()
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            handleVoiceHistoryKeyPress(keyPress)
        }
    }

    private struct VoiceTranscriptPageState {
        let visible: [VoiceTranscript]
        let currentPage: Int
        let totalPages: Int
        let totalItems: Int
        let pageSize: Int
        var canGoPrevious: Bool { currentPage > 0 }
        var canGoNext: Bool { currentPage < totalPages - 1 }
        var rangeText: String {
            guard totalItems > 0 else { return "0 of 0" }
            let start = currentPage * pageSize + 1
            let end = min(start + visible.count - 1, totalItems)
            return "\(start)–\(end) of \(totalItems)"
        }
    }

    private var voiceTranscriptPageState: VoiceTranscriptPageState {
        let size = 15
        let total = transcripts.count
        let pages = max(1, Int(ceil(Double(total) / Double(size))))
        let page = min(max(0, transcriptPage), pages - 1)
        let start = page * size
        let end = min(start + size, total)
        let visible = start < end ? Array(transcripts[start ..< end]) : []
        return VoiceTranscriptPageState(
            visible: visible, currentPage: page, totalPages: pages, totalItems: total, pageSize: size
        )
    }

    private var voiceActivationSection: some View {
        MAYNSection(title: "Activation") {
            MAYNSettingsRow(
                title: "Mode",
                subtitle: "Toggle starts on first press and stops on second press. Hold records while the shortcut is held."
            ) {
                FunctionSegmentedTabStrip(
                    tabs: Array(VoiceActivationMode.allCases),
                    selection: activationModeBinding.wrappedValue,
                    fillsAvailableWidth: false,
                    size: .control
                ) { mode in
                    activationModeBinding.wrappedValue = mode
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Shortcut",
                subtitle: "Global keyboard trigger for voice capture.",
                minHeight: shortcutIssue == nil ? 46 : 72
            ) {
                HotkeyRecorderControl(
                    descriptor: activationShortcutBinding,
                    issueMessage: shortcutIssue?.message,
                    candidateIssueMessage: { shortcutCandidateIssue($0)?.message },
                    defaultDescriptor: VoiceActivationSettings.default.shortcut,
                    recorderWidth: 160,
                    recorderHeight: 26,
                    errorWidth: 230,
                    reset: { applyActivationShortcut(VoiceActivationSettings.default.shortcut) }
                )
            }

            if let errorMessage {
                MAYNDivider()
                MAYNSettingsRow(title: "Voice error") {
                    StatusPill(text: errorMessage, kind: .danger)
                }
            }
        }
    }

    private var voiceModelSummarySection: some View {
        MAYNSection(title: "Models") {
            MAYNSettingsRow(
                title: "Recognition model",
                subtitle: recognitionModelSummary
            ) {
                MAYNButton("Open Models") {
                    selectedTabRaw = VoiceFunctionTab.models.rawValue
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Cleanup model",
                subtitle: cleanupModelSummary
            ) {
                StatusPill(text: cleanupEnabled ? cleanupProvider.label : "Off", kind: .neutral)
            }
        }
    }

    private var voiceAudioSection: some View {
        MAYNSection(title: "Audio") {
            MAYNSettingsRow(
                title: "Microphone",
                subtitle: "Choose the preferred input device for voice capture. Auto follows macOS Sound settings."
            ) {
                MAYNDropdown(
                    selection: $preferredMicrophoneID,
                    options: microphoneOptions.map(\.id),
                    title: microphoneTitle,
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Interaction sounds",
                subtitle: "Reserved for voice start/stop feedback."
            ) {
                Toggle("", isOn: $interactionSounds)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Mute when dictating",
                subtitle: "Preference only; automatic app audio ducking is not wired yet."
            ) {
                Toggle("", isOn: $muteWhenDictating)
                    .labelsHidden()
            }
        }
    }

    private var voiceCleanupSection: some View {
        MAYNSection(title: "Cleanup") {
            MAYNSettingsRow(
                title: "AI cleanup",
                subtitle: "Send recognized text through the configured cleanup provider before paste."
            ) {
                Toggle("", isOn: $cleanupEnabled)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Provider") {
                MAYNDropdown(
                    selection: $cleanupProvider,
                    options: Array(VoiceCleanupProviderKind.allCases),
                    title: { $0.label }
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Model") {
                MAYNTextField(text: $cleanupModel)
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Base URL") {
                MAYNTextField(text: $cleanupBaseURLString)
            }
            if cleanupProvider == .ollama {
                MAYNDivider()
                VoiceOllamaCleanupControls(
                    controller: controller,
                    model: $cleanupModel,
                    baseURLString: $cleanupBaseURLString,
                    statusMessage: $cleanupStatusMessage
                )
            }
            if cleanupProvider.requiresAPIKey {
                MAYNDivider()
                MAYNSettingsRow(title: "API key") {
                    MAYNSecureField(text: $cleanupAPIKey)
                }
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Timeout") {
                MAYNNumericStepper(
                    text: "\(cleanupTimeoutSeconds)s",
                    value: $cleanupTimeoutSeconds,
                    range: 1...30,
                    presets: [3, 5, 7, 10, 15, 30],
                    suffix: "s"
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Latency policy",
                subtitle: cleanupLatencyPolicy.subtitle
            ) {
                MAYNDropdown(
                    selection: $cleanupLatencyPolicy,
                    options: Array(VoiceCleanupLatencyPolicy.allCases),
                    title: { $0.label },
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            MAYNSettingsRow(title: "Cleanup actions") {
                HStack(spacing: 8) {
                    MAYNButton("Test") { testCleanupSettings() }
                    MAYNButton("Apply", role: .primary) { applyCleanupSettings() }
                }
            }

            if let cleanupStatusMessage {
                MAYNDivider()
                MAYNSettingsRow(title: "Cleanup status") {
                    StatusPill(text: cleanupStatusMessage, kind: .neutral)
                }
            }
        }
    }

    private func reload() {
        onboardingProgress = VoiceOnboardingProgressStore.load()
        let asrSettings = VoiceASRSettingsStore.load()
        let cloudSettings = VoiceCloudASRSettingsStore.load()
        let recognitionLanguageHint = asrSettings.providerKind.isCloud
            ? cloudSettings.languageHint
            : asrSettings.languageHint
        selectedASRModelID = asrSettings.modelID
        languageHint = recognitionLanguageHint
        asrProviderKind = asrSettings.providerKind
        cloudModelID = asrSettings.providerKind.isCloud
            ? cloudSettings.modelID(for: asrSettings.providerKind)
            : cloudSettings.modelID
        cloudLanguageHint = recognitionLanguageHint
        cloudAPIKeys = Dictionary(
            uniqueKeysWithValues: VoiceASRProviderKind.allCases
                .filter(\.isCloud)
                .map { ($0, controller.cloudASRAPIKey(for: $0)) }
        )
        cloudSetupProviderKind = asrSettings.providerKind.isCloud ? asrSettings.providerKind : cloudSettings.modelID.providerKind
        transcripts = controller.listRecentVoiceTranscripts(limit: 500)
        transcriptPage = 0
        pruneVoiceTranscriptSelection()
        refreshMicrophoneOptions()
        voiceHistorySettings = controller.loadVoiceHistorySettings()
    }

    private var voiceTranscriptIDs: [String] {
        transcripts.map(\.id)
    }

    private func selectVoiceTranscript(_ transcript: VoiceTranscript) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterClicking: transcript.id,
            orderedIDs: voiceTranscriptIDs,
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift)
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID
    }

    private func applyASRProviderSelection(_ providerKind: VoiceASRProviderKind) {
        switch providerKind {
        case .local:
            controller.applyVoiceASRSettings(providerASRSettingsDraft)
            cloudStatusMessage = nil
            errorMessage = nil
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudSetupProviderKind = providerKind
            cloudModelID = cloudASRSettingsDraft.modelID(for: providerKind)
            guard hasUsableCloudAPIKey(for: providerKind) else {
                isCloudAPISetupExpanded = true
                cloudStatusMessage = "Add \(providerKind.apiKeyLabel) before dictating with \(providerKind.label)."
                return
            }
            controller.applyCloudASRSettings(cloudASRSettingsDraft)
            controller.applyVoiceASRSettings(providerASRSettingsDraft)
            applyCloudProviderSettings(successMessage: "\(providerKind.label) selected.")
        }
    }

    private func applyCloudDropdownSettings() {
        controller.applyCloudASRSettings(cloudASRSettingsDraft)
        if asrProviderKind == cloudModelID.providerKind {
            applyASRProviderSelection(cloudModelID.providerKind)
        }
    }

    private func applyCloudProviderSettings(successMessage: String) {
        do {
            try controller.applyVoiceASRProviderSettings(
                asrSettings: providerASRSettingsDraft,
                cloudSettings: cloudASRSettingsDraft,
                cloudAPIKey: cloudAPIKeys[cloudSetupProviderKind] ?? ""
            )
            cloudStatusMessage = successMessage
            errorMessage = nil
        } catch {
            let message = error.localizedDescription
            cloudStatusMessage = message
            errorMessage = message
        }
    }

    private func testCloudConnection() {
        isTestingCloud = true
        cloudStatusMessage = "Connecting..."
        let settings = cloudASRSettingsDraft.updating(modelID: cloudASRSettingsDraft.modelID(for: cloudSetupProviderKind))
        let providerKind = cloudSetupProviderKind
        let key = cloudAPIKeys[providerKind] ?? ""
        Task {
            let result = await controller.testCloudASRSettings(settings, providerKind: providerKind, apiKey: key)
            await MainActor.run {
                if result.localizedCaseInsensitiveContains("succeeded") {
                    cloudModelID = settings.modelID
                    asrProviderKind = providerKind
                    applyCloudProviderSettings(successMessage: "Connection succeeded. Future dictations will use \(providerKind.label).")
                } else {
                    cloudStatusMessage = result
                }
                isTestingCloud = false
            }
        }
    }

    private func handleVoiceHistoryKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let raw = keyPress.key.character

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "a" {
            selectedTranscriptIDs = Set(voiceTranscriptIDs)
            transcriptAnchorID = voiceTranscriptIDs.first
            return .handled
        }

        if keyPress.modifiers.contains(.command), String(raw).lowercased() == "c" {
            copyVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        }

        if keyPress.modifiers.contains(.command), Self.isDeleteKey(raw) {
            deleteVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        }

        switch raw {
        case " ":
            previewVoiceTranscript(id: effectiveVoiceTranscriptIDs().first)
            return .handled
        case "\r":
            copyVoiceTranscripts(ids: effectiveVoiceTranscriptIDs())
            return .handled
        case Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            moveVoiceTranscriptSelection(delta: 1)
            return .handled
        case Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            moveVoiceTranscriptSelection(delta: -1)
            return .handled
        default:
            return .ignored
        }
    }

    private func moveVoiceTranscriptSelection(delta: Int) {
        let previousIndex = transcriptAnchorID.flatMap { voiceTranscriptIDs.firstIndex(of: $0) } ?? 0
        let state = MainVoiceTranscriptHistoryPresentation.selection(
            afterMovingFrom: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs,
            delta: delta
        )
        selectedTranscriptIDs = state.selectedIDs
        transcriptAnchorID = state.anchorID

        if PreviewPanel.isVisible,
           let transcriptAnchorID {
            let nextIndex = voiceTranscriptIDs.firstIndex(of: transcriptAnchorID) ?? previousIndex
            previewVoiceTranscript(
                id: transcriptAnchorID,
                direction: PreviewPanelTransitionDirection.horizontal(from: previousIndex, to: nextIndex)
            )
        }
    }

    private func effectiveVoiceTranscriptIDs() -> [String] {
        MainVoiceTranscriptHistoryPresentation.effectiveIDs(
            selectedIDs: selectedTranscriptIDs,
            anchorID: transcriptAnchorID,
            orderedIDs: voiceTranscriptIDs
        )
    }

    private func copyVoiceTranscripts(ids: [String]) {
        let strings = ids.compactMap { id in
            transcripts.first { $0.id == id }.map(MainVoiceTranscriptHistoryPresentation.displayText)
        }.filter { $0 != "Empty transcript" }
        guard !strings.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
        NSPasteboard.general.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        CopyHUD.show(strings.count == 1 ? "Copied" : "Copied \(strings.count)")
    }

    private func previewVoiceTranscript(
        id: String?,
        direction: PreviewPanelTransitionDirection = .none
    ) {
        guard let id,
              let transcript = transcripts.first(where: { $0.id == id })
        else { return }

        PreviewPanel.show(
            .text(MainVoiceTranscriptHistoryPresentation.displayText(transcript), monospaced: false),
            metadata: PreviewPanelMetadata(
                title: "Voice transcript",
                subtitle: "\(CompactTimestamp.format(transcript.endedAt)) · \(transcript.language.rawValue)",
                badge: "\(transcript.durationMs) ms",
                symbol: "waveform"
            ),
            direction: direction
        )
    }

    private func deleteVoiceTranscripts(ids: [String]) {
        guard !ids.isEmpty else { return }
        do {
            try controller.deleteVoiceTranscripts(ids: ids)
            selectedTranscriptIDs.subtract(ids)
            if let transcriptAnchorID, ids.contains(transcriptAnchorID) {
                self.transcriptAnchorID = nil
            }
            reload()
            CopyHUD.show(ids.count == 1 ? "Deleted" : "Deleted \(ids.count)", symbol: "trash.fill")
            if PreviewPanel.isVisible {
                PreviewPanel.dismiss()
            }
        } catch {
            CopyHUD.show("Delete failed", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func pruneVoiceTranscriptSelection() {
        let existingIDs = Set(voiceTranscriptIDs)
        selectedTranscriptIDs.formIntersection(existingIDs)
        if let transcriptAnchorID, !existingIDs.contains(transcriptAnchorID) {
            self.transcriptAnchorID = selectedTranscriptIDs.first ?? voiceTranscriptIDs.first
        }
    }

    private func retryTranscript(_ transcript: VoiceTranscript) {
        Task { @MainActor in
            do {
                _ = try await controller.retryVoiceTranscript(id: transcript.id)
                reload()
            } catch {
                CopyHUD.show("Retry failed", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    private func downloadTranscript(_ transcript: VoiceTranscript) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "voice-\(formatter.string(from: transcript.endedAt)).wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.downloadVoiceAudio(transcript: transcript, to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save audio"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func deleteTranscriptWithUndo(_ transcript: VoiceTranscript) {
        let token = controller.deleteVoiceTranscriptWithUndo(transcript)
        toastClearTask?.cancel()
        historyToast = token
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            historyToast = nil
        }
        toastClearTask = task
        reload()
    }

    private static func isDeleteKey(_ character: Character) -> Bool {
        character == Character(UnicodeScalar(NSDeleteCharacter)!)
            || character == Character(UnicodeScalar(NSBackspaceCharacter)!)
    }

    private func refreshMicrophoneOptions() {
        let options = VoiceMicrophoneOptionDescriptor.available()
        microphoneOptions = options
        let normalized = VoiceAudioSettings.normalizedPreferredMicrophoneID(
            preferredMicrophoneID,
            availableDeviceIDs: Set(options.map(\.id))
        )
        if normalized != preferredMicrophoneID {
            preferredMicrophoneID = normalized
        }
    }

    private func microphoneTitle(_ id: String) -> String {
        microphoneOptions.first { $0.id == id }?.name ?? "Auto-detect"
    }

    private var activationShortcutBinding: Binding<HotkeyDescriptor> {
        Binding(
            get: { shortcut },
            set: { descriptor in
                applyActivationShortcut(descriptor)
            }
        )
    }

    private var activationModeBinding: Binding<VoiceActivationMode> {
        Binding(
            get: { mode },
            set: { newMode in
                mode = newMode
                applyActivationSettingsIfValid()
            }
        )
    }

    private func applyActivationShortcut(_ descriptor: HotkeyDescriptor) {
        shortcut = descriptor
        applyActivationSettingsIfValid()
    }

    private func toggleVoice() {
        if controller.voiceCoordinator.state == .recording {
            Task {
                await controller.voiceCoordinator.stopRecordingAndPaste()
                await MainActor.run { reload() }
            }
        } else {
            Task { await controller.voiceCoordinator.startRecording() }
        }
    }

    private func applyActivationSettingsIfValid() {
        if let shortcutIssue {
            errorMessage = shortcutIssue.message
            return
        }

        do {
            try controller.applyVoiceActivationSettings(VoiceActivationSettings(shortcut: shortcut, mode: mode))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectModel(_ modelID: VoiceASRModelID) {
        if isDownloaded(modelID) {
            useModel(modelID)
        } else {
            downloadModel(modelID, selectWhenReady: true)
        }
    }

    private func selectCloudModel(_ modelID: VoiceCloudASRModelID) {
        cloudSetupProviderKind = modelID.providerKind
        guard hasUsableCloudAPIKey(for: modelID.providerKind) else {
            isCloudAPISetupExpanded = true
            cloudStatusMessage = "Add \(modelID.providerKind.apiKeyLabel) before selecting this cloud model."
            return
        }

        cloudModelID = modelID
        let providerKind = VoiceASRModelSelectionState.providerKindAfterSelectingCloudModel(modelID)
        asrProviderKind = providerKind
        applyASRProviderSelection(providerKind)
    }

    private func useModel(_ modelID: VoiceASRModelID) {
        selectedASRModelID = modelID
        let providerKind = VoiceASRModelSelectionState.providerKindAfterSelectingLocalModel()
        asrProviderKind = providerKind
        controller.applyVoiceASRSettings(
            VoiceASRSettings(
                modelID: modelID,
                languageHint: languageHint,
                providerKind: providerKind
            )
        )
        modelDownloadStatus[modelID] = "Selected for future dictation."
    }

    private func downloadModel(_ modelID: VoiceASRModelID, selectWhenReady: Bool = false) {
        guard downloadingModelID == nil else { return }

        downloadingModelID = modelID
        modelDownloadFractions[modelID] = 0
        modelDownloadStatus[modelID] = "Preparing download..."
        Task {
            do {
                try await VoiceModelManager.downloadLocalASRModel(
                    modelID,
                    progressHandler: { progress in
                        Task { @MainActor in
                            modelDownloadStatus[modelID] = VoiceModelDownloadPresenter.describe(progress)
                            modelDownloadFractions[modelID] = progress.fractionCompleted
                        }
                    }
                )
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    modelDownloadStatus[modelID] = "Downloaded."
                    if selectWhenReady {
                        useModel(modelID)
                    }
                }
            } catch {
                await MainActor.run {
                    downloadingModelID = nil
                    modelDownloadFractions[modelID] = nil
                    modelDownloadStatus[modelID] = error.localizedDescription
                }
            }
        }
    }

    private func showModelInFinder(_ modelID: VoiceASRModelID) {
        VoiceModelManager.showLocalASRModelInFinder(modelID)
    }

    private func deleteModel(_ modelID: VoiceASRModelID) {
        do {
            try VoiceModelManager.deleteLocalASRModel(modelID)
            let installed = VoiceModelManager.installedLocalASRModelIDs()
            if let fallback = VoiceModelManager.fallbackLocalASRModel(
                afterDeleting: modelID,
                selectedModelID: selectedASRModelID,
                installedModelIDsAfterDelete: installed
            ), fallback != selectedASRModelID {
                useModel(fallback)
                modelDownloadStatus[fallback] = "Selected because the previous model was deleted."
            }
            modelDownloadStatus[modelID] = "Deleted."
        } catch {
            modelDownloadStatus[modelID] = error.localizedDescription
        }
    }

    private func isDownloaded(_ modelID: VoiceASRModelID) -> Bool {
        VoiceModelManager.isLocalASRModelInstalled(modelID)
    }

    private func applyCleanupSettings() {
        do {
            try controller.applyVoiceCleanupSettings(cleanupSettingsDraft, apiKey: cleanupAPIKey)
            cleanupStatusMessage = "Cleanup settings saved."
            errorMessage = nil
        } catch {
            cleanupStatusMessage = error.localizedDescription
        }
    }

    private func testCleanupSettings() {
        cleanupStatusMessage = controller.validateVoiceCleanupSettings(
            cleanupSettingsDraft,
            apiKey: cleanupAPIKey
        )
    }

    private var canToggleVoice: Bool {
        switch controller.voiceCoordinator.state {
        case .idle, .recording:
            true
        case .transcribing, .pasting, .error:
            false
        }
    }

    private var shortcutIssue: HotkeyValidationIssue? {
        HotkeyValidation.issue(forVoiceShortcut: shortcut, appHotkeys: HotkeyMapStore.load())
    }

    private func shortcutCandidateIssue(_ descriptor: HotkeyDescriptor) -> HotkeyValidationIssue? {
        HotkeyValidation.issue(forVoiceShortcut: descriptor, appHotkeys: HotkeyMapStore.load())
    }

    private var voiceStateTitle: String {
        switch controller.voiceCoordinator.state {
        case .idle:
            "Ready for local dictation."
        case .recording:
            "Listening. Stop to transcribe and paste."
        case .transcribing:
            "Transcribing audio."
        case .pasting:
            "Pasting into the focused app."
        case let .error(message):
            message
        }
    }

    private var voiceStatusText: String {
        switch controller.voiceCoordinator.state {
        case .idle: "Ready"
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .pasting: "Pasting"
        case .error: "Error"
        }
    }

    private var voiceStatusKind: StatusPill.Kind {
        switch controller.voiceCoordinator.state {
        case .idle: .success
        case .recording, .transcribing, .pasting: .progress
        case .error: .warning
        }
    }

    private var recognitionModelSummary: String {
        switch asrProviderKind {
        case .local:
            selectedASRModelID.title
        case .groq, .elevenLabs, .openAITranscribe, .deepgram:
            cloudModelID.title
        }
    }

    private var cleanupModelSummary: String {
        guard cleanupEnabled else {
            return "AI cleanup is off; local cleanup and dictionary still apply."
        }
        let model = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? cleanupProvider.label : "\(cleanupProvider.label) · \(model)"
    }

    private var cleanupSettingsDraft: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: cleanupProvider,
            model: cleanupModel,
            baseURLString: cleanupBaseURLString,
            timeoutSeconds: cleanupTimeoutSeconds,
            latencyPolicy: cleanupLatencyPolicy
        )
    }

    private var currentAppliedASRSettings: VoiceASRSettings {
        VoiceASRSettings(
            modelID: selectedASRModelID,
            languageHint: languageHint,
            providerKind: VoiceASRSettingsStore.load().providerKind
        )
    }

    private var providerASRSettingsDraft: VoiceASRSettings {
        VoiceASRSettings(
            modelID: selectedASRModelID,
            languageHint: languageHint,
            providerKind: asrProviderKind
        )
    }

    private var cloudASRSettingsDraft: VoiceCloudASRSettings {
        VoiceCloudASRSettings(modelID: cloudModelID, languageHint: cloudLanguageHint)
    }

    private var cloudAPIKeyBinding: Binding<String> {
        Binding(
            get: { cloudAPIKeys[cloudSetupProviderKind] ?? "" },
            set: { cloudAPIKeys[cloudSetupProviderKind] = $0 }
        )
    }

    private func hasUsableCloudAPIKey(for providerKind: VoiceASRProviderKind) -> Bool {
        VoiceASRModelSelectionState.canSelectCloudModel(apiKey: cloudAPIKeys[providerKind] ?? "")
    }
}

private struct VoiceTranscriptHistoryRow: View {
    let transcript: VoiceTranscript
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayText)
                    .font(.callout)
                    .lineLimit(2)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy transcript")
                .opacity(isHovering || isSelected ? 1 : 0)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
                .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)

            VoiceTranscriptRowMenu(
                hasAudio: transcript.audioPath != nil,
                onRetry: onRetry,
                onDownload: onDownload,
                onDelete: onDelete
            )
            .opacity(isHovering || isSelected ? 1 : 0)
            .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
            .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(TapGesture(count: 2).onEnded { onCopy() })
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var displayText: String {
        MainVoiceTranscriptHistoryPresentation.displayText(transcript)
    }

    private var metadataLine: String {
        let time = CompactTimestamp.format(transcript.endedAt)
        let duration = formatDuration(ms: transcript.durationMs)
        return "\(time) · \(transcript.language.rawValue) · \(transcript.modelIdentifier) · \(duration)"
    }

    private func formatDuration(ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainder)s"
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private enum VoiceModelDownloadPresenter {
    static func describe(_ progress: DownloadUtils.DownloadProgress) -> String {
        switch progress.phase {
        case .listing:
            "Listing model files..."
        case let .downloading(completedFiles, totalFiles):
            "Downloading \(completedFiles)/\(totalFiles) files..."
        case let .compiling(modelName):
            "Compiling \(modelName)..."
        }
    }
}

private struct VoiceASRModelRow: View {
    let modelID: VoiceASRModelID
    let isSelected: Bool
    let isDownloaded: Bool
    let statusMessage: String?
    let downloadFraction: Double?
    let isDownloading: Bool
    let onSelect: () -> Void
    let onShowInFinder: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    VoiceASRModelTitleLine(modelID: modelID)
                    Text(modelID.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    if let statusText = presentation.statusText {
                        StatusPill(text: statusText, kind: presentation.statusKind.statusPillKind)
                    }
                    if let downloadFraction {
                        ProgressView(value: downloadFraction)
                            .frame(width: 170)
                    }
                    if let actionTitle = presentation.actionTitle {
                        MAYNButton(actionTitle) {
                            onSelect()
                        }
                    }
                    if isDownloaded, !isDownloading {
                        HStack(spacing: 6) {
                            MAYNButton("Show", height: 24, action: onShowInFinder)
                            MAYNButton("Delete", role: .destructive, height: 24, action: onDelete)
                        }
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
            }

            VoiceModelDetailLines(
                strengths: modelID.strengths,
                tradeoffs: modelID.tradeoffs
            )
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .contentShape(Rectangle())
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }

    private var presentation: VoiceASRModelRowPresentation {
        VoiceASRModelRowPresentation.model(
            isSelected: isSelected,
            isDownloaded: isDownloaded,
            isDownloading: isDownloading
        )
    }
}

private struct VoiceModelDetailLines: View {
    let strengths: String
    let tradeoffs: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(strengths, systemImage: "checkmark.circle")
            Label(tradeoffs, systemImage: "exclamationmark.circle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DownloadsMainPage: View {
    let controller: AppController
    @AppStorage("downloadConcurrency", store: AppGroupSettings.defaults) private var concurrency = 3
    @AppStorage("downloadOutputTemplate", store: AppGroupSettings.defaults) private var template = "%(title)s [%(id)s].%(ext)s"
    @AppStorage("downloadDirectory", store: AppGroupSettings.defaults) private var downloadDir = ""
    @AppStorage(DownloadsFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = DownloadsFunctionTab.queue.rawValue
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]
    @State private var showingAddURL = false
    @State private var addURL = ""
    @State private var detectedClipboardURL: String?

    private var selectedTab: Binding<DownloadsFunctionTab> {
        Binding {
            DownloadsFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Downloads",
            subtitle: "Queue media downloads, review results, and tune downloader behavior.",
            selection: selectedTab,
            toolbar: {
                HStack(spacing: 8) {
                    MainHeaderShortcutDisplay(
                        text: MainToolHeaderShortcutModel.display(
                            for: .downloads,
                            hotkeys: hotkeyMap,
                            voiceSettings: VoiceActivationSettingsStore.load()
                        ),
                        issueMessage: MainToolHeaderShortcutModel.issue(
                            for: .downloads,
                            hotkeys: hotkeyMap,
                            voiceSettings: VoiceActivationSettingsStore.load()
                        )
                    )
                    MAYNButton("Paste URL") {
                        enqueueClipboardURL()
                    }
                    MAYNButton("Add URL", role: .primary) {
                        presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL())
                    }
                }
            }
        ) {
            switch DownloadsFunctionTab.storedSelection(selectedTabRaw) {
            case .queue:
                FunctionPageScrollContent {
                    clipboardURLDetectedSection
                    downloadsQueueSection
                }
            case .completed:
                FunctionPageScrollContent {
                    downloadsCompletedSection
                }
            case .settings:
                FunctionPageScrollContent {
                    downloadsSettingsSection
                }
            }
        }
        .sheet(isPresented: $showingAddURL) {
            DownloadAddURLSheet(
                urlString: $addURL,
                onCancel: { showingAddURL = false },
                onDownload: submitAddURL
            )
        }
        .onChange(of: concurrency) { _, n in
            Task { await controller.downloader.queue.setMaxConcurrent(n) }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
            refreshDetectedClipboardURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDownloadRequested)) { _ in
            presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL())
        }
    }

    @ViewBuilder
    private var clipboardURLDetectedSection: some View {
        if let detectedClipboardURL {
            DownloadClipboardURLDetectedBanner(urlString: detectedClipboardURL) {
                enqueueURL(detectedClipboardURL)
            }
        }
    }

    private var downloadsQueueSection: some View {
        MAYNSection(title: "Queue") {
            DownloadsListView(
                vm: controller.downloaderVM,
                filter: .activeQueue,
                onPasteURL: enqueueClipboardURL,
                onAddURL: { presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL()) }
            )
                .frame(height: 420)
        }
    }

    private var downloadsCompletedSection: some View {
        MAYNSection(title: "Completed") {
            DownloadsListView(
                vm: controller.downloaderVM,
                filter: .completed,
                onPasteURL: enqueueClipboardURL,
                onAddURL: { presentAddURLSheet(prefill: DownloaderViewModel.clipboardVideoURL()) }
            )
                .frame(height: 420)
        }
    }

    private var downloadsSettingsSection: some View {
        DownloadsSettingsContent(
            concurrency: $concurrency,
            template: $template,
            downloadDir: $downloadDir
        )
    }

    private func presentAddURLSheet(prefill: String?) {
        addURL = prefill ?? ""
        showingAddURL = true
    }

    private func submitAddURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showingAddURL = false
        addURL = ""
        enqueueURL(trimmed)
    }

    private func enqueueClipboardURL() {
        Task {
            await controller.downloaderVM.enqueueClipboardURL()
            await MainActor.run {
                refreshDetectedClipboardURL()
            }
        }
    }

    private func enqueueURL(_ url: String) {
        Task {
            await controller.downloaderVM.add(url: url)
            await MainActor.run {
                refreshDetectedClipboardURL()
            }
        }
    }

    private func refreshDetectedClipboardURL() {
        detectedClipboardURL = DownloaderViewModel.clipboardVideoURL()
    }

    private func hotkeyBinding(for action: HotkeyAction) -> Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = action.primaryDefaultDescriptor ?? .defaultClipboard
                let descriptors = hotkeyMap[action] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { descriptor in
                setHotkey(descriptor, for: action)
            }
        )
    }

    private func setHotkey(_ descriptor: HotkeyDescriptor, for action: HotkeyAction) {
        var descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[action] = descriptors
        autoApplyHotkeys(next, changedAction: action)
    }

    private func hotkeyIssueMessage(for action: HotkeyAction) -> String? {
        let descriptors = hotkeyMap[action] ?? action.defaultDescriptors
        guard let descriptor = descriptors.first ?? action.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: action,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: action
        )
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [HotkeyDescriptor]], changedAction: HotkeyAction) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: changedAction
            )
        }
    }
}

private struct DownloadClipboardURLDetectedBanner: View {
    let urlString: String
    let onEnqueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.callout.weight(.semibold))
                .foregroundStyle(MAYNTheme.progress)
                .frame(width: MAYNControlMetrics.controlHeight, height: MAYNControlMetrics.controlHeight)
                .background(MAYNTheme.progress.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard URL detected")
                    .font(.callout.weight(.semibold))
                Text("\(urlString) is ready to enqueue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            MAYNButton("Enqueue", action: onEnqueue)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
    }
}

private struct FolderPreviewMainPage: View {
    let controller: AppController
    @AppStorage("folderPreviewIncludeHidden", store: AppGroupSettings.defaults) private var includeHidden = false
    @AppStorage(FolderPreviewSettings.cascadeKey, store: AppGroupSettings.defaults) private var cascade = FolderPreviewSettings.defaultCascadeEnabled
    @AppStorage("folderPreviewMaxEntries", store: AppGroupSettings.defaults) private var maxEntries = 50_000
    @AppStorage(FolderPreviewFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = FolderPreviewFunctionTab.settings.rawValue

    private var selectedTab: Binding<FolderPreviewFunctionTab> {
        Binding {
            FolderPreviewFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    var body: some View {
        FunctionPageShell(
            title: "Folder Preview",
            subtitle: "Configure the Finder Space preview for folders and archives.",
            selection: selectedTab,
            toolbar: {
                StatusPill(text: "Quick Look", kind: .neutral)
            }
        ) {
            FunctionPageScrollContent {
                folderSettingsSection
            }
        }
    }

    private var folderSettingsSection: some View {
        MAYNSection(title: FolderPreviewMainPagePresentation.settingsSectionTitle) {
            MAYNSettingsRow(
                title: "Include hidden files",
                subtitle: "Show dotfiles and hidden entries in folder previews."
            ) {
                Toggle("", isOn: $includeHidden)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Cascade folders",
                subtitle: "Include nested folder contents in previews. Turn off to show only top-level items."
            ) {
                Toggle("", isOn: $cascade)
                    .labelsHidden()
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Maximum entries",
                subtitle: "Upper bound for very large folders and archives."
            ) {
                MAYNNumericStepper(
                    text: "\(maxEntries)",
                    value: $maxEntries,
                    range: 1000...500_000,
                    step: 1000,
                    presets: [1_000, 10_000, 50_000, 100_000, 250_000, 500_000],
                    suffix: "entries",
                    fieldWidth: 78
                )
            }
        }
    }
}

private struct SnippetsMainPage: View {
    let controller: AppController
    @AppStorage(SnippetsFunctionTab.storageKey, store: AppGroupSettings.defaults) private var selectedTabRaw = SnippetsFunctionTab.library.rawValue
    @AppStorage(SnippetExpansionSettings.modeKey, store: AppGroupSettings.defaults) private var expansionModeRaw = SnippetExpansionSettings.defaultMode.rawValue
    @State private var hotkeyMap = HotkeyMapStore.defaultMap
    @State private var hotkeyRegistrationErrors: [HotkeyAction: String] = [:]

    private var selectedTab: Binding<SnippetsFunctionTab> {
        Binding {
            SnippetsFunctionTab.storedSelection(selectedTabRaw)
        } set: { tab in
            selectedTabRaw = tab.rawValue
        }
    }

    private var expansionMode: SnippetExpansionMode {
        SnippetExpansionMode(rawValue: expansionModeRaw) ?? SnippetExpansionSettings.defaultMode
    }

    var body: some View {
        FunctionPageShell(
            title: "Snippets",
            subtitle: "Reusable text entries and expansion triggers.",
            selection: selectedTab,
            toolbar: {
                MainHeaderShortcutDisplay(
                    text: MainToolHeaderShortcutModel.display(
                        for: .snippets,
                        hotkeys: hotkeyMap,
                        voiceSettings: VoiceActivationSettingsStore.load()
                    )
                )
            }
        ) {
            switch SnippetsFunctionTab.storedSelection(selectedTabRaw) {
            case .library:
                SnippetsListView(model: controller.clipboardDeps.dockModel)
            case .settings:
                FunctionPageScrollContent {
                    snippetsSettingsSection
                }
            }
        }
        .onAppear {
            hotkeyMap = HotkeyMapStore.load()
        }
    }

    private var snippetsSettingsSection: some View {
        MAYNSection(title: "Expansion") {
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.expansionModeRowTitle,
                subtitle: SnippetsSettingsPresentation.expansionModeSubtitle(for: expansionMode)
            ) {
                FunctionSegmentedTabStrip(
                    tabs: Array(SnippetExpansionMode.allCases),
                    selection: expansionMode,
                    fillsAvailableWidth: false,
                    size: .control
                ) { mode in
                    expansionModeRaw = mode.rawValue
                }
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.accessibilityRowTitle,
                subtitle: "Snippet expansion uses the main app Accessibility permission to type into the focused app."
            ) {
                StatusPill(
                    text: AXIsProcessTrusted() ? "Granted" : "Needed",
                    kind: AXIsProcessTrusted() ? .success : .warning
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: SnippetsSettingsPresentation.shortcutRowTitle,
                subtitle: "Use the Clipboard shortcut to open the dock, then switch to snippets."
            ) {
                HotkeyRecorderControl(
                    descriptor: hotkeyBinding,
                    issueMessage: hotkeyIssueMessage,
                    candidateIssueMessage: { hotkeyCandidateIssueMessage($0) },
                    defaultDescriptor: HotkeyAction.clipboard.primaryDefaultDescriptor,
                    recorderWidth: 112,
                    errorWidth: 260,
                    reset: {
                        if let descriptor = HotkeyAction.clipboard.primaryDefaultDescriptor {
                            setHotkey(descriptor)
                        }
                    }
                )
            }
        }
    }

    private var hotkeyBinding: Binding<HotkeyDescriptor> {
        Binding(
            get: {
                let defaultDescriptor = HotkeyAction.clipboard.primaryDefaultDescriptor ?? .defaultClipboard
                let descriptors = hotkeyMap[.clipboard] ?? [defaultDescriptor]
                return descriptors.first ?? defaultDescriptor
            },
            set: { descriptor in
                setHotkey(descriptor)
            }
        )
    }

    private var hotkeyIssueMessage: String? {
        let descriptors = hotkeyMap[.clipboard] ?? HotkeyAction.clipboard.defaultDescriptors
        guard let descriptor = descriptors.first ?? HotkeyAction.clipboard.primaryDefaultDescriptor else {
            return nil
        }
        let validationIssue = HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
        return HotkeyRecorderControlPresentation.rowIssueMessage(
            validationIssue: validationIssue,
            registrationErrors: hotkeyRegistrationErrors,
            action: .clipboard
        )
    }

    private func hotkeyCandidateIssueMessage(_ descriptor: HotkeyDescriptor) -> String? {
        HotkeyValidation.issue(
            forAppHotkey: descriptor,
            action: .clipboard,
            index: 0,
            appHotkeys: hotkeyMap,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        )?.message
    }

    private func setHotkey(_ descriptor: HotkeyDescriptor) {
        var descriptors = hotkeyMap[.clipboard] ?? HotkeyAction.clipboard.defaultDescriptors
        if descriptors.isEmpty {
            descriptors = [descriptor]
        } else {
            descriptors[0] = descriptor
        }
        var next = hotkeyMap
        next[.clipboard] = descriptors
        autoApplyHotkeys(next)
    }

    private func autoApplyHotkeys(_ next: [HotkeyAction: [HotkeyDescriptor]]) {
        hotkeyMap = next
        if HotkeyValidation.firstIssue(
            in: next,
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut
        ) != nil {
            hotkeyRegistrationErrors = [:]
            return
        }

        do {
            try controller.applyHotkeyMap(next)
            HotkeyMapStore.save(next)
            hotkeyRegistrationErrors = [:]
        } catch {
            hotkeyRegistrationErrors = HotkeyRecorderControlPresentation.registrationErrors(
                from: error,
                changedAction: .clipboard
            )
        }
    }
}

private struct MainPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 30)
        }
    }
}

private struct MainStatusRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let pill: StatusPill

    var body: some View {
        MAYNSettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 10) {
                pill
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }
        }
    }
}
