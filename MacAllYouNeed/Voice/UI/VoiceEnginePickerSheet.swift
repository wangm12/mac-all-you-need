import SwiftUI

struct VoiceEnginePickerSheet<Detail: View>: View {
    @Binding var selectedEngineID: VoiceEngineID
    @Binding var filter: VoiceEnginePickerFilter
    @Binding var searchText: String
    let currentEngineID: VoiceEngineID
    let entries: [VoiceEngineListEntry]
    let onDone: () -> Void
    @ViewBuilder let detail: (VoiceEngineID) -> Detail

    private var filteredEntries: [VoiceEngineListEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard VoiceEngineCatalogPresentation.matchesFilter(entry, filter: filter) else {
                return false
            }
            guard !query.isEmpty else {
                return true
            }
            return entry.searchableText.lowercased().contains(query)
        }
    }

    private var localEntries: [VoiceEngineListEntry] {
        filteredEntries.filter { $0.group == .local }
    }

    private var cloudEntries: [VoiceEngineListEntry] {
        filteredEntries.filter { $0.group == .cloud }
    }

    private var experimentalEntries: [VoiceEngineListEntry] {
        filteredEntries.filter { $0.group == .experimental }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose recognition engine")
                    .font(.title3.weight(.semibold))
                Text("Advanced selection for exact local, cloud, and experimental recognizers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MAYNButton("Done", action: onDone)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            MAYNTextField(placeholder: "Search engines", text: $searchText, width: 286)

            FunctionSegmentedTabStrip(
                tabs: Array(VoiceEnginePickerFilter.allCases),
                selection: filter,
                fillsAvailableWidth: false,
                size: .control
            ) { newFilter in
                filter = newFilter
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    groupSection(.local, entries: localEntries)
                    groupSection(.cloud, entries: cloudEntries)
                    groupSection(.experimental, entries: experimentalEntries)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(MAYNTheme.panel)
    }

    @ViewBuilder
    private func groupSection(_ group: VoiceEngineGroup, entries: [VoiceEngineListEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        VoiceEnginePickerRow(
                            entry: entry,
                            isSelected: selectedEngineID == entry.id,
                            isCurrent: currentEngineID == entry.id,
                            onSelect: { selectedEngineID = entry.id }
                        )
                    }
                }
            }
        }
    }

    private var detailPane: some View {
        ScrollView {
            detail(selectedEngineID)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MAYNTheme.panel)
    }

    private var footer: some View {
        Text("Rows only identify engines. Status and actions live in the detail pane.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
    }
}

private struct VoiceEnginePickerRow: View {
    let entry: VoiceEngineListEntry
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.id.iconSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.subtitle)
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
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
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
}
