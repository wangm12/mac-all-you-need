import CryptoKit
import Foundation

public final class BlobStore {
    private let root: URL
    private let key: SymmetricKey

    public init(rootURL: URL, key: SymmetricKey) {
        root = rootURL
        self.key = key
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @discardableResult
    public func write(_ data: Data) throws -> String {
        let id = RecordID.generate().rawValue
        let envelope = try Cipher.seal(data, with: key)
        let url = root.appendingPathComponent("\(id).bin")
        try envelope.combined.write(to: url, options: .atomic)
        return id
    }

    public func read(id: String) throws -> Data {
        let url = root.appendingPathComponent("\(id).bin")
        let raw = try Data(contentsOf: url)
        return try Cipher.open(Envelope(combined: raw), with: key)
    }

    public func delete(id: String) throws {
        let url = root.appendingPathComponent("\(id).bin")
        try? FileManager.default.removeItem(at: url)
    }
}
