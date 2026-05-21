import XCTest
import AppKit
import SwiftUI
import UI
@testable import MacAllYouNeed

/// Tests for NonActivatingFloatingPanelController.
/// NSPanel work requires AppKit to be initialized; we use NSApplication.shared
/// to ensure that, and run all tests on MainActor.
final class NonActivatingFloatingPanelControllerTests: XCTestCase {

    // A minimal SwiftUI view used as test content.
    private struct TestView: View {
        let label: String
        var body: some View { Text(label) }
    }

    // MARK: - 1. Initial state

    @MainActor func testInitialState() async {
        let controller = NonActivatingFloatingPanelController<TestView>()
        XCTAssertNil(controller.currentPanel)
        XCTAssertFalse(controller.isPresented)
    }

    // MARK: - 2. Present creates panel with correct config

    @MainActor func testPresentCreatesPanelWithCorrectConfig() async throws {
        let controller = NonActivatingFloatingPanelController<TestView>(
            styleMask: [.borderless, .nonactivatingPanel],
            level: .floating,
            collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
            hasShadow: false,
            backgroundColor: .red
        )
        controller.present(rootView: TestView(label: "hello"), size: CGSize(width: 200, height: 100), animated: false)

        let panel = try XCTUnwrap(controller.currentPanel)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertEqual(panel.backgroundColor, .red)

        controller.dismiss(animated: false)
    }

    // MARK: - 3. Positioner called with correct arguments

    @MainActor func testPositionerIsCalled() async {
        var capturedPanel: NSPanel?
        var capturedSize: CGSize?

        let expectedSize = CGSize(width: 300, height: 150)
        let controller = NonActivatingFloatingPanelController<TestView>(
            positioner: { panel, size in
                capturedPanel = panel
                capturedSize = size
            }
        )

        controller.present(rootView: TestView(label: "pos"), size: expectedSize, animated: false)

        XCTAssertNotNil(capturedPanel)
        XCTAssertEqual(capturedPanel, controller.currentPanel)
        XCTAssertEqual(capturedSize, expectedSize)

        controller.dismiss(animated: false)
    }

    // MARK: - 4. Update reuses the same panel

    @MainActor func testUpdateReusesPanel() async throws {
        let controller = NonActivatingFloatingPanelController<TestView>()
        controller.present(rootView: TestView(label: "first"), size: CGSize(width: 100, height: 50), animated: false)

        let originalPanel = try XCTUnwrap(controller.currentPanel)

        controller.update(rootView: TestView(label: "second"))

        XCTAssertTrue(controller.currentPanel === originalPanel, "update(rootView:) must reuse the same panel instance")

        controller.dismiss(animated: false)
    }

    // MARK: - 5. Dismiss without animation

    @MainActor func testDismissWithoutAnimation() async {
        let controller = NonActivatingFloatingPanelController<TestView>()
        controller.present(rootView: TestView(label: "bye"), size: CGSize(width: 100, height: 50), animated: false)
        XCTAssertNotNil(controller.currentPanel)

        controller.dismiss(animated: false)

        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.currentPanel)
    }

    // MARK: - 6. Dismiss with animation

    @MainActor func testDismissWithAnimation() async {
        let controller = NonActivatingFloatingPanelController<TestView>(
            hideAnimationDuration: 0.05
        )
        controller.present(rootView: TestView(label: "fade"), size: CGSize(width: 100, height: 50), animated: false)

        controller.dismiss(animated: true)
        // Give the animation + completion handler time to run.
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 s

        XCTAssertFalse(controller.isPresented)
        XCTAssertNil(controller.currentPanel)
    }

    // MARK: - 7. Default style includes nonactivatingPanel

    @MainActor func testDefaultStyleMask() async throws {
        let controller = NonActivatingFloatingPanelController<TestView>()
        controller.present(rootView: TestView(label: "default"), size: CGSize(width: 100, height: 50), animated: false)

        let panel = try XCTUnwrap(controller.currentPanel)
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))

        controller.dismiss(animated: false)
    }
}
