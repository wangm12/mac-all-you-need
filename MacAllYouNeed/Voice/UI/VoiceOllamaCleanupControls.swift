import Foundation
import SwiftUI

struct VoiceOllamaCleanupControls: View {
    let controller: AppController
    @Binding var model: String
    @Binding var baseURLString: String
    @Binding var statusMessage: String?
    @State private var models: [OllamaModel] = []
    @State private var activity: Activity?
    @State private var didAutoRefresh = false

    var body: some View {
        MAYNSettingsRow(
            title: "Ollama service",
            subtitle: "Uses Ollama's local management API for installed cleanup models."
        ) {
            HStack(spacing: 8) {
                if let activity {
                    StatusPill(text: activity.label, kind: .progress)
                }
                MAYNButton("Refresh") { refreshModels() }
                    .disabled(activity != nil)
                MAYNButton("Test") { testService() }
                    .disabled(activity != nil)
            }
        }
        MAYNDivider()
        MAYNSettingsRow(
            title: "Installed models",
            subtitle: installedModelsSubtitle
        ) {
            if modelNames.isEmpty {
                StatusPill(text: "None", kind: .neutral)
            } else {
                MAYNDropdown(
                    selection: $model,
                    options: modelNames,
                    title: { $0 },
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
        }
        MAYNDivider()
        MAYNSettingsRow(
            title: "Model actions",
            subtitle: "Pull or delete the model named in the Model field."
        ) {
            HStack(spacing: 8) {
                MAYNButton(activity == .pulling ? "Pulling..." : "Pull") { pullModel() }
                    .disabled(trimmedModel.isEmpty || activity != nil)
                MAYNButton(activity == .deleting ? "Deleting..." : "Delete", role: .destructive) { deleteModel() }
                    .disabled(trimmedModel.isEmpty || activity != nil)
            }
        }
        .task {
            guard !didAutoRefresh else { return }
            didAutoRefresh = true
            await loadModels(statusPrefix: nil)
        }
    }

    private var modelNames: [String] {
        models.map(\.name)
    }

    private var installedModelsSubtitle: String {
        if models.isEmpty {
            return "Refresh to detect models installed in Ollama."
        }
        return "Select one to use it for cleanup."
    }

    private var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var settings: VoiceCleanupSettings {
        VoiceCleanupSettings(
            isEnabled: true,
            provider: .ollama,
            model: model,
            baseURLString: baseURLString,
            timeoutSeconds: VoiceCleanupSettings.default.timeoutSeconds
        )
    }

    private func refreshModels() {
        Task {
            await loadModels(statusPrefix: "Ollama model list refreshed")
        }
    }

    private func testService() {
        activity = .refreshing
        let draft = settings
        Task {
            let message = await controller.testOllamaCleanupService(settings: draft)
            let fetchedModels = (try? await controller.listOllamaCleanupModels(settings: draft)) ?? []
            await MainActor.run {
                models = fetchedModels
                statusMessage = message
                activity = nil
            }
        }
    }

    private func pullModel() {
        let modelName = trimmedModel
        guard !modelName.isEmpty else { return }

        activity = .pulling
        statusMessage = "Pulling \(modelName)..."
        let draft = settings
        Task {
            do {
                try await controller.pullOllamaCleanupModel(settings: draft, model: modelName)
                let fetchedModels = try await controller.listOllamaCleanupModels(settings: draft)
                await MainActor.run {
                    models = fetchedModels
                    statusMessage = "Pulled \(modelName)."
                    activity = nil
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Ollama pull failed: \(error.localizedDescription)"
                    activity = nil
                }
            }
        }
    }

    private func deleteModel() {
        let modelName = trimmedModel
        guard !modelName.isEmpty else { return }

        activity = .deleting
        statusMessage = "Deleting \(modelName)..."
        let draft = settings
        Task {
            do {
                try await controller.deleteOllamaCleanupModel(settings: draft, model: modelName)
                let fetchedModels = try await controller.listOllamaCleanupModels(settings: draft)
                await MainActor.run {
                    models = fetchedModels
                    if self.model == modelName, let fallback = fetchedModels.first?.name {
                        self.model = fallback
                    }
                    statusMessage = "Deleted \(modelName)."
                    activity = nil
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Ollama delete failed: \(error.localizedDescription)"
                    activity = nil
                }
            }
        }
    }

    private func loadModels(statusPrefix: String?) async {
        await MainActor.run {
            activity = .refreshing
        }
        let draft = settings
        do {
            let fetchedModels = try await controller.listOllamaCleanupModels(settings: draft)
            await MainActor.run {
                models = fetchedModels
                if let statusPrefix {
                    statusMessage = "\(statusPrefix): \(fetchedModels.count) found."
                }
                activity = nil
            }
        } catch {
            await MainActor.run {
                statusMessage = "Ollama refresh failed: \(error.localizedDescription)"
                activity = nil
            }
        }
    }
}

private extension VoiceOllamaCleanupControls {
    enum Activity: Equatable {
        case refreshing
        case pulling
        case deleting

        var label: String {
            switch self {
            case .refreshing:
                "Checking"
            case .pulling:
                "Pulling"
            case .deleting:
                "Deleting"
            }
        }
    }
}
