import CommonCrypto
import Foundation
import GRDB
import Security

public enum ChromiumCookiesError: Error { case keyNotFound, decryptFailed }

public enum ChromiumCookies {
    public static func discoverProfiles() -> [BrowserProfile] {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let candidates: [(BrowserProfile.Browser, String)] = [
            (.chrome, "Google/Chrome"),
            (.edge, "Microsoft Edge"),
            (.brave, "BraveSoftware/Brave-Browser"),
            (.arc, "Arc")
        ]
        var out: [BrowserProfile] = []
        for (b, sub) in candidates {
            let root = supportRoot.appendingPathComponent(sub, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            else { continue }
            for entry in entries {
                let cookieDB = entry.appendingPathComponent("Cookies")
                if FileManager.default.fileExists(atPath: cookieDB.path) {
                    out.append(BrowserProfile(browser: b, name: entry.lastPathComponent, cookieDB: cookieDB, safariBinaryStore: nil))
                }
            }
        }
        return out
    }

    public static func keychainKey(for browser: BrowserProfile.Browser) throws -> Data {
        let service: String
        switch browser {
        case .chrome: service = "Chrome Safe Storage"
        case .edge: service = "Microsoft Edge Safe Storage"
        case .brave: service = "Brave Safe Storage"
        case .arc: service = "Arc Safe Storage"
        case .safari: throw ChromiumCookiesError.keyNotFound
        }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw ChromiumCookiesError.keyNotFound }
        return data
    }

    public static func exportNetscape(profile: BrowserProfile) throws -> String {
        guard let cookieDB = profile.cookieDB else { throw ChromiumCookiesError.keyNotFound }
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("mayn-cookies-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmp = tmpDir.appendingPathComponent("Cookies")
        try FileManager.default.copyItem(at: cookieDB, to: tmp)
        for ext in ["-wal", "-shm"] {
            let side = cookieDB.deletingLastPathComponent().appendingPathComponent(cookieDB.lastPathComponent + ext)
            if FileManager.default.fileExists(atPath: side.path) {
                try FileManager.default.copyItem(at: side, to: tmpDir.appendingPathComponent("Cookies\(ext)"))
            }
        }
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try DatabaseQueue(path: tmp.path)
        let safeStorageKey = try keychainKey(for: profile.browser)
        var out = "# Netscape HTTP Cookie File\n"
        try db.read { conn in
            for row in try Row
                .fetchAll(conn, sql: "SELECT host_key, path, secure, expires_utc, name, value, encrypted_value FROM cookies")
            {
                let host: String = row["host_key"]
                let path: String = row["path"]
                let secure: Int = row["secure"]
                let expires: Int64 = row["expires_utc"]
                let name: String = row["name"]
                let plainValue: String = row["value"]
                let encryptedValue: Data = row["encrypted_value"]
                let value = !plainValue.isEmpty
                    ? plainValue
                    : (try? decryptChromiumValue(encryptedValue, safeStorageKey: safeStorageKey)) ?? ""
                let secureFlag = secure == 1 ? "TRUE" : "FALSE"
                let expiresEpoch = expires == 0 ? 0 : Int(expires / 1_000_000) - 11_644_473_600
                out += "\(host)\tFALSE\t\(path)\t\(secureFlag)\t\(expiresEpoch)\t\(name)\t\(value)\n"
            }
        }
        return out
    }

    private static func decryptChromiumValue(_ encrypted: Data, safeStorageKey: Data) throws -> String {
        let prefix = Data("v10".utf8)
        let cipherText = encrypted.starts(with: prefix) ? encrypted.dropFirst(prefix.count) : encrypted[...]
        var key = Data(count: kCCKeySizeAES128)
        let password = String(data: safeStorageKey, encoding: .utf8) ?? ""
        let status = key.withUnsafeMutableBytes { keyBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password, password.utf8.count,
                Array("saltysalt".utf8), "saltysalt".utf8.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003,
                keyBytes.bindMemory(to: UInt8.self).baseAddress,
                kCCKeySizeAES128
            )
        }
        guard status == kCCSuccess else { throw ChromiumCookiesError.decryptFailed }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: cipherText.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let cryptStatus = output.withUnsafeMutableBytes { outBytes in
            cipherText.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, cipherText.count,
                            outBytes.baseAddress, outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard cryptStatus == kCCSuccess else { throw ChromiumCookiesError.decryptFailed }
        output = Data(output.prefix(outputLength))
        guard let value = String(data: output, encoding: .utf8) else { throw ChromiumCookiesError.decryptFailed }
        return value
    }
}
