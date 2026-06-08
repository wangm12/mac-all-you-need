@testable import MacAllYouNeed
import Core
import CryptoKit
import FeatureCore
import XCTest

@MainActor
final class AppFeatureWorkerHostTests: XCTestCase {
    func testStartStopClipboardWorker() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let key = SymmetricKey(size: .bits256)
        let clipDB = try Database(url: dir.appendingPathComponent("clip.sqlite"), migrations: ClipboardStore.migrations)
        let clip = try ClipboardStore(
            database: clipDB,
            deviceKey: key,
            deviceID: DeviceID(rawValue: "00000000-0000-0000-0000-000000000003")!
        )
        let searchDB = try Database(url: dir.appendingPathComponent("search.sqlite"), migrations: SearchStore.migrations)
        let search = SearchStore(database: searchDB)

        let host = AppFeatureWorkerHost(clip: clip, search: search)
        await host.startWorker(for: .clipboard)
        await host.startWorker(for: .clipboardSmartText)
        await host.stopWorker(for: .clipboard)
        await host.stopWorker(for: .clipboardSmartText)
    }
}
