import Foundation

public enum DownloadState: String, Codable, Sendable {
    case queued, running, paused, completed, failed
}

public struct DownloadRecord: Codable, Equatable, Sendable, Identifiable {
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
    public var collectionID: String?
    public var collectionIndex: Int?
    public var collectionTitle: String?
    public var collectionKind: DownloadCollectionKind?
    public var pageURL: String?
    // Routing metadata persisted so extension-dispatched direct media and
    // site-specific fallback behavior survive retries and app restarts.
    public var mediaType: String?
    public var referer: String?
    public var customHeaders: [String: String]?
    public var nativeYoutubePlaylist: Bool
    public var ytdlpID: String?
    public var douyinAwemeID: String?
    public var douyinMediaType: String?
    public var douyinImageURLs: [String]?
    public var playlistTitle: String?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case title
        case destinationPath
        case state
        case deviceID
        case lamport
        case bytesDownloaded
        case bytesTotal
        case lastError
        case created
        case modified
        case videoTitle
        case channelName
        case durationSeconds
        case thumbnailURL
        case collectionID
        case collectionIndex
        case collectionTitle
        case collectionKind
        case pageURL
        case mediaType
        case referer
        case customHeaders
        case nativeYoutubePlaylist
        case ytdlpID
        case douyinAwemeID
        case douyinMediaType
        case douyinImageURLs
        case playlistTitle
    }

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
        collectionID = nil
        collectionIndex = nil
        collectionTitle = nil
        collectionKind = nil
        pageURL = nil
        mediaType = nil
        referer = nil
        customHeaders = nil
        nativeYoutubePlaylist = false
        ytdlpID = nil
        douyinAwemeID = nil
        douyinMediaType = nil
        douyinImageURLs = nil
        playlistTitle = nil
        let now = Date()
        created = now
        modified = now
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RecordID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        destinationPath = try container.decode(String.self, forKey: .destinationPath)
        state = try container.decode(DownloadState.self, forKey: .state)
        deviceID = try container.decodeIfPresent(DeviceID.self, forKey: .deviceID)
        lamport = try container.decodeIfPresent(UInt64.self, forKey: .lamport) ?? 0
        bytesDownloaded = try container.decodeIfPresent(Int64.self, forKey: .bytesDownloaded) ?? 0
        bytesTotal = try container.decodeIfPresent(Int64.self, forKey: .bytesTotal)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? created
        videoTitle = try container.decodeIfPresent(String.self, forKey: .videoTitle)
        channelName = try container.decodeIfPresent(String.self, forKey: .channelName)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        collectionID = try container.decodeIfPresent(String.self, forKey: .collectionID)
        collectionIndex = try container.decodeIfPresent(Int.self, forKey: .collectionIndex)
        collectionTitle = try container.decodeIfPresent(String.self, forKey: .collectionTitle)
        collectionKind = try container.decodeIfPresent(DownloadCollectionKind.self, forKey: .collectionKind)
        pageURL = try container.decodeIfPresent(String.self, forKey: .pageURL)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        referer = try container.decodeIfPresent(String.self, forKey: .referer)
        customHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders)
        nativeYoutubePlaylist = try container.decodeIfPresent(Bool.self, forKey: .nativeYoutubePlaylist) ?? false
        ytdlpID = try container.decodeIfPresent(String.self, forKey: .ytdlpID)
        douyinAwemeID = try container.decodeIfPresent(String.self, forKey: .douyinAwemeID)
        douyinMediaType = try container.decodeIfPresent(String.self, forKey: .douyinMediaType)
        douyinImageURLs = try container.decodeIfPresent([String].self, forKey: .douyinImageURLs)
        playlistTitle = try container.decodeIfPresent(String.self, forKey: .playlistTitle)
    }
}
