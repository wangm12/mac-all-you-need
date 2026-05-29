import SwiftUI

/// Thin adapter over `VoiceTwoPanePickerSheet` for cleanup model selection.
struct VoiceCleanupPickerSheet<Detail: View>: View {
    @Binding var selectedProvider: VoiceCleanupProviderKind
    @Binding var filter: VoiceCleanupPickerFilter
    @Binding var searchText: String
    let currentProvider: VoiceCleanupProviderKind
    /// When AI cleanup is off, hide the list checkmark so a row does not look “in use.”
    let showsAppliedProviderCheckmark: Bool
    let controller: AppController
    @Binding var draftModel: String
    @Binding var draftBaseURL: String
    @Binding var draftAPIKey: String
    @Binding var draftTimeout: Int
    @Binding var draftLatency: VoiceCleanupLatencyPolicy
    let cleanupEnabled: Bool
    @Binding var statusMessage: String?
    let onClose: () -> Void
    let onSelect: () -> Void
    @ViewBuilder let detail: (VoiceCleanupProviderKind) -> Detail

    var body: some View {
        VoiceTwoPanePickerSheet(
            selection: $selectedProvider,
            filter: $filter,
            searchText: $searchText,
            currentSelection: currentProvider,
            showsCurrentRowIndicator: showsAppliedProviderCheckmark,
            entries: VoiceCleanupCatalogPresentation.pickerEntries(),
            groupOrder: VoiceCleanupCatalogPresentation.pickerGroupOrder(),
            groupTitle: { $0.title },
            filterTabs: VoiceCleanupCatalogPresentation.pickerFilters(),
            matchesFilter: VoiceCleanupCatalogPresentation.matchesFilter,
            headerTitle: "Choose cleanup model",
            headerSubtitle: "Select a cloud or local cleanup provider used after recognition.",
            searchPlaceholder: "Search cleanup models",
            footerText: "Rows identify cleanup providers. Configure the model and credentials in the detail pane.",
            onClose: onClose,
            footerActions: {
                VoiceCleanupPickerFooterActions(
                    controller: controller,
                    selectedProvider: selectedProvider,
                    draftModel: $draftModel,
                    draftBaseURL: $draftBaseURL,
                    draftAPIKey: $draftAPIKey,
                    draftTimeout: $draftTimeout,
                    draftLatency: $draftLatency,
                    cleanupEnabled: cleanupEnabled,
                    statusMessage: $statusMessage,
                    onSelect: onSelect
                )
            },
            detail: detail
        )
    }
}
