import Core
import SwiftUI

struct VoiceLLMStepView: View {
    let controller: AppController
    @State private var cleanupEnabled: Bool
    @State private var provider: VoiceCleanupProviderKind
    @State private var model: String
    @State private var learnFromEdits: Bool
    @State private var baseURLString: String
    @State private var apiKey: String
    @State private var timeoutSeconds: Int
    @State private var statusMessage: String?
    @State private var isTesting = false

    init(controller: AppController) {
        self.controller = controller
        let settings = controller.voiceCleanupSettings()
        _cleanupEnabled = State(initialValue: settings.isEnabled)
        _provider = State(initialValue: settings.provider)
        _model = State(initialValue: settings.model)
        _baseURLString = State(initialValue: settings.baseURLString)
        _apiKey = State(initialValue: controller.voiceCleanupAPIKey(for: settings.provider))
        _timeoutSeconds = State(initialValue: settings.timeoutSeconds)
        _learnFromEdits = State(initialValue: controller.voicePersonalizationSettings().learnFromEditsEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI cleanup")
                .font(.title)
                .bold()
            Text("This step is optional. Local filler cleanup and your dictionary still work when AI cleanup is off.")
                .foregroundStyle(.secondary)
            Text("Cloud cleanup sends transcript text to the provider you choose. Audio stays local.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enable AI cleanup", isOn: $cleanupEnabled)
            HStack(spacing: 10) {
                ForEach(VoiceCleanupProviderKind.allCases) { kind in
                    Button {
                        provider = kind
                    } label: {
                        VoiceCleanupProviderCard(
                            provider: kind,
                            isSelected: provider == kind
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            MAYNTextField(placeholder: "Model", text: $model, width: 360)
            MAYNTextField(placeholder: "Base URL", text: $baseURLString, width: 360)
            if provider == .ollama {
                VoiceOllamaCleanupControls(
                    controller: controller,
                    model: $model,
                    baseURLString: $baseURLString,
                    statusMessage: $statusMessage
                )
            }
            if provider.requiresAPIKey {
                MAYNSecureField(placeholder: "API key", text: $apiKey, width: 360)
            }
            HStack {
                Text("Timeout")
                Spacer()
                MAYNNumericStepper(
                    text: "\(timeoutSeconds)s",
                    value: $timeoutSeconds,
                    range: 1...30,
                    presets: [3, 5, 7, 10, 15, 30],
                    suffix: "s"
                )
            }
            HStack {
                MAYNButton(isTesting ? "Testing..." : "Test") { testSettings() }
                    .disabled(isTesting)
                MAYNButton("Apply", role: .primary) { applySettings() }
                MAYNButton("Skip AI cleanup") {
                    cleanupEnabled = false
                    controller.disableVoiceCleanup()
                    statusMessage = "AI cleanup disabled. Local cleanup remains active."
                }
            }
            Divider()
            Toggle(isOn: $learnFromEdits) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Improve cleanup over time by learning from your edits")
                        .font(.body)
                    Text("Edit samples are stored locally and encrypted. Older samples are summarized via your selected cleanup LLM provider to refine your style profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: learnFromEdits) { _, value in
                var s = controller.voicePersonalizationSettings()
                s.learnFromEditsEnabled = value
                controller.applyVoicePersonalizationSettings(s)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onChange(of: provider) { _, nextProvider in
            model = nextProvider.defaultModel
            baseURLString = nextProvider.defaultBaseURLString
            apiKey = controller.voiceCleanupAPIKey(for: nextProvider)
        }
    }

    private var draft: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: cleanupEnabled,
            provider: provider,
            model: model,
            baseURLString: baseURLString,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func testSettings() {
        isTesting = true
        statusMessage = "Sending provider ping..."
        Task {
            let message = await controller.testVoiceCleanupSettings(draft, apiKey: apiKey)
            await MainActor.run {
                statusMessage = message
                isTesting = false
            }
        }
    }

    private func applySettings() {
        do {
            try controller.applyVoiceCleanupSettings(draft, apiKey: apiKey)
            statusMessage = "Cleanup settings saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

struct VoiceCleanupProviderCard: View {
    let provider: VoiceCleanupProviderKind
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.45) : Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch provider {
        case .anthropic:
            "Claude Haiku 4.5"
        case .openAICompatible:
            "OpenAI gpt-5-nano"
        case .ollama:
            "Ollama"
        }
    }

    private var subtitle: String {
        switch provider {
        case .anthropic:
            "Recommended cloud cleanup"
        case .openAICompatible:
            "OpenAI-compatible endpoint"
        case .ollama:
            "Local cleanup provider"
        }
    }
}
