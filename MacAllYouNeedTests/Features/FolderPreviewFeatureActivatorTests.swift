import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FolderPreviewFeatureActivatorTests: XCTestCase {
    func testActivateRegistersBrowseFolderHotkey() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(await activator.isHotkeyRegistered)
        try await activator.deactivate()
        XCTAssertFalse(await activator.isHotkeyRegistered)
    }

    func testIdempotency() async throws {
        let activator = FolderPreviewFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()
        XCTAssertTrue(await activator.isHotkeyRegistered)
        try await activator.deactivate()
        try await activator.deactivate()
        XCTAssertFalse(await activator.isHotkeyRegistered)
    }
}
