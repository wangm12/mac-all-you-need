import Foundation

enum WindowHubActionPlanner {
    static func plan(
        action: WindowHubDirectAction,
        target: WindowHubTarget,
        settings: WindowHubSettings
    ) -> WindowHubActionPlan {
        let steps: [WindowHubActionStep]
        let title: String
        switch action {
        case .closeTab:
            title = "Close tab"
            steps = [
                WindowHubActionStep(
                    id: "close-tab",
                    title: "Close \(target.displayTitle)",
                    action: .closeTab,
                    targetID: target.id,
                    executable: target.capabilities.contains(.close),
                    reason: target.capabilities.contains(.close) ? nil : "This app does not support closing tabs."
                ),
            ]
        case .closeWindow:
            title = "Close window"
            steps = [
                WindowHubActionStep(
                    id: "close-window",
                    title: "Close \(target.windowTitle ?? target.displayTitle)",
                    action: .closeWindow,
                    targetID: target.id,
                    executable: true,
                    reason: nil
                ),
            ]
        case .closeAllTabsInWindow:
            title = "Close all tabs in window"
            steps = [
                WindowHubActionStep(
                    id: "close-all-tabs",
                    title: "Close all tabs in \(target.windowTitle ?? "window")",
                    action: .closeAllTabsInWindow,
                    targetID: target.id,
                    executable: target.capabilities.contains(.close),
                    reason: target.capabilities.contains(.close) ? nil : "Tab close is unavailable for this app."
                ),
            ]
        case .quitApp:
            title = "Quit app"
            steps = [
                WindowHubActionStep(
                    id: "quit-app",
                    title: "Quit \(target.appName)",
                    action: .quitApp,
                    targetID: .app(pid: target.pid),
                    executable: true,
                    reason: nil
                ),
            ]
        }

        let requiresConfirmation = shouldConfirm(action: action, target: target, settings: settings)
        let canUndo = false
        return WindowHubActionPlan(title: title, steps: steps, requiresConfirmation: requiresConfirmation, canUndo: canUndo)
    }

    private static func shouldConfirm(
        action: WindowHubDirectAction,
        target: WindowHubTarget,
        settings: WindowHubSettings
    ) -> Bool {
        if target.isPinned || target.isAudible || target.isPrivate || target.riskLevel == .high {
            return true
        }
        if settings.skipLowRiskConfirmations, target.riskLevel == .low, action != .quitApp {
            return false
        }
        return true
    }
}
