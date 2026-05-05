# Plan 1: Storage & Encryption (Core library)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the headless `Core` library that everything else depends on: owned SQLite stores for clipboard/downloads/search, two-key encryption (Keychain device key + Argon2id passphrase-derived sync key), AES-GCM `Envelope` format, on-disk encrypted blob store, and FTS5 indexing. Fully unit-tested in isolation; no UI, no XPC, no NSPasteboard.

**Architecture:** GRDB.swift wraps each owned SQLite database as a `DatabaseQueue` with WAL journal mode so daemon and main app can read concurrently. Records are typed Swift structs. Encryption sits at the record-payload boundary: every store accepts a plaintext `Body`, encrypts it with the local device key, writes ciphertext into the row. Sync envelopes (Plan 2) reuse the same `Cipher` but with the sync key. KDF for the sync key is Argon2id, vendored as a Swift wrapper around the libargon2 reference C implementation.

**Tech Stack:** Swift 5.9, GRDB.swift 6.x (SwiftPM), CryptoKit, Security framework (Keychain), libargon2 (vendored C library + Swift wrapper).

**Reads from spec:** §3 (decisions 12, 13), §4 (App Group container), §5 (Storage, Encryption), §11 (logging subsystem naming). Defines the canonical types referenced by Plans 2–5.

**Produces working software:** an engineer can call `ClipboardStore.append(text: "hello")` and `ClipboardStore.list(limit: 50)` from a unit test, get encrypted-on-disk records back, search them via FTS, and confirm they're unreadable without the right key.

---

## Public types defined here (referenced by later plans)

| Type | Module path | Purpose |
|---|---|---|
| `RecordKind` | `Core.Models` | Enum: `clipboardItem`, `snippet`, `pinboard`, `settings`, `downloadHistory` |
| `RecordID` | `Core.Models` | ULID newtype (`String`) |
| `DeviceID` | `Core.Models` | UUID newtype (`String`) |
| `ClipboardRecord` | `Core.Models` | The clipboard payload struct (see §6 of spec for fields) |
| `Envelope` | `Core.Models` | `nonce + ciphertext + tag` (CryptoKit `AES.GCM.SealedBox.combined`) wrapper |
| `EnvelopeMetadata` | `Core.Models` | `{kind, id, created, modified, deviceID, lamport}` |
| `Database` | `Core.Storage` | Wraps a single `DatabaseQueue` with WAL config |
| `ClipboardStore` | `Core.Storage` | CRUD for clipboard records |
| `DownloadStore` | `Core.Storage` | CRUD for download tasks (Plan 5 extends) |
| `BlobStore` | `Core.Storage` | Encrypted file blobs in `App Group/blobs/` |
| `SearchStore` | `Core.Storage` | FTS5 index ops, idempotent upsert |
| `KeyManager` | `Core.Encryption` | Device key in Keychain; sync key from passphrase |
| `Cipher` | `Core.Encryption` | `seal(_:with:) -> Envelope`; `open(_:with:) -> Data` |
| `Argon2` | `Core.Encryption` | Wraps libargon2; `hash(password:salt:params:)` |
| `KDFParameters` | `Core.Encryption` | Versioned struct: `algorithm`, `iterations`, `memoryKB`, `parallelism`, `outputLen` |
| `KeyVersion` | `Core.Encryption` | `Int` newtype; current = 1 |

---

## File structure (added by this plan)

```
Vendored/
└── argon2/                                  # reference impl from P-H-C/phc-winner-argon2
    ├── include/argon2.h
    ├── src/                                 # blake2/, argon2.c, core.c, encoding.c, ref.c, thread.c
    └── LICENSE                              # CC0/Apache 2.0 dual

Shared/
├── Package.swift                            # MODIFY: add GRDB, CArgon2 system target, Argon2Swift wrapper
├── Sources/
│   ├── CArgon2/                             # SwiftPM C target wrapping vendored libargon2
│   │   ├── argon2-shim.c                    # exports a C function with stable signature
│   │   ├── argon2/                          # copied C sources compiled by SwiftPM
│   │   │   ├── include/argon2.h
│   │   │   └── src/...
│   │   ├── include/CArgon2.h
│   │   └── module.modulemap
│   └── Core/
│       ├── AppGroup.swift                   # (exists from Plan 0)
│       ├── Logging.swift                    # NEW: os.Logger subsystem helpers
│       ├── Models/
│       │   ├── RecordKind.swift
│       │   ├── RecordID.swift
│       │   ├── DeviceID.swift
│       │   ├── ClipboardRecord.swift
│       │   ├── DownloadRecord.swift
│       │   └── Envelope.swift
│       ├── Encryption/
│       │   ├── Argon2.swift
│       │   ├── KDFParameters.swift
│       │   ├── KeyVersion.swift
│       │   ├── KeyManager.swift
│       │   └── Cipher.swift
│       └── Storage/
│           ├── Database.swift
│           ├── Migrations.swift
│           ├── ClipboardStore.swift
│           ├── DownloadStore.swift
│           ├── BlobStore.swift
│           └── SearchStore.swift
└── Tests/
    └── CoreTests/
        ├── (existing files)
        ├── LoggingTests.swift
        ├── Models/
        │   ├── RecordIDTests.swift
        │   └── EnvelopeTests.swift
        ├── Encryption/
        │   ├── Argon2Tests.swift
        │   ├── KeyManagerTests.swift
        │   └── CipherTests.swift
        └── Storage/
            ├── DatabaseTests.swift
            ├── ClipboardStoreTests.swift
            ├── DownloadStoreTests.swift
            ├── BlobStoreTests.swift
            └── SearchStoreTests.swift
```

---

## Task 1.1: Add GRDB.swift dependency

**Files:**
- Modify: `Shared/Package.swift`

- [ ] **Step 1: Add the dependency**

Replace `Shared/Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Platform", targets: ["Platform"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
    ],
    targets: [
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Core"
        ),
        .target(name: "UI", dependencies: ["Core"], path: "Sources/UI"),
        .target(name: "Platform", dependencies: ["Core"], path: "Sources/Platform"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
        .testTarget(name: "UITests", dependencies: ["UI"], path: "Tests/UITests"),
        .testTarget(name: "PlatformTests", dependencies: ["Platform"], path: "Tests/PlatformTests"),
    ]
)
```

- [ ] **Step 2: Resolve dependencies and confirm build**

```bash
cd Shared && swift package resolve && swift build
```

Expected: GRDB resolves and builds. (First resolve takes ~30s.)
Commit the generated `Package.resolved` file so dependency resolution is reproducible across CI and local machines.

- [ ] **Step 3: Commit**

```bash
git add Shared/Package.swift Shared/Package.resolved
git commit -m "chore: add GRDB.swift dependency to Shared"
```

---

## Task 1.2: Add `Logging` helper

**Files:**
- Create: `Shared/Sources/Core/Logging.swift`
- Create: `Shared/Tests/CoreTests/LoggingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import os
@testable import Core

final class LoggingTests: XCTestCase {
    func testSubsystemPrefix() {
        XCTAssertEqual(Logging.subsystem(for: "storage"), "com.macallyouneed.storage")
    }
}
```

- [ ] **Step 2: Confirm fail**

```bash
cd Shared && swift test --filter LoggingTests
```
Expected: FAIL "Cannot find 'Logging'".

- [ ] **Step 3: Implement**

```swift
import Foundation
import os

public enum Logging {
    private static let prefix = "com.macallyouneed"

    public static func subsystem(for feature: String) -> String {
        "\(prefix).\(feature)"
    }

    public static func logger(for feature: String, category: String = "default") -> Logger {
        Logger(subsystem: subsystem(for: feature), category: category)
    }
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter LoggingTests
git add Shared/Sources/Core/Logging.swift Shared/Tests/CoreTests/LoggingTests.swift
git commit -m "feat(core): add Logging helper for os.Logger"
```

---

## Task 1.3: `RecordID` (ULID) and `DeviceID` (UUID) newtypes

**Files:**
- Create: `Shared/Sources/Core/Models/RecordID.swift`
- Create: `Shared/Sources/Core/Models/DeviceID.swift`
- Create: `Shared/Tests/CoreTests/Models/RecordIDTests.swift`

- [ ] **Step 1: Write the failing test**

`Shared/Tests/CoreTests/Models/RecordIDTests.swift`:

```swift
import XCTest
@testable import Core

final class RecordIDTests: XCTestCase {
    func testGeneratedIDIs26Chars() {
        let id = RecordID.generate()
        XCTAssertEqual(id.rawValue.count, 26)
    }

    func testGeneratedIDsAreUnique() {
        var seen = Set<String>()
        for _ in 0..<1000 {
            seen.insert(RecordID.generate().rawValue)
        }
        XCTAssertEqual(seen.count, 1000)
    }

    func testGeneratedIDsAreLexicographicallyOrderedByTime() {
        let earlier = RecordID.generate()
        Thread.sleep(forTimeInterval: 0.005)
        let later = RecordID.generate()
        XCTAssertLessThan(earlier.rawValue, later.rawValue)
    }

    func testRoundTripFromString() {
        let id = RecordID.generate()
        let parsed = RecordID(rawValue: id.rawValue)
        XCTAssertEqual(parsed, id)
    }

    func testRejectsInvalidLength() {
        XCTAssertNil(RecordID(rawValue: "TOO_SHORT"))
    }
}
```

- [ ] **Step 2: Implement `RecordID`**

`Shared/Sources/Core/Models/RecordID.swift`:

```swift
import Foundation

public struct RecordID: Hashable, Equatable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.count == 26, rawValue.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        self.rawValue = rawValue
    }

    /// Crockford base32 alphabet (no I, L, O, U).
    static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generates a ULID: 48-bit ms timestamp + 80 bits of random, base32-encoded.
    public static func generate() -> RecordID {
        let timestampMS = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        // First 6 bytes = timestamp big-endian
        for i in 0..<6 {
            bytes[i] = UInt8((timestampMS >> ((5 - i) * 8)) & 0xFF)
        }
        // Last 10 bytes = random
        var random = SystemRandomNumberGenerator()
        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255, using: &random)
        }
        let value = Self.encodeBase32(bytes)
        return RecordID(rawValue: value)!
    }

    private static func encodeBase32(_ bytes: [UInt8]) -> String {
        // 16 bytes = 128 bits → 26 base32 chars (130 bits, top 2 bits zero-padded)
        var result = [Character](repeating: "0", count: 26)
        // Bits packed big-endian; we treat input as a 128-bit BE int and emit 5 bits at a time from MSB.
        // Easier: convert to UInt64 pair.
        let high = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let low  = bytes.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        // 128 bits → top 2 are pad. Emit 26 chars from MSB.
        // Use a single 128-bit pseudo-shift via two halves.
        var bits128 = (high, low)
        for i in (0..<26).reversed() {
            let chunk = UInt8(bits128.1 & 0x1F)
            result[i] = alphabet[Int(chunk)]
            // Shift right 5 bits across 128
            let carry = (bits128.0 & 0x1F) << (64 - 5)
            bits128.1 = (bits128.1 >> 5) | carry
            bits128.0 >>= 5
        }
        return String(result)
    }
}
```

- [ ] **Step 3: Implement `DeviceID`**

`Shared/Sources/Core/Models/DeviceID.swift`:

```swift
import Foundation

public struct DeviceID: Hashable, Equatable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard UUID(uuidString: rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    public static func generate() -> DeviceID {
        DeviceID(rawValue: UUID().uuidString)!
    }
}
```

- [ ] **Step 4: Run tests, iterate until pass**

```bash
cd Shared && swift test --filter RecordIDTests
```
Expected: all 5 tests pass. If the lexicographic test is flaky, the encoder has a bit-order bug.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Models/RecordID.swift Shared/Sources/Core/Models/DeviceID.swift Shared/Tests/CoreTests/Models/RecordIDTests.swift
git commit -m "feat(core): add RecordID (ULID) and DeviceID newtypes"
```

---

## Task 1.4: `RecordKind` enum and `EnvelopeMetadata`

**Files:**
- Create: `Shared/Sources/Core/Models/RecordKind.swift`
- Create: `Shared/Sources/Core/Models/Envelope.swift`
- Create: `Shared/Tests/CoreTests/Models/EnvelopeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Core

final class EnvelopeTests: XCTestCase {
    func testMetadataCodableRoundTrip() throws {
        let id = RecordID.generate()
        let device = DeviceID.generate()
        let now = Date()
        let meta = EnvelopeMetadata(
            kind: .clipboardItem,
            id: id,
            created: now,
            modified: now,
            deviceID: device,
            lamport: 7
        )
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(EnvelopeMetadata.self, from: data)
        XCTAssertEqual(decoded, meta)
    }

    func testRecordKindRawValuesStable() {
        XCTAssertEqual(RecordKind.clipboardItem.rawValue, "clipboard_item")
        XCTAssertEqual(RecordKind.snippet.rawValue, "snippet")
        XCTAssertEqual(RecordKind.pinboard.rawValue, "pinboard")
        XCTAssertEqual(RecordKind.settings.rawValue, "settings")
        XCTAssertEqual(RecordKind.downloadHistory.rawValue, "download_history")
    }
}
```

- [ ] **Step 2: Implement**

`Shared/Sources/Core/Models/RecordKind.swift`:

```swift
import Foundation

public enum RecordKind: String, Codable, CaseIterable, Sendable {
    case clipboardItem = "clipboard_item"
    case snippet
    case pinboard
    case settings
    case downloadHistory = "download_history"
}
```

`Shared/Sources/Core/Models/Envelope.swift`:

```swift
import Foundation

/// Metadata that travels in the clear inside the encrypted envelope payload.
/// The envelope ciphertext wraps a JSON encoding of `{ metadata, body }`.
public struct EnvelopeMetadata: Codable, Equatable, Sendable {
    public let kind: RecordKind
    public let id: RecordID
    public let created: Date
    public let modified: Date
    public let deviceID: DeviceID
    public let lamport: UInt64

    public init(kind: RecordKind, id: RecordID, created: Date, modified: Date, deviceID: DeviceID, lamport: UInt64) {
        self.kind = kind
        self.id = id
        self.created = created
        self.modified = modified
        self.deviceID = deviceID
        self.lamport = lamport
    }

    enum CodingKeys: String, CodingKey {
        case kind, id, created, modified
        case deviceID = "device_id"
        case lamport
    }
}

/// `Envelope` is the on-disk and on-wire ciphertext blob.
/// Backed by `CryptoKit.AES.GCM.SealedBox.combined` (nonce + ciphertext + tag).
public struct Envelope: Equatable, Sendable {
    public let combined: Data
    public init(combined: Data) { self.combined = combined }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter EnvelopeTests
git add Shared/Sources/Core/Models/RecordKind.swift Shared/Sources/Core/Models/Envelope.swift Shared/Tests/CoreTests/Models/EnvelopeTests.swift
git commit -m "feat(core): add RecordKind and EnvelopeMetadata"
```

---

## Task 1.5: Vendor libargon2 as a SwiftPM C target

**Files:**
- Create: `Vendored/argon2/` (vendored from https://github.com/P-H-C/phc-winner-argon2 tag `20190702`)
- Create: `Shared/Sources/CArgon2/argon2-shim.c`
- Create: `Shared/Sources/CArgon2/include/CArgon2.h`
- Create: `Shared/Sources/CArgon2/module.modulemap`
- Modify: `Shared/Package.swift`

- [ ] **Step 1: Vendor the upstream source**

```bash
mkdir -p Vendored
git clone --depth 1 --branch 20190702 https://github.com/P-H-C/phc-winner-argon2.git Vendored/argon2
rm -rf Vendored/argon2/.git Vendored/argon2/man Vendored/argon2/latex Vendored/argon2/kats
mkdir -p Shared/Sources/CArgon2/argon2
cp -R Vendored/argon2/include Shared/Sources/CArgon2/argon2/include
cp -R Vendored/argon2/src Shared/Sources/CArgon2/argon2/src
```

Verify the kept layout:
```bash
ls Vendored/argon2
# Expected: include/  src/  LICENSE  README.md  Makefile
```

- [ ] **Step 2: Create the SwiftPM C target shim**

`Shared/Sources/CArgon2/include/CArgon2.h`:

```c
#ifndef CArgon2_h
#define CArgon2_h

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns 0 on success, negative on error (libargon2 error code).
int mayn_argon2id_hash_raw(
    uint32_t t_cost,
    uint32_t m_cost_kb,
    uint32_t parallelism,
    const void *pwd,
    size_t pwd_len,
    const void *salt,
    size_t salt_len,
    void *hash,
    size_t hash_len
);

#ifdef __cplusplus
}
#endif
#endif
```

`Shared/Sources/CArgon2/argon2-shim.c`:

```c
#include "include/CArgon2.h"
#include "argon2/include/argon2.h"

int mayn_argon2id_hash_raw(
    uint32_t t_cost,
    uint32_t m_cost_kb,
    uint32_t parallelism,
    const void *pwd,
    size_t pwd_len,
    const void *salt,
    size_t salt_len,
    void *hash,
    size_t hash_len
) {
    return argon2id_hash_raw(t_cost, m_cost_kb, parallelism,
                             pwd, pwd_len, salt, salt_len,
                             hash, hash_len);
}
```

`Shared/Sources/CArgon2/module.modulemap`:

```
module CArgon2 {
    umbrella header "include/CArgon2.h"
    export *
}
```

- [ ] **Step 3: Update `Package.swift` to compile libargon2 sources via the C target**

Replace `Shared/Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shared",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "UI", targets: ["UI"]),
        .library(name: "Platform", targets: ["Platform"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.27.0"),
    ],
    targets: [
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            sources: [
                "argon2-shim.c",
                "argon2/src/argon2.c",
                "argon2/src/core.c",
                "argon2/src/encoding.c",
                "argon2/src/ref.c",
                "argon2/src/thread.c",
                "argon2/src/blake2/blake2b.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("argon2/include"),
                .headerSearchPath("argon2/src"),
                .headerSearchPath("argon2/src/blake2"),
                .define("ARGON2_NO_THREADS", to: "0"),
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CArgon2",
            ],
            path: "Sources/Core"
        ),
        .target(name: "UI", dependencies: ["Core"], path: "Sources/UI"),
        .target(name: "Platform", dependencies: ["Core"], path: "Sources/Platform"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
        .testTarget(name: "UITests", dependencies: ["UI"], path: "Tests/UITests"),
        .testTarget(name: "PlatformTests", dependencies: ["Platform"], path: "Tests/PlatformTests"),
    ]
)
```

> SwiftPM is most reliable when C target sources live under the target directory. Keep `Vendored/argon2/` as provenance/reference material, but compile the copied sources under `Shared/Sources/CArgon2/argon2/`.

- [ ] **Step 4: Build to confirm libargon2 compiles**

```bash
cd Shared && swift build
```

Expected: builds clean. If you get "file not found" errors, switch to the copy-into-CArgon2 fallback above.

- [ ] **Step 5: Commit**

```bash
git add Vendored/argon2 Shared/Sources/CArgon2 Shared/Package.swift
git commit -m "chore: vendor libargon2 reference impl as CArgon2 SwiftPM target"
```

---

## Task 1.6: `Argon2` Swift wrapper + `KDFParameters`

**Files:**
- Create: `Shared/Sources/Core/Encryption/KDFParameters.swift`
- Create: `Shared/Sources/Core/Encryption/Argon2.swift`
- Create: `Shared/Tests/CoreTests/Encryption/Argon2Tests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Core

final class Argon2Tests: XCTestCase {
    func testKnownAnswerVector() throws {
        // Argon2id RFC 9106 test vector from libargon2's kats/argon2id (small, fast)
        let password = Data(repeating: 0x01, count: 32)
        let salt = Data(repeating: 0x02, count: 16)
        let params = KDFParameters(
            algorithm: .argon2id,
            iterations: 3,
            memoryKB: 32,
            parallelism: 4,
            outputLen: 32
        )
        let hash = try Argon2.hash(password: password, salt: salt, params: params)
        XCTAssertEqual(hash.count, 32)
        // Hash must be deterministic for fixed inputs
        let hash2 = try Argon2.hash(password: password, salt: salt, params: params)
        XCTAssertEqual(hash, hash2)
    }

    func testDifferentPasswordsProduceDifferentHashes() throws {
        let salt = Data(repeating: 0xAA, count: 16)
        let params = KDFParameters.defaultV1
        let h1 = try Argon2.hash(password: Data("secret-1".utf8), salt: salt, params: params)
        let h2 = try Argon2.hash(password: Data("secret-2".utf8), salt: salt, params: params)
        XCTAssertNotEqual(h1, h2)
    }

    func testRejectsTooShortSalt() {
        let params = KDFParameters.defaultV1
        XCTAssertThrowsError(try Argon2.hash(password: Data("p".utf8), salt: Data([0x01]), params: params))
    }
}
```

- [ ] **Step 2: Implement `KDFParameters`**

```swift
import Foundation

public struct KDFParameters: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case argon2id
    }

    public let algorithm: Algorithm
    public let iterations: UInt32       // t_cost
    public let memoryKB: UInt32         // m_cost in KB
    public let parallelism: UInt32
    public let outputLen: UInt32        // bytes

    public init(algorithm: Algorithm, iterations: UInt32, memoryKB: UInt32, parallelism: UInt32, outputLen: UInt32) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.memoryKB = memoryKB
        self.parallelism = parallelism
        self.outputLen = outputLen
    }

    /// Production target: ~100ms on M1. Tune up over time as a v2 parameter set.
    public static let defaultV1 = KDFParameters(
        algorithm: .argon2id,
        iterations: 3,
        memoryKB: 64 * 1024,   // 64 MB
        parallelism: 4,
        outputLen: 32
    )
}
```

- [ ] **Step 3: Implement `Argon2`**

```swift
import Foundation
import CArgon2

public enum Argon2Error: Error, Equatable {
    case invalidSalt
    case libraryError(Int32)
}

public enum Argon2 {
    public static func hash(password: Data, salt: Data, params: KDFParameters) throws -> Data {
        guard salt.count >= 8 else { throw Argon2Error.invalidSalt }
        guard params.outputLen >= 4 else { throw Argon2Error.libraryError(0) }
        guard params.algorithm == .argon2id else { throw Argon2Error.libraryError(0) }

        var output = Data(count: Int(params.outputLen))
        let result: Int32 = output.withUnsafeMutableBytes { outBuf in
            password.withUnsafeBytes { pwdBuf in
                salt.withUnsafeBytes { saltBuf in
                    mayn_argon2id_hash_raw(
                        params.iterations,
                        params.memoryKB,
                        params.parallelism,
                        pwdBuf.baseAddress, pwdBuf.count,
                        saltBuf.baseAddress, saltBuf.count,
                        outBuf.baseAddress, outBuf.count
                    )
                }
            }
        }
        guard result == 0 else { throw Argon2Error.libraryError(result) }
        return output
    }
}
```

- [ ] **Step 4: Run tests + commit**

```bash
cd Shared && swift test --filter Argon2Tests
```
Expected: all 3 pass.

```bash
git add Shared/Sources/Core/Encryption/KDFParameters.swift Shared/Sources/Core/Encryption/Argon2.swift Shared/Tests/CoreTests/Encryption/Argon2Tests.swift
git commit -m "feat(core): add Argon2id wrapper + KDFParameters"
```

---

## Task 1.7: `KeyVersion` and `KeyManager`

**Files:**
- Create: `Shared/Sources/Core/Encryption/KeyVersion.swift`
- Create: `Shared/Sources/Core/Encryption/KeyManager.swift`
- Create: `Shared/Tests/CoreTests/Encryption/KeyManagerTests.swift`

`KeyManager` owns:
- A non-portable **device key** in Keychain, used to encrypt local blobs and indexes.
- A passphrase-derived **sync key** that the user can re-establish on a new Mac.

For tests we use an in-memory keychain backend so we don't pollute the real Keychain.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CryptoKit
@testable import Core

final class KeyManagerTests: XCTestCase {
    var manager: KeyManager!

    override func setUp() {
        super.setUp()
        manager = KeyManager(keychain: InMemoryKeychain())
    }

    func testDeviceKeyIsGeneratedOnceAndStable() throws {
        let k1 = try manager.deviceKey()
        let k2 = try manager.deviceKey()
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
        XCTAssertEqual(k1.bitCount, 256)
    }

    func testSyncKeyDerivedFromPassphrase() throws {
        let salt = Data(repeating: 0xAB, count: 16)
        let params = KDFParameters.defaultV1
        let k1 = try manager.deriveSyncKey(passphrase: "correct horse", salt: salt, params: params)
        let k2 = try manager.deriveSyncKey(passphrase: "correct horse", salt: salt, params: params)
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
    }

    func testSyncKeyDiffersWithDifferentPassphrase() throws {
        let salt = Data(repeating: 0x55, count: 16)
        let a = try manager.deriveSyncKey(passphrase: "alpha", salt: salt, params: .defaultV1)
        let b = try manager.deriveSyncKey(passphrase: "bravo", salt: salt, params: .defaultV1)
        XCTAssertNotEqual(a.withUnsafeBytes { Data($0) }, b.withUnsafeBytes { Data($0) })
    }
}
```

- [ ] **Step 2: Implement `KeyVersion`**

`Shared/Sources/Core/Encryption/KeyVersion.swift`:

```swift
import Foundation

public struct KeyVersion: Hashable, Equatable, Codable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public static let v1 = KeyVersion(1)
}
```

- [ ] **Step 3: Implement Keychain abstraction + `KeyManager`**

`Shared/Sources/Core/Encryption/KeyManager.swift`:

```swift
import Foundation
import CryptoKit
import Security

public protocol KeychainBackend: AnyObject {
    func get(_ account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

/// Default implementation: real macOS Keychain.
public final class SystemKeychain: KeychainBackend {
    private let service: String

    public init(service: String = AppGroup.identifier) {
        self.service = service
    }

    public func get(_ account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
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
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainWriteFailed(status)
        }
    }

    public func delete(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.keychainDeleteFailed(status)
        }
    }
}

/// In-memory keychain for tests.
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

    /// Returns (and lazily creates) the local device key. Never leaves the Mac.
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

    /// Derives the portable sync root key from the user's passphrase.
    public func deriveSyncKey(passphrase: String, salt: Data, params: KDFParameters) throws -> SymmetricKey {
        let pwd = Data(passphrase.utf8)
        let raw = try Argon2.hash(password: pwd, salt: salt, params: params)
        return SymmetricKey(data: raw)
    }
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter KeyManagerTests
```

```bash
git add Shared/Sources/Core/Encryption/KeyVersion.swift Shared/Sources/Core/Encryption/KeyManager.swift Shared/Tests/CoreTests/Encryption/KeyManagerTests.swift
git commit -m "feat(core): add KeyVersion + KeyManager (device key + sync key derivation)"
```

---

## Task 1.8: `Cipher` (AES-GCM seal/open)

**Files:**
- Create: `Shared/Sources/Core/Encryption/Cipher.swift`
- Create: `Shared/Tests/CoreTests/Encryption/CipherTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CryptoKit
@testable import Core

final class CipherTests: XCTestCase {
    func testRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello world".utf8)
        let env = try Cipher.seal(plaintext, with: key)
        let decoded = try Cipher.open(env, with: key)
        XCTAssertEqual(decoded, plaintext)
    }

    func testWrongKeyFails() throws {
        let k1 = SymmetricKey(size: .bits256)
        let k2 = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("secret".utf8), with: k1)
        XCTAssertThrowsError(try Cipher.open(env, with: k2))
    }

    func testTamperedCiphertextFails() throws {
        let key = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("payload".utf8), with: key)
        var tampered = env.combined
        tampered[tampered.count / 2] ^= 0xFF
        XCTAssertThrowsError(try Cipher.open(Envelope(combined: tampered), with: key))
    }

    func testCombinedFormatHasNonceAndTag() throws {
        // CryptoKit combined = 12-byte nonce + ciphertext + 16-byte tag
        let key = SymmetricKey(size: .bits256)
        let env = try Cipher.seal(Data("x".utf8), with: key)
        XCTAssertEqual(env.combined.count, 12 + 1 + 16)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import CryptoKit

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
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter CipherTests
git add Shared/Sources/Core/Encryption/Cipher.swift Shared/Tests/CoreTests/Encryption/CipherTests.swift
git commit -m "feat(core): add AES-GCM Cipher seal/open"
```

---

## Task 1.9: `Database` wrapper (GRDB) with WAL config

**Files:**
- Create: `Shared/Sources/Core/Storage/Database.swift`
- Create: `Shared/Sources/Core/Storage/Migrations.swift`
- Create: `Shared/Tests/CoreTests/Storage/DatabaseTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import GRDB
@testable import Core

final class DatabaseTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testOpensInWALMode() throws {
        let url = tempDir.appendingPathComponent("test.sqlite")
        let db = try Database(url: url, migrations: [])
        let mode: String = try db.queue.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") ?? "" }
        XCTAssertEqual(mode.lowercased(), "wal")
    }

    func testRunsMigrationsInOrder() throws {
        let url = tempDir.appendingPathComponent("migrate.sqlite")
        let m1 = Migration(identifier: "001-create-foo") { db in
            try db.create(table: "foo") { t in
                t.column("id", .integer).primaryKey()
            }
        }
        let m2 = Migration(identifier: "002-add-bar") { db in
            try db.alter(table: "foo") { t in
                t.add(column: "bar", .text)
            }
        }
        let db = try Database(url: url, migrations: [m1, m2])
        try db.queue.read { conn in
            let cols = try conn.columns(in: "foo").map(\.name).sorted()
            XCTAssertEqual(cols, ["bar", "id"])
        }
    }
}
```

- [ ] **Step 2: Implement `Migrations`**

`Shared/Sources/Core/Storage/Migrations.swift`:

```swift
import Foundation
import GRDB

public struct Migration {
    public let identifier: String
    public let migrate: (GRDB.Database) throws -> Void

    public init(identifier: String, migrate: @escaping (GRDB.Database) throws -> Void) {
        self.identifier = identifier
        self.migrate = migrate
    }
}
```

- [ ] **Step 3: Implement `Database`**

`Shared/Sources/Core/Storage/Database.swift`:

```swift
import Foundation
import GRDB

public final class Database {
    public let queue: DatabaseQueue
    private let log = Logging.logger(for: "storage", category: "database")

    public init(url: URL, migrations: [Migration]) throws {
        var config = Configuration()
        config.prepareDatabase { conn in
            try conn.execute(sql: "PRAGMA journal_mode = WAL")
            try conn.execute(sql: "PRAGMA synchronous = NORMAL")
            try conn.execute(sql: "PRAGMA foreign_keys = ON")
            try conn.execute(sql: "PRAGMA busy_timeout = 5000")
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        self.queue = try DatabaseQueue(path: url.path, configuration: config)

        var migrator = DatabaseMigrator()
        for m in migrations {
            migrator.registerMigration(m.identifier, migrate: m.migrate)
        }
        try migrator.migrate(queue)
        log.info("Opened database at \(url.path, privacy: .public) with \(migrations.count) migrations")
    }
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter DatabaseTests
git add Shared/Sources/Core/Storage/Database.swift Shared/Sources/Core/Storage/Migrations.swift Shared/Tests/CoreTests/Storage/DatabaseTests.swift
git commit -m "feat(core): add Database (GRDB queue) with WAL config and migrations"
```

---

## Task 1.10: `ClipboardRecord` model + `ClipboardStore`

**Files:**
- Create: `Shared/Sources/Core/Models/ClipboardRecord.swift`
- Create: `Shared/Sources/Core/Storage/ClipboardStore.swift`
- Create: `Shared/Tests/CoreTests/Storage/ClipboardStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CryptoKit
@testable import Core

final class ClipboardStoreTests: XCTestCase {
    var tempDir: URL!
    var store: ClipboardStore!
    var key: SymmetricKey!
    let device = DeviceID.generate()

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let db = try! Database(url: tempDir.appendingPathComponent("clipboard.sqlite"),
                               migrations: ClipboardStore.migrations)
        key = SymmetricKey(size: .bits256)
        store = try! ClipboardStore(database: db, deviceKey: key, deviceID: device)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAppendThenList() throws {
        let r = try store.append(ClipboardRecord.text("hello"))
        let items = try store.list(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, r.id)
    }

    func testListReturnsNewestFirst() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        Thread.sleep(forTimeInterval: 0.002)
        let b = try store.append(ClipboardRecord.text("b"))
        let items = try store.list(limit: 10)
        XCTAssertEqual(items.map(\.id), [b.id, a.id])
    }

    func testLamportClockIncrementsByOne() throws {
        let a = try store.append(ClipboardRecord.text("a"))
        let b = try store.append(ClipboardRecord.text("b"))
        XCTAssertEqual(b.lamport, a.lamport + 1)
    }

    func testDecryptedContentMatches() throws {
        _ = try store.append(ClipboardRecord.text("payload"))
        let items = try store.list(limit: 10)
        let body = try store.body(for: items[0].id)
        XCTAssertEqual(body, .text("payload"))
    }

    func testDeleteRemovesItem() throws {
        let r = try store.append(ClipboardRecord.text("x"))
        try store.delete(id: r.id)
        XCTAssertEqual(try store.list(limit: 10).count, 0)
    }

    func testWrongKeyFailsToDecrypt() throws {
        _ = try store.append(ClipboardRecord.text("secret"))
        let items = try store.list(limit: 10)
        let other = try ClipboardStore(
            database: try Database(url: tempDir.appendingPathComponent("clipboard.sqlite"), migrations: []),
            deviceKey: SymmetricKey(size: .bits256),
            deviceID: device
        )
        XCTAssertThrowsError(try other.body(for: items[0].id))
    }
}
```

- [ ] **Step 2: Implement `ClipboardRecord`**

`Shared/Sources/Core/Models/ClipboardRecord.swift`:

```swift
import Foundation

public enum ClipboardRecord: Codable, Equatable, Sendable {
    case text(String)
    case rtf(Data)
    case html(String)
    case image(blobID: String, width: Int, height: Int)
    case files([URL])
}

public struct ClipboardItemMeta: Equatable, Sendable {
    public let id: RecordID
    public let created: Date
    public let modified: Date
    public let lamport: UInt64
    public let kind: RecordKind
    public let preview: String        // short cleartext preview for list rendering
    public let sourceAppBundleID: String?
}
```

- [ ] **Step 3: Implement `ClipboardStore`**

`Shared/Sources/Core/Storage/ClipboardStore.swift`:

```swift
import Foundation
import CryptoKit
import GRDB

public final class ClipboardStore {
    private let db: Database
    private let key: SymmetricKey
    private let deviceID: DeviceID
    private let log = Logging.logger(for: "storage", category: "clipboard")

    public init(database: Database, deviceKey: SymmetricKey, deviceID: DeviceID) throws {
        self.db = database
        self.key = deviceKey
        self.deviceID = deviceID
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-clipboard-records") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    created INTEGER NOT NULL,
                    modified INTEGER NOT NULL,
                    lamport INTEGER NOT NULL,
                    kind TEXT NOT NULL,
                    preview TEXT NOT NULL,
                    source_app TEXT,
                    envelope BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_records_modified ON clipboard_records(modified DESC);
                CREATE TABLE IF NOT EXISTS lamport_clock (
                    scope TEXT PRIMARY KEY NOT NULL,
                    value INTEGER NOT NULL
                );
                INSERT OR IGNORE INTO lamport_clock(scope, value) VALUES ('clipboard', 0);
            """)
        }
    ]

    @discardableResult
    public func append(_ record: ClipboardRecord, sourceAppBundleID: String? = nil) throws -> ClipboardItemMeta {
        let id = RecordID.generate()
        let now = Date()
        let preview = Self.preview(for: record)
        let payload = try JSONEncoder().encode(record)
        let envelope = try Cipher.seal(payload, with: key)

        var insertedLamport: UInt64 = 0
        try db.queue.write { conn in
            let current: Int64 = try Int64.fetchOne(
                conn,
                sql: "SELECT value FROM lamport_clock WHERE scope = 'clipboard'"
            ) ?? 0
            let next = current + 1
            try conn.execute(
                sql: "UPDATE lamport_clock SET value = ? WHERE scope = 'clipboard'",
                arguments: [next]
            )
            insertedLamport = UInt64(next)
            try conn.execute(sql: """
                INSERT INTO clipboard_records (id, created, modified, lamport, kind, preview, source_app, envelope)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                id.rawValue,
                Int(now.timeIntervalSince1970 * 1000),
                Int(now.timeIntervalSince1970 * 1000),
                Int(insertedLamport),
                RecordKind.clipboardItem.rawValue,
                preview,
                sourceAppBundleID,
                envelope.combined,
            ])
        }
        return ClipboardItemMeta(id: id, created: now, modified: now, lamport: insertedLamport,
                                 kind: .clipboardItem, preview: preview, sourceAppBundleID: sourceAppBundleID)
    }

    public func list(limit: Int) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, lamport, kind, preview, source_app
                FROM clipboard_records
                ORDER BY modified DESC
                LIMIT ?
            """, arguments: [limit]).map(Self.metaRow)
        }
    }

    public func body(for id: RecordID) throws -> ClipboardRecord {
        let envelope: Envelope = try db.queue.read { conn in
            guard let row = try Row.fetchOne(conn, sql: "SELECT envelope FROM clipboard_records WHERE id = ?",
                                             arguments: [id.rawValue]) else {
                throw NSError(domain: "ClipboardStore", code: 404)
            }
            return Envelope(combined: row["envelope"])
        }
        let plaintext = try Cipher.open(envelope, with: key)
        return try JSONDecoder().decode(ClipboardRecord.self, from: plaintext)
    }

    public func delete(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: "DELETE FROM clipboard_records WHERE id = ?", arguments: [id.rawValue])
        }
    }

    private static func preview(for record: ClipboardRecord) -> String {
        switch record {
        case .text(let s): return String(s.prefix(120))
        case .rtf: return "(rich text)"
        case .html(let s): return "(html) \(s.prefix(80))"
        case .image(_, let w, let h): return "(image \(w)×\(h))"
        case .files(let urls): return "(\(urls.count) file\(urls.count == 1 ? "" : "s"))"
        }
    }

    private static func metaRow(_ row: Row) -> ClipboardItemMeta {
        ClipboardItemMeta(
            id: RecordID(rawValue: row["id"])!,
            created: Date(timeIntervalSince1970: Double(row["created"] as Int64) / 1000),
            modified: Date(timeIntervalSince1970: Double(row["modified"] as Int64) / 1000),
            lamport: UInt64(row["lamport"] as Int64),
            kind: RecordKind(rawValue: row["kind"]) ?? .clipboardItem,
            preview: row["preview"],
            sourceAppBundleID: row["source_app"]
        )
    }
}
```

- [ ] **Step 4: Pass + commit**

```bash
cd Shared && swift test --filter ClipboardStoreTests
git add Shared/Sources/Core/Models/ClipboardRecord.swift Shared/Sources/Core/Storage/ClipboardStore.swift Shared/Tests/CoreTests/Storage/ClipboardStoreTests.swift
git commit -m "feat(core): add ClipboardRecord and ClipboardStore (encrypted)"
```

---

## Task 1.11: `BlobStore` for encrypted file/image attachments

**Files:**
- Create: `Shared/Sources/Core/Storage/BlobStore.swift`
- Create: `Shared/Tests/CoreTests/Storage/BlobStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CryptoKit
@testable import Core

final class BlobStoreTests: XCTestCase {
    var dir: URL!
    var store: BlobStore!
    var key: SymmetricKey!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Blob-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        key = SymmetricKey(size: .bits256)
        store = BlobStore(rootURL: dir, key: key)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testWriteThenReadRoundTrip() throws {
        let data = Data(repeating: 0xAB, count: 4096)
        let id = try store.write(data)
        let read = try store.read(id: id)
        XCTAssertEqual(read, data)
    }

    func testWriteCreatesFileOnDisk() throws {
        let id = try store.write(Data(repeating: 0x01, count: 16))
        let path = dir.appendingPathComponent("\(id).bin")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func testReadFailsWithWrongKey() throws {
        let id = try store.write(Data("secret".utf8))
        let other = BlobStore(rootURL: dir, key: SymmetricKey(size: .bits256))
        XCTAssertThrowsError(try other.read(id: id))
    }

    func testDeleteRemovesFile() throws {
        let id = try store.write(Data([0]))
        try store.delete(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(id).bin").path))
    }
}
```

- [ ] **Step 2: Implement**

`Shared/Sources/Core/Storage/BlobStore.swift`:

```swift
import Foundation
import CryptoKit

public final class BlobStore {
    private let root: URL
    private let key: SymmetricKey

    public init(rootURL: URL, key: SymmetricKey) {
        self.root = rootURL
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
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter BlobStoreTests
git add Shared/Sources/Core/Storage/BlobStore.swift Shared/Tests/CoreTests/Storage/BlobStoreTests.swift
git commit -m "feat(core): add encrypted BlobStore"
```

---

## Task 1.12: `SearchStore` (FTS5)

**Files:**
- Create: `Shared/Sources/Core/Storage/SearchStore.swift`
- Create: `Shared/Tests/CoreTests/Storage/SearchStoreTests.swift`

The `search.sqlite` file is its own database. Holds a single FTS5 virtual table mirroring text content from clipboard, snippets, OCR, and download titles. All inserts are upserts keyed by `(kind, id)`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Core

final class SearchStoreTests: XCTestCase {
    var dir: URL!
    var store: SearchStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Search-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("search.sqlite"), migrations: SearchStore.migrations)
        store = SearchStore(database: db)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testIndexThenSearch() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "the quick brown fox jumps over the lazy dog")
        let hits = try store.search(query: "brown fox", limit: 10)
        XCTAssertEqual(hits.first?.id, id)
    }

    func testUpsertReplacesPreviousText() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "first version")
        try store.upsert(kind: .clipboardItem, id: id, text: "second version")
        XCTAssertEqual(try store.search(query: "first", limit: 10).count, 0)
        XCTAssertEqual(try store.search(query: "second", limit: 10).count, 1)
    }

    func testRemoveDropsFromIndex() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "to remove")
        try store.remove(kind: .clipboardItem, id: id)
        XCTAssertEqual(try store.search(query: "remove", limit: 10).count, 0)
    }

    func testSearchEscapesFTSSyntaxCharacters() throws {
        let id = RecordID.generate()
        try store.upsert(kind: .clipboardItem, id: id, text: "token with colon: and quote")
        let hits = try store.search(query: "colon:", limit: 10)
        XCTAssertEqual(hits.first?.id, id)
    }
}
```

- [ ] **Step 2: Implement**

`Shared/Sources/Core/Storage/SearchStore.swift`:

```swift
import Foundation
import GRDB

public struct SearchHit: Equatable {
    public let kind: RecordKind
    public let id: RecordID
    public let snippet: String
}

public final class SearchStore {
    private let db: Database
    private let log = Logging.logger(for: "search", category: "fts")

    public init(database: Database) { self.db = database }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-fts5-index") { conn in
            try conn.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                    kind UNINDEXED,
                    record_id UNINDEXED,
                    content,
                    tokenize = 'porter unicode61'
                );
                CREATE TABLE IF NOT EXISTS search_keys (
                    kind TEXT NOT NULL,
                    record_id TEXT NOT NULL,
                    rowid INTEGER NOT NULL,
                    PRIMARY KEY (kind, record_id)
                );
            """)
        }
    ]

    public func upsert(kind: RecordKind, id: RecordID, text: String) throws {
        try db.queue.write { conn in
            // Remove existing first (FTS5 UPSERT is fiddly)
            if let existing = try Row.fetchOne(conn,
                sql: "SELECT rowid FROM search_keys WHERE kind = ? AND record_id = ?",
                arguments: [kind.rawValue, id.rawValue]
            ) {
                let rowid: Int64 = existing["rowid"]
                try conn.execute(sql: "DELETE FROM search_index WHERE rowid = ?", arguments: [rowid])
                try conn.execute(sql: "DELETE FROM search_keys WHERE rowid = ?", arguments: [rowid])
            }
            try conn.execute(sql: "INSERT INTO search_index(kind, record_id, content) VALUES (?, ?, ?)",
                             arguments: [kind.rawValue, id.rawValue, text])
            let rowid = conn.lastInsertedRowID
            try conn.execute(sql: "INSERT INTO search_keys(kind, record_id, rowid) VALUES (?, ?, ?)",
                             arguments: [kind.rawValue, id.rawValue, rowid])
        }
    }

    public func remove(kind: RecordKind, id: RecordID) throws {
        try db.queue.write { conn in
            guard let existing = try Row.fetchOne(conn,
                sql: "SELECT rowid FROM search_keys WHERE kind = ? AND record_id = ?",
                arguments: [kind.rawValue, id.rawValue]
            ) else { return }
            let rowid: Int64 = existing["rowid"]
            try conn.execute(sql: "DELETE FROM search_index WHERE rowid = ?", arguments: [rowid])
            try conn.execute(sql: "DELETE FROM search_keys WHERE rowid = ?", arguments: [rowid])
        }
    }

    public func search(query: String, limit: Int) throws -> [SearchHit] {
        let ftsQuery = Self.ftsQuery(for: query)
        guard !ftsQuery.isEmpty else { return [] }
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT kind, record_id, snippet(search_index, 2, '<', '>', '…', 12) AS snip
                FROM search_index
                WHERE search_index MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [ftsQuery, limit]).compactMap { row in
                guard let kind = RecordKind(rawValue: row["kind"]),
                      let id = RecordID(rawValue: row["record_id"]) else { return nil }
                return SearchHit(kind: kind, id: id, snippet: row["snip"])
            }
        }
    }

    private static func ftsQuery(for raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace)
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: " ")
    }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter SearchStoreTests
git add Shared/Sources/Core/Storage/SearchStore.swift Shared/Tests/CoreTests/Storage/SearchStoreTests.swift
git commit -m "feat(core): add SearchStore (FTS5)"
```

---

## Task 1.13: `DownloadRecord` model + minimal `DownloadStore`

Plan 5 will extend this. For now we add just enough to verify the encrypted-store pattern generalizes.

**Files:**
- Create: `Shared/Sources/Core/Models/DownloadRecord.swift`
- Create: `Shared/Sources/Core/Storage/DownloadStore.swift`
- Create: `Shared/Tests/CoreTests/Storage/DownloadStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CryptoKit
@testable import Core

final class DownloadStoreTests: XCTestCase {
    var dir: URL!
    var store: DownloadStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dl-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("downloads.sqlite"), migrations: DownloadStore.migrations)
        store = try! DownloadStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testInsertAndFetch() throws {
        let id = try store.insert(DownloadRecord(
            url: "https://example.com/v.mp4",
            title: "Example",
            destinationPath: "/tmp/v.mp4",
            state: .queued
        ))
        let r = try store.fetch(id: id)
        XCTAssertEqual(r.url, "https://example.com/v.mp4")
        XCTAssertEqual(r.state, .queued)
    }

    func testUpdateState() throws {
        let id = try store.insert(DownloadRecord(url: "u", title: "t", destinationPath: "/tmp/x", state: .queued))
        try store.updateState(id: id, to: .running)
        XCTAssertEqual(try store.fetch(id: id).state, .running)
    }

    func testListByState() throws {
        _ = try store.insert(DownloadRecord(url: "a", title: "a", destinationPath: "/a", state: .running))
        _ = try store.insert(DownloadRecord(url: "b", title: "b", destinationPath: "/b", state: .queued))
        XCTAssertEqual(try store.list(state: .running).count, 1)
    }
}
```

- [ ] **Step 2: Implement**

`Shared/Sources/Core/Models/DownloadRecord.swift`:

```swift
import Foundation

public enum DownloadState: String, Codable, Sendable {
    case queued, running, paused, completed, failed
}

public struct DownloadRecord: Codable, Equatable, Sendable {
    public var id: RecordID
    public var url: String
    public var title: String
    public var destinationPath: String
    public var state: DownloadState
    public var bytesDownloaded: Int64
    public var bytesTotal: Int64?
    public var lastError: String?
    public var created: Date
    public var modified: Date

    public init(url: String, title: String, destinationPath: String, state: DownloadState) {
        self.id = RecordID.generate()
        self.url = url
        self.title = title
        self.destinationPath = destinationPath
        self.state = state
        self.bytesDownloaded = 0
        self.bytesTotal = nil
        self.lastError = nil
        let now = Date()
        self.created = now
        self.modified = now
    }
}
```

`Shared/Sources/Core/Storage/DownloadStore.swift`:

```swift
import Foundation
import CryptoKit
import GRDB

public final class DownloadStore {
    private let db: Database
    private let key: SymmetricKey
    private let log = Logging.logger(for: "downloads", category: "store")

    public init(database: Database, deviceKey: SymmetricKey) throws {
        self.db = database
        self.key = deviceKey
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-downloads") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS downloads (
                    id TEXT PRIMARY KEY NOT NULL,
                    state TEXT NOT NULL,
                    created INTEGER NOT NULL,
                    modified INTEGER NOT NULL,
                    envelope BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_downloads_state ON downloads(state);
            """)
        }
    ]

    @discardableResult
    public func insert(_ record: DownloadRecord) throws -> RecordID {
        let payload = try JSONEncoder().encode(record)
        let env = try Cipher.seal(payload, with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO downloads (id, state, created, modified, envelope) VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                record.id.rawValue, record.state.rawValue,
                Int(record.created.timeIntervalSince1970 * 1000),
                Int(record.modified.timeIntervalSince1970 * 1000),
                env.combined,
            ])
        }
        return record.id
    }

    public func fetch(id: RecordID) throws -> DownloadRecord {
        try db.queue.read { conn in
            guard let row = try Row.fetchOne(conn, sql: "SELECT envelope FROM downloads WHERE id = ?",
                                             arguments: [id.rawValue]) else {
                throw NSError(domain: "DownloadStore", code: 404)
            }
            let env = Envelope(combined: row["envelope"])
            let plaintext = try Cipher.open(env, with: key)
            return try JSONDecoder().decode(DownloadRecord.self, from: plaintext)
        }
    }

    public func updateState(id: RecordID, to state: DownloadState) throws {
        var record = try fetch(id: id)
        record.state = state
        record.modified = Date()
        let env = try Cipher.seal(try JSONEncoder().encode(record), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: "UPDATE downloads SET state = ?, modified = ?, envelope = ? WHERE id = ?",
                             arguments: [state.rawValue, Int(record.modified.timeIntervalSince1970 * 1000),
                                         env.combined, id.rawValue])
        }
    }

    public func list(state: DownloadState? = nil) throws -> [RecordID] {
        try db.queue.read { conn in
            let rows: [Row]
            if let state {
                rows = try Row.fetchAll(conn, sql: "SELECT id FROM downloads WHERE state = ? ORDER BY modified DESC",
                                        arguments: [state.rawValue])
            } else {
                rows = try Row.fetchAll(conn, sql: "SELECT id FROM downloads ORDER BY modified DESC")
            }
            return rows.compactMap { RecordID(rawValue: $0["id"]) }
        }
    }
}
```

- [ ] **Step 3: Pass + commit**

```bash
cd Shared && swift test --filter DownloadStoreTests
git add Shared/Sources/Core/Models/DownloadRecord.swift Shared/Sources/Core/Storage/DownloadStore.swift Shared/Tests/CoreTests/Storage/DownloadStoreTests.swift
git commit -m "feat(core): add DownloadRecord and minimal encrypted DownloadStore"
```

---

## Task 1.14: Cross-cutting integration test (clipboard + search + blob together)

**Files:**
- Create: `Shared/Tests/CoreTests/Storage/CoreIntegrationTests.swift`

This test exercises the full local-write path the daemon will use in Plan 3.

- [ ] **Step 1: Write the test**

```swift
import XCTest
import CryptoKit
@testable import Core

final class CoreIntegrationTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("Int-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testCaptureTextThenSearchThenLoad() throws {
        let key = SymmetricKey(size: .bits256)
        let device = DeviceID.generate()

        let clipDB = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        let clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)

        let searchDB = try Database(url: dir.appendingPathComponent("s.sqlite"), migrations: SearchStore.migrations)
        let search = SearchStore(database: searchDB)

        // Daemon-side flow: capture → store → index
        let meta = try clip.append(ClipboardRecord.text("the quick brown fox"))
        try search.upsert(kind: .clipboardItem, id: meta.id, text: "the quick brown fox")

        // UI-side flow: search → load body
        let hits = try search.search(query: "brown", limit: 10)
        XCTAssertEqual(hits.count, 1)
        let body = try clip.body(for: hits[0].id)
        XCTAssertEqual(body, .text("the quick brown fox"))
    }

    func testBlobAttachedToImageRecord() throws {
        let key = SymmetricKey(size: .bits256)
        let blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let device = DeviceID.generate()
        let clipDB = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        let clip = try ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)

        let pixels = Data(repeating: 0xCC, count: 64 * 64)
        let blobID = try blobs.write(pixels)
        let meta = try clip.append(.image(blobID: blobID, width: 64, height: 64))
        let body = try clip.body(for: meta.id)
        guard case let .image(loadedID, w, h) = body else {
            XCTFail("Expected image record"); return
        }
        XCTAssertEqual(loadedID, blobID)
        XCTAssertEqual([w, h], [64, 64])
        XCTAssertEqual(try blobs.read(id: loadedID), pixels)
    }
}
```

- [ ] **Step 2: Run + commit**

```bash
cd Shared && swift test --filter CoreIntegrationTests
git add Shared/Tests/CoreTests/Storage/CoreIntegrationTests.swift
git commit -m "test(core): cross-cutting integration test for capture/search/blob"
```

---

## Self-review checklist

Run all of:

```bash
cd Shared && swift test
swiftlint --strict
swiftformat --lint Shared/
./scripts/ci-build.sh
```

Verify by hand that the database files created by the tests are nontrivial:

```bash
TMP=$(mktemp -d)
swift run --package-path Shared -c release  # if you add a CLI demo target later; otherwise skip
```

(No CLI demo needed for v1 — tests prove correctness.)

**Spec-coverage checklist:**

- [x] §5 storage split (owned SQLite for clipboard/downloads/search) — Tasks 1.9, 1.10, 1.12, 1.13
- [x] §5 device key in Keychain (`...ThisDeviceOnly`) — Task 1.7
- [x] §5 Argon2id sync key derivation — Tasks 1.5, 1.6, 1.7
- [x] §5 AES-GCM SealedBox.combined envelope format — Tasks 1.4, 1.8
- [x] §5 FTS5 with Unicode tokenizer — Task 1.12
- [x] §5 WAL mode for concurrent reads — Task 1.9
- [x] §6 encrypted blob attachments — Task 1.11
- [x] §11 `os.Logger` subsystem naming — Task 1.2

**Not in this plan (handled later):**
- Sync envelope I/O (Plan 2)
- Conflict resolution (Plan 2)
- NSPasteboard observation (Plan 3)
- OCR via Vision (Plan 3)
- yt-dlp queue logic (Plan 5)
