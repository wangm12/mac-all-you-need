@testable import Platform
import XCTest

final class PasteboardObserverTests: XCTestCase {
    final class FakeReader: PasteboardReading {
        var changeCount: Int = 0
        var types: [String] = []
        var items: [PasteboardItem] = []
        var frontmost: String? = "com.test"
        func currentChangeCount() -> Int {
            changeCount
        }

        func currentTypes() -> [String] {
            types
        }

        func currentItems() -> [PasteboardItem] {
            items
        }

        func frontmostBundleID() -> String? {
            frontmost
        }
    }

    func testEmitsOnlyOnChange() {
        let reader = FakeReader()
        let obs = PasteboardObserver(reader: reader, rules: ExclusionRules(), pollInterval: 0.05)
        var changes: [PasteboardChange] = []
        let exp1 = expectation(description: "first change")
        obs.start {
            changes.append($0)
            exp1.fulfill()
        }
        defer { obs.stop() }

        reader.changeCount = 1
        reader.types = ["public.utf8-plain-text"]
        reader.items = [.text("hello")]
        wait(for: [exp1], timeout: 1)

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.items, [.text("hello")])
    }

    func testDoesNotEmitExistingClipboardOnStart() {
        let reader = FakeReader()
        reader.changeCount = 7
        reader.types = ["public.utf8-plain-text"]
        reader.items = [.text("already there")]
        let obs = PasteboardObserver(reader: reader, rules: ExclusionRules(), pollInterval: 0.05)
        var changes: [PasteboardChange] = []
        let inverted = expectation(description: "initial clipboard should be treated as baseline")
        inverted.isInverted = true
        obs.start {
            changes.append($0)
            inverted.fulfill()
        }
        defer { obs.stop() }

        wait(for: [inverted], timeout: 0.2)

        XCTAssertEqual(changes.count, 0)
    }

    func testFiltersConcealed() {
        let reader = FakeReader()
        let obs = PasteboardObserver(reader: reader, rules: ExclusionRules(), pollInterval: 0.05)
        var changes: [PasteboardChange] = []
        let inverted = expectation(description: "concealed clipboard should not emit")
        inverted.isInverted = true
        obs.start {
            changes.append($0)
            inverted.fulfill()
        }
        defer { obs.stop() }

        reader.changeCount = 5
        reader.types = ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"]
        reader.items = [.text("password")]
        wait(for: [inverted], timeout: 0.2)

        XCTAssertEqual(changes.count, 0)
    }
}
