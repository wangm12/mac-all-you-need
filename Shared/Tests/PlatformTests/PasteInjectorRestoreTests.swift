import AppKit
@testable import Platform
import XCTest

final class PasteInjectorRestoreTests: XCTestCase {
    func testPasteWithRestoreRestoresPreviousString() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("restore-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        _ = await PasteInjector.pasteWithRestore("voice text", into: pasteboard, restoreDelay: .milliseconds(1))

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }

    func testManualFallbackCanLeaveVoiceTextOnPasteboard() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("manual-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let outcome = await PasteInjector.pasteWithRestore(
            "voice text",
            into: pasteboard,
            restoreDelay: .milliseconds(1),
            restoreOnManualPasteRequired: false
        )

        if outcome.result == .manualPasteRequired {
            XCTAssertFalse(outcome.restoredPasteboard)
            XCTAssertEqual(pasteboard.string(forType: .string), "voice text")
        }
    }
}
