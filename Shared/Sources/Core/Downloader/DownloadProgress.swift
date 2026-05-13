import Foundation

public struct DownloadProgress: Equatable, Sendable {
    public let fraction: Double
    public let speedBytesPerSec: Double?
    public let etaSeconds: Int?
    public let downloadedBytes: Int64?
    public let totalBytes: Int64?

    public init(fraction: Double, speedBytesPerSec: Double?, etaSeconds: Int?, downloadedBytes: Int64?, totalBytes: Int64?) {
        self.fraction = fraction
        self.speedBytesPerSec = speedBytesPerSec
        self.etaSeconds = etaSeconds
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }
}
