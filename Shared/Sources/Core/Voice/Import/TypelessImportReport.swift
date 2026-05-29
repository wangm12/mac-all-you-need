import Foundation

public struct TypelessImportOptions: Sendable {
    public var dryRun: Bool
    public var skipAudio: Bool
    public var limit: Int?
    public var progressInterval: Int

    public init(
        dryRun: Bool = false,
        skipAudio: Bool = false,
        limit: Int? = nil,
        progressInterval: Int = 25
    ) {
        self.dryRun = dryRun
        self.skipAudio = skipAudio
        self.limit = limit
        self.progressInterval = max(1, progressInterval)
    }
}

public struct TypelessImportReport: Sendable, Equatable {
    public var scanned: Int
    public var imported: Int
    public var skippedExisting: Int
    public var audioImported: Int
    public var audioFailed: Int
    public var errors: [String]

    public init(
        scanned: Int = 0,
        imported: Int = 0,
        skippedExisting: Int = 0,
        audioImported: Int = 0,
        audioFailed: Int = 0,
        errors: [String] = []
    ) {
        self.scanned = scanned
        self.imported = imported
        self.skippedExisting = skippedExisting
        self.audioImported = audioImported
        self.audioFailed = audioFailed
        self.errors = errors
    }
}
