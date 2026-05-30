@testable import Core
@testable import MacAllYouNeed
import Platform
import XCTest

final class FolderHistoryRecorderTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RecorderTest-\(UUID()).sqlite")
    }

    @MainActor
    private func makeRecorder(store: FolderHistoryStore, exclusions: Set<String> = []) -> FolderHistoryRecorder {
        let engine = SystemAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        return FolderHistoryRecorder(
            store: store,
            coordinator: coordinator,
            axReader: SystemFolderHistoryAXReader(),
            exclusions: { exclusions }
        )
    }

    @MainActor
    func testRecordsSinglePath() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let recorder = makeRecorder(store: store)
        recorder.record(path: "/Users/me/Documents")
        let rows = try store.list(limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.path, "/Users/me/Documents")
    }

    @MainActor
    func testDebouncesSamePath() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let recorder = makeRecorder(store: store)
        let t0 = Date()
        recorder.record(path: "/Users/me/A", now: t0)
        recorder.record(path: "/Users/me/A", now: t0.addingTimeInterval(0.5)) // within window → ignored
        let rows = try store.list(limit: 10)
        XCTAssertEqual(rows.first?.visitCount, 1)
    }

    @MainActor
    func testSkipsExcludedPath() throws {
        let store = try FolderHistoryStore(url: temporaryURL())
        let recorder = makeRecorder(store: store, exclusions: ["/Users/me/Secret"])
        recorder.record(path: "/Users/me/Secret")
        XCTAssertEqual(try store.list(limit: 10).count, 0)
    }
}
