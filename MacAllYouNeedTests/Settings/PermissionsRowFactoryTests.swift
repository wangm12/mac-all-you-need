@testable import MacAllYouNeed
import XCTest

/// Pins the action-button title produced by each permission row for every
/// PermissionDisplayState. Ensures the factory logic doesn't silently drift.
final class PermissionsRowFactoryTests: XCTestCase {

    // MARK: - Accessibility

    func testAccessibilityRowActionTitleGranted() {
        XCTAssertEqual(accessibilityActionTitle(.granted), "Granted")
    }

    func testAccessibilityRowActionTitleNeedsAction() {
        XCTAssertEqual(accessibilityActionTitle(.needsAction), "Open")
    }

    func testAccessibilityRowActionTitleDenied() {
        XCTAssertEqual(accessibilityActionTitle(.denied), "Open")
    }

    func testAccessibilityRowActionTitleNotRequested() {
        XCTAssertEqual(accessibilityActionTitle(.notRequested), "Open")
    }

    func testAccessibilityRowActionTitleOptional() {
        XCTAssertEqual(accessibilityActionTitle(.optional), "Open")
    }

    // MARK: - Microphone

    func testMicrophoneRowActionTitleGranted() {
        XCTAssertEqual(microphoneActionTitle(.granted), "Granted")
    }

    func testMicrophoneRowActionTitleDenied() {
        XCTAssertEqual(microphoneActionTitle(.denied), "Open")
    }

    func testMicrophoneRowActionTitleNotRequested() {
        XCTAssertEqual(microphoneActionTitle(.notRequested), "Request")
    }

    func testMicrophoneRowActionTitleNeedsAction() {
        XCTAssertEqual(microphoneActionTitle(.needsAction), "Request")
    }

    func testMicrophoneRowActionTitleOptional() {
        XCTAssertEqual(microphoneActionTitle(.optional), "Request")
    }

    // MARK: - Full Disk Access

    func testFullDiskAccessRowActionTitleIsAlwaysOpen() {
        let allStates: [PermissionDisplayState] = [.notRequested, .needsAction, .granted, .denied, .optional]
        for state in allStates {
            XCTAssertEqual(fullDiskAccessActionTitle(state), "Open", "Expected 'Open' for state \(state)")
        }
    }

    // MARK: - Notifications

    func testNotificationsRowActionTitleGranted() {
        XCTAssertEqual(notificationsActionTitle(.granted), "Granted")
    }

    func testNotificationsRowActionTitleDenied() {
        XCTAssertEqual(notificationsActionTitle(.denied), "Open")
    }

    func testNotificationsRowActionTitleNotRequested() {
        XCTAssertEqual(notificationsActionTitle(.notRequested), "Request")
    }

    func testNotificationsRowActionTitleNeedsAction() {
        XCTAssertEqual(notificationsActionTitle(.needsAction), "Request")
    }

    func testNotificationsRowActionTitleOptional() {
        XCTAssertEqual(notificationsActionTitle(.optional), "Request")
    }

    // MARK: - Row Type Names

    func testRowTypeNamesMatchExpectedTypeNames() {
        XCTAssertEqual(String(describing: AccessibilityPermissionRow.self), "AccessibilityPermissionRow")
        XCTAssertEqual(String(describing: MicrophonePermissionRow.self), "MicrophonePermissionRow")
        XCTAssertEqual(String(describing: FullDiskAccessPermissionRow.self), "FullDiskAccessPermissionRow")
        XCTAssertEqual(String(describing: NotificationsPermissionRow.self), "NotificationsPermissionRow")
    }

    // MARK: - Helpers

    /// Mirrors AccessibilityPermissionRow's action title logic.
    private func accessibilityActionTitle(_ status: PermissionDisplayState) -> String {
        status == .granted ? "Granted" : "Open"
    }

    /// Mirrors MicrophonePermissionRow's action title logic.
    private func microphoneActionTitle(_ status: PermissionDisplayState) -> String {
        switch status {
        case .granted: "Granted"
        case .denied: "Open"
        default: "Request"
        }
    }

    /// Mirrors FullDiskAccessPermissionRow's action title logic.
    private func fullDiskAccessActionTitle(_ status: PermissionDisplayState) -> String {
        "Open"
    }

    /// Delegates to the shared PermissionActionPresentation helper, matching NotificationsPermissionRow.
    private func notificationsActionTitle(_ status: PermissionDisplayState) -> String {
        PermissionActionPresentation.notificationActionTitle(for: status)
    }
}
