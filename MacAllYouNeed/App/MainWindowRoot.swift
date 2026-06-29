import AppKit
import Core
import FeatureCore
import Platform
import SwiftUI

struct MainWindowRoot: View {
    let controller: AppController
    @State private var selectedDestination: MainAppDestination = MainAppDestination.load(from: AppGroupSettings.defaults)
    @State private var pendingOrphans: [OrphanCacheScanner.Orphan] = []
    @State private var showWhatsNew = false
    @State private var whatsNewReport: MigrationReport?
    @State private var isSidebarCollapsed = false
    @State private var isCommandPalettePresented = false
    @State private var cachedAttention = CommandPaletteAttentionSnapshot(
        failedDownloadCount: 0,
        orphanCacheCount: 0,
        missingPermissions: [],
        permissionsAttentionTitle: nil,
        voiceSetupNeeded: false
    )
    @State private var cachedOrphanCount = 0
    @State private var titlebarTopInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: AppController) {
        self.controller = controller
    }

    private var selection: Binding<MainAppDestination> {
        Binding(
            get: { selectedDestination },
            set: { selectedDestination = $0 }
        )
    }

    var body: some View {
        mainWindowContent
            .animation(MAYNMotion.paletteMorphAnimation(reduceMotion: reduceMotion), value: isCommandPalettePresented)
        .background(MAYNTheme.window.ignoresSafeArea())
        .tint(MAYNTheme.controlTint)
        .accentColor(.gray)
        .maynDismissTextFocusOnOutsideClick()
        .background {
            CommandPaletteKeyboardMonitor(
                isPresented: $isCommandPalettePresented,
                reduceMotion: reduceMotion
            )
        }
        .onChange(of: selectedDestination) { _, destination in
            MainAppDestination.persist(destination, to: AppGroupSettings.defaults)
            applyDestinationTabDefaults(for: destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .globalSettingsOpenRequested)) { note in
            if DockSettingsNavigation.isClipboardRulesRoute(note.object as? String) {
                openClipboardRulesInMain()
                return
            }
            let destination = SettingsDestination.legacySelection(note.object as? String)
            openSettingsInMain(destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteOpenRequested)) { _ in
            setCommandPalettePresented(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .orphanCachesFound)) { note in
            guard let orphans = note.userInfo?["orphans"] as? [OrphanCacheScanner.Orphan] else { return }
            pendingOrphans = orphans
            cachedOrphanCount = orphans.count
            refreshShellAttentionCache()
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
            refreshShellAttentionCache()
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
                        selectedDestination = .settings
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
        }
    }

    private var mainWindowContent: some View {
        ZStack {
            NavigationSplitView {
                mainSidebar
                    .navigationSplitViewColumnWidth(
                        isSidebarCollapsed
                            ? MainSidebarMetrics.collapsedWidth
                            : MainSidebarMetrics.expandedWidth
                    )
            } detail: {
                MainWindowDetailView(
                    destination: selectedDestination,
                    controller: controller,
                    openDestination: openMainDestination
                )
                .equatable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MAYNTheme.window)
                .toolbar(removing: .sidebarToggle)
            }
            .toolbar(removing: .sidebarToggle)
            .toolbar { mainToolbarItems }
            .navigationSplitViewStyle(.balanced)

            if isCommandPalettePresented {
                CommandPaletteOverlay(
                    isPresented: $isCommandPalettePresented,
                    sections: CommandPaletteCatalog.sections(context: commandPaletteContext),
                    onSelect: handleCommandPaletteSelection
                )
                .transition(.opacity)
            }
        }
    }

    /// Lightweight attention refresh — never walks disk; orphan count comes from
    /// `AppController`'s background scan via `.orphanCachesFound`.
    private func refreshShellAttentionCache() {
        cachedAttention = CommandPaletteAttentionPlanner.snapshot(
            registry: controller.runtime.registry,
            stateFor: { controller.featureStatePublisher.state(for: $0) },
            failedDownloadCount: controller.downloaderVM.rows.filter { $0.state == .failed }.count,
            orphanCacheCount: cachedOrphanCount
        )
    }

    private func refreshOrphanCacheCountForPalette() {
        let registry = controller.runtime.registry
        Task.detached(priority: .utility) {
            let scanner = OrphanCacheScanner.makeForRegistry(registry)
            let count = OrphanCacheDismissal.unseen(scanner.scan()).count
            await MainActor.run {
                cachedOrphanCount = count
                refreshShellAttentionCache()
            }
        }
    }

    private var commandPaletteContext: CommandPaletteContext {
        let enabledDestinations = Set(
            MainAppDestination.primarySidebarDestinations.filter { !isFeatureDisabled(for: $0) }
                + [.settings]
        )
        return CommandPaletteContext(
            destination: selectedDestination,
            hotkeys: HotkeyMapStore.load(),
            voiceShortcut: VoiceActivationSettingsStore.load().shortcut.display,
            voiceMode: VoiceActivationSettingsStore.load().mode,
            failedDownloadCount: cachedAttention.failedDownloadCount,
            enabledDestinations: enabledDestinations,
            attention: cachedAttention,
            recentActionIDs: CommandPaletteRecentStore.load()
        )
    }

    private func setCommandPalettePresented(_ presented: Bool) {
        if presented {
            refreshShellAttentionCache()
            refreshOrphanCacheCountForPalette()
        }
        withAnimation(MAYNMotion.paletteMorphAnimation(reduceMotion: reduceMotion)) {
            isCommandPalettePresented = presented
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
        AppGroupSettings.defaults.set(ClipboardFunctionTab.settings.rawValue, forKey: ClipboardFunctionTab.storageKey)
        openMainDestination(.clipboard)
    }

    private func openMainDestination(_ destination: MainAppDestination) {
        selectedDestination = destination
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Tab defaults for destinations that share a detail view with another sidebar entry.
    private func applyDestinationTabDefaults(for destination: MainAppDestination) {
        switch destination {
        case .voiceReminders:
            AppGroupSettings.defaults.set(VoiceFunctionTab.settings.rawValue, forKey: VoiceFunctionTab.storageKey)
        case .finderHistory:
            AppGroupSettings.defaults.set(
                FolderPreviewFunctionTab.history.rawValue,
                forKey: FolderPreviewFunctionTab.storageKey
            )
        case .snippets:
            AppGroupSettings.defaults.set(
                SnippetsFunctionTab.library.rawValue,
                forKey: SnippetsFunctionTab.storageKey
            )
        default:
            break
        }
    }

    private func handleCommandPaletteSelection(_ action: CommandPaletteAction) {
        CommandPaletteRecentStore.record(action.id)
        guard isCommandPaletteActionAllowed(action) else { return }
        switch action.kind {
        case .openDestination(let destination):
            openMainDestination(destination)
        case .startDictation:
            NSApp.activate(ignoringOtherApps: true)
            Task { await controller.voiceCoordinator.startRecording() }
        case .openVoiceTab(let tab):
            AppGroupSettings.defaults.set(tab.rawValue, forKey: VoiceFunctionTab.storageKey)
            openMainDestination(.voice)
        case .toggleVoiceActivationMode:
            var activation = VoiceActivationSettingsStore.load()
            activation.mode = activation.mode == .hold ? .toggle : .hold
            try? controller.applyVoiceActivationSettings(activation)
        case .reviewFailedDownloads:
            openMainDestination(.downloads)
        case .openClipboardHistory:
            AppGroupSettings.defaults.set(ClipboardFunctionTab.history.rawValue, forKey: ClipboardFunctionTab.storageKey)
            openMainDestination(.clipboard)
        case .openClipboardDock:
            controller.clipboardDock.show()
        case .openClipboardSnippets:
            AppGroupSettings.defaults.set(SnippetsFunctionTab.library.rawValue, forKey: SnippetsFunctionTab.storageKey)
            openMainDestination(.snippets)
        case .openPermissionsSettings:
            openSettingsInMain(.permissions)
        case .reviewOrphanCaches:
            presentOrphanCachesSheetIfNeeded()
        case .completeVoiceSetup:
            if !PermissionGateProbe.isGranted(.microphone) || !PermissionGateProbe.isGranted(.accessibility) {
                controller.showFeatureOnboardingIfNeeded(for: .voice)
            }
            AppGroupSettings.defaults.set(VoiceFunctionTab.settings.rawValue, forKey: VoiceFunctionTab.storageKey)
            openMainDestination(.voice)
        case .openSettings(let destination):
            openSettingsInMain(destination)
        }
    }

    private func isCommandPaletteActionAllowed(_ action: CommandPaletteAction) -> Bool {
        switch action.kind {
        case .openDestination(let destination):
            return !isFeatureDisabled(for: destination)
        case .startDictation, .openVoiceTab, .toggleVoiceActivationMode, .completeVoiceSetup:
            return !isFeatureDisabled(for: .voice)
        case .openClipboardHistory, .openClipboardDock, .openClipboardSnippets:
            return !isFeatureDisabled(for: .clipboard)
        case .reviewFailedDownloads:
            return !isFeatureDisabled(for: .downloads)
        case .openPermissionsSettings, .reviewOrphanCaches, .openSettings:
            return true
        }
    }

    // MARK: Feature gating helpers

    private func isFeatureDisabled(for destination: MainAppDestination) -> Bool {
        !MainSidebarDestinationPresentation.isFeatureEnabled(for: destination) { id in
            controller.featureStatePublisher.state(for: id)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbarItems: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                CommandPaletteToolbarSearch(
                    isPalettePresented: isCommandPalettePresented,
                    onOpen: { setCommandPalettePresented(true) }
                )
            }
            .sharedBackgroundVisibility(isCommandPalettePresented ? .hidden : .automatic)
        } else {
            ToolbarItem(placement: .principal) {
                CommandPaletteToolbarSearch(
                    isPalettePresented: isCommandPalettePresented,
                    onOpen: { setCommandPalettePresented(true) }
                )
            }
        }
        if !isCommandPalettePresented {
            ToolbarItem(placement: .primaryAction) {
                MainAttentionBadge(
                    controller: controller,
                    attention: cachedAttention,
                    onTap: handleAttentionBadgeTap
                )
            }
        }
    }

    private func handleAttentionBadgeTap() {
        let attention = cachedAttention
        if attention.voiceSetupNeeded, !isFeatureDisabled(for: .voice) {
            handleCommandPaletteSelection(
                CommandPaletteAction(
                    id: "attention-voice-setup",
                    title: "Complete Voice setup",
                    symbolName: "mic",
                    section: .attention,
                    kind: .completeVoiceSetup
                )
            )
            return
        }
        if attention.permissionsAttentionTitle != nil {
            openSettingsInMain(.permissions)
            return
        }
        if attention.failedDownloadCount > 0, !isFeatureDisabled(for: .downloads) {
            openMainDestination(.downloads)
            return
        }
        if attention.orphanCacheCount > 0 {
            presentOrphanCachesSheetIfNeeded()
        }
    }

    private func presentOrphanCachesSheetIfNeeded() {
        guard pendingOrphans.isEmpty else { return }
        let registry = controller.runtime.registry
        Task.detached(priority: .utility) {
            let scanner = OrphanCacheScanner.makeForRegistry(registry)
            let orphans = OrphanCacheDismissal.unseen(scanner.scan())
            guard !orphans.isEmpty else { return }
            await MainActor.run {
                pendingOrphans = orphans
                cachedOrphanCount = orphans.count
                refreshShellAttentionCache()
            }
        }
    }

    private var activeDownloadCount: Int {
        MainSidebarBadgePresentation.inProgressDownloadCount(in: controller.downloaderVM.rows)
    }

    private var mainSidebar: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 6) {
            sidebarCollapseButton
                .padding(.horizontal, 4)
                .padding(.bottom, 2)

            ForEach(MainSidebarGroup.allCases) { group in
                Text(group.title)
                    .font(MAYNTypography.sidebarGroup())
                    .kerning(MAYNTypography.sidebarGroupTracking)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
                    .padding(.top, group == .core ? 0 : 8)
                    .opacity(isSidebarCollapsed ? 0 : 1)
                    .frame(height: isSidebarCollapsed ? 0 : nil)
                    .clipped()
                    .animation(
                        MAYNMotion.sidebarLabelAnimation(
                            collapsing: isSidebarCollapsed,
                            reduceMotion: reduceMotion
                        ),
                        value: isSidebarCollapsed
                    )
                ForEach(group.destinations) { destination in
                    let isDisabled = isFeatureDisabled(for: destination)
                    MainSidebarButton(
                        destination: destination,
                        isSelected: selectedDestination == destination,
                        isDisabled: isDisabled,
                        isCollapsed: isSidebarCollapsed,
                        badge: MainSidebarBadgePresentation.badgeText(
                            for: destination,
                            activeDownloadCount: activeDownloadCount
                        )
                    ) {
                        guard selectedDestination != destination else { return }
                        selectedDestination = destination
                    }
                }
            }

            Spacer(minLength: 0)

            Divider()
                .padding(.vertical, 6)

            MainSidebarSettingsButton(
                isCollapsed: isSidebarCollapsed,
                isSelected: selectedDestination == .settings
            ) {
                openSettingsInMain()
            }
        }
        .padding(.horizontal, isSidebarCollapsed ? 8 : 10)
        .padding(.top, MainSidebarMetrics.sidebarTopClearance(measuredTitlebarInset: titlebarTopInset))
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isSidebarCollapsed ? .top : .topLeading)
        .background {
            MainWindowTitlebarInsetReader(topInset: $titlebarTopInset)
        }
        .toolbar(removing: .sidebarToggle)
    }

    private var sidebarCollapseButton: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                withAnimation(MAYNMotion.sidebarWidthAnimation(reduceMotion: reduceMotion)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
            if isSidebarCollapsed { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
    }
}

enum MainSidebarMetrics {
    static let expandedWidth: CGFloat = MAYNControlMetrics.sidebarWidth
    static let collapsedWidth: CGFloat = 88
    /// Pre-window fallback only; once attached we use AppKit titlebar inset.
    static let sidebarTopPaddingFallback: CGFloat = 10
    /// The collapsed icon rail is 88pt wide so the toggle and traffic lights have
    /// comfortable clearance. The clearance floor guarantees the toggle (and every
    /// first item) always sits below the lights, while the ceiling keeps the gap
    /// tight. Both collapsed and expanded use the *same* value so the rail never
    /// shifts vertically when toggling.
    static let trafficLightClearanceFloor: CGFloat = 38
    static let trafficLightClearanceCeiling: CGFloat = 44
    static let collapsedHorizontalPadding: CGFloat = 8

    static func sidebarTopPadding(measuredTitlebarInset: CGFloat) -> CGFloat {
        measuredTitlebarInset > 0 ? measuredTitlebarInset : sidebarTopPaddingFallback
    }

    /// A single, deterministic top inset shared by both sidebar states. Clamped
    /// so it always clears the traffic lights yet never balloons if the measured
    /// titlebar inset over-reports.
    static func sidebarTopClearance(measuredTitlebarInset: CGFloat) -> CGFloat {
        let base = sidebarTopPadding(measuredTitlebarInset: measuredTitlebarInset)
        return min(max(base, trafficLightClearanceFloor), trafficLightClearanceCeiling)
    }

    /// Horizontal inset for the selected-row background when collapsed — centers a
    /// square matching `sidebarItemHeight` inside the padded rail content area.
    static func selectionHorizontalInset(isCollapsed: Bool) -> CGFloat {
        guard isCollapsed else { return 0 }
        let contentWidth = collapsedWidth - (collapsedHorizontalPadding * 2)
        return max(0, (contentWidth - MAYNControlMetrics.sidebarItemHeight) / 2)
    }
}

/// Reads the host `NSWindow` titlebar inset so sidebar content clears traffic lights once,
/// without stacking a second manual spacer on top of SwiftUI safe area.
private struct MainWindowTitlebarInsetReader: NSViewRepresentable {
    @Binding var topInset: CGFloat

    func makeNSView(context: Context) -> TitlebarInsetProbe {
        let probe = TitlebarInsetProbe()
        probe.onInsetChange = { topInset = $0 }
        return probe
    }

    func updateNSView(_ nsView: TitlebarInsetProbe, context: Context) {
        nsView.reportInset()
    }

    final class TitlebarInsetProbe: NSView {
        var onInsetChange: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportInset()
        }

        override func layout() {
            super.layout()
            reportInset()
        }

        func reportInset() {
            guard let window else { return }
            let measured = MainWindowTitlebarMetrics.topInset(for: window)
            guard measured > 0 else { return }
            onInsetChange?(measured)
        }
    }
}

enum MainWindowTitlebarMetrics {
    static func topInset(for window: NSWindow) -> CGFloat {
        if let contentView = window.contentView, contentView.safeAreaInsets.top > 0 {
            return contentView.safeAreaInsets.top
        }

        let layoutRect = window.contentLayoutRect
        let frameHeight = window.frame.height
        let titlebarHeight = frameHeight - layoutRect.maxY
        return max(titlebarHeight, 0)
    }
}

/// Stable detail column — avoids re-instantiating `AnyView` on every shell re-render
/// (downloader ticks, clipboard poll, feature-state refresh) which was tearing down
/// destination `.task` / async work and freezing or crashing on sidebar navigation.
private struct MainWindowDetailView: View, Equatable {
    let destination: MainAppDestination
    let controller: AppController
    let openDestination: (MainAppDestination) -> Void

    static func == (lhs: MainWindowDetailView, rhs: MainWindowDetailView) -> Bool {
        lhs.destination == rhs.destination
    }

    var body: some View {
        if let featureID = MainSidebarDestinationPresentation.featureID(for: destination),
           let factory = controller.runtime.registry.descriptor(for: featureID)?.mainPageViewFactory {
            factory()
        } else {
            routedDetail
        }
    }

    @ViewBuilder
    private var routedDetail: some View {
        switch destination {
        case .dashboard:
            DashboardDestinationView(controller: controller, openDestination: openDestination)
        case .clipboard:
            ClipboardDestinationView(controller: controller)
        case .voice, .voiceReminders:
            VoiceDestinationView(controller: controller)
                .id(destination)
        case .downloads:
            DownloadsDestinationView(controller: controller)
        case .aiFileOrganizer:
            AIFileOrganizerPage(controller: controller)
        case .folderPreview, .finderHistory:
            FolderPreviewDestinationView(controller: controller)
        case .snippets:
            SnippetsDestinationView(controller: controller)
        case .windowLayouts:
            WindowLayoutsDestinationView(controller: controller)
        case .grabAnywhere:
            WindowGrabDestinationView(controller: controller)
        case .windowHub:
            WindowHubPage(controller: controller)
        case .settings:
            SettingsDestinationView(controller: controller)
        }
    }
}

enum MainWindowRootPresentation {
    static let usesStableDetailViewRouting = true
    /// Sidebar selection uses opaque fills — not animated `glassEffect` (macOS 26 crash workaround).
    static let sidebarUsesOpaqueSelectionChrome = true
    static let observesFeatureStatePublisher = true
    static let disabledSidebarItemsAreNonClickable = true
    static let disabledSidebarItemsIgnoreHover = true
    static let sidebarCollapsesToIconRail = true
    /// Native `NavigationSplitView` sidebar toggles are removed; one in-sidebar control drives icon-rail collapse.
    static let removesNativeSidebarToggle = true
    static let ownsSidebarCollapseControlInSidebarColumn = true
    /// Main shell uses `NavigationSplitView` so sidebar/toolbar pick up system Liquid Glass.
    static let usesNavigationSplitView = true
    /// Global search + attention badge live on the split view, not only the detail column.
    static let usesWindowLevelToolbar = true
    /// Command palette search pill does not resize or hide its label when the sidebar collapses.
    static let commandPaletteSearchDecoupledFromSidebar = true
    /// Sidebar top padding follows AppKit titlebar inset instead of a fixed spacer band.
    static let usesAppKitTitlebarInsetForSidebar = true
}

/// Test contract: maps each `MainAppDestination` to the typename of the View
/// that `MainWindowRoot.detailView` instantiates for that destination. Locks
/// the routing table so the Phase 5a extraction can be verified.
enum MainWindowDestinationRouter {
    static func detailViewTypeName(for destination: MainAppDestination) -> String {
        switch destination {
        case .dashboard: String(describing: DashboardDestinationView.self)
        case .clipboard: String(describing: ClipboardDestinationView.self)
        case .voice: String(describing: VoiceDestinationView.self)
        case .voiceReminders: String(describing: VoiceDestinationView.self)
        case .downloads: String(describing: DownloadsDestinationView.self)
        case .aiFileOrganizer: String(describing: AIFileOrganizerPage.self)
        case .folderPreview: String(describing: FolderPreviewDestinationView.self)
        case .finderHistory: String(describing: FolderHistoryPageView.self)
        case .snippets: String(describing: SnippetsDestinationView.self)
        case .windowLayouts: String(describing: WindowLayoutsDestinationView.self)
        case .grabAnywhere: String(describing: WindowGrabDestinationView.self)
        case .windowHub: String(describing: WindowHubPage.self)
        case .settings: String(describing: SettingsDestinationView.self)
        }
    }
}

private struct MainSidebarButton: View {
    let destination: MainAppDestination
    let isSelected: Bool
    let isDisabled: Bool
    let isCollapsed: Bool
    let badge: String?
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                destinationIcon

                HStack(spacing: 9) {
                    Text(destination.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    trailingAccessory
                }
                .padding(.leading, isCollapsed ? 0 : 9)
                .frame(maxWidth: isCollapsed ? 0 : .infinity, alignment: .leading)
                .opacity(isCollapsed ? 0 : 1)
                .clipped()
                .animation(
                    MAYNMotion.sidebarLabelAnimation(
                        collapsing: isCollapsed,
                        reduceMotion: reduceMotion
                    ),
                    value: isCollapsed
                )
            }
            .foregroundStyle(
                MAYNSelectionLabelStyle.foreground(
                    isSelected: isSelected && !isDisabled,
                    isDisabled: isDisabled,
                    scheme: colorScheme
                )
            )
            .fontWeight(MAYNSelectionLabelStyle.weight(isSelected: isSelected && !isDisabled))
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .frame(height: MAYNControlMetrics.sidebarItemHeight)
            .maynSidebarSelectionBackground(
                isSelected: isSelected && !isDisabled,
                isHovering: isHovering && !isDisabled,
                cornerRadius: MAYNControlMetrics.sidebarItemRadius,
                horizontalInset: MainSidebarMetrics.selectionHorizontalInset(isCollapsed: isCollapsed)
            )
            .animation(
                MAYNMotion.sidebarSelectionMorphAnimation(reduceMotion: reduceMotion),
                value: isCollapsed
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(isDisabled)
        .help(destination.title)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isDisabled {
            Text("Setup")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay {
                    Capsule().strokeBorder(MAYNTheme.hairline, lineWidth: 1)
                }
        } else if let badge {
            Text(badge)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 18)
                .background(MAYNTheme.statusMutedFill, in: Capsule())
                .accessibilityLabel("\(badge) downloads in progress")
        }
    }

    private var destinationIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: destination.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 16, height: 16)
            if isDisabled {
                Image(systemName: "slash.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .offset(x: 5, y: -5)
            } else if isCollapsed, let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(MAYNTheme.statusMutedFill, in: Capsule())
                    .offset(x: 6, y: -6)
                    .accessibilityLabel("\(badge) downloads in progress")
            }
        }
    }

    private var accessibilityLabel: String {
        if let badge, !isCollapsed {
            return "\(destination.title), \(badge) downloads in progress"
        }
        return destination.title
    }
}

private struct MainSidebarSettingsButton: View {
    let isCollapsed: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, height: 16)

                Text("Settings")
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                    .padding(.leading, isCollapsed ? 0 : 9)
                    .frame(maxWidth: isCollapsed ? 0 : .infinity, alignment: .leading)
                    .opacity(isCollapsed ? 0 : 1)
                    .clipped()
                    .animation(
                        MAYNMotion.sidebarLabelAnimation(
                            collapsing: isCollapsed,
                            reduceMotion: reduceMotion
                        ),
                        value: isCollapsed
                    )
            }
            .foregroundStyle(
                MAYNSelectionLabelStyle.foreground(
                    isSelected: isSelected,
                    isDisabled: false,
                    scheme: colorScheme
                )
            )
            .fontWeight(MAYNSelectionLabelStyle.weight(isSelected: isSelected))
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 12)
            .frame(height: MAYNControlMetrics.sidebarItemHeight)
            .maynSidebarSelectionBackground(
                isSelected: isSelected,
                isHovering: isHovering,
                cornerRadius: MAYNControlMetrics.sidebarItemRadius,
                horizontalInset: MainSidebarMetrics.selectionHorizontalInset(isCollapsed: isCollapsed)
            )
            .animation(
                MAYNMotion.sidebarSelectionMorphAnimation(reduceMotion: reduceMotion),
                value: isCollapsed
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help("Settings")
        .onHover { isHovering = $0 }
    }
}

private struct MainAttentionBadge: View {
    let controller: AppController
    let attention: CommandPaletteAttentionSnapshot
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsPopover = false
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        switch controller.voiceCoordinator.state {
        case .recording:
            listeningPill
        default:
            if let badgeTitle = attention.badgeTitle {
                attentionPill(title: badgeTitle)
            }
        }
    }

    private var listeningPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(MAYNTheme.textPrimary(colorScheme))
                .frame(width: 6, height: 6)
            Text("Listening")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
        }
        .padding(.horizontal, 12)
        .frame(height: MAYNControlMetrics.attentionPillHeight)
        .maynGlassSurface(.panel, cornerRadius: MAYNControlMetrics.attentionPillHeight / 2, showsShadow: false)
        .overlay {
            Capsule().strokeBorder(MAYNTheme.attentionPillBorder(colorScheme), lineWidth: 1)
        }
        .accessibilityLabel("Voice listening")
    }

    private func attentionPill(title: String) -> some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                Circle()
                    .fill(MAYNTheme.textPrimary(colorScheme))
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                    .lineLimit(1)
                    .frame(maxWidth: 210, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: MAYNControlMetrics.attentionPillHeight)
        }
        .buttonStyle(.plain)
        .maynGlassSurface(.panel, cornerRadius: MAYNControlMetrics.attentionPillHeight / 2, showsShadow: false)
        .overlay {
            Capsule().strokeBorder(MAYNTheme.attentionPillBorder(colorScheme), lineWidth: 1)
        }
        .onHover(perform: handleAttentionHover)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            attentionPopover(title: title)
        }
        .help(title)
        .accessibilityLabel(title)
    }

    private func attentionPopover(title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
            Text(attentionPopoverDetail)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            MAYNButton("Review", role: .primary) {
                showsPopover = false
                onTap()
            }
        }
        .padding(14)
        .frame(width: 240)
        .maynGlassSurface(.panel, cornerRadius: MAYNControlMetrics.panelRadius, showsShadow: false)
        .overlay {
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .strokeBorder(MAYNTheme.hairline, lineWidth: 1)
        }
    }

    private var attentionPopoverDetail: String {
        if attention.failedDownloadCount > 0 {
            return "Open the queue to retry or remove failed items."
        }
        if attention.orphanCacheCount > 0 {
            return "Review leftover cache folders from disabled features."
        }
        if attention.voiceSetupNeeded {
            return "Finish microphone and Accessibility setup for Voice."
        }
        return "Open settings to grant the permissions Mayn needs."
    }

    private func handleAttentionHover(_ hovering: Bool) {
        hoverWorkItem?.cancel()
        if hovering {
            let work = DispatchWorkItem { showsPopover = true }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + MAYNMotionDuration.badgePopoverDelay, execute: work)
        } else {
            showsPopover = false
        }
    }
}

private struct CommandPaletteKeyboardMonitor: View {
    @Binding var isPresented: Bool
    let reduceMotion: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background(
                CommandPaletteKeyboardMonitorBridge(
                    isPresented: $isPresented,
                    reduceMotion: reduceMotion
                )
            )
    }
}

private struct CommandPaletteKeyboardMonitorBridge: NSViewRepresentable {
    @Binding var isPresented: Bool
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.isPresented = $isPresented
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.reduceMotion = reduceMotion
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isPresented: Binding<Bool>?
        var reduceMotion = false
        private weak var view: NSView?
        private var monitor: NSEventMonitorHandle?

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEventMonitorHandle(local: [.keyDown]) { [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                    guard let isPresented = self.isPresented else { return event }
                    let next = !isPresented.wrappedValue
                    if let animation = MAYNMotion.paletteMorphAnimation(reduceMotion: self.reduceMotion) {
                        withAnimation(animation) {
                            isPresented.wrappedValue = next
                        }
                    } else {
                        isPresented.wrappedValue = next
                    }
                    return nil
                }
                return event
            }
        }

        func detach() {
            monitor = nil
            view = nil
        }
    }
}

// MARK: - Shared helpers used by destination views

enum DashboardHeaderPresentation {
    static let trailingActionTitle: String? = nil
}

enum DashboardRenderingPresentation {
    static let usesStaticStartupSummary = false
    static let usesToolCards = true
    static let usesPlainRows = false
    static let toolCardHeight: CGFloat = 168
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
    let pagination: MAYNListPaginationState

    var currentPage: Int { pagination.currentPage }
    var totalPages: Int { pagination.totalPages }
    var totalItems: Int { pagination.totalItems }
    var pageSize: Int { pagination.pageSize }
    var canGoPrevious: Bool { pagination.canGoPrevious }
    var canGoNext: Bool { pagination.canGoNext }
    var rangeText: String { pagination.rangeText(visibleItemCount: visibleItems.count) }
}

enum MainClipboardHistoryPresentation {
    static func state(
        items: [ClipboardItemMeta],
        query: String,
        requestedPage: Int,
        pageSize requestedPageSize: Int
    ) -> MainClipboardHistoryPageState {
        let filteredItems = filter(items, query: query)
        let pagination = MAYNListPagination.make(
            totalItems: filteredItems.count,
            requestedPage: requestedPage,
            pageSize: requestedPageSize
        )
        let visibleItems = MAYNListPagination.slice(filteredItems, pagination: pagination)

        return MainClipboardHistoryPageState(
            filteredItems: filteredItems,
            visibleItems: visibleItems,
            pagination: pagination
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
        if !raw.isEmpty {
            return transcript.rawText
        }
        if transcript.failedStage == .cancelled {
            return "Cancelled"
        }
        if transcript.status == .failed {
            return "Failed: \(transcript.failureReason ?? "unknown")"
        }
        return "Empty transcript"
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
                    .saturation(0.75)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 0.5)
                    )
                    .accessibilityLabel("\(appIcons.displayName(for: bundleID)) source app")
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
            .accessibilityLabel("Clipboard item source indicator")
            .accessibilityHint("Indicates where this clipboard item came from")
    }
}

struct MainHeaderShortcutDisplay: View {
    let text: String?
    var issueMessage: String?

    var body: some View {
        if let text {
            HStack(spacing: 6) {
                MAYNHotkeyDisplay(text: text)
                if let issueMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MAYNTheme.strongBorder)
                        .accessibilityLabel(issueMessage)
                }
            }
            .accessibilityLabel("Current shortcut \(text)")
            .help(issueMessage ?? "Change this shortcut in Settings")
        }
    }
}

// MARK: - Dead-code helpers preserved from the pre-decomposition file.
// These types were defined in the previous monolithic MainWindowRoot.swift but
// were not referenced anywhere. They are preserved as-is so this Phase 5a
// refactor stays purely structural; remove them in a follow-up if confirmed
// unused.

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
        .scrollIndicators(.hidden)
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
