import Foundation

public struct DownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let speedBytesPerSec: Double?
    public let etaSeconds: Int?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?
}
