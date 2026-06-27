import AppKit
import Core
import Platform
import SwiftUI

// MARK: - Models

enum CommandPaletteSection: String, CaseIterable, Equatable {
    case navigation
    case currentContext
    case attention
    case recent
    case settings

    var title: String {
        switch self {
        case .navigation: "Navigation"
        case .currentContext: "Current Context"
        case .attention: "Attention"
        case .recent: "Recent"
        case .settings: "Settings"
        }
    }
}

enum CommandPaletteKind: Equatable {
    case openDestination(MainAppDestination)
    case startDictation
    case openVoiceTab(VoiceFunctionTab)
    case toggleVoiceActivationMode
    case reviewFailedDownloads
    case openClipboardHistory
    case openClipboardDock
    case openClipboardSnippets
    case openPermissionsSettings
    case reviewOrphanCaches
    case completeVoiceSetup
    case openSettings(SettingsDestination)
}

struct CommandPaletteAction: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
    let section: CommandPaletteSection
    let kind: CommandPaletteKind
    let shortcut: String?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        section: CommandPaletteSection,
        kind: CommandPaletteKind,
        shortcut: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.section = section
        self.kind = kind
        self.shortcut = shortcut
    }
}

struct CommandPaletteSectionModel: Identifiable, Equatable {
    var id: String { section.rawValue }
    let section: CommandPaletteSection
    let items: [CommandPaletteAction]
}

struct CommandPaletteContext: Equatable {
    let destination: MainAppDestination
    let hotkeys: [HotkeyAction: [Platform.HotkeyDescriptor]]
    let voiceShortcut: String
    let voiceMode: VoiceActivationMode
    let failedDownloadCount: Int
    let enabledDestinations: Set<MainAppDestination>
    let attention: CommandPaletteAttentionSnapshot
    let recentActionIDs: [String]

    func isDestinationEnabled(_ destination: MainAppDestination) -> Bool {
        enabledDestinations.contains(destination)
    }
}

enum CommandPaletteLayout {
    static let panelWidth: CGFloat = 680
    static let cornerRadius: CGFloat = 28
    static let shellPadding: CGFloat = 8
    static let topOffset: CGFloat = 112
    static let searchHeight: CGFloat = 58
    static let searchHorizontalPadding: CGFloat = 18
    static let rowHeight: CGFloat = 48
    static let rowRadius: CGFloat = 13
    static let rowInset: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let iconColumnWidth: CGFloat = 34
    static let listMaxHeight: CGFloat = 440
    static let panelMaxHeight: CGFloat = 560
}

// MARK: - Catalog

enum CommandPaletteCatalog {
    static func sections(context: CommandPaletteContext) -> [CommandPaletteSectionModel] {
        var result: [CommandPaletteSectionModel] = []

        let contextual = contextualItems(context: context).filter { isActionEnabled($0, context: context) }
        if !contextual.isEmpty {
            result.append(CommandPaletteSectionModel(section: .currentContext, items: contextual))
        }

        let attention = attentionItems(context: context).filter { isActionEnabled($0, context: context) }
        if !attention.isEmpty {
            result.append(CommandPaletteSectionModel(section: .attention, items: attention))
        }

        let navigation = navigationItems(context: context).filter { isActionEnabled($0, context: context) }
        let settings = settingsItems().filter { isActionEnabled($0, context: context) }
        let recentPool = contextual + attention + navigation + settings
        let recent = recentItems(from: recentPool, ids: context.recentActionIDs)
            .filter { isActionEnabled($0, context: context) }
        if !recent.isEmpty {
            result.append(CommandPaletteSectionModel(section: .recent, items: recent))
        }

        if !navigation.isEmpty {
            result.append(CommandPaletteSectionModel(section: .navigation, items: navigation))
        }

        if !settings.isEmpty {
            result.append(CommandPaletteSectionModel(section: .settings, items: settings))
        }

        return result
    }

    static func flatItems(from sections: [CommandPaletteSectionModel]) -> [CommandPaletteAction] {
        sections.flatMap(\.items)
    }

    static func filter(_ items: [CommandPaletteAction], query: String) -> [CommandPaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        let lower = trimmed.lowercased()
        return items.filter {
            $0.title.lowercased().contains(lower)
                || ($0.subtitle?.lowercased().contains(lower) ?? false)
                || $0.section.title.lowercased().contains(lower)
        }
    }

    static func filteredSections(
        _ sections: [CommandPaletteSectionModel],
        query: String
    ) -> (sections: [CommandPaletteSectionModel], isFiltering: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (sections, false) }

        let filtered = filter(flatItems(from: sections), query: query)
        guard !filtered.isEmpty else { return ([], true) }
        return ([CommandPaletteSectionModel(section: .navigation, items: filtered)], true)
    }

    private static func isActionEnabled(_ action: CommandPaletteAction, context: CommandPaletteContext) -> Bool {
        switch action.kind {
        case .openDestination(let destination):
            return context.isDestinationEnabled(destination)
        case .startDictation, .openVoiceTab, .toggleVoiceActivationMode:
            return context.isDestinationEnabled(.voice)
        case .openClipboardHistory, .openClipboardDock, .openClipboardSnippets:
            return context.isDestinationEnabled(.clipboard)
        case .reviewFailedDownloads:
            return context.isDestinationEnabled(.downloads)
        case .openPermissionsSettings:
            return true
        case .reviewOrphanCaches:
            return context.attention.orphanCacheCount > 0
        case .completeVoiceSetup:
            return context.isDestinationEnabled(.voice)
        case .openSettings:
            return true
        }
    }

    private static func recentItems(
        from pool: [CommandPaletteAction],
        ids: [String]
    ) -> [CommandPaletteAction] {
        let map = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

    private static func settingsItems() -> [CommandPaletteAction] {
        [
            CommandPaletteAction(
                id: "settings-general",
                title: "General",
                symbolName: "gearshape",
                section: .settings,
                kind: .openSettings(.general)
            ),
            CommandPaletteAction(
                id: "settings-permissions",
                title: "Permissions",
                symbolName: "checkmark.shield",
                section: .settings,
                kind: .openSettings(.permissions)
            ),
            CommandPaletteAction(
                id: "settings-hotkeys",
                title: "Hotkeys",
                symbolName: "keyboard",
                section: .settings,
                kind: .openSettings(.hotkeys)
            ),
        ]
    }

    private static func navigationItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        var items = MainAppDestination.primarySidebarDestinations.compactMap {
            navigationAction(for: $0, context: context)
        }
        return items
    }

    private static func navigationAction(
        for destination: MainAppDestination,
        context: CommandPaletteContext
    ) -> CommandPaletteAction? {
        let shortcut: String? = switch destination {
        case .clipboard:
            MainHotkeyPresentation.display(for: .clipboard, in: context.hotkeys)
        case .voice:
            context.voiceShortcut
        case .windowHub:
            MainHotkeyPresentation.display(for: .windowHub, in: context.hotkeys)
        default:
            nil
        }
        let symbolName = switch destination {
        case .clipboard: "clipboard"
        case .voice: "waveform"
        case .windowHub: "rectangle.3.group"
        default: destination.symbolName
        }
        return CommandPaletteAction(
            id: "nav-\(destination.rawValue)",
            title: navigationTitle(for: destination),
            symbolName: symbolName,
            section: .navigation,
            kind: .openDestination(destination),
            shortcut: shortcut
        )
    }

    private static func navigationTitle(for destination: MainAppDestination) -> String {
        switch destination {
        case .windowHub: "Windows Hub"
        default: destination.title
        }
    }

    private static func contextualItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        switch context.destination {
        case .clipboard:
            return clipboardContextItems(context: context)
        case .voice:
            return voiceContextItems(context: context)
        default:
            return defaultContextItems(context: context)
        }
    }

    private static func clipboardContextItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        [
            CommandPaletteAction(
                id: "ctx-clipboard-search",
                title: "Search clipboard history",
                symbolName: "magnifyingglass",
                section: .currentContext,
                kind: .openClipboardDock,
                shortcut: MainHotkeyPresentation.display(for: .clipboard, in: context.hotkeys)
            ),
            CommandPaletteAction(
                id: "ctx-clipboard-history",
                title: "Open clipboard history",
                symbolName: "clock",
                section: .currentContext,
                kind: .openClipboardHistory
            ),
            CommandPaletteAction(
                id: "ctx-clipboard-snippets",
                title: "Open snippet library",
                symbolName: "text.quote",
                section: .currentContext,
                kind: .openClipboardSnippets
            ),
        ]
    }

    private static func voiceContextItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        [
            CommandPaletteAction(
                id: "ctx-start-dictation",
                title: "Start dictation",
                symbolName: "mic",
                section: .currentContext,
                kind: .startDictation,
                shortcut: context.voiceShortcut
            ),
            CommandPaletteAction(
                id: "ctx-transcript-history",
                title: "Open transcript history",
                symbolName: "clock",
                section: .currentContext,
                kind: .openVoiceTab(.history)
            ),
            CommandPaletteAction(
                id: "ctx-change-shortcut",
                title: "Change voice shortcut",
                symbolName: "keyboard",
                section: .currentContext,
                kind: .openVoiceTab(.settings)
            ),
            CommandPaletteAction(
                id: "ctx-toggle-mode",
                title: "Toggle hold-to-talk",
                subtitle: context.voiceMode == .hold ? "Hold to talk" : "Toggle mode",
                symbolName: context.voiceMode.symbolName,
                section: .currentContext,
                kind: .toggleVoiceActivationMode
            ),
            CommandPaletteAction(
                id: "ctx-voice-settings",
                title: "Open Voice settings",
                symbolName: "slider.horizontal.3",
                section: .currentContext,
                kind: .openVoiceTab(.settings)
            ),
        ]
    }

    private static func defaultContextItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        [
            CommandPaletteAction(
                id: "ctx-start-dictation",
                title: "Start dictation",
                symbolName: "mic",
                section: .currentContext,
                kind: .startDictation,
                shortcut: context.voiceShortcut
            ),
            CommandPaletteAction(
                id: "ctx-clipboard-dock",
                title: "Open clipboard dock",
                symbolName: "clipboard",
                section: .currentContext,
                kind: .openClipboardDock,
                shortcut: MainHotkeyPresentation.display(for: .clipboard, in: context.hotkeys)
            ),
        ]
    }

    private static func attentionItems(context: CommandPaletteContext) -> [CommandPaletteAction] {
        var items: [CommandPaletteAction] = []
        let snapshot = context.attention

        if snapshot.voiceSetupNeeded, context.isDestinationEnabled(.voice) {
            items.append(
                CommandPaletteAction(
                    id: "attention-voice-setup",
                    title: "Complete Voice setup",
                    subtitle: "Microphone or Accessibility required",
                    symbolName: "mic",
                    section: .attention,
                    kind: .completeVoiceSetup
                )
            )
        }

        if let permissionsTitle = snapshot.permissionsAttentionTitle {
            items.append(
                CommandPaletteAction(
                    id: "attention-permissions",
                    title: permissionsTitle,
                    symbolName: "lock.shield",
                    section: .attention,
                    kind: .openPermissionsSettings
                )
            )
        }

        if snapshot.failedDownloadCount > 0, context.isDestinationEnabled(.downloads) {
            items.append(
                CommandPaletteAction(
                    id: "attention-downloads",
                    title: "Review \(snapshot.failedDownloadCount) downloads",
                    symbolName: "arrow.down.circle",
                    section: .attention,
                    kind: .reviewFailedDownloads
                )
            )
        }

        if snapshot.orphanCacheCount > 0 {
            items.append(
                CommandPaletteAction(
                    id: "attention-orphans",
                    title: "Review \(snapshot.orphanCacheCount) orphan caches",
                    symbolName: "externaldrive",
                    section: .attention,
                    kind: .reviewOrphanCaches
                )
            )
        }

        return items
    }
}

// MARK: - Overlay

struct CommandPaletteOverlay: View {
    @Binding var isPresented: Bool
    let sections: [CommandPaletteSectionModel]
    let onSelect: (CommandPaletteAction) -> Void

    @State private var query = ""
    @State private var selectedActionID: String?
    @State private var isClosing = false
    @State private var closeWorkItem: DispatchWorkItem?
    @State private var rowsRevealed = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: (sections: [CommandPaletteSectionModel], isFiltering: Bool) {
        CommandPaletteCatalog.filteredSections(sections, query: query)
    }

    private var visibleItems: [CommandPaletteAction] {
        CommandPaletteCatalog.flatItems(from: presentation.sections)
    }

    /// Flat index → ⌘1…⌘9 quick-execute label for the first nine visible rows.
    private func quickShortcut(forFlatIndex index: Int) -> String? {
        guard index < 9 else { return nil }
        return "⌘\(index + 1)"
    }

    private func flatIndex(for actionID: String) -> Int? {
        visibleItems.firstIndex { $0.id == actionID }
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(CommandPaletteLayout.panelWidth, geo.size.width - 160)

            ZStack(alignment: .top) {
                MAYNTheme.commandPaletteBackdrop(colorScheme)
                    .ignoresSafeArea()
                    .opacity(isPresented ? 1 : 0)
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    MAYNCommandPaletteShell {
                        VStack(spacing: 0) {
                            searchHeader
                            paletteDivider
                            resultsBody
                        }
                    }
                    .frame(width: panelWidth)
                    .frame(maxHeight: CommandPaletteLayout.panelMaxHeight)
                    .fixedSize(horizontal: true, vertical: true)
                    .scaleEffect(paletteScale, anchor: .top)
                    .opacity(isPresented ? 1 : 0)
                    .offset(y: isPresented || reduceMotion ? 0 : -8)

                    Spacer(minLength: 0)
                }
                .padding(.top, CommandPaletteLayout.topOffset)
            }
        }
        .onAppear {
            syncSelection()
            if isPresented {
                focusSearchField()
                revealRows()
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                syncSelection()
                focusSearchField()
                revealRows()
            } else {
                rowsRevealed = false
            }
        }
        .onChange(of: query) {
            syncSelection()
        }
        .onExitCommand { dismiss() }
        .onDisappear {
            closeWorkItem?.cancel()
            closeWorkItem = nil
        }
        .background {
            CommandPaletteKeyCapture(
                isActive: isPresented,
                onMove: moveSelection,
                onActivate: activateSelected,
                onQuickSelect: activateQuickSelect,
                onDismiss: { dismiss() }
            )
        }
    }

    private var paletteScale: CGFloat {
        if reduceMotion || isPresented { return 1 }
        return isClosing ? 0.985 : 0.975
    }

    private func revealRows() {
        guard !reduceMotion else {
            rowsRevealed = true
            return
        }
        rowsRevealed = false
        DispatchQueue.main.async {
            withAnimation(MAYNMotion.paletteMorphAnimation(reduceMotion: false)) {
                rowsRevealed = true
            }
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private var searchHeader: some View {
        HStack(spacing: MAYNSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
                .accessibilityHidden(true)

            TextField("Search Mayn", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                .focused($isSearchFocused)

            CommandPaletteKeycap(text: "esc", isInverted: false)
                .accessibilityLabel("Escape to close")
                .onTapGesture { dismiss() }
        }
        .padding(.horizontal, CommandPaletteLayout.searchHorizontalPadding)
        .frame(height: CommandPaletteLayout.searchHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Command palette search")
        .accessibilityHint("Type to filter actions. Press Escape to close.")
    }

    @ViewBuilder
    private var resultsBody: some View {
        if visibleItems.isEmpty {
            Text("No matching actions")
                .font(MAYNTypography.caption())
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: CommandPaletteLayout.rowHeight, alignment: .leading)
                .padding(.horizontal, CommandPaletteLayout.rowHorizontalPadding)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(presentation.sections) { sectionModel in
                            if !presentation.isFiltering {
                                CommandPaletteSectionHeader(title: sectionModel.section.title)
                            }
                            ForEach(Array(sectionModel.items.enumerated()), id: \.element.id) { itemIndex, action in
                                let revealIndex = flatIndex(for: action.id) ?? itemIndex
                                CommandPaletteRow(
                                    action: action,
                                    isSelected: selectedActionID == action.id,
                                    quickShortcut: flatIndex(for: action.id).flatMap { quickShortcut(forFlatIndex: $0) },
                                    rowRevealIndex: revealIndex,
                                    rowsRevealed: rowsRevealed
                                ) {
                                    select(action)
                                }
                                .id(action.id)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: CommandPaletteLayout.listMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: selectedActionID) {
                    guard let actionID = selectedActionID else { return }
                    withAnimation(MAYNMotion.animation(.hover, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(actionID, anchor: .center)
                    }
                }
            }
        }
    }

    private var paletteDivider: some View {
        Rectangle()
            .fill(MAYNTheme.commandPaletteDivider)
            .frame(height: 1)
    }

    private func syncSelection() {
        let items = visibleItems
        guard !items.isEmpty else {
            selectedActionID = nil
            return
        }
        if let selectedActionID, items.contains(where: { $0.id == selectedActionID }) {
            return
        }
        selectedActionID = items.first?.id
    }

    private func moveSelection(_ delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedActionID,
              let index = items.firstIndex(where: { $0.id == currentID })
        else {
            selectedActionID = items.first?.id
            return
        }
        let nextIndex = min(max(index + delta, 0), items.count - 1)
        selectedActionID = items[nextIndex].id
    }

    private func activateSelected() {
        guard let selectedActionID,
              let action = visibleItems.first(where: { $0.id == selectedActionID })
        else { return }
        select(action)
    }

    private func activateQuickSelect(_ index: Int) {
        let items = visibleItems
        guard items.indices.contains(index) else { return }
        select(items[index])
    }

    private func select(_ action: CommandPaletteAction) {
        onSelect(action)
        dismiss(animated: false)
    }

    private func dismiss(animated: Bool = true) {
        guard !isClosing else { return }
        isClosing = true
        closeWorkItem?.cancel()

        let close = {
            isPresented = false
            query = ""
            selectedActionID = nil
            isClosing = false
            closeWorkItem = nil
        }

        guard animated, isPresented, !reduceMotion else {
            close()
            return
        }

        withAnimation(MAYNMotion.paletteCloseAnimation(reduceMotion: reduceMotion)) {
            isPresented = false
        }
        let work = DispatchWorkItem {
            if !isPresented {
                query = ""
                selectedActionID = nil
            }
            isClosing = false
            closeWorkItem = nil
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MAYNMotionDuration.paletteClose, execute: work)
    }
}

// MARK: - Rows & chrome

private struct CommandPaletteSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.48)
            .foregroundStyle(MAYNTheme.commandPaletteSectionTitle)
            .padding(.horizontal, CommandPaletteLayout.searchHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommandPaletteRow: View {
    let action: CommandPaletteAction
    let isSelected: Bool
    var quickShortcut: String?
    let rowRevealIndex: Int
    let rowsRevealed: Bool
    let onSelect: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var rowRevealAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return MAYNMotion.controlAnimation(reduceMotion: false)?
            .delay(MAYNMotion.paletteRowStaggerDelay(for: rowRevealIndex))
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: MAYNSpacing.sm) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        MAYNSelectionLabelStyle.foreground(
                            isSelected: isSelected,
                            scheme: colorScheme
                        )
                    )
                    .frame(width: CommandPaletteLayout.iconColumnWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 14.5, weight: MAYNSelectionLabelStyle.weight(isSelected: isSelected)))
                        .foregroundStyle(
                            MAYNSelectionLabelStyle.foreground(
                                isSelected: isSelected,
                                scheme: colorScheme
                            )
                        )
                        .lineLimit(1)

                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(
                                MAYNSelectionLabelStyle.subtitle(
                                    isSelected: isSelected,
                                    scheme: colorScheme
                                )
                            )
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let shortcut = action.shortcut ?? quickShortcut {
                    CommandPaletteKeycap(text: shortcut)
                }
            }
            .padding(.horizontal, CommandPaletteLayout.rowHorizontalPadding)
            .frame(height: CommandPaletteLayout.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .maynSelectionBackground(
                isSelected: isSelected,
                isHovering: isHovering,
                shape: .rounded(CommandPaletteLayout.rowRadius)
            )
            .contentShape(RoundedRectangle(cornerRadius: CommandPaletteLayout.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CommandPaletteLayout.rowInset)
        .opacity(rowsRevealed || reduceMotion ? 1 : 0)
        .offset(y: rowsRevealed || reduceMotion ? 0 : 3)
        .animation(rowRevealAnimation, value: rowsRevealed)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(MAYNMotion.paletteSelectionAnimation(reduceMotion: reduceMotion), value: isSelected)
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }
}

private struct CommandPaletteKeycap: View {
    let text: String
    var isInverted: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: 28)
            .frame(height: MAYNControlMetrics.keycapHeight)
            .background(keycapBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.keycapRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.keycapRadius, style: .continuous)
                    .strokeBorder(keycapBorder, lineWidth: 1)
            }
            .foregroundStyle(keycapForeground)
    }

    private var keycapBackground: Color {
        isInverted
            ? MAYNTheme.selectionInversionKeycapBackground(colorScheme)
            : Color.primary.opacity(colorScheme == .dark ? 0.065 : 0.045)
    }

    private var keycapBorder: Color {
        isInverted
            ? MAYNTheme.selectionInversionKeycapBorder(colorScheme)
            : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
    }

    private var keycapForeground: Color {
        isInverted
            ? MAYNTheme.selectionInversionKeycapForeground(colorScheme)
            : Color.primary.opacity(colorScheme == .dark ? 0.74 : 0.58)
    }
}

// MARK: - Keyboard

private struct CommandPaletteKeyCapture: NSViewRepresentable {
    let isActive: Bool
    let onMove: (Int) -> Void
    let onActivate: () -> Void
    let onQuickSelect: (Int) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onMove = onMove
        context.coordinator.onActivate = onActivate
        context.coordinator.onQuickSelect = onQuickSelect
        context.coordinator.onDismiss = onDismiss
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isActive = false
        var onMove: ((Int) -> Void)?
        var onActivate: (() -> Void)?
        var onQuickSelect: ((Int) -> Void)?
        var onDismiss: (() -> Void)?
        private weak var view: NSView?
        private var monitor: NSEventMonitorHandle?

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEventMonitorHandle(local: [.keyDown]) { [weak self] event in
                guard let self, isActive else { return event }
                switch event.keyCode {
                case 53:
                    onDismiss?()
                    return nil
                case 126:
                    onMove?(-1)
                    return nil
                case 125:
                    onMove?(1)
                    return nil
                case 36, 76:
                    onActivate?()
                    return nil
                default:
                    if event.modifierFlags.contains(.command),
                       let chars = event.charactersIgnoringModifiers,
                       let digit = Int(chars),
                       (1 ... 9).contains(digit) {
                        onQuickSelect?(digit - 1)
                        return nil
                    }
                    return event
                }
            }
        }

        func detach() {
            monitor = nil
            view = nil
        }
    }
}

private enum CommandPaletteSearchMetrics {
    static let chromeCornerRadius: CGFloat = 11
    static let toolbarWidth: CGFloat = 380
}

struct CommandPaletteToolbarSearch: View {
    let isSidebarCollapsed: Bool
    let isPalettePresented: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            searchContent
                .opacity(isPalettePresented ? 0 : 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: CommandPaletteSearchMetrics.toolbarWidth)
        .frame(height: MAYNControlMetrics.searchFieldHeight)
        .background {
            if !isPalettePresented {
                Color.clear
                    .maynGlassSurface(
                        .panel,
                        cornerRadius: CommandPaletteSearchMetrics.chromeCornerRadius,
                        showsShadow: false
                    )
            }
        }
        .allowsHitTesting(!isPalettePresented)
        .accessibilityHidden(isPalettePresented)
        .accessibilityLabel("Open command palette")
        .accessibilityHint("Opens the command palette. Type in the palette search field, not here.")
        .help("Open command palette (⌘K)")
    }

    private var searchContent: some View {
        HStack(spacing: MAYNSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
            if !isSidebarCollapsed {
                Text("Search Mayn")
                    .font(MAYNTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            MAYNKeycap(text: "⌘K")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        .padding(.horizontal, MAYNSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MAYNControlMetrics.searchFieldHeight)
    }
}
