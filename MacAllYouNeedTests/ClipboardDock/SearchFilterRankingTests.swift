@testable import MacAllYouNeed
import Core
import XCTest

final class SearchFilterRankingTests: XCTestCase {
    private func item(
        id: String,
        preview: String,
        bundleID: String? = nil,
        detectedType: DetectedType? = nil,
        ocrText: String? = nil,
        modified: Date = Date()
    ) -> DockItem {
        let json = detectedType.flatMap { try? Detection(type: $0).encodedJSON() }
        let meta = ClipboardXPCMeta(
            id: id,
            modified: modified,
            kind: "clipboardItem",
            preview: preview,
            sourceAppBundleID: bundleID,
            detectedTypeJSON: json,
            ocrText: ocrText
        )
        let app = bundleID.map { SourceApp(bundleID: $0, displayName: $0, icon: nil) }
        return DockItem(from: meta, sourceApp: app, isPinned: false)
    }

    func testTypeFilter() {
        let items = [
            item(id: "1", preview: "https://a.com", detectedType: .url),
            item(id: "2", preview: "user@x.com", detectedType: .email),
            item(id: "3", preview: "plain note", detectedType: .plain)
        ]
        let q = SmartSearchQuery("/type:url")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testTypeFilterOR() {
        let items = [
            item(id: "1", preview: "https://a.com", detectedType: .url),
            item(id: "2", preview: "user@x.com", detectedType: .email),
            item(id: "3", preview: "plain", detectedType: .plain)
        ]
        let q = SmartSearchQuery("/type:url /type:email")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(Set(result.map(\.id)), ["1", "2"])
    }

    func testAppFilter() {
        let items = [
            item(id: "1", preview: "a", bundleID: "com.apple.Safari"),
            item(id: "2", preview: "b", bundleID: "com.tinyspeck.slackmacgap")
        ]
        let q = SmartSearchQuery("/app:safari")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testNegatedAppFilter() {
        let items = [
            item(id: "1", preview: "a", bundleID: "com.apple.Safari"),
            item(id: "2", preview: "b", bundleID: "com.tinyspeck.slackmacgap")
        ]
        let q = SmartSearchQuery("-/app:slack")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testRegexFilter() {
        let items = [
            item(id: "1", preview: "invoice 42"),
            item(id: "2", preview: "invoice 99")
        ]
        let q = SmartSearchQuery("/inv.*42/")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testRegexSearchesOCR() {
        let items = [
            item(id: "1", preview: "(image 10×10)", ocrText: "RECEIPT total"),
            item(id: "2", preview: "(image 10×10)", ocrText: "menu")
        ]
        let q = SmartSearchQuery("/receipt/")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }

    func testDateFilter() {
        let cal = Calendar.current
        let old = cal.date(byAdding: .day, value: -10, to: Date())!
        let recent = Date()
        let items = [
            item(id: "old", preview: "x", modified: old),
            item(id: "new", preview: "x", modified: recent)
        ]
        let q = SmartSearchQuery("/date:1d")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["new"])
    }

    func testCombinedAppAndText() {
        let items = [
            item(id: "1", preview: "meeting notes", bundleID: "com.apple.Notes"),
            item(id: "2", preview: "shopping list", bundleID: "com.apple.Notes"),
            item(id: "3", preview: "meeting notes", bundleID: "com.apple.Safari")
        ]
        let q = SmartSearchQuery("/app:notes meeting")
        let result = SearchFilterSubModel.applySmartPredicates(items, query: q)
        XCTAssertEqual(result.map(\.id), ["1"])
    }
}
