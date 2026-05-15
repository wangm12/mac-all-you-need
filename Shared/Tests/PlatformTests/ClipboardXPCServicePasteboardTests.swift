@testable import Platform
import AppKit
import Core
import CryptoKit
import XCTest

final class ClipboardXPCServicePasteboardTests: XCTestCase {
    func testRestoreHTMLPublishesReadablePlainTextFlavor() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID())"))
        let blobs = BlobStore(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("blobs-\(UUID().uuidString)"),
            key: SymmetricKey(size: .bits256)
        )

        ClipboardXPCService.restoreToPasteboard(
            body: .html("<div style=\"font-family: monospace; white-space: pre;\">CODEX_AUTH_TOKEN=$(usso -ussh genai-api -print) open -n /Applications/Codex.app</div>"),
            blobs: blobs,
            pasteboard: pasteboard
        )

        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "CODEX_AUTH_TOKEN=$(usso -ussh genai-api -print) open -n /Applications/Codex.app"
        )
        XCTAssertNil(pasteboard.string(forType: PasteboardUTI.html))
    }
}
