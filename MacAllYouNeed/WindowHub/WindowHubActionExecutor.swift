import AppKit
import ApplicationServices
import Foundation

@MainActor
final class WindowHubActionExecutor {
    private(set) var state: WindowHubActionExecutionState = .idle

    func execute(plan: WindowHubActionPlan, snapshot: WindowHubSnapshot) async -> WindowHubActionExecutionState {
        let executable = plan.steps.filter(\.executable)
        guard !executable.isEmpty else {
            state = .finished(succeeded: 0, failed: plan.steps.count)
            return state
        }

        state = .running(completed: 0, total: executable.count)
        var succeeded = 0
        var failed = 0

        for (index, step) in executable.enumerated() {
            guard case .running = state else { break }
            let ok = await execute(step: step, snapshot: snapshot)
            if ok { succeeded += 1 } else { failed += 1 }
            state = .running(completed: index + 1, total: executable.count)
        }

        state = .finished(succeeded: succeeded, failed: failed)
        return state
    }

    func cancel() {
        state = .cancelled
    }

    private func execute(step: WindowHubActionStep, snapshot: WindowHubSnapshot) async -> Bool {
        guard let target = snapshot.flatTargets.first(where: { $0.id == step.targetID })
            ?? snapshot.flatTargets.first(where: { $0.pid == pid(from: step.targetID) })
        else { return false }

        switch step.action {
        case .closeTab:
            return closeTab(target: target)
        case .closeWindow:
            return closeWindow(target: target)
        case .closeAllTabsInWindow:
            let tabs = snapshot.flatTargets.filter {
                $0.kind == .tab && $0.pid == target.pid && $0.windowID == target.windowID
            }
            var allOK = true
            for tab in tabs {
                allOK = closeTab(target: tab) && allOK
            }
            return allOK
        case .quitApp:
            guard let app = NSRunningApplication(processIdentifier: target.pid) else { return false }
            return app.terminate()
        case .none:
            return false
        }
    }

    private func closeWindow(target: WindowHubTarget) -> Bool {
        let appElement = AXUIElementCreateApplication(target.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return false }
        guard let window = windows.first(where: { axTitle($0) == target.windowTitle }) ?? windows.first else {
            return false
        }
        return AXUIElementPerformAction(window, kAXCancelAction as CFString) == .success
            || AXUIElementPerformAction(window, "AXClose" as CFString) == .success
    }

    private func closeTab(target: WindowHubTarget) -> Bool {
        guard let bundleID = target.bundleIdentifier,
              BrowserAppleScriptTabReader.isChromium(bundleID)
              || BrowserAppleScriptActionProvider().matches(bundleIdentifier: bundleID)
        else {
            return closeWindow(target: target)
        }

        if let indices = WindowHubAppleScriptTabKey.from(targetID: target.id) {
            return BrowserAppleScriptActions.closeTab(
                bundleIdentifier: bundleID,
                windowIndex: indices.windowIndex,
                tabIndex: indices.tabIndex
            )
        }
        return BrowserAppleScriptActions.closeTab(bundleIdentifier: bundleID, windowIndex: 1, tabIndex: 1)
    }

    private func axTitle(_ element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    private func pid(from id: WindowHubTargetID) -> pid_t? {
        let parts = id.raw.split(separator: ":")
        guard parts.count >= 2, let value = Int32(parts[1]) else { return nil }
        return pid_t(value)
    }
}
