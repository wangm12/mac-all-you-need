import Foundation
import Security

public enum DispatchToken {
    public static func rotate(at url: URL) throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "DispatchToken", code: Int(status))
        }
        let token = bytes.base64EncodedString()
        try token.data(using: .utf8)!.write(to: url, options: .atomic)
        return token
    }

    public static func read(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
