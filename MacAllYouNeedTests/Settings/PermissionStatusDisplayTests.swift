@testable import MacAllYouNeed
import AVFoundation
import XCTest

final class PermissionStatusDisplayTests: XCTestCase {
    func testMicrophoneAuthorizationMapsToDisplayStates() {
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.authorized), .granted)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.notDetermined), .notRequested)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.denied), .denied)
        XCTAssertEqual(PermissionStatusProvider.microphoneStatus(.restricted), .denied)
    }

    func testBooleanPermissionMapsToGrantedOrNeedsAction() {
        XCTAssertEqual(PermissionStatusProvider.requiredPermission(isGranted: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.requiredPermission(isGranted: false), .needsAction)
    }

    func testOptionalPermissionKeepsOptionalWhenUnavailable() {
        XCTAssertEqual(PermissionStatusProvider.optionalPermission(isGranted: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.optionalPermission(isGranted: false), .optional)
    }

    func testFullDiskAccessIsOptionalUntilExplicitlyChecked() {
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: nil), .optional)
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: true), .granted)
        XCTAssertEqual(PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: false), .optional)
    }
}
