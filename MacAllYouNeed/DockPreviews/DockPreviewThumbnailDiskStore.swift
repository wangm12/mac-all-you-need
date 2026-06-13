import AppKit
import Core
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG thumbnail cache on disk under the App Group (`dock-preview-thumbnails/`).
final class DockPreviewThumbnailDiskStore: @unchecked Sendable {
    static let subdirectoryName = "dock-preview-thumbnails"

    private let rootURL: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.macallyouneed.dock-preview-thumbnail-disk", qos: .utility)
    private let jpegQuality: CGFloat = 0.85
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        if let rootURL {
            self.rootURL = rootURL.appendingPathComponent(Self.subdirectoryName, isDirectory: true)
        } else {
            self.rootURL = AppGroup.containerURL()
                .appendingPathComponent(Self.subdirectoryName, isDirectory: true)
        }
        self.fileManager = fileManager
    }

    var rootPath: String { rootURL.path }

    // MARK: - Write / read

    /// Logs on-disk thumbnail counts when dock worklog is enabled (startup / manual debug).
    func logInventory() async {
        await runOnQueue {
            var files = 0
            var bytes = 0
            var pidDirs = 0
            if let dirs = try? self.fileManager.contentsOfDirectory(
                at: self.rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                pidDirs = dirs.count
                for pidDir in dirs {
                    guard let jpgs = try? self.fileManager.contentsOfDirectory(
                        at: pidDir,
                        includingPropertiesForKeys: [.fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for url in jpgs where url.pathExtension == "jpg" {
                        files += 1
                        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            bytes += size
                        }
                    }
                }
            }
            DockPreviewThumbnailDiagnostics.diskInventory(
                pidDirs: pidDirs,
                files: files,
                bytes: bytes,
                root: self.rootURL.path
            )
        }
    }

    func write(
        pid: pid_t,
        windowID: CGWindowID,
        cgImage: CGImage,
        capturedAt: Date,
        title: String? = nil
    ) async {
        await runOnQueue {
            self.writeSync(pid: pid, windowID: windowID, cgImage: cgImage, capturedAt: capturedAt, title: title)
        }
    }

    func isFresh(pid: pid_t, windowID: CGWindowID, lifespan: TimeInterval, now: Date = Date()) -> Bool {
        guard lifespan > 0 else { return false }
        return queue.sync {
            guard let capturedAt = capturedAtSync(pid: pid, windowID: windowID) else { return false }
            return now.timeIntervalSince(capturedAt) <= lifespan
        }
    }

    func hasThumbnail(pid: pid_t, windowID: CGWindowID) -> Bool {
        queue.sync {
            fileManager.fileExists(atPath: jpegURL(pid: pid, windowID: windowID).path)
        }
    }

    func loadImageAsync(
        pid: pid_t,
        windowID: CGWindowID,
        title: String? = nil,
        logMisses: Bool = false
    ) async -> NSImage? {
        await runOnQueueReturning {
            self.loadImage(pid: pid, windowID: windowID, title: title, logMisses: logMisses)
        }
    }

    func loadIfPresentAsync(
        pid: pid_t,
        windowID: CGWindowID,
        title: String? = nil
    ) async -> NSImage? {
        await loadImageAsync(pid: pid, windowID: windowID, title: title, logMisses: false)
    }

    func freshWindowIDs(
        pid: pid_t,
        windowIDs: [CGWindowID],
        lifespan: TimeInterval,
        now: Date = Date()
    ) async -> Set<CGWindowID> {
        await runOnQueueReturning {
            guard lifespan > 0 else { return [] }
            return Set(windowIDs.filter { windowID in
                guard let capturedAt = self.capturedAtSync(pid: pid, windowID: windowID) else { return false }
                return now.timeIntervalSince(capturedAt) <= lifespan
            })
        }
    }

    /// Loads by window ID, then falls back to the newest on-disk capture with the same window title (minimized / ID churn).
    func loadImage(pid: pid_t, windowID: CGWindowID, title: String? = nil, logMisses: Bool = false) -> NSImage? {
        let directURL = jpegURL(pid: pid, windowID: windowID)
        if fileManager.fileExists(atPath: directURL.path), let image = NSImage(contentsOf: directURL) {
            if logMisses {
                DockPreviewThumbnailDiagnostics.diskLoad(
                    pid: pid,
                    windowID: windowID,
                    hit: true,
                    fileBytes: DockPreviewThumbnailDiagnostics.jpegFileBytes(at: directURL)
                )
            }
            return image
        }
        if let fallback = loadImageByTitle(pid: pid, title: title, excludingWindowID: windowID) {
            if logMisses {
                DockPreviewThumbnailDiagnostics.diskLoad(pid: pid, windowID: windowID, hit: true)
            }
            return fallback
        }
        if logMisses {
            DockPreviewThumbnailDiagnostics.diskLoad(pid: pid, windowID: windowID, hit: false)
        }
        return nil
    }

    // MARK: - Delete

    func remove(pid: pid_t, windowID: CGWindowID) async {
        await runOnQueue {
            self.removeSync(pid: pid, windowID: windowID)
            DockPreviewThumbnailDiagnostics.diskRemove(pid: pid, windowID: windowID, scope: "window")
        }
    }

    func removeAll(pid: pid_t) async {
        await runOnQueue {
            let dir = self.pidDirectory(pid: pid)
            try? self.fileManager.removeItem(at: dir)
            DockPreviewThumbnailDiagnostics.diskRemove(pid: pid, scope: "pid")
        }
    }

    func removeAll() async {
        await runOnQueue {
            try? self.fileManager.removeItem(at: self.rootURL)
            try? self.fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
            DockPreviewThumbnailDiagnostics.diskRemove(pid: 0, scope: "all")
        }
    }

    /// Deletes thumbnail files whose `capturedAt` is older than `cutoff`.
    func pruneExpired(olderThan cutoff: Date) async -> Int {
        await runOnQueueReturning {
            var removed = 0
            guard let pidDirs = try? self.fileManager.contentsOfDirectory(
                at: self.rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                DockPreviewThumbnailDiagnostics.diskPrune(removed: 0, cutoff: cutoff)
                return 0
            }

            for pidDir in pidDirs {
                guard let metaFiles = try? self.fileManager.contentsOfDirectory(
                    at: pidDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for metaURL in metaFiles {
                    let name = metaURL.lastPathComponent
                    guard name.hasSuffix(".meta.json") else { continue }
                    let capturedAt = self.readCapturedAt(from: metaURL)
                        ?? (try? metaURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    guard let capturedAt, capturedAt < cutoff else { continue }
                    let windowIDPart = String(name.dropLast(".meta.json".count))
                    let jpgURL = metaURL.deletingLastPathComponent().appendingPathComponent("\(windowIDPart).jpg")
                    try? self.fileManager.removeItem(at: metaURL)
                    if self.fileManager.fileExists(atPath: jpgURL.path) {
                        try? self.fileManager.removeItem(at: jpgURL)
                    }
                    removed += 1
                }
            }
            DockPreviewThumbnailDiagnostics.diskPrune(removed: removed, cutoff: cutoff)
            return removed
        }
    }

    // MARK: - Internals

    private func runOnQueue(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                work()
                continuation.resume()
            }
        }
    }

    private func runOnQueueReturning<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func writeSync(
        pid: pid_t,
        windowID: CGWindowID,
        cgImage: CGImage,
        capturedAt: Date,
        title: String?
    ) {
        let dir = pidDirectory(pid: pid)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let jpgURL = jpegURL(pid: pid, windowID: windowID)
        let tmpURL = jpgURL.appendingPathExtension("tmp")
        let ok = writeJPEG(cgImage, to: tmpURL)
        if ok {
            _ = try? fileManager.replaceItemAt(jpgURL, withItemAt: tmpURL)
            if fileManager.fileExists(atPath: tmpURL.path) {
                try? fileManager.removeItem(at: tmpURL)
            }
            writeMeta(pid: pid, windowID: windowID, capturedAt: capturedAt, title: title)
        }
        DockPreviewThumbnailDiagnostics.diskWrite(
            pid: pid,
            windowID: windowID,
            width: cgImage.width,
            height: cgImage.height,
            fileBytes: ok ? DockPreviewThumbnailDiagnostics.jpegFileBytes(at: jpgURL) : nil,
            ok: ok
        )
    }

    private func writeMeta(pid: pid_t, windowID: CGWindowID, capturedAt: Date, title: String?) {
        let metaURL = metaURL(pid: pid, windowID: windowID)
        var payload: [String: String] = ["capturedAt": isoFormatter.string(from: capturedAt)]
        if let normalized = Self.normalizedTitle(title) {
            payload["title"] = normalized
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let tmpURL = metaURL.appendingPathExtension("tmp")
        try? data.write(to: tmpURL, options: .atomic)
        _ = try? fileManager.replaceItemAt(metaURL, withItemAt: tmpURL)
        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }
    }

    private func writeJPEG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return false }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private func capturedAtSync(pid: pid_t, windowID: CGWindowID) -> Date? {
        readCapturedAt(from: metaURL(pid: pid, windowID: windowID))
    }

    private func readMeta(from metaURL: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: metaURL),
              let payload = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return payload
    }

    private func readCapturedAt(from metaURL: URL) -> Date? {
        guard let raw = readMeta(from: metaURL)?["capturedAt"] else { return nil }
        return isoFormatter.date(from: raw)
    }

    private func loadImageByTitle(pid: pid_t, title: String?, excludingWindowID: CGWindowID) -> NSImage? {
        guard let normalized = Self.normalizedTitle(title) else { return nil }
        let dir = pidDirectory(pid: pid)
        guard let metaFiles = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var bestCapturedAt = Date.distantPast
        var bestWindowID: CGWindowID?
        for metaURL in metaFiles where metaURL.lastPathComponent.hasSuffix(".meta.json") {
            guard let payload = readMeta(from: metaURL),
                  payload["title"] == normalized,
                  let capturedAt = readCapturedAt(from: metaURL)
            else { continue }
            let windowIDPart = String(metaURL.lastPathComponent.dropLast(".meta.json".count))
            guard let windowID = UInt32(windowIDPart), windowID != excludingWindowID else { continue }
            let wid = CGWindowID(windowID)
            guard capturedAt > bestCapturedAt else { continue }
            bestCapturedAt = capturedAt
            bestWindowID = wid
        }
        guard let bestWindowID else { return nil }
        let url = jpegURL(pid: pid, windowID: bestWindowID)
        return fileManager.fileExists(atPath: url.path) ? NSImage(contentsOf: url) : nil
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != "Window" else { return nil }
        return trimmed
    }

    private func removeSync(pid: pid_t, windowID: CGWindowID) {
        try? fileManager.removeItem(at: jpegURL(pid: pid, windowID: windowID))
        try? fileManager.removeItem(at: metaURL(pid: pid, windowID: windowID))
    }

    private func pidDirectory(pid: pid_t) -> URL {
        rootURL.appendingPathComponent("\(pid)", isDirectory: true)
    }

    private func jpegURL(pid: pid_t, windowID: CGWindowID) -> URL {
        pidDirectory(pid: pid).appendingPathComponent("\(windowID).jpg")
    }

    private func metaURL(pid: pid_t, windowID: CGWindowID) -> URL {
        pidDirectory(pid: pid).appendingPathComponent("\(windowID).meta.json")
    }
}
