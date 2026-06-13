import Core
import SwiftUI

/// Two-pane model picker for the AI File Organizer — adapts the existing
/// Voice Cleanup picker infrastructure to use AIFileOrganizerSettings.
struct AIFileOrganizerModelPickerSheet: View {
    let controller: AppController
    @Binding var settings: AIFileOrganizerSettings
    let onClose: () -> Void

    @State private var selectedProvider: LLMProviderKind
    @State private var filter: VoiceCleanupPickerFilter = .all
    @State private var searchText = ""
    @State private var draftModel: String
    @State private var draftBaseURL: String
    @State private var draftAPIKey: String = ""
    @State private var draftTimeout: Int
    @State private var draftLatency: VoiceCleanupLatencyPolicy
    @State private var statusMessage: String?
    @State private var preloadedAPIKeys: [LLMProviderKind: String] = [:]

    init(controller: AppController, settings: Binding<AIFileOrganizerSettings>, onClose: @escaping () -> Void) {
        self.controller = controller
        self._settings = settings
        self.onClose = onClose
        _selectedProvider = State(initialValue: settings.wrappedValue.provider)
        _draftModel = State(initialValue: settings.wrappedValue.model)
        _draftBaseURL = State(initialValue: settings.wrappedValue.baseURLString)
        _draftTimeout = State(initialValue: settings.wrappedValue.timeoutSeconds)
        _draftLatency = State(initialValue: settings.wrappedValue.latencyPolicy)
    }

    var body: some View {
        VoiceTwoPanePickerSheet(
            selection: $selectedProvider,
            filter: $filter,
            searchText: $searchText,
            currentSelection: settings.provider,
            showsCurrentRowIndicator: true,
            entries: VoiceCleanupCatalogPresentation.pickerEntries(),
            groupOrder: VoiceCleanupCatalogPresentation.pickerGroupOrder(),
            groupTitle: { $0.title },
            filterTabs: VoiceCleanupCatalogPresentation.pickerFilters(),
            matchesFilter: VoiceCleanupCatalogPresentation.matchesFilter,
            headerTitle: "Choose AI Organizer model",
            headerSubtitle: "Select the LLM used for filename suggestions and folder categorization.",
            searchPlaceholder: "Search providers",
            footerText: "Configure the model and API key in the detail pane, then tap Use.",
            onClose: onClose,
            footerActions: {
                HStack {
                    Spacer()
                    MAYNButton("Cancel", role: .secondary, action: onClose)
                    MAYNButton("Use", role: .primary) { apply() }
                }
                .padding(16)
            },
            detail: { provider in
                VoiceCleanupPickerDetailView(
                    controller: controller,
                    savedProvider: settings.provider,
                    selectedProvider: provider,
                    draftModel: $draftModel,
                    draftBaseURL: $draftBaseURL,
                    draftAPIKey: Binding(
                        get: { preloadedAPIKeys[provider] ?? "" },
                        set: { preloadedAPIKeys[provider] = $0 }
                    ),
                    draftTimeout: $draftTimeout,
                    draftLatency: $draftLatency,
                    cleanupEnabled: true,
                    statusMessage: $statusMessage
                )
            }
        )
        .onChange(of: selectedProvider) { _, newProvider in
            // Reset drafts to saved values for the new provider when switching rows.
            draftModel = newProvider == settings.provider ? settings.model : newProvider.defaultModel
            draftBaseURL = newProvider == settings.provider ? settings.baseURLString : newProvider.defaultBaseURLString
        }
    }

    private func apply() {
        settings.provider = selectedProvider
        settings.model = draftModel
        settings.baseURLString = draftBaseURL
        settings.timeoutSeconds = draftTimeout
        settings.latencyPolicy = draftLatency
        AIFileOrganizerSettings.save(settings)
        onClose()
    }
}
