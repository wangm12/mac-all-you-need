import Foundation

public struct RecordID: Hashable, Equatable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.count == 26, rawValue.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate() -> RecordID {
        let timestampMS = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 6 {
            bytes[i] = UInt8((timestampMS >> ((5 - i) * 8)) & 0xFF)
        }
        var random = SystemRandomNumberGenerator()
        for i in 6 ..< 16 {
            bytes[i] = UInt8.random(in: 0 ... 255, using: &random)
        }
        return RecordID(rawValue: Self.encodeBase32(bytes))!
    }

    private static func encodeBase32(_ bytes: [UInt8]) -> String {
        var result = [Character](repeating: "0", count: 26)
        let high = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let low = bytes.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        var bits128 = (high, low)
        for i in (0 ..< 26).reversed() {
            let chunk = UInt8(bits128.1 & 0x1F)
            result[i] = alphabet[Int(chunk)]
            let carry = (bits128.0 & 0x1F) << (64 - 5)
            bits128.1 = (bits128.1 >> 5) | carry
            bits128.0 >>= 5
        }
        return String(result)
    }
}
