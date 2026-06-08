import XCTest
@testable import MacAllYouNeed

final class DockPreviewDimensionEngineTests: XCTestCase {
    func testChunkArrayHorizontal() {
        let items = Array(0 ..< 5)
        let chunks = DockPreviewDimensionEngine.chunkArray(
            items: items,
            isHorizontal: true,
            maxColumns: 3,
            maxRows: 2
        )
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(chunks.flatMap { $0 }.count, 5)
    }

    func testOverallMaxDimensionsStayWithinCardCaps() {
        let settings = DockPreviewSettings.default
        let hugeThumb = NSImage(size: NSSize(width: 3840, height: 2160))
        let entry = DockPreviewWindowEntry(
            id: 1,
            pid: 1,
            title: "Big",
            frame: .zero,
            thumbnail: hugeThumb,
            isMinimized: false,
            isOnScreen: true
        )
        let overall = DockPreviewDimensionEngine.overallMaxDimensions(
            entries: [entry],
            dockEdge: .bottom,
            settings: settings,
            panelSize: CGSize(width: 4000, height: 3000)
        )
        let capW = CGFloat(settings.previewCardWidth) * DockPreviewDimensionEngine.dynamicMaxAspectRatio
        let capH = CGFloat(settings.previewCardHeight) * DockPreviewDimensionEngine.dynamicMaxAspectRatio
        XCTAssertLessThanOrEqual(overall.x, capW + 1)
        XCTAssertLessThanOrEqual(overall.y, capH + 1)
    }

    func testExpectedContentSizeNonZeroWithWindows() {
        var state = DockPreviewDimensionEngine.DimensionState(
            overallMax: CGPoint(x: 200, y: 120),
            perWindow: [0: DockPreviewWindowDimensions(
                size: CGSize(width: 200, height: 120),
                maxDimensions: CGSize(width: 200, height: 120)
            )],
            gridColumns: 2,
            gridRows: 1
        )
        let size = DockPreviewDimensionEngine.computeExpectedContentSize(
            dimensionState: state,
            windowCount: 1,
            dockEdge: .bottom,
            hasEmbedded: false,
            isWindowSwitcher: false,
            globalPaddingMultiplier: CGFloat(DockPreviewSettings.default.globalPaddingMultiplier)
        )
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }
}
