@testable import MacAllYouNeed
import AppKit
import XCTest

enum TestImageFactory {
    static func cgImage(text: String, size: CGSize) -> CGImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 36), .foregroundColor: NSColor.black]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(at: .init(x: 10, y: size.height / 2 - 20))
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    static func solid(_ color: NSColor, size: CGSize) -> CGImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }
}

final class ImageOCRServiceTests: XCTestCase {
    func testRecognizesRenderedText() async throws {
        let cg = TestImageFactory.cgImage(text: "INVOICE 42", size: .init(width: 400, height: 120))
        let result = await ImageOCRService.shared.recognize(cgImage: cg)
        XCTAssertTrue((result ?? "").uppercased().contains("INVOICE"))
    }

    func testEmptyImageReturnsNilOrEmpty() async throws {
        let cg = TestImageFactory.solid(.white, size: .init(width: 64, height: 64))
        let result = await ImageOCRService.shared.recognize(cgImage: cg)
        XCTAssertTrue((result ?? "").isEmpty)
    }

    func testDownsampleCapApplied() {
        XCTAssertEqual(ImageOCRService.downsampledMaxDimension(forLongestSide: 16384), 8192)
        XCTAssertEqual(ImageOCRService.downsampledMaxDimension(forLongestSide: 4000), 4000)
    }
}
