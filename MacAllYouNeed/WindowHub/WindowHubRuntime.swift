import ApplicationServices
import Core
import Foundation
import Platform

@MainActor
final class WindowHubRuntime {
    private let coordinator = WindowHubCoordinator()
    private lazy var panelController = WindowHubPanelController(coordinator: coordinator)
    private var isEnabled = false
    private let log = Logging.logger(for: "window-hub", category: "runtime")

    init(llmGenerate: ((String, String) async throws -> String)? = nil) {
        if let llmGenerate {
            coordinator.configureLLM(llmGenerate)
        }
        coordinator.onDismissForActivation = { [weak self] in
            self?.panelController.dismiss()
        }
    }

    func applyEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            panelController.dismiss()
        }
    }

    func reloadSettings() {
        coordinator.reloadSettings()
    }

    /// Window Hub shortcuts register through `HotkeyRegistry` like other global actions.
    func reloadHotkey() {}

    func suspendForHotkeyRecording() {}

    func resumeAfterHotkeyRecording() {}

    func togglePanel() {
        guard isEnabled else {
            log.debug("Ignoring Window Hub toggle while feature is disabled.")
            return
        }
        if panelController.isVisible {
            panelController.dismiss()
        } else {
            panelController.present()
        }
    }

    var hubCoordinator: WindowHubCoordinator { coordinator }
}

extension Notification.Name {
    static let windowHubHotkeyDidChange = Notification.Name("windowHubHotkeyDidChange")
}
