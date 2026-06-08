import AppKit
import Core
import Foundation

/// Dock hover preview worklog — gated by Dock Preview settings (`enableWorklog`).
enum DockPreviewWorklog {
    private static let feature = FeatureWorklog.Feature.dockPreviews
    /// In-memory gate — updated from `DockPreviewCoordinator.reloadSettings()` (avoid decoding hub JSON per log line).
    private static var enabled = false

    static var isEnabled: Bool { enabled }

    static func setEnabled(_ value: Bool) {
        enabled = value
    }

    static func log(_ event: String, details: String? = nil, file: String = #fileID, line: Int = #line) {
        guard enabled else { return }
        FeatureWorklog.log(feature, event, details: details, file: file, line: line)
    }

    static func log(
        _ event: String,
        fields: [String: CustomStringConvertible],
        file: String = #fileID,
        line: Int = #line
    ) {
        guard enabled else { return }
        FeatureWorklog.log(feature, event, fields: fields, file: file, line: line)
    }

    static func revealInFinder() {
        let dir = FeatureWorklog.directory(for: feature)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    static func clear() {
        FeatureWorklog.clear(feature)
    }

    /// Avoid calling from SwiftUI `body`; use async refresh instead.
    static func fetchLineCount() async -> Int {
        await Task.detached(priority: .utility) {
            FeatureWorklog.lineCount(for: feature)
        }.value
    }
}
