@testable import Platform
import XCTest

final class PasteboardChangeTests: XCTestCase {
    func testImageRepresentationsCollapseToSinglePNGHistoryItem() {
        let fileURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let change = PasteboardChange(
            changeCount: 1,
            frontmostAppBundleID: "com.test",
            items: [.png(Data([1])), .tiff(Data([2])), .fileURLs([fileURL])]
        )

        XCTAssertEqual(change.historyCaptureItems, [.png(Data([1]))])
    }

    func testImageRepresentationsUseTIFFWhenPNGIsUnavailable() {
        let fileURL = URL(fileURLWithPath: "/tmp/screenshot.tiff")
        let change = PasteboardChange(
            changeCount: 1,
            frontmostAppBundleID: "com.test",
            items: [.tiff(Data([2])), .fileURLs([fileURL])]
        )

        XCTAssertEqual(change.historyCaptureItems, [.tiff(Data([2]))])
    }

    func testNonImageChangesKeepExistingRepresentations() {
        let fileURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let change = PasteboardChange(
            changeCount: 1,
            frontmostAppBundleID: "com.test",
            items: [.text("hello"), .fileURLs([fileURL])]
        )

        XCTAssertEqual(change.historyCaptureItems, [.text("hello"), .fileURLs([fileURL])])
    }
}
