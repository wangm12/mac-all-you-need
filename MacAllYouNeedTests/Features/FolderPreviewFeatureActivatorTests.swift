import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FolderPreviewFeatureActivatorTests: XCTestCase {
    func testActivateLeavesBrowseFolderHotkeyOwnedByAppRegistry() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        let isRegisteredAfterActivate = await activator.isHotkeyRegistered
        XCTAssertFalse(isRegisteredAfterActivate)
        try await activator.deactivate()
        let isRegisteredAfterDeactivate = await activator.isHotkeyRegistered
        XCTAssertFalse(isRegisteredAfterDeactivate)
    }

    func testIdempotency() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()
        let isRegisteredAfterActivate = await activator.isHotkeyRegistered
        XCTAssertFalse(isRegisteredAfterActivate)
        try await activator.deactivate()
        try await activator.deactivate()
        let isRegisteredAfterDeactivate = await activator.isHotkeyRegistered
        XCTAssertFalse(isRegisteredAfterDeactivate)
    }
}
