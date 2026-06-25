import Foundation

public struct PlaylistEntryRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var channel: String
    public var thumbnail: String
    public var durationSeconds: Int
    public var pageURL: String
    public var playlistIndex: Int?

    public init(
        id: String,
        title: String,
        channel: String,
        thumbnail: String,
        durationSeconds: Int,
        pageURL: String,
        playlistIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.thumbnail = thumbnail
        self.durationSeconds = durationSeconds
        self.pageURL = pageURL
        self.playlistIndex = playlistIndex
    }
}

public struct PlaylistListResult: Sendable, Equatable {
    public var items: [PlaylistEntryRow]
    public var collectionTitle: String
    public var channel: String
    public var sourceURL: String

    public init(
        items: [PlaylistEntryRow],
        collectionTitle: String,
        channel: String,
        sourceURL: String
    ) {
        self.items = items
        self.collectionTitle = collectionTitle
        self.channel = channel
        self.sourceURL = sourceURL
    }
}

public struct BulkEnqueueEntry: Sendable, Equatable, Codable {
    public var pageURL: String
    public var title: String
    public var channel: String
    public var thumbnailURL: String?
    public var durationSeconds: Int?
    public var playlistIndex: Int?

    public init(
        pageURL: String,
        title: String,
        channel: String = "",
        thumbnailURL: String? = nil,
        durationSeconds: Int? = nil,
        playlistIndex: Int? = nil
    ) {
        self.pageURL = pageURL
        self.title = title
        self.channel = channel
        self.thumbnailURL = thumbnailURL
        self.durationSeconds = durationSeconds
        self.playlistIndex = playlistIndex
    }
}
