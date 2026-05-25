@testable import MacAllYouNeed
import XCTest

/// Pins the ordered popover identifier list and the typename per identifier
/// for `AppMenuBarContent.Tab`. Any rename or reorder will fail here first.
final class MenuBarPopoverRegistryTests: XCTestCase {

    func testTabOrderAndRawValues() {
        let expected: [AppMenuBarContent.Tab] = [
            .clipboard,
            .voice,
            .downloads,
            .layouts,
            .snippets,
        ]
        XCTAssertEqual(AppMenuBarContent.Tab.allCases, expected,
            "Tab order or membership changed — update split files and this test.")
    }

    func testTabRawValues() {
        XCTAssertEqual(AppMenuBarContent.Tab.clipboard.rawValue, "Clipboard")
        XCTAssertEqual(AppMenuBarContent.Tab.voice.rawValue, "Voice")
        XCTAssertEqual(AppMenuBarContent.Tab.downloads.rawValue, "Downloads")
        XCTAssertEqual(AppMenuBarContent.Tab.layouts.rawValue, "Layouts")
        XCTAssertEqual(AppMenuBarContent.Tab.snippets.rawValue, "Snippets")
    }

    func testTabSymbolNames() {
        XCTAssertEqual(AppMenuBarContent.Tab.clipboard.symbolName, "doc.on.clipboard")
        XCTAssertEqual(AppMenuBarContent.Tab.voice.symbolName, "waveform")
        XCTAssertEqual(AppMenuBarContent.Tab.downloads.symbolName, "arrow.down.circle")
        XCTAssertEqual(AppMenuBarContent.Tab.layouts.symbolName, "rectangle.3.group")
        XCTAssertEqual(AppMenuBarContent.Tab.snippets.symbolName, "text.quote")
    }

    func testFooterModelClipboardShowsCapturePause() {
        let model = CommandCenterFooterPresentation.model(for: .clipboard)
        XCTAssertTrue(model.showsCapturePause)
        XCTAssertEqual(model.shortcutText, "⌘⇧V")
        XCTAssertEqual(model.openButtonTitle, "Open Clipboard")
    }

    func testFooterModelOtherTabsDoNotShowCapturePause() {
        for tab in [AppMenuBarContent.Tab.voice, .downloads, .layouts, .snippets] {
            let model = CommandCenterFooterPresentation.model(for: tab)
            XCTAssertFalse(model.showsCapturePause, "Tab \(tab.rawValue) must not show Pause")
        }
    }

    func testFooterModelDownloadsHasNoShortcut() {
        let model = CommandCenterFooterPresentation.model(for: .downloads)
        XCTAssertNil(model.shortcutText)
    }

    func testFooterModelSnippetsHasNoShortcut() {
        let model = CommandCenterFooterPresentation.model(for: .snippets)
        XCTAssertNil(model.shortcutText)
    }
}
