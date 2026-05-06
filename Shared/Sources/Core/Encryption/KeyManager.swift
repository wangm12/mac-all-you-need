import CryptoKit
import Foundation
import Security

public protocol KeychainBackend: AnyObject {
    func get(_ account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

public enum KeychainAccessGroup {
    public static var shared: String? {
        Bundle.main.object(forInfoDictionaryKey: "MAYNKeychainAccessGroup") as? String
    }
}

public final class SystemKeychain: KeychainBackend {
    private let service: String
    private let accessGroup: String?

    public init(service: String = AppGroup.identifier, accessGroup: String? = KeychainAccessGroup.shared) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func get(_ account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeyManagerError.keychainReadFailed(status)
        }
        return data
    }

    public func set(_ data: Data, for account: String) throws {
        try delete(account)
        var attrs = baseQuery(account: account)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyManagerError.keychainWriteFailed(status) }
    }

    public func delete(_ account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.keychainDeleteFailed(status)
        }
    }
}

public final class InMemoryKeychain: KeychainBackend {
    private var store: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func get(_ account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return store[account]
    }
    public func set(_ data: Data, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[account] = data
    }
    public func delete(_ account: String) throws {
        lock.lock(); defer { lock.unlock() }
        store.removeValue(forKey: account)
    }
}

public enum KeyManagerError: Error {
    case keyGenerationFailed
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
}

public final class KeyManager {
    private let keychain: KeychainBackend
    private let deviceKeyAccount = "device-key.v1"
    private let log = Logging.logger(for: "encryption", category: "keys")

    public init(keychain: KeychainBackend) {
        self.keychain = keychain
    }

    public func deviceKey() throws -> SymmetricKey {
        if let existing = try keychain.get(deviceKeyAccount) {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try keychain.set(data, for: deviceKeyAccount)
        log.info("Generated new device key")
        return key
    }

    public func deriveSyncKey(passphrase: String, salt: Data, params: KDFParameters) throws -> SymmetricKey {
        let pwd = Data(passphrase.utf8)
        let raw = try Argon2.hash(password: pwd, salt: salt, params: params)
        return SymmetricKey(data: raw)
    }
}
