@testable import Platform
import AppKit
import XCTest

final class ThumbnailRendererTests: XCTestCase {
    private func makePNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testReturnsNilForUnreadableData() {
        XCTAssertNil(ThumbnailRenderer.render(data: Data([0xDE, 0xAD]), maxDim: 100))
    }

    func testZeroMaxDimReturnsOriginalDataPassthrough() {
        let png = makePNG(width: 50, height: 50)
        let out = ThumbnailRenderer.render(data: png, maxDim: 0)
        XCTAssertEqual(out, png)
    }

    func testLandscapeImageResizedToMaxDimOnLongestEdge() {
        let png = makePNG(width: 800, height: 400)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 200)!
        let img = NSImage(data: jpeg)!
        XCTAssertEqual(Int(img.size.width), 200)
        XCTAssertEqual(Int(img.size.height), 100)
    }

    func testPortraitImageResizedToMaxDimOnLongestEdge() {
        let png = makePNG(width: 300, height: 900)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 300)!
        let img = NSImage(data: jpeg)!
        XCTAssertEqual(Int(img.size.height), 300)
        XCTAssertEqual(Int(img.size.width), 100)
    }

    func testReturnsJPEGBytes() {
        let png = makePNG(width: 64, height: 64)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 32)!
        XCTAssertEqual(jpeg.prefix(2), Data([0xFF, 0xD8]))
    }

    func testSmallImageNotUpscaled() {
        let png = makePNG(width: 50, height: 50)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 200)!
        let img = NSImage(data: jpeg)!
        XCTAssertLessThanOrEqual(Int(img.size.width), 50)
        XCTAssertLessThanOrEqual(Int(img.size.height), 50)
    }
}
