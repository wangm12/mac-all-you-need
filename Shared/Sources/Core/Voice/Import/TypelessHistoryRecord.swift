import Foundation

public enum TypelessHistorySourceTable: String, Sendable, Equatable {
    case history
    case historyV2 = "history_v2"
}

/// Normalized row from Typeless `history` or `history_v2`.
public struct TypelessHistoryRecord: Sendable, Equatable {
    public let id: String
    public let refinedText: String
    public let editedText: String?
    public let createdAt: Date
    public let durationSeconds: Double
    public let appBundleID: String?
    public let detectedLanguage: String?
    public let languagesJSON: String?
    public let audioLocalPath: String?
    public let sourceTable: TypelessHistorySourceTable

    public init(
        id: String,
        refinedText: String,
        editedText: String?,
        createdAt: Date,
        durationSeconds: Double,
        appBundleID: String?,
        detectedLanguage: String?,
        languagesJSON: String?,
        audioLocalPath: String?,
        sourceTable: TypelessHistorySourceTable
    ) {
        self.id = id
        self.refinedText = refinedText
        self.editedText = editedText
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.appBundleID = appBundleID
        self.detectedLanguage = detectedLanguage
        self.languagesJSON = languagesJSON
        self.audioLocalPath = audioLocalPath
        self.sourceTable = sourceTable
    }

    public var endedAt: Date {
        guard durationSeconds > 0 else { return createdAt.addingTimeInterval(1) }
        return createdAt.addingTimeInterval(durationSeconds)
    }

    public var finalText: String {
        let edited = editedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? refinedText : edited
    }

    public func resolvedAudioURL(recordingsRoot: URL) -> URL? {
        guard let raw = audioLocalPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("/") {
            let url = URL(fileURLWithPath: raw)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        let url = recordingsRoot.appendingPathComponent(raw)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
