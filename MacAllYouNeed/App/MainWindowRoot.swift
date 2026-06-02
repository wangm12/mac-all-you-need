import AppKit
import Core
import FeatureCore
import Platform
import SwiftUI

struct MainWindowRoot: View {
    let controller: AppController
    private var statePublisher: FeatureStatePublisher
    @AppStorage(MainAppDestination.storageKey, store: AppGroupSettings.defaults)
    private var selectedRaw = MainAppDestination.dashboard.rawValue
    @State private var pendingOrphans: [OrphanCacheScanner.Orphan] = []
    @State private var showWhatsNew = false
    @State private var whatsNewReport: MigrationReport?
    @State private var isSidebarCollapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HStack(spacing: 0) {
            mainSidebar
                .frame(width: isSidebarCollapsed ? MainSidebarMetrics.collapsedWidth : MainSidebarMetrics.expandedWidth)
                .background(MAYNTheme.panel)

            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MAYNTheme.window)
        }
        .animation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion), value: isSidebarCollapsed)
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
            AnyView(DashboardDestinationView(
                controller: controller,
                openDestination: openMainDestination
            ))
        case .clipboard:
            AnyView(ClipboardDestinationView(controller: controller))
        case .voice:
            AnyView(VoiceDestinationView(controller: controller))
        case .voiceReminders:
            AnyView(VoiceRemindersPage(controller: controller))
        case .downloads:
            AnyView(DownloadsDestinationView(controller: controller))
        case .aiFileOrganizer:
            AnyView(AIFileOrganizerPage(controller: controller))
        case .folderPreview:
            AnyView(FolderPreviewDestinationView(controller: controller))
        case .finderHistory:
            AnyView(FinderFolderHistoryPage(controller: controller))
        case .snippets:
            AnyView(SnippetsDestinationView(controller: controller))
        case .windowLayouts:
            AnyView(WindowLayoutsDestinationView(controller: controller))
        case .grabAnywhere:
            AnyView(WindowGrabDestinationView(controller: controller))
        case .dockPreviews:
            AnyView(DockHoverPreviewsPage(controller: controller))
        case .settings:
            AnyView(SettingsDestinationView(controller: controller))
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

    private var mainSidebar: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: 6) {
            HStack {
                if !isSidebarCollapsed {
                    Spacer(minLength: 0)
                }
                Button {
                    withAnimation(MAYNMotion.panelAnimation(reduceMotion: reduceMotion)) {
                        isSidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
            }
            .frame(height: 34)
            .frame(maxWidth: .infinity)

            ForEach(MainSidebarDestinationPresentation.renderedDestinations()) { destination in
                let isDisabled = isFeatureDisabled(for: destination)
                MainSidebarButton(
                    destination: destination,
                    isSelected: selection.wrappedValue == destination,
                    isDisabled: isDisabled,
                    isCollapsed: isSidebarCollapsed,
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

            MainSidebarSettingsButton(
                isCollapsed: isSidebarCollapsed,
                isSelected: MainAppDestination.storedSelection(selectedRaw) == .settings
            ) {
                openSettingsInMain()
            }
        }
        .padding(.horizontal, isSidebarCollapsed ? 8 : 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum MainSidebarMetrics {
    static let expandedWidth: CGFloat = 220
    static let collapsedWidth: CGFloat = 56
}

enum MainWindowRootPresentation {
    static let usesTypeErasedDetailViews = true
    static let observesFeatureStatePublisher = true
    static let disabledSidebarItemsAreNonClickable = true
    static let disabledSidebarItemsIgnoreHover = true
    static let sidebarCollapsesToIconRail = true
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
        case .voiceReminders: String(describing: VoiceRemindersPage.self)
        case .downloads: String(describing: DownloadsDestinationView.self)
        case .aiFileOrganizer: String(describing: AIFileOrganizerPage.self)
        case .folderPreview: String(describing: FolderPreviewDestinationView.self)
        case .finderHistory: String(describing: FinderFolderHistoryPage.self)
        case .snippets: String(describing: SnippetsDestinationView.self)
        case .windowLayouts: String(describing: WindowLayoutsDestinationView.self)
        case .grabAnywhere: String(describing: WindowGrabDestinationView.self)
        case .dockPreviews: String(describing: DockHoverPreviewsPage.self)
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

    var body: some View {
        Button(action: action) {
            Group {
                if isCollapsed {
                    collapsedLabel
                } else {
                    expandedLabel
                }
            }
            .foregroundStyle(isSelected && !isDisabled ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(destination.title)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private var expandedLabel: some View {
        HStack(spacing: 9) {
            destinationIcon
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedLabel: some View {
        destinationIcon
            .frame(maxWidth: .infinity)
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(MAYNTheme.progress, in: Capsule())
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

    private var rowBackground: Color {
        if isDisabled { return .clear }
        if isSelected && !isDisabled { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

private struct MainSidebarSettingsButton: View {
    let isCollapsed: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isCollapsed {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 16, height: 16)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Settings", systemImage: "gearshape")
                        .font(.callout)
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 10)
            .padding(.vertical, 7)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Settings")
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.14) }
        if isHovering { return MAYNTheme.hover }
        return .clear
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
    static let toolCardHeight: CGFloat = 170
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
                        .foregroundStyle(MAYNTheme.warning)
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
