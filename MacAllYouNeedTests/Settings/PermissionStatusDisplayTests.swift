@testable import MacAllYouNeed
import AppKit
import AVFoundation
import UserNotifications
import XCTest

final class PermissionStatusDisplayTests: XCTestCase {
    func testMicrophoneAuthorizationMapsToDisplayStates() {
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.authorized), .granted)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.notDetermined), .notRequested)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.denied), .denied)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.restricted), .denied)
    }

    func testAudioRecordPermissionCanMarkMicrophoneAsGranted() {
        XCTAssertEqual(
            PermissionStatusProvider.microphoneStatus(
                captureStatus: .notDetermined,
                recordPermission: .granted
            ),
            .granted
        )
        XCTAssertEqual(
            PermissionStatusProvider.microphoneStatus(
                captureStatus: .authorized,
                recordPermission: .denied
            ),
            .granted
        )
    }

    func testBooleanPermissionMapsToGrantedOrNeedsAction() {
        XCTAssertEqual(PermissionStatusProvider.requiredPermission(isGranted: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.requiredPermission(isGranted: false), .needsAction)
    }

    func testOptionalPermissionKeepsOptionalWhenUnavailable() {
        XCTAssertEqual(PermissionStatusProvider.optionalPermission(isGranted: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.optionalPermission(isGranted: false), .optional)
    }

    func testNotificationAuthorizationMapsDeniedSeparatelyFromOptional() {
        XCTAssertEqual(PermissionStatusProvider.notificationStatus(.authorized), .granted)
        XCTAssertEqual(PermissionStatusProvider.notificationStatus(.provisional), .granted)
        XCTAssertEqual(PermissionStatusProvider.notificationStatus(.denied), .denied)
        XCTAssertEqual(PermissionStatusProvider.notificationStatus(.notDetermined), .optional)
    }

    func testNotificationActionOpensSettingsAfterDenial() {
        XCTAssertEqual(PermissionActionPresentation.notificationActionTitle(for: .granted), "Granted")
        XCTAssertEqual(PermissionActionPresentation.notificationActionTitle(for: .denied), "Open")
        XCTAssertEqual(PermissionActionPresentation.notificationActionTitle(for: .optional), "Request")
    }

    func testFullDiskAccessIsOptionalUntilExplicitlyChecked() {
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: nil), .optional)
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: false), .optional)
    }

    func testAccessibilityInstructionSupportsDraggingAppIntoSystemSettings() {
        let instruction = PermissionInstructionTarget.accessibility.instruction(appName: "Mac All You Need")

        XCTAssertEqual(instruction.systemSettingsAnchor, "Privacy_Accessibility")
        XCTAssertTrue(instruction.supportsAppDrag)
        XCTAssertTrue(instruction.primaryText.contains("Drag Mac All You Need"))
        XCTAssertTrue(instruction.secondaryText.contains("Window Layouts"))
        XCTAssertTrue(instruction.secondaryText.contains("Window Grab"))
        XCTAssertTrue(instruction.secondaryText.contains("already appears"))
    }

    func testFullDiskAccessInstructionSupportsDraggingAppIntoSystemSettings() {
        let instruction = PermissionInstructionTarget.fullDiskAccess.instruction(appName: "Mac All You Need")

        XCTAssertEqual(instruction.systemSettingsAnchor, "Privacy_AllFiles")
        XCTAssertTrue(instruction.supportsAppDrag)
        XCTAssertTrue(instruction.primaryText.contains("Drag Mac All You Need"))
        XCTAssertTrue(instruction.secondaryText.contains("already appears"))
    }

    func testFullDiskAccessUsesFloatingDragInstructionPanel() {
        let instruction = PermissionInstructionTarget.fullDiskAccess.instruction(appName: "Mac All You Need")

        XCTAssertTrue(PermissionFloatingInstructionPresentation.shouldFloat(instruction))
        XCTAssertEqual(PermissionFloatingInstructionPresentation.arrowSymbol, "arrow.down.forward")
        XCTAssertGreaterThan(
            PermissionFloatingInstructionPresentation.windowLevel.rawValue,
            NSWindow.Level.floating.rawValue
        )
    }

    func testMicrophoneUsesFloatingDragInstructionPanel() {
        let instruction = PermissionInstructionTarget.microphone.instruction(appName: "Mac All You Need")

        XCTAssertTrue(PermissionFloatingInstructionPresentation.shouldFloat(instruction))
    }

    func testScreenRecordingInstructionSupportsDraggingAppIntoSystemSettings() {
        let instruction = PermissionInstructionTarget.screenRecording.instruction(appName: "Mac All You Need")

        XCTAssertEqual(instruction.systemSettingsAnchor, "Privacy_ScreenCapture")
        XCTAssertTrue(instruction.supportsAppDrag)
        XCTAssertTrue(instruction.primaryText.contains("Drag Mac All You Need"))
        XCTAssertTrue(PermissionFloatingInstructionPresentation.shouldFloat(instruction))
    }

    func testFloatingInstructionFrameAnchorsBelowSourceWindow() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let sourceWindowFrame = NSRect(x: 820, y: 420, width: 520, height: 420)

        let frame = PermissionFloatingInstructionPresentation.frame(
            in: visibleFrame,
            preferredWindowFrame: sourceWindowFrame
        )

        XCTAssertEqual(frame.midX, sourceWindowFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, sourceWindowFrame.minY - 12, accuracy: 0.5)
    }

    func testFloatingInstructionFrameStaysInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let sourceWindowFrame = NSRect(x: -200, y: 100, width: 220, height: 400)

        let frame = PermissionFloatingInstructionPresentation.frame(
            in: visibleFrame,
            preferredWindowFrame: sourceWindowFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX + 24)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX - 24)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY + 24)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY - 24)
    }

    func testFloatingInstructionFrameAnchorsBelowSystemSettingsQuartzBounds() {
        let mainScreenFrame = NSRect(x: 0, y: 0, width: 2560, height: 1440)
        let visibleFrame = NSRect(x: 0, y: 0, width: 2560, height: 1410)
        let systemSettingsBounds = CGRect(x: 421, y: 352, width: 723, height: 763)

        let sourceWindowFrame = PermissionFloatingInstructionPresentation.appKitFrame(
            fromQuartzBounds: systemSettingsBounds,
            mainScreenFrame: mainScreenFrame
        )
        let frame = PermissionFloatingInstructionPresentation.frame(
            belowQuartzBounds: systemSettingsBounds,
            mainScreenFrame: mainScreenFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(sourceWindowFrame.minY, 325, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, sourceWindowFrame.minY - 12, accuracy: 0.5)
    }

    func testMicrophoneInstructionSupportsAppDrag() {
        let instruction = PermissionInstructionTarget.microphone.instruction(appName: "Mac All You Need")

        XCTAssertEqual(instruction.systemSettingsAnchor, "Privacy_Microphone")
        XCTAssertTrue(instruction.supportsAppDrag)
        XCTAssertTrue(instruction.primaryText.contains("Drag Mac All You Need"))
    }

    func testNotificationInstructionHasSettingsAction() {
        let instruction = PermissionInstructionTarget.notifications.instruction(appName: "Mac All You Need")

        XCTAssertEqual(instruction.systemSettingsAnchor, "Notifications")
        XCTAssertEqual(PermissionInstructionPresentation.actionTitle(for: instruction), "Open Settings")
    }

    func testDefaultInstructionMovesPastGrantedRequiredPermissions() {
        XCTAssertEqual(
            PermissionInstructionTarget.defaultTarget(
                accessibilityStatus: .granted,
                microphoneStatus: .granted,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .optional
            ),
            .screenRecording
        )
    }

    func testInstructionStripIsHiddenUntilUserRequestsPermissionHelp() {
        XCTAssertNil(
            PermissionInstructionPresentation.visibleTarget(
                requestedTarget: nil,
                accessibilityStatus: .needsAction,
                microphoneStatus: .denied,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .optional
            )
        )
    }

    func testInstructionStripShowsClickedPermissionOnlyWhenItIsMissing() {
        XCTAssertEqual(
            PermissionInstructionPresentation.visibleTarget(
                requestedTarget: .fullDiskAccess,
                accessibilityStatus: .granted,
                microphoneStatus: .granted,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .granted
            ),
            .fullDiskAccess
        )

        XCTAssertEqual(
            PermissionInstructionPresentation.visibleTarget(
                requestedTarget: .microphone,
                accessibilityStatus: .granted,
                microphoneStatus: .denied,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .granted
            ),
            .microphone
        )
    }

    func testInstructionStripIsHiddenWhenRequestedPermissionIsGranted() {
        XCTAssertNil(
            PermissionInstructionPresentation.visibleTarget(
                requestedTarget: .accessibility,
                accessibilityStatus: .granted,
                microphoneStatus: .denied,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .optional
            )
        )

        XCTAssertNil(
            PermissionInstructionPresentation.visibleTarget(
                requestedTarget: .notifications,
                accessibilityStatus: .needsAction,
                microphoneStatus: .denied,
                screenRecordingStatus: .optional,
                fullDiskAccessStatus: .optional,
                notificationsStatus: .granted
            )
        )
    }
}
