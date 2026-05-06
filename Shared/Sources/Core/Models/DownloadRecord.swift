import Foundation

public enum DownloadState: String, Codable, Sendable {
    case queued, running, paused, completed, failed
}

public struct DownloadRecord: Codable, Equatable, Sendable {
    public var id: RecordID
    public var url: String
    public var title: String
    public var destinationPath: String
    public var state: DownloadState
    public var deviceID: DeviceID?
    public var lamport: UInt64
    public var bytesDownloaded: Int64
    public var bytesTotal: Int64?
    public var lastError: String?
    public var created: Date
    public var modified: Date
    // Video metadata (populated asynchronously after enqueue)
    public var videoTitle: String?
    public var channelName: String?
    public var durationSeconds: Int?
    public var thumbnailURL: String?

    public init(url: String, title: String, destinationPath: String, state: DownloadState) {
        id = RecordID.generate()
        self.url = url
        self.title = title
        self.destinationPath = destinationPath
        self.state = state
        deviceID = nil
        lamport = 0
        bytesDownloaded = 0
        bytesTotal = nil
        lastError = nil
        videoTitle = nil
        channelName = nil
        durationSeconds = nil
        thumbnailURL = nil
        let now = Date()
        created = now
        modified = now
    }
}
