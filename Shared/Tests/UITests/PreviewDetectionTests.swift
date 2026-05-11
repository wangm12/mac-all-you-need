@testable import UI
import XCTest

final class PreviewDetectionTests: XCTestCase {
    func testDetectsHexColor() {
        if case .color = PreviewDetection.detect("#FF8800") { return }
        XCTFail("expected color")
    }

    func testDetectsURL() {
        if case .url = PreviewDetection.detect("https://example.com") { return }
        XCTFail("expected url")
    }

    func testDetectsCode() {
        if case .code = PreviewDetection.detect("func foo() { return 1 }") { return }
        XCTFail("expected code")
    }

    func testDetectsPlain() {
        if case .plain = PreviewDetection.detect("hello world") { return }
        XCTFail("expected plain")
    }

    func testRejectsInvalidHex() {
        if case .color = PreviewDetection.detect("#XYZ") {
            XCTFail("should not detect color")
            return
        }
    }
}
