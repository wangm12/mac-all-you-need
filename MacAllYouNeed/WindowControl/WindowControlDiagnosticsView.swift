import ApplicationServices
import Core
import Foundation
import Platform
import SwiftUI

struct WindowControlDiagnosticsView: View {
    let settings: WindowControlSettings
    let coordinator: WindowControlCoordinator?

    init(settings: WindowControlSettings, coordinator: WindowControlCoordinator? = nil) {
        self.settings = settings
        self.coordinator = coordinator
    }

    var body: some View {
        MAYNSection(title: "Diagnostics") {
            MAYNSettingsRow(
                title: "Accessibility",
                subtitle: "Required for moving windows in other apps."
            ) {
                StatusPill(
                    text: AXIsProcessTrusted() ? "Granted" : "Needed",
                    kind: AXIsProcessTrusted() ? .success : .warning
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Event tap",
                subtitle: WindowControlDiagnosticsPresentation.eventTapDetail(for: coordinator?.state ?? .off)
            ) {
                StatusPill(
                    text: WindowControlDiagnosticsPresentation.eventTapText(for: coordinator?.state ?? .off),
                    kind: WindowControlDiagnosticsPresentation.eventTapKind(for: coordinator?.state ?? .off)
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Last action",
                subtitle: WindowControlDiagnosticsPresentation.lastResultText(coordinator?.lastMovementResult)
            ) {
                StatusPill(
                    text: WindowControlDiagnosticsPresentation.lastActionText(coordinator?.lastAction),
                    kind: .neutral
                )
            }
        }
    }
}

enum WindowControlDiagnosticsPresentation {
    static func eventTapText(for state: WindowControlCoordinator.State) -> String {
        switch state {
        case .active:
            return "Running"
        case .needsAccessibility:
            return "Needs Accessibility"
        case .suspended:
            return "Suspended"
        case .error:
            return "Error"
        case .off:
            return "Off"
        }
    }

    static func eventTapKind(for state: WindowControlCoordinator.State) -> StatusPill.Kind {
        switch state {
        case .active:
            return .success
        case .needsAccessibility:
            return .warning
        case .suspended:
            return .progress
        case .error:
            return .danger
        case .off:
            return .neutral
        }
    }

    static func eventTapDetail(for state: WindowControlCoordinator.State) -> String {
        switch state {
        case .active:
            return "Coordinator state: active."
        case .needsAccessibility:
            return "Coordinator state: needs Accessibility."
        case let .suspended(reason):
            return "Coordinator state: suspended (\(suspensionReasonText(reason)))."
        case let .error(message):
            return "Coordinator state: error - \(message)"
        case .off:
            return "Coordinator state: off."
        }
    }

    static func lastActionText(_ action: WindowAction?) -> String {
        action?.title ?? "None"
    }

    static func lastResultText(_ result: WindowMovementResult?) -> String {
        guard let result else { return "No movement recorded yet." }
        switch result.status {
        case .moved:
            return "Moved"
        case .unsupportedWindow:
            return "Unsupported window"
        case .noDisplay:
            return "No display"
        case .noTargetFrame:
            return "No target frame"
        case .fixedSizeWindow:
            return "Fixed-size window"
        case .writeFailed:
            return "Write failed"
        }
    }

    private static func suspensionReasonText(_ reason: WindowControlCoordinator.SuspensionReason) -> String {
        switch reason {
        case .hotkeyRecording:
            return "hotkey recording"
        case .ignoredApp:
            return "ignored app"
        }
    }
}
