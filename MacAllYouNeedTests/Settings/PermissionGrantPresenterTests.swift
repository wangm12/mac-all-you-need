@testable import MacAllYouNeed
import FeatureCore
import XCTest

final class PermissionGrantPresenterTests: XCTestCase {
    func testInlineInstructionMapsAllPermissions() {
        let permissions: [Permission] = [
            .accessibility,
            .fullDiskAccess,
            .microphone,
            .notifications,
            .screenRecording,
            .reminders
        ]
        for permission in permissions {
            let inline = PermissionGrantPresenter.inlineInstruction(for: permission)
            XCTAssertFalse(inline.primaryText.isEmpty, "Missing primary text for \(permission)")
            XCTAssertFalse(inline.symbol.isEmpty, "Missing symbol for \(permission)")
        }
    }

    func testDragCapablePermissionsExposeBundleURL() {
        let dragPermissions: [Permission] = [
            .accessibility,
            .fullDiskAccess,
            .microphone,
            .screenRecording
        ]
        for permission in dragPermissions {
            let inline = PermissionGrantPresenter.inlineInstruction(for: permission)
            XCTAssertNotNil(inline.dragAppURL, "Expected drag URL for \(permission)")
        }
    }

    func testInstructionOnlyPermissionsHaveNoDragURL() {
        let noDragPermissions: [Permission] = [.notifications, .reminders]
        for permission in noDragPermissions {
            let inline = PermissionGrantPresenter.inlineInstruction(for: permission)
            XCTAssertNil(inline.dragAppURL, "Unexpected drag URL for \(permission)")
        }
    }

    func testShouldPresentFloatingPanelForDragPermissions() {
        XCTAssertTrue(PermissionGrantPresenter.shouldPresentFloatingPanel(for: .accessibility))
        XCTAssertTrue(PermissionGrantPresenter.shouldPresentFloatingPanel(for: .fullDiskAccess))
        XCTAssertTrue(PermissionGrantPresenter.shouldPresentFloatingPanel(for: .screenRecording))
    }

    func testShouldNotPresentFloatingPanelForInstructionOnlyPermissions() {
        XCTAssertFalse(PermissionGrantPresenter.shouldPresentFloatingPanel(for: .notifications))
        XCTAssertFalse(PermissionGrantPresenter.shouldPresentFloatingPanel(for: .reminders))
    }

    func testPermissionInstructionTargetMapping() {
        XCTAssertEqual(PermissionInstructionTarget.from(.accessibility), .accessibility)
        XCTAssertEqual(PermissionInstructionTarget.from(.microphone), .microphone)
        XCTAssertEqual(PermissionInstructionTarget.from(.screenRecording), .screenRecording)
        XCTAssertEqual(PermissionInstructionTarget.from(.fullDiskAccess), .fullDiskAccess)
        XCTAssertEqual(PermissionInstructionTarget.from(.notifications), .notifications)
        XCTAssertNil(PermissionInstructionTarget.from(.reminders))
    }

    func testRemindersInlineInstructionIsInstructionOnly() {
        let inline = PermissionGrantPresenter.inlineInstruction(for: .reminders)
        XCTAssertTrue(inline.primaryText.contains("Reminders"))
        XCTAssertNil(inline.dragAppURL)
    }
}
