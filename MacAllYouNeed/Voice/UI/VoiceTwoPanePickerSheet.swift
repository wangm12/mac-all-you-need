import SwiftUI

/// Shared list row for two-pane pickers (recognition engine, cleanup model, etc.).
struct VoiceTwoPanePickerRow: View {
    let icon: VoicePickerRowIcon
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                pickerIconView
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MAYNTheme.success)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected {
            return MAYNTheme.selected
        }
        if isHovering {
            return MAYNTheme.hover
        }
        return .clear
    }

    private var border: Color {
        if isSelected {
            return MAYNTheme.tabSelectedBorder
        }
        return MAYNTheme.subtleBorder.opacity(0.45)
    }

    @ViewBuilder
    private var pickerIconView: some View {
        switch icon {
        case let .brandAsset(name):
            Image(name)
                .resizable()
                .scaledToFit()
        case let .systemSymbol(name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// One selectable row in a grouped two-pane picker.
struct VoiceTwoPanePickerEntry<SelectionID: Hashable, Group: Hashable>: Identifiable, Hashable {
    let id: SelectionID
    let title: String
    let subtitle: String
    let icon: VoicePickerRowIcon
    let group: Group

    /// SF Symbol or asset catalog name (legacy); prefer `icon`.
    var iconSymbol: String {
        switch icon {
        case let .brandAsset(name):
            name
        case let .systemSymbol(name):
            name
        }
    }

    var searchableText: String {
        "\(title) \(subtitle)"
    }
}

/// Two-pane picker shell: search + segmented filter, grouped list, detail column.
struct VoiceTwoPanePickerSheet<
    SelectionID: Hashable,
    Group: Hashable,
    Filter: SegmentedTabDestination,
    FooterActions: View,
    Detail: View
>: View {
    @Binding var selection: SelectionID
    @Binding var filter: Filter
    @Binding var searchText: String
    /// Row matching this ID shows the green “current” checkmark when `showsCurrentRowIndicator` is true.
    let currentSelection: SelectionID
    /// When false, no row shows the checkmark (e.g. cleanup model saved but AI cleanup is off).
    var showsCurrentRowIndicator: Bool = true
    let entries: [VoiceTwoPanePickerEntry<SelectionID, Group>]
    let groupOrder: [Group]
    let groupTitle: (Group) -> String
    let filterTabs: [Filter]
    let matchesFilter: (VoiceTwoPanePickerEntry<SelectionID, Group>, Filter) -> Bool
    let headerTitle: String
    let headerSubtitle: String
    let searchPlaceholder: String
    let footerText: String
    let onClose: () -> Void
    @ViewBuilder let footerActions: () -> FooterActions
    @ViewBuilder let detail: (SelectionID) -> Detail

    init(
        selection: Binding<SelectionID>,
        filter: Binding<Filter>,
        searchText: Binding<String>,
        currentSelection: SelectionID,
        showsCurrentRowIndicator: Bool = true,
        entries: [VoiceTwoPanePickerEntry<SelectionID, Group>],
        groupOrder: [Group],
        groupTitle: @escaping (Group) -> String,
        filterTabs: [Filter] = Array(Filter.allCases),
        matchesFilter: @escaping (VoiceTwoPanePickerEntry<SelectionID, Group>, Filter) -> Bool,
        headerTitle: String,
        headerSubtitle: String,
        searchPlaceholder: String,
        footerText: String,
        onClose: @escaping () -> Void,
        @ViewBuilder footerActions: @escaping () -> FooterActions,
        @ViewBuilder detail: @escaping (SelectionID) -> Detail
    ) {
        _selection = selection
        _filter = filter
        _searchText = searchText
        self.currentSelection = currentSelection
        self.showsCurrentRowIndicator = showsCurrentRowIndicator
        self.entries = entries
        self.groupOrder = groupOrder
        self.groupTitle = groupTitle
        self.filterTabs = filterTabs
        self.matchesFilter = matchesFilter
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.searchPlaceholder = searchPlaceholder
        self.footerText = footerText
        self.onClose = onClose
        self.footerActions = footerActions
        self.detail = detail
    }

    private var filteredEntries: [VoiceTwoPanePickerEntry<SelectionID, Group>] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard matchesFilter(entry, filter) else { return false }
            guard !query.isEmpty else { return true }
            return entry.searchableText.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            bodyContent
            footer
        }
        .frame(width: 820, height: 660)
        .background(MAYNTheme.window)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            closeButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(MAYNTheme.elevated, in: Circle())
                .overlay(Circle().stroke(MAYNTheme.subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }

    private var bodyContent: some View {
        HStack(spacing: 0) {
            listPane
                .frame(width: 326)

            Rectangle()
                .fill(MAYNTheme.divider)
                .frame(width: 1)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            MAYNTextField(placeholder: searchPlaceholder, text: $searchText, width: 286)

            FunctionSegmentedTabStrip(
                tabs: filterTabs,
                selection: filter,
                fillsAvailableWidth: false,
                size: .control
            ) { newFilter in
                filter = newFilter
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupOrder, id: \.self) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    scheduleScrollToSelection(selection, proxy: proxy)
                }
                .onChange(of: selection) { _, newValue in
                    scheduleScrollToSelection(newValue, proxy: proxy)
                }
                .onChange(of: filter.rawValue) { _, _ in
                    scheduleScrollToSelection(selection, proxy: proxy)
                }
                .onChange(of: searchText) { _, _ in
                    scheduleScrollToSelection(selection, proxy: proxy)
                }
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MAYNTheme.panel)
    }

    private func scheduleScrollToSelection(_ id: SelectionID, proxy: ScrollViewProxy) {
        guard filteredEntries.contains(where: { $0.id == id }) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    @ViewBuilder
    private func groupSection(_ group: Group) -> some View {
        let rows = filteredEntries.filter { $0.group == group }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(groupTitle(group))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 4) {
                    ForEach(rows) { entry in
                        VoiceTwoPanePickerRow(
                            icon: entry.icon,
                            title: entry.title,
                            subtitle: entry.subtitle,
                            isSelected: selection == entry.id,
                            isCurrent: showsCurrentRowIndicator && currentSelection == entry.id,
                            onSelect: {
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    selection = entry.id
                                }
                            }
                        )
                        .id(entry.id)
                    }
                }
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            detail(selection)
                .id(selection)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MAYNTheme.panel)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MAYNDivider()
            HStack(alignment: .center, spacing: 12) {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                footerActions()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}
