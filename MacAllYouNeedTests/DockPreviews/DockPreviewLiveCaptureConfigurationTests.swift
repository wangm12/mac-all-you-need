import XCTest
@testable import MacAllYouNeed

final class DockPreviewLiveCaptureConfigurationTests: XCTestCase {
    func testDockHoverUsesAdvancedQualityAndFrameRate() {
        var hub = DockHubSettings.default
        hub.advanced.dockLivePreviewQuality = .retina
        hub.advanced.dockLivePreviewFrameRate = .fps15
        hub.advanced.livePreviewStreamKeepAlive = 5

        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: .dockHover)

        XCTAssertEqual(config.streamWidth, 480)
        XCTAssertEqual(config.streamHeight, 300)
        XCTAssertEqual(config.frameRate, 15)
        XCTAssertEqual(config.keepAliveSec, 5)
        XCTAssertEqual(config.queueDepth, 5)
        XCTAssertFalse(config.enableHDR)
    }

    func testDockHoverHighQualityUsesDeeperQueue() {
        var hub = DockHubSettings.default
        hub.advanced.dockLivePreviewQuality = .standard

        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: .dockHover)

        XCTAssertEqual(config.queueDepth, 3)
    }

    func testEnableHDRWhenAdvancedToggleOn() {
        var hub = DockHubSettings.default
        hub.advanced.enableHDRLivePreview = true

        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: .dockHover)

        XCTAssertTrue(config.enableHDR)
    }

    func testSwitcherUsesSwitcherAdvancedSettings() {
        var hub = DockHubSettings.default
        hub.advanced.switcherLivePreviewQuality = .low
        hub.advanced.switcherLivePreviewFrameRate = .fps10

        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: .windowSwitcher)

        XCTAssertEqual(config.streamWidth, 240)
        XCTAssertEqual(config.frameRate, 10)
    }
}
