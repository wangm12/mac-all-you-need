import XCTest
@testable import MacAllYouNeed

@MainActor
final class DockPreviewDockMouseTests: XCTestCase {
    func testIsCrossAppDockSwitchByPID() {
        XCTAssertTrue(
            DockPreviewDockMouse.isCrossAppDockSwitch(
                displayedPID: 1884,
                targetPID: 1853,
                displayedBundleID: nil,
                targetBundleID: nil
            )
        )
    }

    func testIsCrossAppDockSwitchByBundleWhenPIDMissing() {
        XCTAssertTrue(
            DockPreviewDockMouse.isCrossAppDockSwitch(
                displayedPID: nil,
                targetPID: 1853,
                displayedBundleID: "com.tinyspeck.slackmacgap",
                targetBundleID: "com.todesktop.cursor"
            )
        )
    }

    func testShouldIgnoreDockHoverChangeWhenMouseInPreviewSameApp() {
        XCTAssertTrue(
            DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: true,
                mouseIsWithinPreview: true,
                panelFrame: CGRect(x: 100, y: 200, width: 300, height: 180),
                folderFrame: nil,
                currentToken: 1,
                newToken: 2,
                currentPID: 100,
                newPID: 100,
                currentBundleID: "com.example.app",
                newBundleID: "com.example.app"
            )
        )
    }

    func testShouldNotIgnoreDifferentAppWhileOnPreview() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: true,
                mouseIsWithinPreview: true,
                panelFrame: CGRect(x: 100, y: 200, width: 300, height: 180),
                folderFrame: nil,
                currentToken: 1,
                newToken: 2,
                currentPID: 1884,
                newPID: 1853,
                currentBundleID: "com.tinyspeck.slackmacgap",
                newBundleID: "com.todesktop.cursor"
            )
        )
    }

    func testShouldNotIgnoreDifferentAppByBundleWhenPIDNil() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: true,
                mouseIsWithinPreview: true,
                panelFrame: CGRect(x: 100, y: 200, width: 300, height: 180),
                folderFrame: nil,
                currentToken: 1,
                newToken: 2,
                currentPID: nil,
                newPID: 1853,
                currentBundleID: "com.tinyspeck.slackmacgap",
                newBundleID: "com.todesktop.cursor"
            )
        )
    }

    func testShouldNotIgnoreWhenNotOnPreview() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: true,
                mouseIsWithinPreview: false,
                panelFrame: CGRect(x: 5000, y: 5000, width: 100, height: 100),
                folderFrame: nil,
                currentToken: 1,
                newToken: 2,
                currentPID: 100,
                newPID: 200,
                currentBundleID: "com.example.a",
                newBundleID: "com.example.b"
            )
        )
    }

    func testShouldNotIgnoreWhenSameToken() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldIgnoreDockHoverChange(
                panelVisible: true,
                mouseIsWithinPreview: true,
                panelFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                folderFrame: nil,
                currentToken: 42,
                newToken: 42,
                currentPID: 100,
                newPID: 200,
                currentBundleID: "com.example.a",
                newBundleID: "com.example.b"
            )
        )
    }

    func testShouldAbsorbSameAppDockTokenChurnOnDockBand() {
        XCTAssertTrue(
            DockPreviewDockMouse.shouldAbsorbSameAppDockTokenChurn(
                panelVisible: true,
                mouseIsWithinPreview: false,
                pointerInDockRegion: true,
                currentPID: 95186,
                newPID: 95186,
                currentToken: 1,
                newToken: 2
            )
        )
    }

    func testShouldNotAbsorbCrossAppTokenChurn() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldAbsorbSameAppDockTokenChurn(
                panelVisible: true,
                mouseIsWithinPreview: false,
                pointerInDockRegion: true,
                currentPID: 95186,
                newPID: 1864,
                currentToken: 1,
                newToken: 2
            )
        )
    }

    func testShouldAllowInstantDockSwitchWhenBundleMatches() {
        XCTAssertTrue(
            DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                mouseIsWithinPreview: false,
                onPreviewSurface: false,
                pointerInDockRegion: false,
                targetBundleID: "com.example.app",
                targetPID: 100,
                hoveredBundleID: "com.example.app",
                hoveredPID: 100,
                displayedPID: nil,
                crossAppSwitch: false
            )
        )
    }

    func testShouldAllowInstantDockSwitchOnDockBandDespitePreviewOverlap() {
        XCTAssertTrue(
            DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                mouseIsWithinPreview: false,
                onPreviewSurface: true,
                pointerInDockRegion: true,
                targetBundleID: "com.google.Chrome.canary",
                targetPID: 95186,
                hoveredBundleID: "com.google.Chrome.canary",
                hoveredPID: 95186,
                displayedPID: 95186,
                crossAppSwitch: false
            )
        )
    }

    func testShouldAllowCrossAppInstantSwitchOnPreviewEvenWhenAXHoverLags() {
        XCTAssertTrue(
            DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                mouseIsWithinPreview: true,
                onPreviewSurface: true,
                pointerInDockRegion: false,
                targetBundleID: "com.todesktop.cursor",
                targetPID: 1853,
                hoveredBundleID: "com.tinyspeck.slackmacgap",
                hoveredPID: 1884,
                displayedPID: 1884,
                crossAppSwitch: true
            )
        )
    }

    func testShouldBlockInstantDockSwitchOnPreviewSurfaceSameApp() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                mouseIsWithinPreview: false,
                onPreviewSurface: true,
                pointerInDockRegion: false,
                targetBundleID: "com.example.app",
                targetPID: 100,
                hoveredBundleID: "com.example.app",
                hoveredPID: 100,
                displayedPID: 100,
                crossAppSwitch: false
            )
        )
    }

    func testShouldBlockInstantDockSwitchWhenBundleDiffers() {
        XCTAssertFalse(
            DockPreviewDockMouse.shouldAllowInstantDockSwitch(
                mouseIsWithinPreview: false,
                onPreviewSurface: false,
                pointerInDockRegion: false,
                targetBundleID: "com.example.a",
                targetPID: 100,
                hoveredBundleID: "com.example.b",
                hoveredPID: 200,
                displayedPID: nil,
                crossAppSwitch: false
            )
        )
    }
}
