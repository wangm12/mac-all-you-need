import XCTest
@testable import PackPipeline

final class PackDownloaderTests: XCTestCase {
    func testDownloadsLocalFile() async throws {
        let fm = FileManager.default
        let payload = Data(repeating: 0x42, count: 50_000)
        let src = fm.temporaryDirectory.appendingPathComponent("dl-src-\(UUID()).bin")
        try payload.write(to: src)
        defer { try? fm.removeItem(at: src) }

        let dst = fm.temporaryDirectory.appendingPathComponent("dl-dst-\(UUID()).bin")
        defer { try? fm.removeItem(at: dst) }

        let progressUpdates = ProgressCollector()
        let downloader = PackDownloader()
        try await downloader.download(from: src, to: dst, progress: { progressUpdates.append($0) })

        XCTAssertEqual(try Data(contentsOf: dst), payload)
        XCTAssertGreaterThan(progressUpdates.count, 0)
        XCTAssertLessThanOrEqual(progressUpdates.last ?? 0, 1.0)
    }

    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        func append(_ p: Double) { lock.lock(); values.append(p); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
        var last: Double? { lock.lock(); defer { lock.unlock() }; return values.last }
    }
}
