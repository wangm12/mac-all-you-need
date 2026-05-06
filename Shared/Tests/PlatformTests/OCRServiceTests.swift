import AppKit
@testable import Platform
import XCTest

final class OCRServiceTests: XCTestCase {
    func testRecognizesTextInGeneratedImage() async throws {
        let image = renderImage(text: "HELLO MAYN")
        let png = try XCTUnwrap(image.pngData())
        let recognized = try await OCRService.recognize(pngData: png)
        XCTAssertTrue(recognized.uppercased().contains("HELLO"))
    }

    private func renderImage(text: String) -> NSImage {
        let size = NSSize(width: 400, height: 100)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: NSPoint(x: 10, y: 20), withAttributes: attrs)
        img.unlockFocus()
        return img
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
