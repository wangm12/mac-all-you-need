@testable import MacAllYouNeed
import Core
import XCTest

final class DockItemSmartTextTests: XCTestCase {
    private func item(detectedType: DetectedType?, calculation: CalculationResult? = nil,
                      linkClean: LinkCleanResult? = nil, ocrText: String? = nil,
                      preview: String = "x") -> DockItem {
        let json: String?
        if let detectedType {
            json = try? Detection(type: detectedType, calculation: calculation, linkClean: linkClean).encodedJSON()
        } else {
            json = nil
        }
        let meta = ClipboardXPCMeta(
            id: "1", modified: Date(), kind: "clipboardItem", preview: preview,
            detectedTypeJSON: json, ocrText: ocrText
        )
        return DockItem(from: meta, sourceApp: nil, isPinned: false)
    }

    func testCalculationExposed() {
        let calc = CalculationResult(expression: "2+2", value: "4")
        let it = item(detectedType: .plain, calculation: calc)
        XCTAssertEqual(it.calculation?.value, "4")
    }

    func testNoCalculationWhenAbsent() {
        XCTAssertNil(item(detectedType: .plain).calculation)
    }

    func testTrackerCount() {
        let link = LinkCleanResult(cleaned: "https://x.com/", removedCount: 2, original: "https://x.com/?utm_source=a&fbclid=b")
        let it = item(detectedType: .url, linkClean: link)
        XCTAssertEqual(it.trackerCount, 2)
    }

    func testTrackerCountZeroWhenNoLink() {
        XCTAssertEqual(item(detectedType: .url).trackerCount, 0)
    }

    func testHasOCRText() {
        XCTAssertTrue(item(detectedType: nil, ocrText: "scanned").hasOCRText)
        XCTAssertFalse(item(detectedType: nil, ocrText: "").hasOCRText)
        XCTAssertFalse(item(detectedType: nil, ocrText: nil).hasOCRText)
    }

    func testDetectedTypeName() {
        XCTAssertEqual(item(detectedType: .url).detectedTypeName, "url")
        XCTAssertEqual(item(detectedType: .code(language: .swift)).detectedTypeName, "code")
        XCTAssertNil(item(detectedType: nil).detectedTypeName)
    }

    func testPopoverQueryTypeFilter() {
        let url = ClipboardItemMeta(
            id: RecordID.generate(), created: Date(), modified: Date(),
            deviceID: DeviceID.generate(), lamport: 1, kind: .clipboardItem,
            preview: "https://a.com", sourceAppBundleID: nil, frequency: 0, lastAccessed: nil,
            detectedTypeJSON: try? Detection(type: .url).encodedJSON()
        )
        let plain = ClipboardItemMeta(
            id: RecordID.generate(), created: Date(), modified: Date(),
            deviceID: DeviceID.generate(), lamport: 2, kind: .clipboardItem,
            preview: "note", sourceAppBundleID: nil, frequency: 0, lastAccessed: nil,
            detectedTypeJSON: try? Detection(type: .plain).encodedJSON()
        )
        let result = LocalClipboardReader.applyQuery("/type:url", to: [url, plain])
        XCTAssertEqual(result.map { $0.preview }, ["https://a.com"])
    }
}
