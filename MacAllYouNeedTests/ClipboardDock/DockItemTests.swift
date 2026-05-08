@testable import MacAllYouNeed
import Core
import XCTest

final class DockItemTests: XCTestCase {
    func testDeriveKindFromImageMeta() {
        let meta = ClipboardXPCMeta(
            id: "1",
            modified: Date(),
            kind: "clipboardItem",
            preview: "(image 32x32)",
            imageWidth: 32,
            imageHeight: 32,
            imageBlobID: "blob1"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .image(w, h, blobID) = item.kind else {
            XCTFail("expected image kind")
            return
        }
        XCTAssertEqual(w, 32)
        XCTAssertEqual(h, 32)
        XCTAssertEqual(blobID, "blob1")
    }

    func testDeriveKindFromTextWithURLPreview() {
        let meta = ClipboardXPCMeta(
            id: "2",
            modified: Date(),
            kind: "clipboardItem",
            preview: "https://example.com"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        guard case let .link(url) = item.kind else {
            XCTFail("expected link")
            return
        }
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testDeriveKindFromTextWithColorPreview() {
        let meta = ClipboardXPCMeta(
            id: "3",
            modified: Date(),
            kind: "clipboardItem",
            preview: "#ABCDEF"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .color = item.kind { return }
        XCTFail("expected color")
    }

    func testDeriveKindFromTextDefaultsToText() {
        let meta = ClipboardXPCMeta(
            id: "4",
            modified: Date(),
            kind: "clipboardItem",
            preview: "hello world"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .text = item.kind { return }
        XCTFail("expected text")
    }

    func testFilesPreviewYieldsFileKind() {
        let meta = ClipboardXPCMeta(
            id: "5",
            modified: Date(),
            kind: "clipboardItem",
            preview: "(2 files)"
        )
        let item = DockItem(from: meta, sourceApp: nil, isPinned: false)
        if case .file = item.kind { return }
        XCTFail("expected file")
    }
}
