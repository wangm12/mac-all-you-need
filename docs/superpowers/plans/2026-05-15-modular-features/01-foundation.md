# Phase 01 — Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the foundational types (`FeatureID`, `FeatureRuntimeState`, `AssetState`, `ActivationState`, `FeatureDescriptor`, `FeatureRegistry`, `FeatureActivator` protocol, `FeatureManager` actor) and persist state to App Group settings. No user-visible change yet — this is internal scaffolding that everything else builds on.

**Architecture:** All new types live in a new Swift package target `FeatureCore` inside the existing `Shared/` SwiftPM workspace. `FeatureManager` is a Swift actor that owns the per-feature `FeatureRuntimeState`. State persists to `AppGroupSettings` as JSON-encoded values keyed by `feature.<id>.runtimeState`. Every successful write posts a Darwin notification (the consumer lands in Phase 10).

**Tech Stack:** Swift 5.9+, Swift actors, `Codable`, `AppGroupSettings` (existing in `Shared/Sources/Core/AppGroupSettings.swift`), `CFNotificationCenterPostNotification`.

---

## File structure

```
Shared/Sources/FeatureCore/
├── FeatureID.swift
├── AssetState.swift
├── ActivationState.swift
├── FeatureRuntimeState.swift
├── FeatureDescriptor.swift
├── FeatureRegistry.swift
├── FeatureActivator.swift
├── FeatureManager.swift
├── FeaturePackManifest.swift
├── AssetPack.swift
├── AssetCacheDescriptor.swift
└── DarwinNotification.swift           # thin CFNotification wrapper

Shared/Tests/FeatureCoreTests/
├── FeatureRuntimeStateTests.swift
├── FeatureRegistryTests.swift
├── FeatureManagerStateMachineTests.swift
├── FeatureManagerPersistenceTests.swift
└── FeaturePackManifestDecodingTests.swift

Shared/Package.swift                    # add FeatureCore target + tests
```

Why a new SwiftPM target instead of in `Core`: `FeatureCore` introduces actor-based state and Darwin-notification machinery that's distinct from `Core`'s settings/key store. Keeping it isolated lets us evolve the manifest schema without churning unrelated `Core` consumers.

---

### Task 1: Add `FeatureCore` SwiftPM target

**Files:**
- Modify: `Shared/Package.swift`

- [ ] **Step 1: Read current Package.swift to find existing target patterns**

Run: `cat /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Package.swift`

Look for existing `.target(name: "Core", …)` and `.testTarget(name: "CoreTests", …)` to mirror.

- [ ] **Step 2: Add FeatureCore target to products and targets arrays**

Edit `Shared/Package.swift`:

In the `products` array, append:
```swift
.library(name: "FeatureCore", targets: ["FeatureCore"]),
```

In the `targets` array, append:
```swift
.target(
    name: "FeatureCore",
    dependencies: ["Core"],
    path: "Sources/FeatureCore"
),
.testTarget(
    name: "FeatureCoreTests",
    dependencies: ["FeatureCore"],
    path: "Tests/FeatureCoreTests"
),
```

- [ ] **Step 3: Create the source directories**

Run:
```bash
mkdir -p /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/FeatureCore
mkdir -p /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Tests/FeatureCoreTests
```

- [ ] **Step 4: Add a placeholder source file so SPM resolves the target**

Create `Shared/Sources/FeatureCore/FeatureCore.swift`:
```swift
// Module entry point. Real types land in subsequent tasks.
```

- [ ] **Step 5: Verify the package resolves**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift build --target FeatureCore
```

Expected: `Build complete!` (no errors).

- [ ] **Step 6: Commit**

```bash
git add Shared/Package.swift Shared/Sources/FeatureCore/FeatureCore.swift
git commit -m "feat(modular-features): add FeatureCore SwiftPM target"
```

---

### Task 2: `FeatureID` enum

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureID.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureIDTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureIDTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class FeatureIDTests: XCTestCase {
    func testAllCasesPresent() {
        let expected: Set<FeatureID> = [.clipboard, .folderPreview, .downloader, .voice]
        XCTAssertEqual(Set(FeatureID.allCases), expected)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(FeatureID.clipboard.rawValue, "clipboard")
        XCTAssertEqual(FeatureID.folderPreview.rawValue, "folderPreview")
        XCTAssertEqual(FeatureID.downloader.rawValue, "downloader")
        XCTAssertEqual(FeatureID.voice.rawValue, "voice")
    }

    func testCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(FeatureID.clipboard)
        let decoded = try JSONDecoder().decode(FeatureID.self, from: encoded)
        XCTAssertEqual(decoded, .clipboard)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureIDTests
```
Expected: FAIL with "no such module 'FeatureCore'" or "type 'FeatureID' not in scope".

- [ ] **Step 3: Write the implementation**

Create `Shared/Sources/FeatureCore/FeatureID.swift`:
```swift
import Foundation

public enum FeatureID: String, CaseIterable, Codable, Sendable, Hashable {
    case clipboard
    case folderPreview
    case downloader
    case voice
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeatureIDTests` (same command as Step 2).
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureID.swift Shared/Tests/FeatureCoreTests/FeatureIDTests.swift
git commit -m "feat(modular-features): add FeatureID enum"
```

---

### Task 3: `AssetState` and `ActivationState` enums

**Files:**
- Create: `Shared/Sources/FeatureCore/AssetState.swift`
- Create: `Shared/Sources/FeatureCore/ActivationState.swift`
- Create: `Shared/Tests/FeatureCoreTests/StatesTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/StatesTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class StatesTests: XCTestCase {
    func testAssetStateCases() {
        // smoke: ensure all cases compile and are equatable
        let a: AssetState = .notRequired
        let b: AssetState = .notDownloaded
        let c: AssetState = .downloading(progress: 0.5)
        let d: AssetState = .downloadFailed(reason: "disk full")
        let e: AssetState = .present(version: "1.0.0")

        XCTAssertEqual(a, .notRequired)
        XCTAssertEqual(b, .notDownloaded)
        XCTAssertEqual(c, .downloading(progress: 0.5))
        XCTAssertEqual(d, .downloadFailed(reason: "disk full"))
        XCTAssertEqual(e, .present(version: "1.0.0"))
        XCTAssertNotEqual(c, .downloading(progress: 0.6))
    }

    func testActivationStateCases() {
        XCTAssertEqual(ActivationState.disabled, .disabled)
        XCTAssertEqual(ActivationState.enabled, .enabled)
        XCTAssertNotEqual(ActivationState.disabled, .enabled)
    }

    func testAssetStateCodableRoundTrip() throws {
        let cases: [AssetState] = [
            .notRequired,
            .notDownloaded,
            .downloading(progress: 0.42),
            .downloadFailed(reason: "SHA mismatch"),
            .present(version: "1.0.0"),
        ]
        for value in cases {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AssetState.self, from: data)
            XCTAssertEqual(value, decoded, "round-trip failed for \(value)")
        }
    }

    func testActivationStateCodableRoundTrip() throws {
        for value in [ActivationState.disabled, .enabled] {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(ActivationState.self, from: data)
            XCTAssertEqual(value, decoded)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StatesTests`.
Expected: FAIL ("type 'AssetState' not in scope").

- [ ] **Step 3: Implement AssetState**

Create `Shared/Sources/FeatureCore/AssetState.swift`:
```swift
import Foundation

public enum AssetState: Equatable, Sendable {
    case notRequired
    case notDownloaded
    case downloading(progress: Double)
    case downloadFailed(reason: String)
    case present(version: String)
}

extension AssetState: Codable {
    private enum CodingKeys: String, CodingKey { case kind, progress, reason, version }
    private enum Kind: String, Codable { case notRequired, notDownloaded, downloading, downloadFailed, present }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .notRequired: self = .notRequired
        case .notDownloaded: self = .notDownloaded
        case .downloading: self = .downloading(progress: try c.decode(Double.self, forKey: .progress))
        case .downloadFailed: self = .downloadFailed(reason: try c.decode(String.self, forKey: .reason))
        case .present: self = .present(version: try c.decode(String.self, forKey: .version))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notRequired: try c.encode(Kind.notRequired, forKey: .kind)
        case .notDownloaded: try c.encode(Kind.notDownloaded, forKey: .kind)
        case .downloading(let p):
            try c.encode(Kind.downloading, forKey: .kind)
            try c.encode(p, forKey: .progress)
        case .downloadFailed(let r):
            try c.encode(Kind.downloadFailed, forKey: .kind)
            try c.encode(r, forKey: .reason)
        case .present(let v):
            try c.encode(Kind.present, forKey: .kind)
            try c.encode(v, forKey: .version)
        }
    }
}
```

- [ ] **Step 4: Implement ActivationState**

Create `Shared/Sources/FeatureCore/ActivationState.swift`:
```swift
import Foundation

public enum ActivationState: String, Codable, Equatable, Sendable {
    case disabled
    case enabled
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter StatesTests`.
Expected: PASS, 4/4 tests.

- [ ] **Step 6: Commit**

```bash
git add Shared/Sources/FeatureCore/AssetState.swift Shared/Sources/FeatureCore/ActivationState.swift Shared/Tests/FeatureCoreTests/StatesTests.swift
git commit -m "feat(modular-features): add AssetState + ActivationState"
```

---

### Task 4: `FeatureRuntimeState` aggregate

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureRuntimeState.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureRuntimeStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureRuntimeStateTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class FeatureRuntimeStateTests: XCTestCase {
    func testInitialDefault() {
        let state = FeatureRuntimeState.initialDefault(assetRequired: true)
        XCTAssertEqual(state.assetState, .notDownloaded)
        XCTAssertEqual(state.activationState, .disabled)
    }

    func testInitialDefaultForSwiftOnly() {
        let state = FeatureRuntimeState.initialDefault(assetRequired: false)
        XCTAssertEqual(state.assetState, .notRequired)
        XCTAssertEqual(state.activationState, .disabled)
    }

    func testCanActivateOnlyWhenAssetReady() {
        let states: [(FeatureRuntimeState, Bool)] = [
            (.init(assetState: .notRequired, activationState: .disabled), true),
            (.init(assetState: .present(version: "1.0"), activationState: .disabled), true),
            (.init(assetState: .notDownloaded, activationState: .disabled), false),
            (.init(assetState: .downloading(progress: 0), activationState: .disabled), false),
            (.init(assetState: .downloadFailed(reason: ""), activationState: .disabled), false),
        ]
        for (state, expected) in states {
            XCTAssertEqual(state.canActivate, expected, "canActivate wrong for \(state)")
        }
    }

    func testCodableRoundTrip() throws {
        let cases: [FeatureRuntimeState] = [
            .init(assetState: .notRequired, activationState: .enabled),
            .init(assetState: .present(version: "2.0"), activationState: .disabled),
            .init(assetState: .downloading(progress: 0.7), activationState: .disabled),
        ]
        for state in cases {
            let data = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(FeatureRuntimeState.self, from: data)
            XCTAssertEqual(state, decoded)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeatureRuntimeStateTests`.
Expected: FAIL ("type 'FeatureRuntimeState' not in scope").

- [ ] **Step 3: Implement FeatureRuntimeState**

Create `Shared/Sources/FeatureCore/FeatureRuntimeState.swift`:
```swift
import Foundation

public struct FeatureRuntimeState: Equatable, Sendable, Codable {
    public let assetState: AssetState
    public let activationState: ActivationState

    public init(assetState: AssetState, activationState: ActivationState) {
        self.assetState = assetState
        self.activationState = activationState
    }

    public static func initialDefault(assetRequired: Bool) -> FeatureRuntimeState {
        .init(
            assetState: assetRequired ? .notDownloaded : .notRequired,
            activationState: .disabled
        )
    }

    public var canActivate: Bool {
        switch assetState {
        case .notRequired, .present: return true
        case .notDownloaded, .downloading, .downloadFailed: return false
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeatureRuntimeStateTests`.
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureRuntimeState.swift Shared/Tests/FeatureCoreTests/FeatureRuntimeStateTests.swift
git commit -m "feat(modular-features): add FeatureRuntimeState aggregate"
```

---

### Task 5: `AssetPack`, `AssetCacheDescriptor`, supporting types

**Files:**
- Create: `Shared/Sources/FeatureCore/AssetPack.swift`
- Create: `Shared/Sources/FeatureCore/AssetCacheDescriptor.swift`

- [ ] **Step 1: Implement AssetPack**

Create `Shared/Sources/FeatureCore/AssetPack.swift`:
```swift
import Foundation

public struct AssetPack: Equatable, Sendable {
    public let id: String                      // matches FeatureID raw string
    public let bundledManifestKey: String      // key into FeaturePackManifest.packs
    public init(id: String, bundledManifestKey: String) {
        self.id = id
        self.bundledManifestKey = bundledManifestKey
    }
}
```

- [ ] **Step 2: Implement AssetCacheDescriptor**

Create `Shared/Sources/FeatureCore/AssetCacheDescriptor.swift`:
```swift
import Foundation

public enum AssetCacheCategory: String, Sendable {
    case modelWeights, databaseCache, other
}

public struct AssetCacheDescriptor: Sendable {
    public let id: String
    public let displayName: String
    public let directoryURL: @Sendable () -> URL
    public let estimatedBytes: Int64
    public let category: AssetCacheCategory

    public init(
        id: String,
        displayName: String,
        directoryURL: @escaping @Sendable () -> URL,
        estimatedBytes: Int64,
        category: AssetCacheCategory
    ) {
        self.id = id
        self.displayName = displayName
        self.directoryURL = directoryURL
        self.estimatedBytes = estimatedBytes
        self.category = category
    }

    /// Actual on-disk size, computed by walking the directory. Returns 0 if missing.
    public func actualBytes() -> Int64 {
        let url = directoryURL()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift build --target FeatureCore
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Sources/FeatureCore/AssetPack.swift Shared/Sources/FeatureCore/AssetCacheDescriptor.swift
git commit -m "feat(modular-features): add AssetPack + AssetCacheDescriptor"
```

---

### Task 6: `FeaturePackManifest` (and tests for JSON decoding)

**Files:**
- Create: `Shared/Sources/FeatureCore/FeaturePackManifest.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeaturePackManifestDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeaturePackManifestDecodingTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class FeaturePackManifestDecodingTests: XCTestCase {
    func testValidManifest() throws {
        let json = """
        {
          "schemaVersion": 1,
          "wrapperVersion": "2.0.0",
          "packs": {
            "downloader": {
              "version": "1.0.0",
              "url": "https://github.com/owner/repo/releases/download/v2.0.0/Downloader-1.0.0.zip",
              "zipSha256": "abc",
              "sizeBytes": 200,
              "files": {
                "yt-dlp": { "sha256": "111", "executable": true, "maxBytes": 50 },
                "ffmpeg": { "sha256": "222", "executable": true, "maxBytes": 200 }
              },
              "codesignRequirement": "anchor apple generic and certificate leaf [subject.OU] = \\"TEAM\\""
            }
          }
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(FeaturePackManifest.self, from: json)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.wrapperVersion, "2.0.0")
        XCTAssertEqual(manifest.packs.count, 1)

        let pack = manifest.packs["downloader"]!
        XCTAssertEqual(pack.version, "1.0.0")
        XCTAssertEqual(pack.zipSha256, "abc")
        XCTAssertEqual(pack.sizeBytes, 200)
        XCTAssertEqual(pack.files.count, 2)
        XCTAssertEqual(pack.files["yt-dlp"]?.sha256, "111")
        XCTAssertTrue(pack.files["yt-dlp"]!.executable)
        XCTAssertEqual(pack.files["yt-dlp"]?.maxBytes, 50)
    }

    func testRejectsMismatchedSchemaVersion() {
        let json = #"{"schemaVersion":2,"wrapperVersion":"1","packs":{}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try FeaturePackManifest.decode(from: json, expectedSchemaVersion: 1)) { error in
            XCTAssertTrue(error is FeaturePackManifest.DecodingFailure)
        }
    }

    func testRejectsMissingFields() {
        let json = #"{"schemaVersion":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(FeaturePackManifest.self, from: json))
    }

    func testRejectsMissingPerFileSha() {
        let json = """
        {
          "schemaVersion": 1, "wrapperVersion": "1",
          "packs": { "downloader": {
            "version":"1","url":"https://x","zipSha256":"a","sizeBytes":1,
            "files": { "yt-dlp": { "executable": true, "maxBytes": 1 } },
            "codesignRequirement":"r"
          }}
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(FeaturePackManifest.self, from: json))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeaturePackManifestDecodingTests`.
Expected: FAIL ("type 'FeaturePackManifest' not in scope").

- [ ] **Step 3: Implement FeaturePackManifest**

Create `Shared/Sources/FeatureCore/FeaturePackManifest.swift`:
```swift
import Foundation

public struct FeaturePackManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wrapperVersion: String
    public let packs: [String: PackEntry]

    public struct PackEntry: Codable, Equatable, Sendable {
        public let version: String
        public let url: URL
        public let zipSha256: String
        public let sizeBytes: Int64
        public let files: [String: FileEntry]
        public let codesignRequirement: String
    }

    public struct FileEntry: Codable, Equatable, Sendable {
        public let sha256: String
        public let executable: Bool
        public let maxBytes: Int64
    }

    public enum DecodingFailure: Error, Equatable {
        case schemaMismatch(expected: Int, found: Int)
    }

    public static func decode(from data: Data, expectedSchemaVersion: Int) throws -> FeaturePackManifest {
        let manifest = try JSONDecoder().decode(FeaturePackManifest.self, from: data)
        if manifest.schemaVersion != expectedSchemaVersion {
            throw DecodingFailure.schemaMismatch(expected: expectedSchemaVersion, found: manifest.schemaVersion)
        }
        return manifest
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeaturePackManifestDecodingTests`.
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeaturePackManifest.swift Shared/Tests/FeatureCoreTests/FeaturePackManifestDecodingTests.swift
git commit -m "feat(modular-features): add FeaturePackManifest + decoding tests"
```

---

### Task 7: `FeatureActivator` protocol + `FeatureDescriptor`

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureActivator.swift`
- Create: `Shared/Sources/FeatureCore/FeatureDescriptor.swift`

- [ ] **Step 1: Implement FeatureActivator**

Create `Shared/Sources/FeatureCore/FeatureActivator.swift`:
```swift
import Foundation

public protocol FeatureActivator: Sendable {
    func activate() async throws
    func deactivate() async throws
}

/// A no-op activator used in tests and as a default for skeleton features.
public struct NoopFeatureActivator: FeatureActivator {
    public init() {}
    public func activate() async throws {}
    public func deactivate() async throws {}
}
```

- [ ] **Step 2: Implement FeatureDescriptor**

Create `Shared/Sources/FeatureCore/FeatureDescriptor.swift`:
```swift
import Foundation
import SwiftUI

public enum Permission: String, Sendable, Codable, Hashable {
    case accessibility
    case fullDiskAccess
    case microphone
    case notifications
}

public struct HotkeyDescriptor: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }
}

public enum OSExtensionPolicy: Sendable {
    case none
    case staticBundleExtension(StaticExtensionConfig)
}

public struct StaticExtensionConfig: Sendable {
    public let extensionBundleID: String
    public let runsRegardlessOfFeatureState: Bool
    public let respectsFeatureFlag: Bool
    public init(
        extensionBundleID: String,
        runsRegardlessOfFeatureState: Bool,
        respectsFeatureFlag: Bool
    ) {
        self.extensionBundleID = extensionBundleID
        self.runsRegardlessOfFeatureState = runsRegardlessOfFeatureState
        self.respectsFeatureFlag = respectsFeatureFlag
    }
}

public struct FeatureDescriptor: Sendable {
    public let id: FeatureID
    public let displayName: String
    public let icon: String
    public let summary: String
    public let detailDescription: String
    public let requiredPermissions: [Permission]
    public let assetPacks: [AssetPack]
    public let assetCaches: [AssetCacheDescriptor]
    public let hotkeys: [HotkeyDescriptor]
    public let osExtensionPolicy: OSExtensionPolicy
    public let activator: any FeatureActivator
    public let settingsTabFactory: (@Sendable () -> AnyView)?
    public let onboardingSetupFactory: (@Sendable () -> AnyView)?
    public let menuBarItemFactory: (@Sendable () -> AnyView)?

    public init(
        id: FeatureID,
        displayName: String,
        icon: String,
        summary: String,
        detailDescription: String,
        requiredPermissions: [Permission] = [],
        assetPacks: [AssetPack] = [],
        assetCaches: [AssetCacheDescriptor] = [],
        hotkeys: [HotkeyDescriptor] = [],
        osExtensionPolicy: OSExtensionPolicy = .none,
        activator: any FeatureActivator,
        settingsTabFactory: (@Sendable () -> AnyView)? = nil,
        onboardingSetupFactory: (@Sendable () -> AnyView)? = nil,
        menuBarItemFactory: (@Sendable () -> AnyView)? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.summary = summary
        self.detailDescription = detailDescription
        self.requiredPermissions = requiredPermissions
        self.assetPacks = assetPacks
        self.assetCaches = assetCaches
        self.hotkeys = hotkeys
        self.osExtensionPolicy = osExtensionPolicy
        self.activator = activator
        self.settingsTabFactory = settingsTabFactory
        self.onboardingSetupFactory = onboardingSetupFactory
        self.menuBarItemFactory = menuBarItemFactory
    }

    public var requiresAsset: Bool { !assetPacks.isEmpty }
}
```

- [ ] **Step 3: Verify it compiles**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift build --target FeatureCore
```
Expected: `Build complete!`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureActivator.swift Shared/Sources/FeatureCore/FeatureDescriptor.swift
git commit -m "feat(modular-features): add FeatureActivator + FeatureDescriptor"
```

---

### Task 8: `FeatureRegistry`

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureRegistry.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureRegistryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureRegistryTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import FeatureCore

private func makeDescriptor(_ id: FeatureID) -> FeatureDescriptor {
    FeatureDescriptor(
        id: id, displayName: id.rawValue, icon: "circle",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
}

final class FeatureRegistryTests: XCTestCase {
    func testIterationOrder() {
        let registry = FeatureRegistry(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.folderPreview),
            makeDescriptor(.downloader),
            makeDescriptor(.voice),
        ])
        XCTAssertEqual(registry.descriptors.map(\.id), [.clipboard, .folderPreview, .downloader, .voice])
    }

    func testLookupById() {
        let registry = FeatureRegistry(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.voice),
        ])
        XCTAssertNotNil(registry.descriptor(for: .clipboard))
        XCTAssertNotNil(registry.descriptor(for: .voice))
        XCTAssertNil(registry.descriptor(for: .downloader))
    }

    func testRejectsDuplicateIDs() {
        XCTAssertThrowsError(try FeatureRegistry.validated(descriptors: [
            makeDescriptor(.clipboard),
            makeDescriptor(.clipboard),
        ])) { error in
            XCTAssertEqual(error as? FeatureRegistry.ValidationError, .duplicateID(.clipboard))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeatureRegistryTests`.
Expected: FAIL ("type 'FeatureRegistry' not in scope").

- [ ] **Step 3: Implement FeatureRegistry**

Create `Shared/Sources/FeatureCore/FeatureRegistry.swift`:
```swift
import Foundation

public struct FeatureRegistry: Sendable {
    public let descriptors: [FeatureDescriptor]

    public init(descriptors: [FeatureDescriptor]) {
        self.descriptors = descriptors
    }

    public func descriptor(for id: FeatureID) -> FeatureDescriptor? {
        descriptors.first(where: { $0.id == id })
    }

    public enum ValidationError: Error, Equatable {
        case duplicateID(FeatureID)
    }

    public static func validated(descriptors: [FeatureDescriptor]) throws -> FeatureRegistry {
        var seen = Set<FeatureID>()
        for d in descriptors {
            if !seen.insert(d.id).inserted {
                throw ValidationError.duplicateID(d.id)
            }
        }
        return FeatureRegistry(descriptors: descriptors)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeatureRegistryTests`.
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureRegistry.swift Shared/Tests/FeatureCoreTests/FeatureRegistryTests.swift
git commit -m "feat(modular-features): add FeatureRegistry"
```

---

### Task 9: Darwin notification thin wrapper

**Files:**
- Create: `Shared/Sources/FeatureCore/DarwinNotification.swift`

- [ ] **Step 1: Implement DarwinNotification**

Create `Shared/Sources/FeatureCore/DarwinNotification.swift`:
```swift
import Foundation

public enum DarwinNotification {
    public static let featureStateDidChange = "com.macallyouneed.featureStateDidChange"

    public static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = CFNotificationName(rawValue: name as CFString)
        CFNotificationCenterPostNotification(center, cfName, nil, nil, true)
    }
}
```

(Consumer side — `addObserver` — lives in Phase 10's daemon code.)

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target FeatureCore`. Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Shared/Sources/FeatureCore/DarwinNotification.swift
git commit -m "feat(modular-features): add DarwinNotification post helper"
```

---

### Task 10: `FeatureManager` actor — read path + persistence

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureManager.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureManagerPersistenceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureManagerPersistenceTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import FeatureCore
@testable import Core

private func makeRegistry() -> FeatureRegistry {
    let clipboard = FeatureDescriptor(
        id: .clipboard, displayName: "Clipboard", icon: "doc",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
    let downloader = FeatureDescriptor(
        id: .downloader, displayName: "Downloader", icon: "arrow.down",
        summary: "", detailDescription: "",
        assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
        activator: NoopFeatureActivator()
    )
    return FeatureRegistry(descriptors: [clipboard, downloader])
}

final class FeatureManagerPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "FeatureManagerPersistenceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReturnsInitialDefaultWhenUnset() async {
        let manager = FeatureManager(registry: makeRegistry(), defaults: defaults)
        let clipboard = await manager.state(for: .clipboard)
        let downloader = await manager.state(for: .downloader)
        XCTAssertEqual(clipboard, .init(assetState: .notRequired, activationState: .disabled))
        XCTAssertEqual(downloader, .init(assetState: .notDownloaded, activationState: .disabled))
    }

    func testPersistsAcrossInstances() async throws {
        let mgr1 = FeatureManager(registry: makeRegistry(), defaults: defaults)
        try await mgr1.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)

        let mgr2 = FeatureManager(registry: makeRegistry(), defaults: defaults)
        let read = await mgr2.state(for: .clipboard)
        XCTAssertEqual(read, .init(assetState: .notRequired, activationState: .enabled))
    }

    func testStateWriteIsIsolatedPerFeature() async throws {
        let manager = FeatureManager(registry: makeRegistry(), defaults: defaults)
        try await manager.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        let downloader = await manager.state(for: .downloader)
        XCTAssertEqual(downloader, .init(assetState: .notDownloaded, activationState: .disabled),
                       "Writing one feature must not affect another")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeatureManagerPersistenceTests`.
Expected: FAIL ("type 'FeatureManager' not in scope").

- [ ] **Step 3: Implement FeatureManager (read/write path only — transitions in Task 11)**

Create `Shared/Sources/FeatureCore/FeatureManager.swift`:
```swift
import Foundation

public actor FeatureManager {
    public let registry: FeatureRegistry
    private let defaults: UserDefaults
    private let darwinNotificationName: String

    public init(
        registry: FeatureRegistry,
        defaults: UserDefaults,
        darwinNotificationName: String = DarwinNotification.featureStateDidChange
    ) {
        self.registry = registry
        self.defaults = defaults
        self.darwinNotificationName = darwinNotificationName
    }

    public func state(for id: FeatureID) -> FeatureRuntimeState {
        if let data = defaults.data(forKey: Self.persistKey(for: id)),
           let decoded = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data) {
            return decoded
        }
        let descriptor = registry.descriptor(for: id)
        return .initialDefault(assetRequired: descriptor?.requiresAsset ?? false)
    }

    public func allStates() -> [FeatureID: FeatureRuntimeState] {
        Dictionary(uniqueKeysWithValues: registry.descriptors.map { ($0.id, state(for: $0.id)) })
    }

    /// Used by Tasks 11+ and tests. Persists and posts the Darwin notification.
    public func setState(_ state: FeatureRuntimeState, for id: FeatureID) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: Self.persistKey(for: id))
        DarwinNotification.post(darwinNotificationName)
    }

    public static func persistKey(for id: FeatureID) -> String {
        "feature.\(id.rawValue).runtimeState"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeatureManagerPersistenceTests`.
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureManager.swift Shared/Tests/FeatureCoreTests/FeatureManagerPersistenceTests.swift
git commit -m "feat(modular-features): add FeatureManager actor with persistence"
```

---

### Task 11: `FeatureManager` state-machine transitions (no I/O)

**Files:**
- Modify: `Shared/Sources/FeatureCore/FeatureManager.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureManagerStateMachineTests.swift`

- [ ] **Step 1: Write the failing test (truth-table style)**

Create `Shared/Tests/FeatureCoreTests/FeatureManagerStateMachineTests.swift`:
```swift
import XCTest
@testable import FeatureCore
@testable import Core

private func makeManager() -> FeatureManager {
    let downloader = FeatureDescriptor(
        id: .downloader, displayName: "Downloader", icon: "arrow.down",
        summary: "", detailDescription: "",
        assetPacks: [AssetPack(id: "downloader", bundledManifestKey: "downloader")],
        activator: NoopFeatureActivator()
    )
    let clipboard = FeatureDescriptor(
        id: .clipboard, displayName: "Clipboard", icon: "doc",
        summary: "", detailDescription: "",
        activator: NoopFeatureActivator()
    )
    let registry = FeatureRegistry(descriptors: [clipboard, downloader])
    let defaults = UserDefaults(suiteName: "FeatureManagerStateMachineTests-\(UUID().uuidString)")!
    return FeatureManager(registry: registry, defaults: defaults)
}

final class FeatureManagerStateMachineTests: XCTestCase {
    func testEnableSwiftOnlyFromDisabled() async throws {
        let mgr = makeManager()
        try await mgr.transition(.enable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s, .init(assetState: .notRequired, activationState: .enabled))
    }

    func testDisableSwiftOnlyFromEnabled() async throws {
        let mgr = makeManager()
        try await mgr.transition(.enable, for: .clipboard)
        try await mgr.transition(.disable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s, .init(assetState: .notRequired, activationState: .disabled))
    }

    func testCannotEnableWhileNotDownloaded() async {
        let mgr = makeManager()
        do {
            try await mgr.transition(.enable, for: .downloader)
            XCTFail("expected transition to throw")
        } catch let error as FeatureManager.TransitionError {
            XCTAssertEqual(error, .assetNotReady)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testEnableAfterAssetBecomesPresent() async throws {
        let mgr = makeManager()
        try await mgr.setState(.init(assetState: .present(version: "1.0"), activationState: .disabled), for: .downloader)
        try await mgr.transition(.enable, for: .downloader)
        let s = await mgr.state(for: .downloader)
        XCTAssertEqual(s, .init(assetState: .present(version: "1.0"), activationState: .enabled))
    }

    func testDisableIsIdempotent() async throws {
        let mgr = makeManager()
        try await mgr.transition(.disable, for: .clipboard)
        try await mgr.transition(.disable, for: .clipboard)
        let s = await mgr.state(for: .clipboard)
        XCTAssertEqual(s.activationState, .disabled)
    }

    func testMarkAssetTransitions() async throws {
        let mgr = makeManager()
        try await mgr.markAssetState(.downloading(progress: 0.1), for: .downloader)
        XCTAssertEqual(await mgr.state(for: .downloader).assetState, .downloading(progress: 0.1))

        try await mgr.markAssetState(.present(version: "1.0"), for: .downloader)
        XCTAssertEqual(await mgr.state(for: .downloader).assetState, .present(version: "1.0"))

        try await mgr.markAssetState(.notDownloaded, for: .downloader)
        let final = await mgr.state(for: .downloader)
        XCTAssertEqual(final.assetState, .notDownloaded)
        XCTAssertEqual(final.activationState, .disabled, "asset removal must force-disable")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FeatureManagerStateMachineTests`.
Expected: FAIL ("no such method 'transition'").

- [ ] **Step 3: Extend FeatureManager with transitions**

Append to `Shared/Sources/FeatureCore/FeatureManager.swift`:
```swift
extension FeatureManager {
    public enum Transition {
        case enable
        case disable
    }

    public enum TransitionError: Error, Equatable {
        case assetNotReady
        case unknownFeature(FeatureID)
    }

    public func transition(_ transition: Transition, for id: FeatureID) throws {
        guard registry.descriptor(for: id) != nil else { throw TransitionError.unknownFeature(id) }
        let current = state(for: id)
        switch transition {
        case .enable:
            guard current.canActivate else { throw TransitionError.assetNotReady }
            if current.activationState == .enabled { return }
            try setState(.init(assetState: current.assetState, activationState: .enabled), for: id)
        case .disable:
            if current.activationState == .disabled { return }
            try setState(.init(assetState: current.assetState, activationState: .disabled), for: id)
        }
    }

    /// Used by the install pipeline (Phase 02) and tests. Forces disable when asset is removed.
    public func markAssetState(_ newAssetState: AssetState, for id: FeatureID) throws {
        guard registry.descriptor(for: id) != nil else { throw TransitionError.unknownFeature(id) }
        let current = state(for: id)
        var newActivation = current.activationState
        switch newAssetState {
        case .notRequired, .present:
            break
        case .notDownloaded, .downloading, .downloadFailed:
            newActivation = .disabled
        }
        try setState(.init(assetState: newAssetState, activationState: newActivation), for: id)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FeatureManagerStateMachineTests`.
Expected: PASS, 6/6 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureManager.swift Shared/Tests/FeatureCoreTests/FeatureManagerStateMachineTests.swift
git commit -m "feat(modular-features): add FeatureManager transition state machine"
```

---

### Task 12: Wire `FeatureCore` into the Xcode project

**Files:**
- Modify: `project.yml` (add `FeatureCore` as a dependency of the `MacAllYouNeed` and `ClipboardDaemon` targets)

- [ ] **Step 1: Read current project.yml dependencies**

Run: `grep -n "Core\|Shared" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -40`

Find the `MacAllYouNeed` target's dependencies (looks for `package: Shared` with `product: Core`).

- [ ] **Step 2: Add FeatureCore as a dependency for MacAllYouNeed**

In `project.yml`, locate `MacAllYouNeed`'s `dependencies:` block and add a new entry:
```yaml
      - package: Shared
        product: FeatureCore
```

Repeat for `ClipboardDaemon` target.

- [ ] **Step 3: Regenerate the Xcode project**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && xcodegen generate
```
Expected: `Generated project successfully`.

- [ ] **Step 4: Verify the Xcode build still works**

Run:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && \
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' build | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): wire FeatureCore into Xcode project"
```

---

### Task 13: Phase verification

- [ ] **Step 1: Run full test suite for FeatureCore**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureCore
```
Expected: all tests pass.

- [ ] **Step 2: Run full CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 3: Mark phase complete in index plan**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md`, change:
```markdown
- [ ] Phase 01 — Foundation
```
to:
```markdown
- [x] Phase 01 — Foundation
```

- [ ] **Step 4: Commit + open PR**

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 01 complete"
git push -u origin <branch>
gh pr create --title "Phase 01 — Foundation: FeatureCore types and FeatureManager" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/01-foundation.md"
```
