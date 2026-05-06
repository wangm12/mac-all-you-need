import CryptoKit
import Foundation

public enum CipherError: Error {
    case sealFailed(Error)
    case openFailed(Error)
}

public enum Cipher {
    public static func seal(_ plaintext: Data, with key: SymmetricKey) throws -> Envelope {
        do {
            let box = try AES.GCM.seal(plaintext, using: key)
            guard let combined = box.combined else {
                throw CipherError.sealFailed(NSError(domain: "Cipher", code: -1))
            }
            return Envelope(combined: combined)
        } catch {
            throw CipherError.sealFailed(error)
        }
    }

    public static func open(_ envelope: Envelope, with key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CipherError.openFailed(error)
        }
    }
}
