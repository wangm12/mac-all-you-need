import Foundation

public actor PackDownloader {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Downloads `sourceURL` to `destinationFile`. Calls `progress` with [0.0, 1.0] estimates as bytes arrive.
    public func download(
        from sourceURL: URL,
        to destinationFile: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (asyncBytes, response) = try await urlSession.bytes(from: sourceURL)
        let totalBytes = response.expectedContentLength

        let fm = FileManager.default
        if fm.fileExists(atPath: destinationFile.path) {
            try fm.removeItem(at: destinationFile)
        }
        try fm.createDirectory(at: destinationFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: destinationFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationFile)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var written: Int64 = 0

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if totalBytes > 0 {
                    progress(Double(written) / Double(totalBytes))
                }
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }

        progress(1.0)
    }
}
