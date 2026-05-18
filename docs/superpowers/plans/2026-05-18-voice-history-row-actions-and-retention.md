# Voice History Row Actions and Retention Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-row Retry / Download audio / Delete transcript actions to the Voice history, a `Keep history` retention dropdown, and a `Save audio recordings` toggle that decouples audio retention from personalization.

**Architecture:** Pure settings, retention policy, and audio codec live in `Shared/Sources/Core/Voice/` so they are testable without the main app. The `VoiceCoordinator` gains an audio-persist helper used by both the personalization path and the new save-audio path, plus a `retryTranscript` entry point that re-runs ASR + cleanup and inserts a new row. The Voice history section on `MainWindowRoot` gets a storage header row and a hover-revealed overflow menu per transcript row. A `VoiceTranscriptRetentionRunner` sweeps on launch, hourly, and after each new transcript. Undo for delete uses an in-view toast plus a deferred audio-delete `Task`.

**Tech Stack:** Swift 5.9, SwiftUI, GRDB, CryptoKit AES-GCM, App Group `UserDefaults`, existing MAYN design system primitives, XCTest.

---

## File Map

**Create — Shared (Core)**
- `Shared/Sources/Core/Voice/VoiceHistoryRetention.swift` — retention enum + window-in-seconds helper.
- `Shared/Sources/Core/Voice/VoiceHistorySettings.swift` — value type + UserDefaults round-trip.
- `Shared/Sources/Core/Voice/VoiceAudioCodec.swift` — pure WAV decode (encode already lives on `GroqASREngine`; see Task 7 for the relocation rationale).
- `Shared/Tests/CoreTests/Voice/VoiceHistoryRetentionTests.swift`
- `Shared/Tests/CoreTests/Voice/VoiceHistorySettingsTests.swift`
- `Shared/Tests/CoreTests/Voice/VoiceAudioCodecTests.swift`

**Create — Main app**
- `MacAllYouNeed/Voice/VoiceAudioAccess.swift` — decrypt + decode `.wav.aesgcm` file at a path; expose `loadWav(at:)` and `loadSamples(at:)`.
- `MacAllYouNeed/Voice/VoiceTranscriptRetentionRunner.swift` — periodic + on-launch + after-append sweep, with orphan audio cleanup.
- `MacAllYouNeed/Voice/UI/VoiceHistoryStorageHeader.swift` — `MAYNSection` with retention dropdown + save-audio toggle.
- `MacAllYouNeed/Voice/UI/VoiceTranscriptRowMenu.swift` — overflow menu on hover.
- `MacAllYouNeed/Voice/UI/VoiceHistoryToast.swift` — undo toast view + view model.
- `MacAllYouNeedTests/Voice/VoiceCoordinatorRetryTests.swift`
- `MacAllYouNeedTests/Voice/VoiceCoordinatorAudioPolicyTests.swift`
- `MacAllYouNeedTests/Voice/VoiceTranscriptRetentionRunnerTests.swift`
- `MacAllYouNeedTests/Voice/VoiceAudioAccessTests.swift`

**Modify**
- `Shared/Sources/Core/Voice/VoiceTranscriptStore.swift` — add `existingID:` to `save`; add `expireByAge(maxAge:now:) -> [VoiceTranscript]`.
- `Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift` — expose `audioRoot` and `loadEncryptedAudio(path:) -> Data`.
- `Shared/Tests/CoreTests/Voice/VoiceTranscriptStoreTests.swift` — cover new methods.
- `Shared/Tests/CoreTests/Voice/VoiceTrainingExampleStoreTests.swift` — cover `loadEncryptedAudio`.
- `MacAllYouNeed/Voice/VoiceCoordinator.swift` — gate audio save on either personalization or `historySettings().saveAudio`; extract `persistAudio` helper that callers use before building the `VoiceTranscriptDraft`; expose `retryTranscript(id:) async throws -> VoiceTranscript`.
- `MacAllYouNeed/Voice/ASR/GroqASREngine.swift` — `encodeWAV` made `public` and moved to `VoiceAudioCodec` (call site updated to delegate).
- `MacAllYouNeed/App/AppController.swift` — own `VoiceHistorySettings` accessor, own `VoiceTranscriptRetentionRunner`, expose to `AppControllerVoice`.
- `MacAllYouNeed/App/AppControllerVoice.swift` — add `loadVoiceHistorySettings()`, `saveVoiceHistorySettings(_:)`, `retryVoiceTranscript(id:) async throws`, `downloadVoiceAudio(transcript:) async throws -> URL?`, `deleteVoiceTranscriptWithUndo(transcript:) -> VoiceHistoryUndoToken`.
- `MacAllYouNeed/App/MainWindowRoot.swift` — call `VoiceHistoryStorageHeader` at top of history section; replace duration pill + add `VoiceTranscriptRowMenu`; show undo toast.
- `MacAllYouNeed/Voice/UI/VoicePersonalizationPage.swift` — add a one-line help under `saveTrainingExamplesEnabled` toggle clarifying audio is also stored.
- `MacAllYouNeed/Voice/VoiceCoordinator.swift` — emit a notification (`.voiceTranscriptAppended`) after appending so the retention runner can react.

---

## Chunk 1: Core Models

### Task 1: VoiceHistoryRetention Enum

**Files:**
- Create: `Shared/Sources/Core/Voice/VoiceHistoryRetention.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceHistoryRetentionTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Core

final class VoiceHistoryRetentionTests: XCTestCase {
    func test_storageKeyRoundTrip_succeeds_for_all_cases() {
        for case in VoiceHistoryRetention.allCases {
            XCTAssertEqual(VoiceHistoryRetention(storageKey: case.storageKey), case)
        }
    }

    func test_storageKey_for_forever_is_forever() {
        XCTAssertEqual(VoiceHistoryRetention.forever.storageKey, "forever")
    }

    func test_maxAgeSeconds_forever_is_nil() {
        XCTAssertNil(VoiceHistoryRetention.forever.maxAgeSeconds)
    }

    func test_maxAgeSeconds_oneDay_is_86400() {
        XCTAssertEqual(VoiceHistoryRetention.days1.maxAgeSeconds, 86_400)
    }

    func test_maxAgeSeconds_thirtyDays_is_2_592_000() {
        XCTAssertEqual(VoiceHistoryRetention.days30.maxAgeSeconds, 2_592_000)
    }

    func test_init_unknownKey_fallsBackToForever() {
        XCTAssertEqual(VoiceHistoryRetention(storageKey: "nonsense"), .forever)
    }

    func test_displayTitle_isHumanReadable() {
        XCTAssertEqual(VoiceHistoryRetention.forever.displayTitle, "Forever")
        XCTAssertEqual(VoiceHistoryRetention.days1.displayTitle, "Last 1 day")
        XCTAssertEqual(VoiceHistoryRetention.days7.displayTitle, "Last 7 days")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceHistoryRetentionTests`
Expected: FAIL — cannot find type `VoiceHistoryRetention`.

- [ ] **Step 3: Implement the enum**

```swift
import Foundation

public enum VoiceHistoryRetention: String, CaseIterable, Hashable, Sendable {
    case forever
    case days1
    case days7
    case days30
    case days90

    public var storageKey: String {
        switch self {
        case .forever: return "forever"
        case .days1:   return "1d"
        case .days7:   return "7d"
        case .days30:  return "30d"
        case .days90:  return "90d"
        }
    }

    public init(storageKey: String) {
        switch storageKey {
        case "forever": self = .forever
        case "1d":      self = .days1
        case "7d":      self = .days7
        case "30d":     self = .days30
        case "90d":     self = .days90
        default:        self = .forever
        }
    }

    public var maxAgeSeconds: TimeInterval? {
        switch self {
        case .forever: return nil
        case .days1:   return 1 * 86_400
        case .days7:   return 7 * 86_400
        case .days30:  return 30 * 86_400
        case .days90:  return 90 * 86_400
        }
    }

    public var displayTitle: String {
        switch self {
        case .forever: return "Forever"
        case .days1:   return "Last 1 day"
        case .days7:   return "Last 7 days"
        case .days30:  return "Last 30 days"
        case .days90:  return "Last 90 days"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceHistoryRetentionTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceHistoryRetention.swift \
        Shared/Tests/CoreTests/Voice/VoiceHistoryRetentionTests.swift
git commit -m "feat(voice): add VoiceHistoryRetention enum"
```

---

### Task 2: VoiceHistorySettings + UserDefaults round-trip

**Files:**
- Create: `Shared/Sources/Core/Voice/VoiceHistorySettings.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceHistorySettingsTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Core

final class VoiceHistorySettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "VoiceHistorySettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        super.tearDown()
    }

    func test_defaults_when_keys_absent_are_forever_and_off() {
        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .forever)
        XCTAssertFalse(loaded.saveAudio)
    }

    func test_save_then_load_roundtrips() {
        var settings = VoiceHistorySettings(retention: .days7, saveAudio: true)
        settings.save(to: defaults)

        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .days7)
        XCTAssertTrue(loaded.saveAudio)
    }

    func test_load_reads_individual_keys() {
        defaults.set("30d", forKey: "voice.history.retention")
        defaults.set(true, forKey: "voice.history.saveAudio")

        let loaded = VoiceHistorySettings.load(from: defaults)
        XCTAssertEqual(loaded.retention, .days30)
        XCTAssertTrue(loaded.saveAudio)
    }
}
```

- [ ] **Step 2: Run test — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceHistorySettingsTests`
Expected: FAIL — cannot find type `VoiceHistorySettings`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct VoiceHistorySettings: Equatable, Sendable {
    public var retention: VoiceHistoryRetention
    public var saveAudio: Bool

    public init(retention: VoiceHistoryRetention = .forever, saveAudio: Bool = false) {
        self.retention = retention
        self.saveAudio = saveAudio
    }

    public static let retentionKey = "voice.history.retention"
    public static let saveAudioKey = "voice.history.saveAudio"

    public static func load(from defaults: UserDefaults) -> VoiceHistorySettings {
        let retention: VoiceHistoryRetention
        if let raw = defaults.string(forKey: retentionKey) {
            retention = VoiceHistoryRetention(storageKey: raw)
        } else {
            retention = .forever
        }
        let saveAudio = defaults.bool(forKey: saveAudioKey)
        return VoiceHistorySettings(retention: retention, saveAudio: saveAudio)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(retention.storageKey, forKey: Self.retentionKey)
        defaults.set(saveAudio, forKey: Self.saveAudioKey)
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceHistorySettingsTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceHistorySettings.swift \
        Shared/Tests/CoreTests/Voice/VoiceHistorySettingsTests.swift
git commit -m "feat(voice): add VoiceHistorySettings load/save"
```

---

## Chunk 2: Store API Extensions

### Task 3: VoiceTranscriptStore.save accepts existingID

**Files:**
- Modify: `Shared/Sources/Core/Voice/VoiceTranscriptStore.swift:11-47`
- Modify: `Shared/Tests/CoreTests/Voice/VoiceTranscriptStoreTests.swift`

- [ ] **Step 1: Write failing test**

Append to `VoiceTranscriptStoreTests.swift`:

```swift
func test_save_with_existingID_preservesID() throws {
    let store = try makeStore()
    let draft = VoiceTranscriptDraft(
        startedAt: Date(timeIntervalSince1970: 1),
        endedAt: Date(timeIntervalSince1970: 2),
        rawText: "hi",
        cleanedText: "Hi",
        appBundleID: nil,
        language: .english,
        modelIdentifier: "test",
        audioPath: nil
    )
    let saved = try store.save(draft, existingID: "fixed-uuid")
    XCTAssertEqual(saved.id, "fixed-uuid")

    let refetched = try store.fetch(id: "fixed-uuid")
    XCTAssertEqual(refetched?.id, "fixed-uuid")
}

func test_save_withoutExistingID_generatesNewID() throws {
    let store = try makeStore()
    let draft = VoiceTranscriptDraft(
        startedAt: Date(),
        endedAt: Date(),
        rawText: "",
        cleanedText: "",
        appBundleID: nil,
        language: .english,
        modelIdentifier: "x",
        audioPath: nil
    )
    let a = try store.save(draft)
    let b = try store.save(draft)
    XCTAssertNotEqual(a.id, b.id)
}
```

If `makeStore()` does not already exist, add it near the top of the test file by following the pattern in `VoiceTrainingExampleStoreTests.swift` (in-memory GRDB connection).

- [ ] **Step 2: Run — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTranscriptStoreTests/test_save_with_existingID_preservesID`
Expected: FAIL — extra argument `existingID` in call.

- [ ] **Step 3: Implement**

Replace `save(_ draft:)` in `Shared/Sources/Core/Voice/VoiceTranscriptStore.swift:11-47`:

```swift
@discardableResult
public func save(_ draft: VoiceTranscriptDraft, existingID: String? = nil) throws -> VoiceTranscript {
    let id = existingID ?? UUID().uuidString
    let durationMs = max(0, Int((draft.endedAt.timeIntervalSince(draft.startedAt) * 1000).rounded()))
    try db.queue.write { conn in
        try conn.execute(sql: """
            INSERT INTO voice_transcripts (
                id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                app_bundle_id, language, model_identifier, audio_path
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            id,
            Self.millis(draft.startedAt),
            Self.millis(draft.endedAt),
            durationMs,
            draft.rawText,
            draft.cleanedText,
            draft.appBundleID,
            draft.language.rawValue,
            draft.modelIdentifier,
            draft.audioPath
        ])
    }
    return VoiceTranscript(
        id: id,
        startedAt: draft.startedAt,
        endedAt: draft.endedAt,
        durationMs: durationMs,
        rawText: draft.rawText,
        cleanedText: draft.cleanedText,
        appBundleID: draft.appBundleID,
        language: draft.language,
        modelIdentifier: draft.modelIdentifier,
        audioPath: draft.audioPath
    )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTranscriptStoreTests`
Expected: all tests pass (existing + 2 new).

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceTranscriptStore.swift \
        Shared/Tests/CoreTests/Voice/VoiceTranscriptStoreTests.swift
git commit -m "feat(voice): allow VoiceTranscriptStore.save to preserve an existing ID"
```

---

### Task 4: VoiceTranscriptStore.expireByAge

**Files:**
- Modify: `Shared/Sources/Core/Voice/VoiceTranscriptStore.swift`
- Modify: `Shared/Tests/CoreTests/Voice/VoiceTranscriptStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Append:

```swift
func test_expireByAge_deletesRowsOlderThanWindow() throws {
    let store = try makeStore()
    let fixedNow = Date(timeIntervalSince1970: 1_000_000)
    let oldEnd = fixedNow.addingTimeInterval(-2 * 86_400) // 2 days old
    let newEnd = fixedNow.addingTimeInterval(-3_600)      // 1 hour old

    let old = try store.save(VoiceTranscriptDraft(
        startedAt: oldEnd.addingTimeInterval(-1), endedAt: oldEnd,
        rawText: "old", cleanedText: "old",
        appBundleID: nil, language: .english,
        modelIdentifier: "m", audioPath: "/tmp/old.aesgcm"
    ))
    let new = try store.save(VoiceTranscriptDraft(
        startedAt: newEnd.addingTimeInterval(-1), endedAt: newEnd,
        rawText: "new", cleanedText: "new",
        appBundleID: nil, language: .english,
        modelIdentifier: "m", audioPath: nil
    ))

    let deleted = try store.expireByAge(maxAge: 86_400, now: fixedNow)

    XCTAssertEqual(deleted.map(\.id), [old.id])
    XCTAssertEqual(deleted.first?.audioPath, "/tmp/old.aesgcm")
    XCTAssertNotNil(try store.fetch(id: new.id))
    XCTAssertNil(try store.fetch(id: old.id))
}

func test_expireByAge_returnsEmptyWhenNothingExpired() throws {
    let store = try makeStore()
    let now = Date()
    _ = try store.save(VoiceTranscriptDraft(
        startedAt: now, endedAt: now,
        rawText: "x", cleanedText: "x",
        appBundleID: nil, language: .english,
        modelIdentifier: "m", audioPath: nil
    ))
    let deleted = try store.expireByAge(maxAge: 86_400, now: now)
    XCTAssertTrue(deleted.isEmpty)
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTranscriptStoreTests`
Expected: FAIL — value of type `VoiceTranscriptStore` has no member `expireByAge`.

- [ ] **Step 3: Implement — append to `VoiceTranscriptStore.swift` after `delete(ids:)`**

```swift
@discardableResult
public func expireByAge(maxAge: TimeInterval, now: Date = Date()) throws -> [VoiceTranscript] {
    let cutoff = Self.millis(now.addingTimeInterval(-maxAge))
    return try db.queue.write { conn in
        let rows = try Row.fetchAll(conn, sql: """
            SELECT id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                   app_bundle_id, language, model_identifier, audio_path
            FROM voice_transcripts
            WHERE ended_at < ?
        """, arguments: [cutoff])
        let expired = rows.map(Self.transcript(from:))
        for transcript in expired {
            try conn.execute(sql: "DELETE FROM voice_transcripts WHERE id = ?", arguments: [transcript.id])
        }
        return expired
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTranscriptStoreTests`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceTranscriptStore.swift \
        Shared/Tests/CoreTests/Voice/VoiceTranscriptStoreTests.swift
git commit -m "feat(voice): add VoiceTranscriptStore.expireByAge"
```

---

### Task 5: VoiceTrainingExampleStore exposes audioRoot + loadEncryptedAudio

**Files:**
- Modify: `Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift`
- Modify: `Shared/Tests/CoreTests/Voice/VoiceTrainingExampleStoreTests.swift`

- [ ] **Step 1: Write failing test**

Append:

```swift
func test_loadEncryptedAudio_roundtripsWAVBytes() throws {
    let (store, _, _) = try makeStore()
    let original = Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03, 0x04])
    let path = try store.saveEncryptedAudio(original, id: "abc")

    let loaded = try store.loadEncryptedAudio(path: path)
    XCTAssertEqual(loaded, original)
}

func test_audioRoot_isReadable() throws {
    let (store, _, audioRoot) = try makeStore()
    XCTAssertEqual(store.audioRoot, audioRoot)
}
```

If `makeStore()` doesn't return audioRoot today, update it to return the URL it created.

- [ ] **Step 2: Run — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTrainingExampleStoreTests`
Expected: FAIL — `loadEncryptedAudio` not found; `audioRoot` not visible.

- [ ] **Step 3: Implement — modify `Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift`**

Change the `private let audioRoot: URL` line to `public let audioRoot: URL`. Then add a new public method after `saveEncryptedAudio`:

```swift
public func loadEncryptedAudio(path: String) throws -> Data {
    let url = URL(fileURLWithPath: path)
    let encrypted = try Data(contentsOf: url)
    return try Cipher.open(Envelope(combined: encrypted), with: key)
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceTrainingExampleStoreTests`
Expected: existing + 2 new tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift \
        Shared/Tests/CoreTests/Voice/VoiceTrainingExampleStoreTests.swift
git commit -m "feat(voice): expose audioRoot and loadEncryptedAudio on training example store"
```

---

## Chunk 3: Audio Codec + Access

### Task 6: VoiceAudioCodec — pure WAV decode

**Files:**
- Create: `Shared/Sources/Core/Voice/VoiceAudioCodec.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceAudioCodecTests.swift`

The existing `GroqASREngine.encodeWAV` is also moved here in Task 7. Decode is a separate, smaller responsibility; we add it first because Retry needs it.

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import Core

final class VoiceAudioCodecTests: XCTestCase {
    func test_decodeWAV_returnsSamplesAndSampleRate() throws {
        let wav = Self.fixtureWAV(sampleRate: 16_000, int16Samples: [0, 1, -1, 32_767])
        let decoded = try VoiceAudioCodec.decodeWAV(wav)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.samples.count, 4)
        XCTAssertEqual(decoded.samples[0], 0)
        XCTAssertEqual(decoded.samples[3], Float(32_767) / 32_768, accuracy: 0.0001)
    }

    func test_decodeWAV_rejectsTruncatedHeader() {
        XCTAssertThrowsError(try VoiceAudioCodec.decodeWAV(Data([0x52, 0x49, 0x46, 0x46]))) { error in
            XCTAssertEqual(error as? VoiceAudioCodec.DecodeError, .truncated)
        }
    }

    func test_decodeWAV_rejectsWrongFormat() {
        var bad = Self.fixtureWAV(sampleRate: 16_000, int16Samples: [0])
        // Flip the "RIFF" magic to something else
        bad[0] = 0x58
        XCTAssertThrowsError(try VoiceAudioCodec.decodeWAV(bad)) { error in
            XCTAssertEqual(error as? VoiceAudioCodec.DecodeError, .badMagic)
        }
    }

    private static func fixtureWAV(sampleRate: Int, int16Samples: [Int16]) -> Data {
        // Reuses the same little-endian layout as GroqASREngine.encodeWAV produces,
        // but we build it inline so this test does not depend on the encoder.
        let dataSize = int16Samples.count * 2
        let fmtSize = 16
        let fileSize = 4 + 8 + fmtSize + 8 + dataSize
        var wav = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) }) }
        func u16(_ v: UInt16) { var x = v.littleEndian; wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) }) }
        func ascii(_ s: String) { wav.append(contentsOf: s.utf8.prefix(4)) }
        ascii("RIFF")
        u32(UInt32(fileSize))
        ascii("WAVE")
        ascii("fmt ")
        u32(UInt32(fmtSize))
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        ascii("data")
        u32(UInt32(dataSize))
        for s in int16Samples {
            var x = s.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        return wav
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceAudioCodecTests`
Expected: FAIL — cannot find `VoiceAudioCodec`.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum VoiceAudioCodec {
    public enum DecodeError: Error, Equatable {
        case truncated
        case badMagic
        case unsupportedFormat
    }

    public struct DecodedAudio: Equatable {
        public let samples: [Float]
        public let sampleRate: Int
    }

    public static func decodeWAV(_ data: Data) throws -> DecodedAudio {
        guard data.count >= 44 else { throw DecodeError.truncated }
        let bytes = [UInt8](data)

        func ascii(_ at: Int, length: Int) -> String {
            String(bytes: bytes[at..<at + length], encoding: .ascii) ?? ""
        }
        func u16(_ at: Int) -> UInt16 {
            UInt16(bytes[at]) | (UInt16(bytes[at + 1]) << 8)
        }
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8)
                | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24)
        }

        guard ascii(0, length: 4) == "RIFF", ascii(8, length: 4) == "WAVE" else {
            throw DecodeError.badMagic
        }
        guard ascii(12, length: 4) == "fmt " else {
            throw DecodeError.unsupportedFormat
        }
        let audioFormat = u16(20)
        let numChannels = u16(22)
        let sampleRate = Int(u32(24))
        let bitsPerSample = u16(34)
        guard audioFormat == 1, numChannels == 1, bitsPerSample == 16 else {
            throw DecodeError.unsupportedFormat
        }

        // Walk chunks until we find "data".
        var cursor = 36
        while cursor + 8 <= bytes.count {
            let chunkID = ascii(cursor, length: 4)
            let chunkSize = Int(u32(cursor + 4))
            let payloadStart = cursor + 8
            if chunkID == "data" {
                guard payloadStart + chunkSize <= bytes.count else { throw DecodeError.truncated }
                var samples: [Float] = []
                samples.reserveCapacity(chunkSize / 2)
                var i = payloadStart
                while i + 1 < payloadStart + chunkSize {
                    let raw = Int16(bitPattern: u16(i))
                    samples.append(Float(raw) / 32_768)
                    i += 2
                }
                return DecodedAudio(samples: samples, sampleRate: sampleRate)
            }
            cursor = payloadStart + chunkSize
        }
        throw DecodeError.truncated
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceAudioCodecTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceAudioCodec.swift \
        Shared/Tests/CoreTests/Voice/VoiceAudioCodecTests.swift
git commit -m "feat(voice): add VoiceAudioCodec.decodeWAV"
```

---

### Task 7: Move encodeWAV into VoiceAudioCodec

**Files:**
- Modify: `Shared/Sources/Core/Voice/VoiceAudioCodec.swift`
- Modify: `MacAllYouNeed/Voice/ASR/GroqASREngine.swift:160-219`
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift:427`

Move the implementation so both the existing capture flow and the new Retry flow can use it, and so encoding gains test coverage from `Shared/Tests`.

- [ ] **Step 1: Write a parity test in `VoiceAudioCodecTests.swift`**

Append:

```swift
func test_encodeWAV_decodes_back_to_same_samples() throws {
    let input: [Float] = [0, 0.5, -0.5, 1.0, -1.0]
    let wav = VoiceAudioCodec.encodeWAV(samples: input, sampleRate: 16_000)
    let decoded = try VoiceAudioCodec.decodeWAV(wav)
    XCTAssertEqual(decoded.sampleRate, 16_000)
    XCTAssertEqual(decoded.samples.count, input.count)
    for (i, expected) in input.enumerated() {
        XCTAssertEqual(decoded.samples[i], expected, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceAudioCodecTests/test_encodeWAV_decodes_back_to_same_samples`
Expected: FAIL — `VoiceAudioCodec` has no member `encodeWAV`.

- [ ] **Step 3: Add `encodeWAV` to `VoiceAudioCodec`**

Append to `Shared/Sources/Core/Voice/VoiceAudioCodec.swift` inside the enum:

```swift
public static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
    let int16Samples = samples.map { sample -> Int16 in
        let clamped = max(-1.0, min(1.0, sample))
        let scaled = clamped * 32_768.0
        return Int16(max(Float(Int16.min), min(Float(Int16.max), scaled)))
    }
    let dataSize = int16Samples.count * 2
    let fmtSize = 16
    let fileSize = 4 + 8 + fmtSize + 8 + dataSize

    var wav = Data(capacity: 8 + fileSize)
    func u32(_ value: UInt32) {
        var v = value.littleEndian
        wav.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }
    func u16(_ value: UInt16) {
        var v = value.littleEndian
        wav.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
    }
    func ascii(_ s: String) { wav.append(contentsOf: s.utf8.prefix(4)) }

    let sampleRateU = UInt32(sampleRate)
    let bitsPerSample: UInt16 = 16
    let numChannels: UInt16 = 1
    let byteRate = sampleRateU * UInt32(numChannels) * UInt32(bitsPerSample) / 8
    let blockAlign = numChannels * bitsPerSample / 8

    ascii("RIFF")
    u32(UInt32(fileSize))
    ascii("WAVE")

    ascii("fmt ")
    u32(UInt32(fmtSize))
    u16(UInt16(1))
    u16(numChannels)
    u32(sampleRateU)
    u32(byteRate)
    u16(blockAlign)
    u16(bitsPerSample)

    ascii("data")
    u32(UInt32(dataSize))
    for sample in int16Samples {
        var s = sample.littleEndian
        wav.append(contentsOf: withUnsafeBytes(of: &s) { Array($0) })
    }
    return wav
}
```

- [ ] **Step 4: Delegate `GroqASREngine.encodeWAV` to the codec**

In `MacAllYouNeed/Voice/ASR/GroqASREngine.swift:160-219`, replace the entire body of `encodeWAV` with:

```swift
static func encodeWAV(samples: [Float], sampleRate: Int) -> Data {
    VoiceAudioCodec.encodeWAV(samples: samples, sampleRate: sampleRate)
}
```

Leave the `// MARK: - WAV encoding` comment.

- [ ] **Step 5: Run all relevant test suites — expect pass**

Run:
```
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter VoiceAudioCodecTests
xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/GroqASREngineTests 2>&1 | tail -20
```
Expected: both green; no existing GroqASREngine WAV behavior changes.

- [ ] **Step 6: Commit**

```bash
git add Shared/Sources/Core/Voice/VoiceAudioCodec.swift \
        Shared/Tests/CoreTests/Voice/VoiceAudioCodecTests.swift \
        MacAllYouNeed/Voice/ASR/GroqASREngine.swift
git commit -m "refactor(voice): hoist encodeWAV into VoiceAudioCodec"
```

---

### Task 8: VoiceAudioAccess — decrypt + decode for the main app

**Files:**
- Create: `MacAllYouNeed/Voice/VoiceAudioAccess.swift`
- Create: `MacAllYouNeedTests/Voice/VoiceAudioAccessTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import CryptoKit
@testable import MacAllYouNeed
@testable import Core

final class VoiceAudioAccessTests: XCTestCase {
    func test_loadWav_returnsDecryptedBytes() throws {
        let (access, store) = try makeAccess()
        let wav = VoiceAudioCodec.encodeWAV(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        let path = try store.saveEncryptedAudio(wav, id: "id-1")

        let bytes = try access.loadWav(at: path)
        XCTAssertEqual(bytes, wav)
    }

    func test_loadSamples_decodesWAV() throws {
        let (access, store) = try makeAccess()
        let wav = VoiceAudioCodec.encodeWAV(samples: [0, 1.0, -1.0], sampleRate: 16_000)
        let path = try store.saveEncryptedAudio(wav, id: "id-2")

        let decoded = try access.loadSamples(at: path)
        XCTAssertEqual(decoded.sampleRate, 16_000)
        XCTAssertEqual(decoded.samples.count, 3)
    }

    private func makeAccess() throws -> (VoiceAudioAccess, VoiceTrainingExampleStore) {
        let database = try Database.inMemory()
        // Apply the existing voice migration so the training example schema exists.
        try VoiceTrainingExampleStore.applyMigrations(to: database)
        let key = SymmetricKey(size: .bits256)
        let audioRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voice-audio-access-\(UUID().uuidString)", isDirectory: true)
        let store = VoiceTrainingExampleStore(database: database, deviceKey: key, audioRoot: audioRoot)
        let access = VoiceAudioAccess(store: store)
        return (access, store)
    }
}
```

If `Database.inMemory()` or `VoiceTrainingExampleStore.applyMigrations` do not exist, mirror the helper pattern in `Shared/Tests/CoreTests/Voice/VoiceTrainingExampleStoreTests.swift` instead.

- [ ] **Step 2: Run — expect failure**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceAudioAccessTests 2>&1 | tail -20`
Expected: FAIL — `VoiceAudioAccess` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Core

struct VoiceAudioAccess {
    private let store: VoiceTrainingExampleStore

    init(store: VoiceTrainingExampleStore) {
        self.store = store
    }

    func loadWav(at path: String) throws -> Data {
        try store.loadEncryptedAudio(path: path)
    }

    func loadSamples(at path: String) throws -> VoiceAudioCodec.DecodedAudio {
        let wav = try loadWav(at: path)
        return try VoiceAudioCodec.decodeWAV(wav)
    }
}
```

- [ ] **Step 4: Add file to Xcode project**

Run: `xcodegen generate` from the repo root. Verify `MacAllYouNeed/Voice/VoiceAudioAccess.swift` is now in `MacAllYouNeed.xcodeproj/project.pbxproj`.

- [ ] **Step 5: Run — expect pass**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceAudioAccessTests 2>&1 | tail -20`
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add MacAllYouNeed/Voice/VoiceAudioAccess.swift \
        MacAllYouNeedTests/Voice/VoiceAudioAccessTests.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add VoiceAudioAccess wrapper"
```

---

## Chunk 4: Coordinator Refactor + Retry

### Task 9: persistAudio helper + audio-first ordering

**Files:**
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift:145-265,416-452`
- Modify: `MacAllYouNeed/App/AppController.swift` (to thread `historySettings` into the coordinator init)
- Create: `MacAllYouNeedTests/Voice/VoiceCoordinatorAudioPolicyTests.swift`

The goal here is to make audio persistence callable by both the personalization path and the new save-audio path, and to ensure the audio file is written *before* the `VoiceTranscriptDraft` is built so its `audioPath` is set on save.

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import CryptoKit
@testable import MacAllYouNeed
@testable import Core

final class VoiceCoordinatorAudioPolicyTests: XCTestCase {
    func test_audio_saved_when_only_saveAudio_isTrue() async throws {
        let env = try Environment(saveAudio: true, personalizationSaveExamples: false)
        try await env.recordAndStop()

        let listed = try env.transcriptStore.listRecent(limit: 1)
        XCTAssertEqual(listed.count, 1)
        XCTAssertNotNil(listed.first?.audioPath)
        XCTAssertEqual(try env.trainingStore.count(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: listed.first!.audioPath!))
    }

    func test_audio_saved_when_only_personalization_isTrue() async throws {
        let env = try Environment(saveAudio: false, personalizationSaveExamples: true)
        try await env.recordAndStop()

        let listed = try env.transcriptStore.listRecent(limit: 1)
        XCTAssertNotNil(listed.first?.audioPath)
        XCTAssertEqual(try env.trainingStore.count(), 1)
    }

    func test_audio_not_saved_when_both_false() async throws {
        let env = try Environment(saveAudio: false, personalizationSaveExamples: false)
        try await env.recordAndStop()

        let listed = try env.transcriptStore.listRecent(limit: 1)
        XCTAssertNil(listed.first?.audioPath)
        XCTAssertEqual(try env.trainingStore.count(), 0)
    }

    // Test harness builds a coordinator with fakes for ASR, cleanup, paste, and audio capture.
    // The harness lives at the bottom of this file. See Task 10 for retry-flavored variant.
    private struct Environment {
        let transcriptStore: VoiceTranscriptStore
        let trainingStore: VoiceTrainingExampleStore
        let coordinator: VoiceCoordinator
        let audioStub: StubAudioCaptureService

        init(saveAudio: Bool, personalizationSaveExamples: Bool) throws {
            // Build in-memory database, stores, and stub services. See VoiceCoordinatorTests
            // for the existing helpers — this test reuses them. If they do not exist yet,
            // create a sibling helper file `VoiceCoordinatorTestSupport.swift` that exposes
            // `makeInMemoryStores()`, `StubAudioCaptureService`, `StubASREngine`,
            // `StubCleanupPipeline`, `StubCursorPaster`, and `StubHUD`. Each stub records
            // calls so tests can assert on them.
            //
            // After construction:
            //   coordinator = VoiceCoordinator(
            //     audio: audioStub,
            //     activation: StubActivation(),
            //     hud: StubHUD(),
            //     transcripts: transcriptStore,
            //     trainingExampleStore: trainingStore,
            //     ...
            //     historySettings: { VoiceHistorySettings(retention: .forever, saveAudio: saveAudio) },
            //     personalizationSettings: { .init(saveTrainingExamplesEnabled: personalizationSaveExamples, ...) },
            //   )
            fatalError("Implement Environment in test support; see comment.")
        }

        func recordAndStop() async throws { fatalError("Implement on harness.") }
    }
}
```

The `fatalError` placeholders are intentional in the plan — the real harness lives in a sibling file you create here, following whatever pattern the existing voice tests already use. Open `MacAllYouNeedTests/Voice/VoiceCoordinator*Tests.swift` to discover the existing helpers; if none exist, implement them in `MacAllYouNeedTests/Voice/VoiceCoordinatorTestSupport.swift` with the API listed in the comment above.

- [ ] **Step 2: Run — expect failure**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceCoordinatorAudioPolicyTests 2>&1 | tail -30`
Expected: FAIL — `historySettings:` parameter not found on `VoiceCoordinator.init`, plus `fatalError` in harness.

- [ ] **Step 3: Add `historySettings` to `VoiceCoordinator`**

In `MacAllYouNeed/Voice/VoiceCoordinator.swift` find the `init(...)` (around line 40-56) and add:

```swift
private let historySettings: () -> VoiceHistorySettings
// in init:
historySettings: @escaping () -> VoiceHistorySettings = { .init() },
// in body:
self.historySettings = historySettings
```

- [ ] **Step 4: Extract `persistAudio` and reorder the pipeline**

In `MacAllYouNeed/Voice/VoiceCoordinator.swift`, replace the `saveTrainingExample` body (lines 416-452) and the relevant section of `stopRecordingAndPaste` (around lines 200-211) so the new flow is:

1. Decide a fresh `transcriptID` up front: `let transcriptID = UUID().uuidString`.
2. Call `let audioPath = persistAudio(captured: captured, transcriptID: transcriptID)`.
3. Build the draft with that `audioPath` and save with `existingID: transcriptID`.
4. Personalization continues to write its training-example row only when its own gate is on, but no longer writes the audio file itself.

Add a new helper:

```swift
private func persistAudio(
    captured: CapturedAudio,
    transcriptID: String
) -> String? {
    let shouldSave = personalizationSettings().saveTrainingExamplesEnabled
        || historySettings().saveAudio
    guard shouldSave, let trainingExampleStore else { return nil }

    let sampleRate = max(1, Int(captured.sampleRate.rounded()))
    let wavData = VoiceAudioCodec.encodeWAV(samples: captured.samples, sampleRate: sampleRate)
    do {
        return try trainingExampleStore.saveEncryptedAudio(wavData, id: transcriptID)
    } catch {
        log.error("Voice audio persist failed: \(error.localizedDescription, privacy: .public)")
        return nil
    }
}
```

Replace the existing `saveTranscript` helper (lines 249-265) with one that uses an explicit `transcriptID` and `audioPath`:

```swift
private func saveTranscript(
    transcriptID: String,
    captured: CapturedAudio,
    result: VoiceTranscriptionResult,
    cleanedText: String,
    appBundleID: String?,
    audioPath: String?
) throws -> VoiceTranscript {
    try transcripts.save(VoiceTranscriptDraft(
        startedAt: captured.startedAt,
        endedAt: captured.endedAt,
        rawText: result.text,
        cleanedText: cleanedText,
        appBundleID: appBundleID,
        language: result.language,
        modelIdentifier: result.modelIdentifier,
        audioPath: audioPath
    ), existingID: transcriptID)
}
```

In `stopRecordingAndPaste` (around lines 200-211), replace:

```swift
let savedTranscript = try saveTranscript(
    captured: captured, result: result, cleanedText: text, appBundleID: appBundleID
)
saveTrainingExample(
    captured: captured,
    result: result,
    cleanedText: text,
    transcriptID: savedTranscript.id,
    appBundleID: appBundleID
)
```

with:

```swift
let transcriptID = UUID().uuidString
let audioPath = persistAudio(captured: captured, transcriptID: transcriptID)
let savedTranscript = try saveTranscript(
    transcriptID: transcriptID,
    captured: captured,
    result: result,
    cleanedText: text,
    appBundleID: appBundleID,
    audioPath: audioPath
)
saveTrainingExample(
    captured: captured,
    result: result,
    cleanedText: text,
    transcriptID: savedTranscript.id,
    appBundleID: appBundleID,
    audioPath: audioPath
)
NotificationCenter.default.post(name: .voiceTranscriptAppended, object: savedTranscript.id)
```

Update `saveTrainingExample` to take the precomputed `audioPath` and **never** write the file itself:

```swift
private func saveTrainingExample(
    captured: CapturedAudio,
    result: VoiceTranscriptionResult,
    cleanedText: String,
    transcriptID: String,
    appBundleID: String?,
    audioPath: String?
) {
    guard personalizationSettings().saveTrainingExamplesEnabled,
          let trainingExampleStore else { return }
    do {
        try trainingExampleStore.save(.init(
            transcriptID: transcriptID,
            rawText: result.text,
            cleanedText: cleanedText,
            finalText: cleanedText,
            appBundleID: appBundleID,
            language: result.language,
            modelIdentifier: result.modelIdentifier,
            audioPath: audioPath,
            quality: .medium,
            qualityReason: "awaiting_post_edit_verification"
        ))
    } catch {
        log.error("Voice training example save failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 5: Add the notification name**

Append to `MacAllYouNeed/Voice/VoiceCoordinator.swift` at file scope:

```swift
extension Notification.Name {
    static let voiceTranscriptAppended = Notification.Name("com.macallyouneed.voiceTranscriptAppended")
}
```

- [ ] **Step 6: Update `AppController` to pass `historySettings`**

In `MacAllYouNeed/App/AppController.swift`, wherever `VoiceCoordinator(` is constructed, add:

```swift
historySettings: { VoiceHistorySettings.load(from: AppGroupSettings.defaults) },
```

just before the `personalizationSettings:` argument.

- [ ] **Step 7: Run — expect pass**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceCoordinatorAudioPolicyTests 2>&1 | tail -30`
Expected: 3 tests pass. If the harness's `recordAndStop` does not yet drive the coordinator end-to-end, fix it before claiming success.

- [ ] **Step 8: Commit**

```bash
git add MacAllYouNeed/Voice/VoiceCoordinator.swift \
        MacAllYouNeed/App/AppController.swift \
        MacAllYouNeedTests/Voice/VoiceCoordinatorAudioPolicyTests.swift \
        MacAllYouNeedTests/Voice/VoiceCoordinatorTestSupport.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "refactor(voice): extract persistAudio, save audio before transcript draft"
```

---

### Task 10: retryTranscript on VoiceCoordinator

**Files:**
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
- Create: `MacAllYouNeedTests/Voice/VoiceCoordinatorRetryTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
import CryptoKit
@testable import MacAllYouNeed
@testable import Core

final class VoiceCoordinatorRetryTests: XCTestCase {
    func test_retry_insertsNewRow_andPreservesOriginal() async throws {
        let env = try Environment.makeWithSavedAudio(originalText: "hi")
        env.asrStub.nextResult = .init(text: "hi there", language: .english, modelIdentifier: "qwen3-asr")
        env.cleanupStub.nextOutput = "Hi there."

        let originalID = env.savedTranscript.id
        let newTranscript = try await env.coordinator.retryTranscript(id: originalID)

        XCTAssertNotEqual(newTranscript.id, originalID)
        XCTAssertEqual(newTranscript.cleanedText, "Hi there.")
        XCTAssertEqual(newTranscript.audioPath, env.savedTranscript.audioPath)

        let listed = try env.transcriptStore.listRecent(limit: 5)
        XCTAssertEqual(listed.count, 2)
        XCTAssertNotNil(listed.first(where: { $0.id == originalID }))

        XCTAssertEqual(env.pasteStub.calls, 0, "Retry must not paste")
    }

    func test_retry_throws_whenAudioPath_isNil() async {
        let env = try! Environment.makeWithoutAudio()
        do {
            _ = try await env.coordinator.retryTranscript(id: env.savedTranscript.id)
            XCTFail("Expected throw")
        } catch let error as VoiceRetryError {
            XCTAssertEqual(error, .noAudio)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(env.asrStub.calls, 0)
    }

    func test_retry_leavesOriginal_whenASR_fails() async throws {
        let env = try Environment.makeWithSavedAudio(originalText: "hi")
        env.asrStub.nextError = NSError(domain: "test", code: 1)

        do {
            _ = try await env.coordinator.retryTranscript(id: env.savedTranscript.id)
            XCTFail("Expected throw")
        } catch {
            // expected
        }

        let listed = try env.transcriptStore.listRecent(limit: 5)
        XCTAssertEqual(listed.count, 1)
    }

    // Environment helpers extend the support file from Task 9.
}
```

- [ ] **Step 2: Run — expect failure**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceCoordinatorRetryTests 2>&1 | tail -30`
Expected: FAIL — `retryTranscript` not found; `VoiceRetryError` not found.

- [ ] **Step 3: Implement**

Append to `MacAllYouNeed/Voice/VoiceCoordinator.swift`:

```swift
enum VoiceRetryError: Error, Equatable {
    case transcriptNotFound
    case noAudio
    case audioReadFailed
    case audioDecodeFailed
}

extension VoiceCoordinator {
    func retryTranscript(id: String) async throws -> VoiceTranscript {
        guard let original = try transcripts.fetch(id: id) else {
            throw VoiceRetryError.transcriptNotFound
        }
        guard let audioPath = original.audioPath else {
            throw VoiceRetryError.noAudio
        }
        guard let trainingExampleStore else {
            throw VoiceRetryError.audioReadFailed
        }

        let wavData: Data
        do {
            wavData = try trainingExampleStore.loadEncryptedAudio(path: audioPath)
        } catch {
            throw VoiceRetryError.audioReadFailed
        }
        let decoded: VoiceAudioCodec.DecodedAudio
        do {
            decoded = try VoiceAudioCodec.decodeWAV(wavData)
        } catch {
            throw VoiceRetryError.audioDecodeFailed
        }

        let asrResult = try await engine.transcribe(
            samples: decoded.samples,
            sampleRate: Double(decoded.sampleRate),
            options: .default
        )
        let dictionaryEntries = (try? dictionary?.list()) ?? []
        let (appCtx, globalCtx) = loadContexts(bundleID: original.appBundleID)
        let recentExamples = loadRecentExamples(context: appCtx ?? globalCtx)
        let cleanupRequest = Self.buildCleanupRequest(
            rawText: asrResult.text,
            appBundleID: original.appBundleID,
            language: asrResult.language,
            dictionaryEntries: dictionaryEntries,
            appContext: appCtx,
            globalContext: globalCtx,
            recentExamples: recentExamples
        )
        let cleanedResult = await makeCleanupPipeline().clean(cleanupRequest)
        let cleanedText = cleanedResult.cleanedText

        let newID = UUID().uuidString
        let saved = try transcripts.save(
            VoiceTranscriptDraft(
                startedAt: original.startedAt,
                endedAt: original.endedAt,
                rawText: asrResult.text,
                cleanedText: cleanedText,
                appBundleID: original.appBundleID,
                language: asrResult.language,
                modelIdentifier: asrResult.modelIdentifier,
                audioPath: audioPath
            ),
            existingID: newID
        )
        NotificationCenter.default.post(name: .voiceTranscriptAppended, object: saved.id)
        return saved
    }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceCoordinatorRetryTests 2>&1 | tail -30`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Voice/VoiceCoordinator.swift \
        MacAllYouNeedTests/Voice/VoiceCoordinatorRetryTests.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add retryTranscript end-to-end"
```

---

## Chunk 5: Retention Runner

### Task 11: VoiceTranscriptRetentionRunner

**Files:**
- Create: `MacAllYouNeed/Voice/VoiceTranscriptRetentionRunner.swift`
- Create: `MacAllYouNeedTests/Voice/VoiceTranscriptRetentionRunnerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import CryptoKit
@testable import MacAllYouNeed
@testable import Core

final class VoiceTranscriptRetentionRunnerTests: XCTestCase {
    func test_sweep_forever_doesNothing() throws {
        let env = try Environment()
        try env.seedTranscript(ageDays: 100, withAudio: true)

        let runner = VoiceTranscriptRetentionRunner(
            transcriptStore: env.transcriptStore,
            trainingExampleStore: env.trainingStore,
            audioRoot: env.audioRoot,
            historySettings: { VoiceHistorySettings(retention: .forever, saveAudio: true) },
            now: { env.now }
        )
        runner.sweepNow()

        XCTAssertEqual(try env.transcriptStore.listRecent(limit: 10).count, 1)
        XCTAssertEqual(try env.countAudioFiles(), 1)
    }

    func test_sweep_30d_deletesOldRows_andAudio() throws {
        let env = try Environment()
        try env.seedTranscript(ageDays: 100, withAudio: true)
        try env.seedTranscript(ageDays: 1, withAudio: true)

        let runner = VoiceTranscriptRetentionRunner(
            transcriptStore: env.transcriptStore,
            trainingExampleStore: env.trainingStore,
            audioRoot: env.audioRoot,
            historySettings: { VoiceHistorySettings(retention: .days30, saveAudio: true) },
            now: { env.now }
        )
        runner.sweepNow()

        let remaining = try env.transcriptStore.listRecent(limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertLessThan(env.now.timeIntervalSince(remaining[0].endedAt), 86_400 * 2)
        XCTAssertEqual(try env.countAudioFiles(), 1)
    }

    func test_orphanSweep_keepsFiles_referencedByTrainingExample() throws {
        let env = try Environment()
        let trainingID = try env.seedTrainingExampleOnly()
        XCTAssertEqual(try env.countAudioFiles(), 1)

        let runner = VoiceTranscriptRetentionRunner(
            transcriptStore: env.transcriptStore,
            trainingExampleStore: env.trainingStore,
            audioRoot: env.audioRoot,
            historySettings: { VoiceHistorySettings(retention: .days1, saveAudio: true) },
            now: { env.now }
        )
        runner.sweepNow()

        XCTAssertEqual(try env.countAudioFiles(), 1, "audio referenced by training example must survive")
        _ = trainingID
    }

    private struct Environment {
        let transcriptStore: VoiceTranscriptStore
        let trainingStore: VoiceTrainingExampleStore
        let audioRoot: URL
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        init() throws {
            let database = try Database.inMemory()
            try VoiceTrainingExampleStore.applyMigrations(to: database)
            try VoiceTranscriptStore.applyMigrations(to: database)
            transcriptStore = VoiceTranscriptStore(database: database)
            let key = SymmetricKey(size: .bits256)
            audioRoot = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("voice-retention-\(UUID().uuidString)", isDirectory: true)
            trainingStore = VoiceTrainingExampleStore(database: database, deviceKey: key, audioRoot: audioRoot)
        }

        @discardableResult
        func seedTranscript(ageDays: Int, withAudio: Bool) throws -> VoiceTranscript {
            let id = UUID().uuidString
            let ended = now.addingTimeInterval(-Double(ageDays) * 86_400)
            let audioPath: String? = withAudio
                ? try trainingStore.saveEncryptedAudio(Data("wav".utf8), id: id)
                : nil
            return try transcriptStore.save(VoiceTranscriptDraft(
                startedAt: ended.addingTimeInterval(-1),
                endedAt: ended,
                rawText: "r", cleanedText: "c",
                appBundleID: nil, language: .english,
                modelIdentifier: "m", audioPath: audioPath
            ), existingID: id)
        }

        @discardableResult
        func seedTrainingExampleOnly() throws -> String {
            let id = UUID().uuidString
            let path = try trainingStore.saveEncryptedAudio(Data("wav".utf8), id: id)
            try trainingStore.save(.init(
                transcriptID: id,
                rawText: "", cleanedText: "", finalText: "",
                appBundleID: nil, language: .english,
                modelIdentifier: "m", audioPath: path,
                quality: .medium, qualityReason: nil
            ))
            return id
        }

        func countAudioFiles() throws -> Int {
            let files = try FileManager.default.contentsOfDirectory(atPath: audioRoot.path)
            return files.filter { $0.hasSuffix(".aesgcm") }.count
        }
    }
}
```

If `VoiceTranscriptStore.applyMigrations(to:)` doesn't already exist, mirror the pattern used in existing voice store tests; do not invent new schema.

- [ ] **Step 2: Run — expect failure**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceTranscriptRetentionRunnerTests 2>&1 | tail -30`
Expected: FAIL — `VoiceTranscriptRetentionRunner` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Core

final class VoiceTranscriptRetentionRunner {
    private let transcriptStore: VoiceTranscriptStore
    private let trainingExampleStore: VoiceTrainingExampleStore?
    private let audioRoot: URL
    private let historySettings: () -> VoiceHistorySettings
    private let now: () -> Date
    private let log = Logging.logger(for: "VoiceTranscriptRetentionRunner", category: "voice")

    private var timer: Timer?
    private var notificationToken: NSObjectProtocol?

    init(
        transcriptStore: VoiceTranscriptStore,
        trainingExampleStore: VoiceTrainingExampleStore?,
        audioRoot: URL,
        historySettings: @escaping () -> VoiceHistorySettings,
        now: @escaping () -> Date = Date.init
    ) {
        self.transcriptStore = transcriptStore
        self.trainingExampleStore = trainingExampleStore
        self.audioRoot = audioRoot
        self.historySettings = historySettings
        self.now = now
    }

    func start() {
        sweepNow()
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            self?.sweepNow()
        }
        notificationToken = NotificationCenter.default.addObserver(
            forName: .voiceTranscriptAppended, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sweepNow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
            notificationToken = nil
        }
    }

    func sweepNow() {
        let settings = historySettings()
        if let maxAge = settings.retention.maxAgeSeconds {
            do {
                let expired = try transcriptStore.expireByAge(maxAge: maxAge, now: now())
                for transcript in expired {
                    if let path = transcript.audioPath, !isReferencedByTrainingExample(path: path) {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }
            } catch {
                log.error("retention sweep failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        sweepOrphanAudio()
    }

    private func sweepOrphanAudio() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: audioRoot.path) else { return }
        let liveIDs = liveAudioIDs()
        for entry in entries where entry.hasSuffix(".aesgcm") {
            let id = audioID(fromFilename: entry)
            guard !liveIDs.contains(id) else { continue }
            try? fm.removeItem(at: audioRoot.appendingPathComponent(entry))
        }
    }

    private func liveAudioIDs() -> Set<String> {
        var ids: Set<String> = []
        if let recent = try? transcriptStore.listRecent(limit: 10_000) {
            for transcript in recent {
                if let path = transcript.audioPath {
                    ids.insert(audioID(fromFilename: (path as NSString).lastPathComponent))
                }
            }
        }
        if let store = trainingExampleStore,
           let paths = try? store.allAudioPaths() {
            for path in paths {
                ids.insert(audioID(fromFilename: (path as NSString).lastPathComponent))
            }
        }
        return ids
    }

    private func isReferencedByTrainingExample(path: String) -> Bool {
        guard let store = trainingExampleStore,
              let paths = try? store.allAudioPaths() else { return false }
        return paths.contains(path)
    }

    /// Strips ".wav.aesgcm" from a filename to recover the original ID stem.
    private func audioID(fromFilename name: String) -> String {
        var stem = name
        if stem.hasSuffix(".aesgcm") { stem.removeLast(".aesgcm".count) }
        if stem.hasSuffix(".wav") { stem.removeLast(".wav".count) }
        return stem
    }
}
```

- [ ] **Step 4: Add `allAudioPaths` to `VoiceTrainingExampleStore`**

In `Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift`, append:

```swift
public func allAudioPaths() throws -> [String] {
    try db.queue.read { conn in
        let rows = try Row.fetchAll(
            conn,
            sql: "SELECT audio_path FROM voice_training_examples WHERE audio_path IS NOT NULL"
        )
        return rows.compactMap { $0["audio_path"] }
    }
}
```

- [ ] **Step 5: Add file to Xcode project**

Run: `xcodegen generate`. Verify both new files appear in `project.pbxproj`.

- [ ] **Step 6: Run — expect pass**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoiceTranscriptRetentionRunnerTests 2>&1 | tail -30`
Expected: 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add MacAllYouNeed/Voice/VoiceTranscriptRetentionRunner.swift \
        MacAllYouNeedTests/Voice/VoiceTranscriptRetentionRunnerTests.swift \
        Shared/Sources/Core/Voice/VoiceTrainingExampleStore.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add VoiceTranscriptRetentionRunner with orphan sweep"
```

---

### Task 12: Wire VoiceTranscriptRetentionRunner into AppController

**Files:**
- Modify: `MacAllYouNeed/App/AppController.swift`

- [ ] **Step 1: Identify the right wire-up point**

`AppController` already owns `voiceTranscriptStore`, `voiceTrainingExampleStore`, and an `audioRoot` for the training-example store. Find where those are constructed.

- [ ] **Step 2: Add a stored property**

```swift
private let voiceRetentionRunner: VoiceTranscriptRetentionRunner
```

Initialize in `init` after the training example store exists:

```swift
self.voiceRetentionRunner = VoiceTranscriptRetentionRunner(
    transcriptStore: voiceTranscriptStore,
    trainingExampleStore: voiceTrainingExampleStore,
    audioRoot: voiceTrainingExampleStore.audioRoot,
    historySettings: { VoiceHistorySettings.load(from: AppGroupSettings.defaults) }
)
```

- [ ] **Step 3: Start/stop the runner**

In the existing `start()` method (the same one that does login-item bootstrap and clipboard retention), add:

```swift
voiceRetentionRunner.start()
```

In whatever teardown the controller has (if any — match the surrounding pattern; there may be none), call `voiceRetentionRunner.stop()`.

- [ ] **Step 4: Compile**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -30`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/AppController.swift
git commit -m "feat(voice): start VoiceTranscriptRetentionRunner from AppController"
```

---

## Chunk 6: AppControllerVoice Façade

### Task 13: Add history settings, retry, download, delete-with-undo helpers

**Files:**
- Modify: `MacAllYouNeed/App/AppControllerVoice.swift`
- Create: `MacAllYouNeed/Voice/VoiceHistoryUndoToken.swift`

- [ ] **Step 1: Define the undo token type**

```swift
// MacAllYouNeed/Voice/VoiceHistoryUndoToken.swift
import Foundation

struct VoiceHistoryUndoToken {
    let message: String
    let undo: () -> Void
    let expiresAt: Date
}
```

- [ ] **Step 2: Add façade methods to `AppControllerVoice`**

Append to `MacAllYouNeed/App/AppControllerVoice.swift`:

```swift
extension AppController {
    func loadVoiceHistorySettings() -> VoiceHistorySettings {
        VoiceHistorySettings.load(from: AppGroupSettings.defaults)
    }

    func saveVoiceHistorySettings(_ settings: VoiceHistorySettings) {
        settings.save(to: AppGroupSettings.defaults)
        // Trigger an immediate sweep if the user shortened retention.
        voiceRetentionRunner.sweepNow()
    }

    func retryVoiceTranscript(id: String) async throws -> VoiceTranscript {
        try await voiceCoordinator.retryTranscript(id: id)
    }

    func downloadVoiceAudio(transcript: VoiceTranscript, to url: URL) throws {
        guard let path = transcript.audioPath else {
            throw VoiceRetryError.noAudio
        }
        let wav = try voiceTrainingExampleStore.loadEncryptedAudio(path: path)
        try wav.write(to: url, options: .atomic)
    }

    /// Removes the transcript row immediately and defers audio-file deletion by 5 s.
    /// The returned token can call `undo()` to re-insert the row with the same ID.
    func deleteVoiceTranscriptWithUndo(_ transcript: VoiceTranscript) -> VoiceHistoryUndoToken {
        try? voiceTranscriptStore.delete(ids: [transcript.id])

        let audioPath = transcript.audioPath
        let id = transcript.id
        let store = voiceTranscriptStore
        let trainingStore = voiceTrainingExampleStore

        // Defer audio cleanup so undo can resurrect the file.
        let cleanup = Task.detached { [audioPath, trainingStore] in
            try? await Task.sleep(for: .seconds(5))
            guard let audioPath else { return }
            if let trainingStore,
               let paths = try? trainingStore.allAudioPaths(),
               paths.contains(audioPath) {
                return // referenced by training example, leave it
            }
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        let undo: () -> Void = { [transcript, store] in
            cleanup.cancel()
            _ = try? store.save(VoiceTranscriptDraft(
                startedAt: transcript.startedAt,
                endedAt: transcript.endedAt,
                rawText: transcript.rawText,
                cleanedText: transcript.cleanedText,
                appBundleID: transcript.appBundleID,
                language: transcript.language,
                modelIdentifier: transcript.modelIdentifier,
                audioPath: transcript.audioPath
            ), existingID: id)
        }

        return VoiceHistoryUndoToken(
            message: "Transcript deleted",
            undo: undo,
            expiresAt: Date().addingTimeInterval(5)
        )
    }
}
```

- [ ] **Step 3: Add file to Xcode project**

Run: `xcodegen generate`.

- [ ] **Step 4: Compile**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/AppControllerVoice.swift \
        MacAllYouNeed/Voice/VoiceHistoryUndoToken.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add history settings, retry, download, and delete-with-undo facade"
```

---

## Chunk 7: UI

### Task 14: VoiceHistoryStorageHeader

**Files:**
- Create: `MacAllYouNeed/Voice/UI/VoiceHistoryStorageHeader.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import Core

struct VoiceHistoryStorageHeader: View {
    @Binding var settings: VoiceHistorySettings

    var body: some View {
        MAYNSection(title: "Storage") {
            MAYNSettingsRow(
                title: "Keep history",
                subtitle: "How long to keep voice transcripts on this device."
            ) {
                MAYNDropdown(
                    selection: $settings.retention,
                    options: VoiceHistoryRetention.allCases,
                    title: { $0.displayTitle },
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Save audio recordings",
                subtitle: "Required for Download audio and Retry. Recordings are encrypted locally."
            ) {
                Toggle("", isOn: $settings.saveAudio)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Run: `xcodegen generate`.

- [ ] **Step 3: Build**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Voice/UI/VoiceHistoryStorageHeader.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add VoiceHistoryStorageHeader UI"
```

---

### Task 15: VoiceTranscriptRowMenu

**Files:**
- Create: `MacAllYouNeed/Voice/UI/VoiceTranscriptRowMenu.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import Core

struct VoiceTranscriptRowMenu: View {
    let hasAudio: Bool
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if hasAudio {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                Button(action: onDownload) {
                    Label("Download audio", systemImage: "arrow.down.circle")
                }
            } else {
                Button(action: {}) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(true)
                .help("Audio recording wasn't saved for this transcript")
                Button(action: {}) {
                    Label("Download audio", systemImage: "arrow.down.circle")
                }
                .disabled(true)
                .help("Audio recording wasn't saved for this transcript")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete transcript", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Run: `xcodegen generate`.

- [ ] **Step 3: Build**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add MacAllYouNeed/Voice/UI/VoiceTranscriptRowMenu.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add VoiceTranscriptRowMenu"
```

---

### Task 16: VoiceHistoryToast

**Files:**
- Create: `MacAllYouNeed/Voice/UI/VoiceHistoryToast.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct VoiceHistoryToastView: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MAYNToastContent(message: message, symbol: "trash")
            Button(action: onUndo) {
                Text("Undo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}
```

- [ ] **Step 2: Add to Xcode project + build**

Run: `xcodegen generate && xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/Voice/UI/VoiceHistoryToast.swift \
        MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "feat(voice): add VoiceHistoryToastView"
```

---

### Task 17: Wire UI into MainWindowRoot's voiceHistorySection

**Files:**
- Modify: `MacAllYouNeed/App/MainWindowRoot.swift` (around lines 1608, 1818-1844, 2459-2508)

- [ ] **Step 1: Add state**

Near the existing `@State private var transcripts:` at line 1608, add:

```swift
@State private var voiceHistorySettings = VoiceHistorySettings()
@State private var voiceHistoryToast: VoiceHistoryUndoToken?
@State private var voiceHistoryToastClearTask: Task<Void, Never>?
```

In the view's `.task` or `.onAppear`, load:

```swift
.task {
    voiceHistorySettings = controller.loadVoiceHistorySettings()
}
.onChange(of: voiceHistorySettings) { _, new in
    controller.saveVoiceHistorySettings(new)
}
```

- [ ] **Step 2: Replace `voiceHistorySection` body**

Replace lines 1818-1844 with:

```swift
private var voiceHistorySection: some View {
    VStack(spacing: 0) {
        VoiceHistoryStorageHeader(settings: $voiceHistorySettings)
            .padding(.bottom, 12)

        MAYNSection(title: "Recent transcripts") {
            if transcripts.isEmpty {
                MAYNSettingsRow(
                    title: "No transcripts yet",
                    subtitle: "Completed voice dictations appear here after transcription and paste."
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, transcript in
                    if index > 0 { MAYNDivider() }
                    VoiceTranscriptHistoryRow(
                        transcript: transcript,
                        isSelected: selectedTranscriptIDs.contains(transcript.id),
                        onSelect: { selectVoiceTranscript(transcript) },
                        onCopy: { copyVoiceTranscripts(ids: [transcript.id]) },
                        onRetry: { retryVoiceTranscript(transcript) },
                        onDownload: { downloadVoiceTranscript(transcript) },
                        onDelete: { deleteVoiceTranscriptWithUndo(transcript) }
                    )
                }
            }
        }
    }
    .overlay(alignment: .bottom) {
        if let toast = voiceHistoryToast {
            VoiceHistoryToastView(message: toast.message) {
                toast.undo()
                voiceHistoryToastClearTask?.cancel()
                voiceHistoryToast = nil
                reloadTranscripts()
            }
            .padding(.bottom, 12)
            .transition(.opacity)
        }
    }
    .focusable()
    .focusEffectDisabled()
    .onKeyPress { keyPress in
        handleVoiceHistoryKeyPress(keyPress)
    }
}
```

- [ ] **Step 3: Add the three action helpers**

Anywhere alongside the existing `copyVoiceTranscripts`, `selectVoiceTranscript`, `deleteVoiceTranscripts(ids:)` helpers:

```swift
private func retryVoiceTranscript(_ transcript: VoiceTranscript) {
    Task {
        do {
            _ = try await controller.retryVoiceTranscript(id: transcript.id)
            reloadTranscripts()
        } catch {
            // Surface as a transient toast; reuse the same overlay slot.
            showHistoryToast(message: "Retry failed: \(error.localizedDescription)")
        }
    }
}

private func downloadVoiceTranscript(_ transcript: VoiceTranscript) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.wav]
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmm"
    panel.nameFieldStringValue = "voice-\(formatter.string(from: transcript.endedAt)).wav"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try controller.downloadVoiceAudio(transcript: transcript, to: url)
    } catch {
        let alert = NSAlert()
        alert.messageText = "Couldn't save audio"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private func deleteVoiceTranscriptWithUndo(_ transcript: VoiceTranscript) {
    let token = controller.deleteVoiceTranscriptWithUndo(transcript)
    voiceHistoryToastClearTask?.cancel()
    voiceHistoryToast = token
    let task = Task { @MainActor in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        voiceHistoryToast = nil
    }
    voiceHistoryToastClearTask = task
    reloadTranscripts()
}

private func showHistoryToast(message: String) {
    let token = VoiceHistoryUndoToken(
        message: message,
        undo: {},
        expiresAt: Date().addingTimeInterval(3)
    )
    voiceHistoryToastClearTask?.cancel()
    voiceHistoryToast = token
    voiceHistoryToastClearTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        voiceHistoryToast = nil
    }
}
```

`reloadTranscripts()` is the existing helper that re-queries `voiceTranscriptStore.listRecent(...)`; if its name in `MainWindowRoot.swift` differs, use the existing equivalent.

- [ ] **Step 4: Update `VoiceTranscriptHistoryRow` signature + body**

Replace the struct at lines 2459-2508 with:

```swift
private struct VoiceTranscriptHistoryRow: View {
    let transcript: VoiceTranscript
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayText)
                    .font(.callout)
                    .lineLimit(2)
                Text(metadataLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VoiceTranscriptRowMenu(
                hasAudio: transcript.audioPath != nil,
                onRetry: onRetry,
                onDownload: onDownload,
                onDelete: onDelete
            )
            .opacity(isHovering || isSelected ? 1 : 0)
            .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onCopy() }
        )
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isSelected)
        .onHover { isHovering = $0 }
    }

    private var displayText: String {
        MainVoiceTranscriptHistoryPresentation.displayText(transcript)
    }

    private var metadataLine: String {
        let time = CompactTimestamp.format(transcript.endedAt)
        let duration = Self.formatDuration(ms: transcript.durationMs)
        return "\(time) · \(transcript.language.rawValue) · \(transcript.modelIdentifier) · \(duration)"
    }

    static func formatDuration(ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainder)s"
    }

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.10) }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}
```

- [ ] **Step 5: Build**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -30`
Expected: build succeeds; existing call sites of `VoiceTranscriptHistoryRow(...)` updated.

- [ ] **Step 6: Commit**

```bash
git add MacAllYouNeed/App/MainWindowRoot.swift
git commit -m "feat(voice): wire row menu + storage header + undo toast into voice history"
```

---

### Task 18: Personalization page helper text

**Files:**
- Modify: `MacAllYouNeed/Voice/UI/VoicePersonalizationPage.swift:55-65`

- [ ] **Step 1: Add a single line of help text under the existing `saveTrainingExamplesEnabled` toggle**

Find the `MAYNSettingsRow` that wraps `Toggle("", isOn: $settings.saveTrainingExamplesEnabled)` and update its `subtitle:` to include a trailing sentence:

```swift
subtitle: "Allow the app to keep your dictation audio and text for on-device personalization. Audio is encrypted on disk and is also what enables Retry and Download in the History view."
```

If the row currently has no subtitle, add the `subtitle:` argument with the same text.

- [ ] **Step 2: Build**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add MacAllYouNeed/Voice/UI/VoicePersonalizationPage.swift
git commit -m "docs(voice): clarify personalization implies audio is stored"
```

---

## Chunk 8: Verification

### Task 19: Full test pass + lint

- [ ] **Step 1: Run Shared tests**

Run: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test 2>&1 | tail -40`
Expected: all green.

- [ ] **Step 2: Run macOS tests**

Run: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -40`
Expected: all green.

- [ ] **Step 3: Run lint**

Run: `swiftlint --strict 2>&1 | tail -20`
Expected: no violations.

- [ ] **Step 4: Run ci-build (lint + tests + app build)**

Run: `./scripts/ci-build.sh 2>&1 | tail -40`
Expected: success.

- [ ] **Step 5: Commit any incidental fixes**

```bash
git add -A
git commit -m "chore: fix lint and test issues from voice history work"
```

(Skip if nothing changed.)

---

### Task 20: Manual QA checklist

- [ ] **Step 1: Build and launch the app**

Run: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10 && open ~/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*/Build/Products/Debug/MacAllYouNeed.app`

- [ ] **Step 2: Verify Save audio toggle gating**

  1. Open Voice in the main window. Confirm the new `Storage` section appears with `Keep history` defaulting to `Forever` and `Save audio recordings` defaulting to `Off`.
  2. Record a dictation. Confirm `Retry` and `Download audio` in the new row's `⋯` menu are disabled with the expected help text.
  3. Toggle `Save audio recordings` on. Record again. Confirm both menu items are now enabled.

- [ ] **Step 3: Verify Retry**

  1. With the audio-enabled row, click `Retry`. Confirm a new row appears at the top with the same `audioPath` (test by clicking `Retry` again on the new row).
  2. Confirm no text is pasted into the frontmost app.

- [ ] **Step 4: Verify Download audio**

  1. Click `Download audio` on an audio-enabled row.
  2. Confirm `NSSavePanel` opens with name `voice-YYYY-MM-DD-HHmm.wav`.
  3. Save and play the file in QuickTime.

- [ ] **Step 5: Verify Delete + Undo**

  1. Delete a row. Confirm the toast appears with `Undo`.
  2. Click `Undo` within 5 s. Confirm the row reappears.
  3. Delete again. Wait 6 s. Confirm the row is gone and (if it had audio) the audio file on disk is gone.

- [ ] **Step 6: Verify retention**

  1. Set retention to `Last 1 day`.
  2. Confirm a small toast appears reporting `Removed N transcripts older than 1 day` (or, if that polish was skipped, simply confirm older rows are gone after navigating away and back).
  3. Set retention back to `Forever`.

- [ ] **Step 7: Verify Reduce Motion**

  1. Enable Reduce Motion in System Settings → Accessibility → Display.
  2. Hover transcript rows. Confirm the `⋯` button appears without animation.
  3. Trigger an undo toast. Confirm it appears/disappears without animation.

- [ ] **Step 8: Commit** (only if any code changed to fix QA gaps; otherwise skip).

---

## Self-Review

I walked through this against the spec; here is the coverage map.

| Spec section | Tasks |
|---|---|
| §3 Storage header at top of section | 14, 17 |
| §4 `voice.history.retention` + `voice.history.saveAudio` keys + defaults | 2, 14 |
| §5.1 No schema migration | n/a — confirmed by reading store |
| §5.2 `expireByAge` returning deleted transcripts | 4 |
| §5.3 Either-gate audio save + reorder + `existingID` | 3, 9 |
| §5.4 Audio file lifecycle + orphan sweep | 11 |
| §6.1 Storage header UI | 14 |
| §6.2 Row metadata + drop pill + hover menu | 15, 17 |
| §6.3 Menu items + disabled tooltip | 15 |
| §6.4 Undo toast with deferred audio delete | 13, 16, 17 |
| §7.1 Retention runner triggers (launch / hourly / append) | 11, 12 |
| §7.2 Retry semantics + new row + no paste | 10 |
| §7.3 Download audio via NSSavePanel | 13, 17 |
| §7.4 Delete with deferred audio cleanup + training-store guard | 13 |
| §8 Edge cases (missing audio, retention shorten, force-quit) | 13, 15, 11 |
| §10 Unit + coordinator + view tests | 1–11, 19 |
| §11 Migration (none) | n/a |
| §13 Pre-PR checklist | 19, 20 |

One spec item only partially covered: §8 row about "Surface a small `MAYNToast` with the count of items pruned." Tasks 13/17 do not include this. Adding it as Step 5 polish in Task 20 is acceptable; if mingjie-father wants it as a hard requirement, lift it into its own task that:
- Make `VoiceTranscriptRetentionRunner.sweepNow()` return a count.
- Post a notification with the count.
- `MainWindowRoot` observes it and shows a transient toast.

This was left out intentionally to keep the plan small and reversible — the toast adds value but is not load-bearing.

Placeholder scan: no `TBD` / `TODO` / "implement later" strings in the plan. The two `fatalError` placeholders in Task 9 are pointers into a test-support file the engineer must create from the existing voice-test pattern; that is by design because the existing test harness shape is the source of truth.

Type consistency check:
- `VoiceHistorySettings(retention:saveAudio:)` initializer used identically across tasks 2, 9, 11, 13, 14, 17. ✓
- `VoiceHistoryRetention` enum cases `.forever / .days1 / .days7 / .days30 / .days90` used identically across tasks 1, 2, 11, 14. ✓
- `existingID:` parameter name on `save` matches across tasks 3, 9, 10, 13. ✓
- `expireByAge(maxAge:now:)` signature consistent across tasks 4, 11. ✓
- `VoiceHistoryUndoToken(message:undo:expiresAt:)` consistent across tasks 13, 17. ✓
- `VoiceTranscriptRowMenu(hasAudio:onRetry:onDownload:onDelete:)` consistent across tasks 15, 17. ✓
- `VoiceRetryError` cases used in tasks 10, 13. ✓
- `VoiceAudioCodec.decodeWAV` / `.encodeWAV` / `.DecodedAudio` used consistently across tasks 6, 7, 8, 10. ✓
- `Notification.Name.voiceTranscriptAppended` defined in task 9, observed in task 11. ✓
- `allAudioPaths()` defined in task 11, used in task 13. ✓
