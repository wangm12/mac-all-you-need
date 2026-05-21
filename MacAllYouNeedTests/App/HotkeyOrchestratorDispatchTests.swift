@testable import MacAllYouNeed
import Core
import Platform
import XCTest

/// Characterization tests for HotkeyOrchestrator action dispatch.
///
/// The orchestrator translates a `HotkeyAction` into a concrete callback
/// (clipboard toggle, browse folder, window action). These tests pin that
/// translation contract — they fire each action through the orchestrator
/// and assert the right side-effect fires.
///
/// Carbon hotkey REGISTRATION is not exercised here; that runs through
/// `HotkeyRegistry.apply(...)` and requires a real run loop. The dispatch
/// table is the AppController-shaped surface that decomposition risks
/// silently rewiring.
@MainActor
final class HotkeyOrchestratorDispatchTests: XCTestCase {
    func testClipboardActionInvokesClipboardToggle() {
        let recorder = ActionRecorder()
        let orchestrator = makeOrchestrator(recorder: recorder)
        orchestrator.performAction(.clipboard)
        XCTAssertEqual(recorder.events, [.clipboardToggled])
    }

    func testBrowseFolderActionInvokesFolderPicker() {
        let recorder = ActionRecorder()
        let orchestrator = makeOrchestrator(recorder: recorder)
        orchestrator.performAction(.browseFolder)
        XCTAssertEqual(recorder.events, [.browseFolderOpened])
    }

    func testWindowActionMapsToCorrespondingWindowControlAction() {
        let recorder = ActionRecorder()
        let orchestrator = makeOrchestrator(recorder: recorder)

        let cases: [(HotkeyAction, WindowAction)] = [
            (.windowLeftHalf, .leftHalf),
            (.windowRightHalf, .rightHalf),
            (.windowTopHalf, .topHalf),
            (.windowBottomHalf, .bottomHalf),
            (.windowTopLeft, .topLeft),
            (.windowTopRight, .topRight),
            (.windowBottomLeft, .bottomLeft),
            (.windowBottomRight, .bottomRight),
            (.windowMaximize, .maximize),
            (.windowAlmostMaximize, .almostMaximize),
            (.windowCenter, .center),
            (.windowRestore, .restore),
            (.windowNextDisplay, .nextDisplay),
            (.windowPreviousDisplay, .previousDisplay)
        ]

        for (action, expected) in cases {
            recorder.events.removeAll()
            orchestrator.performAction(action)
            XCTAssertEqual(recorder.events, [.windowAction(expected)], "for \(action)")
        }
    }

    func testNonWindowActionsDoNotDispatchWindowAction() {
        let recorder = ActionRecorder()
        let orchestrator = makeOrchestrator(recorder: recorder)
        orchestrator.performAction(.clipboard)
        orchestrator.performAction(.browseFolder)
        XCTAssertFalse(recorder.events.contains { event in
            if case .windowAction = event { return true }
            return false
        })
    }

    // MARK: - Helpers

    private func makeOrchestrator(recorder: ActionRecorder) -> HotkeyOrchestrator {
        HotkeyOrchestrator(
            onClipboardToggle: { recorder.events.append(.clipboardToggled) },
            onBrowseFolder: { recorder.events.append(.browseFolderOpened) },
            onWindowAction: { recorder.events.append(.windowAction($0)) }
        )
    }

    @MainActor
    private final class ActionRecorder {
        enum Event: Equatable {
            case clipboardToggled
            case browseFolderOpened
            case windowAction(WindowAction)
        }
        var events: [Event] = []
    }
}
