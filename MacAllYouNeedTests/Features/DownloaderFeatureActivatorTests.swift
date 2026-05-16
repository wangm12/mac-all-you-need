import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class DownloaderFeatureActivatorTests: XCTestCase {
    func testActivateStartsCoordinatorAndDispatchServer() async throws {
        let activator = DownloaderFeatureActivator(testMode: true)
        try await activator.activate()
        XCTAssertTrue(activator.isCoordinatorRunning)
        XCTAssertTrue(activator.isDispatchServerRunning)
        try await activator.deactivate()
        XCTAssertFalse(activator.isCoordinatorRunning)
        XCTAssertFalse(activator.isDispatchServerRunning)
    }

    func testActivateIsIdempotent() async throws {
        let activator = DownloaderFeatureActivator(testMode: true)
        try await activator.activate()
        try await activator.activate()   // second call must not crash or double-start
        XCTAssertTrue(activator.isCoordinatorRunning)
        try await activator.deactivate()
    }

    func testDeactivateIsIdempotent() async throws {
        let activator = DownloaderFeatureActivator(testMode: true)
        try await activator.deactivate()   // already inactive — must not crash
        XCTAssertFalse(activator.isCoordinatorRunning)
        XCTAssertFalse(activator.isDispatchServerRunning)
    }

    func testAssetPackProbeMissingDirectory() {
        let result = DownloaderFeatureActivator.assetPackProbe(
            packDir: URL(fileURLWithPath: "/nonexistent")
        )
        XCTAssertFalse(result, "missing pack must fail probe")
    }

    func testAssetPackProbePresentDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloaderFeatureActivatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Missing both binaries → false
        XCTAssertFalse(DownloaderFeatureActivator.assetPackProbe(packDir: tmp))

        // Create yt-dlp only → still false
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("yt-dlp").path, contents: nil)
        XCTAssertFalse(DownloaderFeatureActivator.assetPackProbe(packDir: tmp))

        // Create ffmpeg too → true
        FileManager.default.createFile(atPath: tmp.appendingPathComponent("ffmpeg").path, contents: nil)
        XCTAssertTrue(DownloaderFeatureActivator.assetPackProbe(packDir: tmp))
    }
}
