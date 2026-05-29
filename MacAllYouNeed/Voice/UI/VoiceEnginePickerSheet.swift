import SwiftUI

struct VoiceEnginePickerSheet<Detail: View>: View {
    @Binding var selectedEngineID: VoiceEngineID
    @Binding var filter: VoiceEnginePickerFilter
    @Binding var searchText: String
    let currentEngineID: VoiceEngineID
    let entries: [VoiceEngineListEntry]
    let onClose: () -> Void
    @ViewBuilder let detail: (VoiceEngineID) -> Detail

    private var twoPaneEntries: [VoiceTwoPanePickerEntry<VoiceEngineID, VoiceEngineGroup>] {
        VoiceEngineCatalogPresentation.twoPaneEntries(from: entries)
    }

    var body: some View {
        VoiceTwoPanePickerSheet(
            selection: $selectedEngineID,
            filter: $filter,
            searchText: $searchText,
            currentSelection: currentEngineID,
            entries: twoPaneEntries,
            groupOrder: [.local, .cloud, .experimental],
            groupTitle: { $0.title },
            matchesFilter: VoiceEngineCatalogPresentation.matchesFilter,
            headerTitle: "Choose recognition engine",
            headerSubtitle: "Advanced selection for exact local, cloud, and experimental recognizers.",
            searchPlaceholder: "Search engines",
            footerText: "Rows only identify engines. Status and actions live in the detail pane.",
            onClose: onClose,
            footerActions: {
                MAYNButton("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            },
            detail: detail
        )
    }
}
