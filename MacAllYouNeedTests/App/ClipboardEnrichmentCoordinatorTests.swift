@testable import MacAllYouNeed
import AppKit
import Core
import CryptoKit
import XCTest

@MainActor
final class ClipboardEnrichmentCoordinatorTests: XCTestCase {
    private var dir: URL!
    private var clip: ClipboardStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Enrich-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        clip = try! ClipboardStore(database: db, deviceKey: SymmetricKey(size: .bits256), deviceID: DeviceID.generate())
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testEmbedsTextRecords() async throws {
        let item = try clip.append(.text("semantic content"))
        var embedCalls = 0
        let coord = ClipboardEnrichmentCoordinator(
            clip: clip,
            embed: { _ in embedCalls += 1; return [0.1, 0.2, 0.3] },
            ocr: { _ in nil },
            isEnabled: { true },
            isSemanticEnabled: { true },
            isOCREnabled: { false }
        )
        await coord.runOneBatch(limit: 10)

        XCTAssertGreaterThan(embedCalls, 0)
        let meta = try XCTUnwrap(clip.meta(for: item.id))
        XCTAssertEqual(ClipEmbeddingService.decode(meta.embedding ?? Data()), [0.1, 0.2, 0.3])
    }

    func testDisabledFeatureSkipsEverything() async throws {
        let item = try clip.append(.text("content"))
        let coord = ClipboardEnrichmentCoordinator(
            clip: clip,
            embed: { _ in [1] },
            ocr: { _ in "x" },
            isEnabled: { false },
            isSemanticEnabled: { true },
            isOCREnabled: { true }
        )
        await coord.runOneBatch(limit: 10)
        let meta = try XCTUnwrap(clip.meta(for: item.id))
        XCTAssertNil(meta.embedding)
    }

    func testSemanticDisabledSkipsEmbedding() async throws {
        let item = try clip.append(.text("content"))
        let coord = ClipboardEnrichmentCoordinator(
            clip: clip,
            embed: { _ in [1] },
            ocr: { _ in nil },
            isEnabled: { true },
            isSemanticEnabled: { false },
            isOCREnabled: { false }
        )
        await coord.runOneBatch(limit: 10)
        let meta = try XCTUnwrap(clip.meta(for: item.id))
        XCTAssertNil(meta.embedding)
    }

    func testOCRPersistsAndIndexes() async throws {
        let img = try clip.append(.image(blobID: "b1", width: 10, height: 10))
        var indexed: [(RecordID, String)] = []
        let cg = TestImageFactory.solid(.white, size: .init(width: 8, height: 8))
        let coord = ClipboardEnrichmentCoordinator(
            clip: clip,
            embed: { _ in nil },
            ocr: { _ in "extracted text" },
            imageProvider: { _ in cg },
            indexSearchText: { id, text in indexed.append((id, text)) },
            isEnabled: { true },
            isSemanticEnabled: { false },
            isOCREnabled: { true }
        )
        await coord.runOneBatch(limit: 10)

        let meta = try XCTUnwrap(clip.meta(for: img.id))
        XCTAssertEqual(meta.ocrText, "extracted text")
        XCTAssertEqual(indexed.count, 1)
        XCTAssertEqual(indexed.first?.1, "extracted text")
    }

    func testOCREmptyResultStillMarksProcessed() async throws {
        let img = try clip.append(.image(blobID: "b1", width: 10, height: 10))
        let cg = TestImageFactory.solid(.white, size: .init(width: 8, height: 8))
        let coord = ClipboardEnrichmentCoordinator(
            clip: clip,
            embed: { _ in nil },
            ocr: { _ in nil },
            imageProvider: { _ in cg },
            isEnabled: { true },
            isSemanticEnabled: { false },
            isOCREnabled: { true }
        )
        await coord.runOneBatch(limit: 10)
        // ocr_text is now "" (not nil), so the next pass won't re-select it.
        let remaining = try clip.idsMissingOCR(limit: 10)
        XCTAssertFalse(remaining.contains(img.id))
    }
}
