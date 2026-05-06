import AppKit
@testable import Platform
import XCTest

final class PasteInjectorTests: XCTestCase {
    func testPlainTextModeStripsRichPasteboardRepresentations() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasteInjectorTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("<b>Hello</b>", forType: .html)
        pasteboard.setString("Hello", forType: .string)

        _ = PasteInjector.paste(nil, mode: .plainText, into: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")
        XCTAssertNil(pasteboard.string(forType: .html))
    }
}
