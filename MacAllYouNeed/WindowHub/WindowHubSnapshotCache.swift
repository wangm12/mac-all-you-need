import Core
import Foundation

enum WindowHubSnapshotCache {
    private static let fileName = "window-hub-snapshot.json"

    private static var fileURL: URL {
        AppGroup.containerURL()
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func load() -> WindowHubCachedSnapshot? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode(WindowHubCachedSnapshot.self, from: data) else {
            return nil
        }
        return decoded.validated()
    }

    static func save(_ snapshot: WindowHubCachedSnapshot) {
        let normalized = WindowHubCachedSnapshot(
            capturedAt: snapshot.capturedAt,
            currentTargetID: snapshot.currentTargetID,
            sections: snapshot.sections
        )
        let url = fileURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
