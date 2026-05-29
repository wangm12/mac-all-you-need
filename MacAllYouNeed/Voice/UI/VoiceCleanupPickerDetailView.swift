import SwiftUI

/// Right-hand detail column for the cleanup model picker.
struct VoiceCleanupPickerDetailView: View {
    let controller: AppController
    /// Provider currently saved (applied) in Voice settings.
    let savedProvider: VoiceCleanupProviderKind
    /// Provider row selected in the picker list.
    let selectedProvider: VoiceCleanupProviderKind
    @Binding var draftModel: String
    @Binding var draftBaseURL: String
    @Binding var draftAPIKey: String
    @Binding var draftTimeout: Int
    @Binding var draftLatency: VoiceCleanupLatencyPolicy
    let cleanupEnabled: Bool
    @Binding var statusMessage: String?

    private var draftSettings: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: selectedProvider,
            model: draftModel,
            baseURLString: draftBaseURL,
            timeoutSeconds: draftTimeout,
            latencyPolicy: draftLatency
        )
    }

    private var isCurrent: Bool {
        savedProvider == selectedProvider
    }

    private var hasAPIKey: Bool {
        !draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var providerCredentialSummary: String {
        if selectedProvider.requiresAPIKey {
            "\(selectedProvider.label) · \(hasAPIKey ? "Key on file" : "Needs key")"
        } else {
            selectedProvider.label
        }
    }

    private var providerCredentialPillKind: StatusPill.Kind {
        if selectedProvider.requiresAPIKey, !hasAPIKey {
            .warning
        } else {
            .neutral
        }
    }

    private var detailKindLabel: String {
        switch selectedProvider.cleanupPickerGroup {
        case .cloud:
            "Cloud cleanup"
        case .local:
            "Local cleanup"
        case .custom:
            "Custom cleanup"
        }
    }

    private var statusText: String {
        if isCurrent, cleanupEnabled {
            "In use"
        } else if isCurrent {
            "Saved"
        } else if selectedProvider.requiresAPIKey, hasAPIKey {
            "API key ready"
        } else if selectedProvider.requiresAPIKey {
            "API key required"
        } else {
            "Local"
        }
    }

    private var statusKind: StatusPill.Kind {
        if isCurrent, cleanupEnabled {
            .success
        } else if isCurrent {
            .neutral
        } else if selectedProvider.requiresAPIKey, !hasAPIKey {
            .warning
        } else {
            .neutral
        }
    }

    private var groqModelDropdownIDs: [String] {
        VoiceGroqCleanupChatModel.dropdownModelIDs(currentDraft: draftModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(detailKindLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        StatusPill(text: statusText, kind: statusKind)
                    }

                    Text(VoiceCleanupCatalogPresentation.rowTitle(for: selectedProvider))
                        .font(.title3.weight(.semibold))

                    Text(VoiceCleanupCatalogPresentation.rowSubtitle(for: selectedProvider))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    StatusPill(text: providerCredentialSummary, kind: providerCredentialPillKind)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Details")
                            .font(.callout.weight(.semibold))
                        detailLabels
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if selectedProvider == .groq {
                            Text("Pick a Groq chat model (OpenAI-compatible). Listed IDs match Groq’s published inference models; see Groq rate limits for quotas.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            MAYNDropdown(
                                selection: $draftModel,
                                options: groqModelDropdownIDs,
                                title: { VoiceGroqCleanupChatModel.pickerTitle(forModelID: $0) },
                                width: MAYNControlMetrics.widePickerWidth
                            )
                        } else {
                            MAYNTextField(text: $draftModel)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MAYNTextField(text: $draftBaseURL)
                    }

                    if selectedProvider == .ollama {
                        VoiceOllamaCleanupControls(
                            controller: controller,
                            model: $draftModel,
                            baseURLString: $draftBaseURL,
                            statusMessage: $statusMessage
                        )
                    }

                    if selectedProvider == .omlx {
                        Text("Confirm host, port, and model id in the oMLX app match Base URL and Model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if selectedProvider.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API key")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            MAYNSecureField(text: $draftAPIKey)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeout")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        MAYNNumericStepper(
                            text: "\(draftTimeout)s",
                            value: $draftTimeout,
                            range: 1...30,
                            presets: [3, 5, 7, 10, 15, 30],
                            suffix: "s"
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latency policy")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(draftLatency.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        MAYNDropdown(
                            selection: $draftLatency,
                            options: Array(VoiceCleanupLatencyPolicy.allCases),
                            title: { $0.label },
                            width: MAYNControlMetrics.widePickerWidth
                        )
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(
                        "Turn on AI cleanup on Voice → Models when you want cleanup after each dictation. Use Select model in the header to save this provider and fields."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: normalizeGroqDraftIfNeeded)
        .onChange(of: selectedProvider) { _, _ in
            normalizeGroqDraftIfNeeded()
        }
    }

    @ViewBuilder
    private var detailLabels: some View {
        switch selectedProvider.cleanupPickerGroup {
        case .cloud, .custom:
            Label("Requires network access.", systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("Sends transcript text to the provider using your configuration.", systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .local:
            Label("Runs on your Mac; verify the local server is reachable.", systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func normalizeGroqDraftIfNeeded() {
        guard selectedProvider == .groq else { return }
        if draftModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftModel = VoiceCleanupProviderKind.groq.defaultModel
        }
    }

}

// MARK: - Footer actions (sheet chrome)

struct VoiceCleanupPickerFooterActions: View {
    let controller: AppController
    let selectedProvider: VoiceCleanupProviderKind
    @Binding var draftModel: String
    @Binding var draftBaseURL: String
    @Binding var draftAPIKey: String
    @Binding var draftTimeout: Int
    @Binding var draftLatency: VoiceCleanupLatencyPolicy
    let cleanupEnabled: Bool
    @Binding var statusMessage: String?
    let onSelect: () -> Void

    @State private var isTestingCleanup = false

    private var draftSettings: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: selectedProvider,
            model: draftModel,
            baseURLString: draftBaseURL,
            timeoutSeconds: draftTimeout,
            latencyPolicy: draftLatency
        )
    }

    private var draftSettingsProbeEnabled: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: true,
            provider: selectedProvider,
            model: draftModel,
            baseURLString: draftBaseURL,
            timeoutSeconds: draftTimeout,
            latencyPolicy: draftLatency
        )
    }

    private var hasAPIKey: Bool {
        !draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Model + base URL must be valid; API key is not required to save a provider choice.
    private var canSelectCleanupModel: Bool {
        let model = draftModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return false }
        return URL(string: draftSettings.effectiveBaseURLString) != nil
    }

    private var canRunCleanupProbe: Bool {
        guard canSelectCleanupModel else { return false }
        if selectedProvider.requiresAPIKey {
            return hasAPIKey
        }
        return true
    }

    var body: some View {
        HStack(spacing: 8) {
            MAYNButton(isTestingCleanup ? "Testing..." : "Test cleanup") {
                runTestCleanup()
            }
            .disabled(isTestingCleanup || !canRunCleanupProbe)

            MAYNButton("Select model", role: .primary) {
                onSelect()
            }
            .disabled(!canSelectCleanupModel)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func runTestCleanup() {
        guard canRunCleanupProbe else {
            statusMessage = controller.validateVoiceCleanupSettings(draftSettingsProbeEnabled, apiKey: draftAPIKey)
            return
        }
        isTestingCleanup = true
        statusMessage = "Sending provider ping..."
        Task {
            let message = await controller.testVoiceCleanupSettings(draftSettingsProbeEnabled, apiKey: draftAPIKey)
            await MainActor.run {
                statusMessage = message
                isTestingCleanup = false
            }
        }
    }
}
