# Finder Folder History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Passively record the folders a user opens in Finder (via AX observation, no new mandatory permission) into an encrypted App-Group store, and let them jump back via a hotkey quick-switcher, a menu-bar dropdown, and an in-Finder FinderSync toolbar button.

**Architecture:** A `@MainActor` `FolderHistoryRecorder` (main app) consumes the shared `AXObserverCoordinator` (S1, assumed built per plan 00) attached to the Finder PID, reads `kAXDocumentAttribute` to a POSIX path, applies skip/exclusion/debounce-dedup logic, and upserts into a GRDB `FolderHistoryStore` in the shared App Group container (encrypted-envelope rows keyed on plaintext `path`). Three read surfaces — a borderless `NSPanel` switcher, a Command Center dropdown, and a sandboxed FinderSync `.appex` — all read that one store and route open/reveal through `NSWorkspace`. The feature ships as a gated `FeatureDescriptor`, disabled by default, with onboarding consent, a pause toggle, and an opt-in lazy Apple Events fallback for special folders.

**Tech Stack:** Swift 5.9+, SwiftUI/AppKit, GRDB, ApplicationServices (AX), ScriptingBridge/AppleEvents, FinderSync, XCTest

---

## File Structure

New files:

- `Shared/Sources/Core/Voice/.. ` — n/a
- `Shared/Sources/Core/Storage/FolderHistoryStore.swift` — GRDB store, migrations, upsert, CRUD, retention.
- `Shared/Sources/Core/Storage/FolderHistoryRecord.swift` — `FolderHistoryRow` model + envelope payload.
- `Shared/Sources/Core/Storage/FolderPathNormalizer.swift` — pure `file://` → canonical POSIX path.
- `Shared/Sources/Core/Storage/FolderHistorySkipRules.swift` — pure skip-rule + exclusion matching.
- `Shared/Sources/Core/Storage/FolderHistoryDedup.swift` — pure debounce/dedup coalescing decision.
- `Shared/Sources/Core/Storage/FolderHistoryRetention.swift` — pure retention eviction (pinned-exempt).
- `Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift`
- `Shared/Tests/CoreTests/Storage/FolderPathNormalizerTests.swift`
- `Shared/Tests/CoreTests/Storage/FolderHistorySkipRulesTests.swift`
- `Shared/Tests/CoreTests/Storage/FolderHistoryDedupTests.swift`
- `Shared/Tests/CoreTests/Storage/FolderHistoryRetentionTests.swift`
- `MacAllYouNeed/FinderHistory/FolderHistoryRecorder.swift` — `@MainActor` capture pipeline (uses S1).
- `MacAllYouNeed/FinderHistory/FolderHistoryAXReading.swift` — injectable AX/AppleEvent seam protocol + live impl.
- `MacAllYouNeed/FinderHistory/FolderHistorySwitcherPanel.swift` — borderless NSPanel switcher controller.
- `MacAllYouNeed/FinderHistory/FolderHistorySwitcherView.swift` — SwiftUI switcher list + actions.
- `MacAllYouNeed/FinderHistory/FolderHistoryActions.swift` — pure open/reveal action router.
- `MacAllYouNeed/FinderHistory/FolderHistoryMenuBarView.swift` — Command Center dropdown.
- `MacAllYouNeed/FinderHistory/FolderHistoryPageView.swift` — config/guidance main page.
- `MacAllYouNeed/FinderHistory/FolderHistoryOnboardingView.swift` — consent step.
- `MacAllYouNeed/App/Descriptors/FinderHistoryDescriptor.swift` — gated `FeatureDescriptor`.
- `FinderHistoryExtension/FinderSync.swift` — `FIFinderSync` principal class.
- `FinderHistoryExtension/Info.plist`, `FinderHistoryExtension/FinderHistoryExtension.entitlements`
- `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryActionsTests.swift`
- `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift`
- `MacAllYouNeedTests/Features/FinderHistory/FolderHistorySwitcherFilterTests.swift`

Edited files:

- `Shared/Sources/FeatureCore/FeatureID.swift` — add `finderHistory`.
- `MacAllYouNeed/App/MainAppDestination.swift` — add `finderHistory`.
- `MacAllYouNeed/App/FeatureRegistryProvider.swift` — register descriptor.
- `project.yml` — add FinderSync `.appex` target + main-app dependency.

Test commands:

- Shared: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- App: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- After `project.yml` changes: `xcodegen generate`

> S1 dependency: `AXObserverCoordinator` (roadmap §S1) is assumed to exist. Tasks below reference its callback surface (`onFocusedWindowChanged` / `onTitleChanged` per target PID) and never re-implement `AXObserverCreate`.

---

### Task 1 — Path normalization (pure)

**Files:** `Shared/Sources/Core/Storage/FolderPathNormalizer.swift`; test `Shared/Tests/CoreTests/Storage/FolderPathNormalizerTests.swift`

- [ ] Write failing test:
```swift
import XCTest
@testable import Core

final class FolderPathNormalizerTests: XCTestCase {
    func testFileURLStringToPOSIX() {
        XCTAssertEqual(FolderPathNormalizer.normalize("file:///Users/me/Docs/"), "/Users/me/Docs")
    }

    func testStripsTrailingSlash() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/Users/me/Docs/"), "/Users/me/Docs")
    }

    func testKeepsRootSlash() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/"), "/")
    }

    func testPercentEncodedSpaces() {
        XCTAssertEqual(FolderPathNormalizer.normalize("file:///Users/me/My%20Folder"), "/Users/me/My Folder")
    }

    func testCanonicalizesPrivateVar() {
        XCTAssertEqual(FolderPathNormalizer.normalize("/private/var/folders/x"), "/var/folders/x")
    }

    func testRejectsEmpty() {
        XCTAssertNil(FolderPathNormalizer.normalize(""))
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FolderPathNormalizerTests` → expect `cannot find 'FolderPathNormalizer' in scope`.
- [ ] Minimal impl:
```swift
import Foundation

public enum FolderPathNormalizer {
    /// Converts an AX `kAXDocumentAttribute` value (a `file://` URL string or a
    /// raw POSIX path) into a canonical POSIX path used as the store's unique key.
    public static func normalize(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        var path: String
        if raw.hasPrefix("file://") {
            guard let url = URL(string: raw), url.isFileURL else { return nil }
            path = url.path
        } else {
            path = raw
        }
        if path == "/private/var" { path = "/var" }
        else if path.hasPrefix("/private/var/") { path = String(path.dropFirst("/private".count)) }
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? nil : path
    }
}
```
- [ ] Run-pass: same `swift test --filter FolderPathNormalizerTests` → all green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderPathNormalizer.swift Shared/Tests/CoreTests/Storage/FolderPathNormalizerTests.swift && git commit -m "Add FolderPathNormalizer for Finder history dedup keys

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 2 — Skip rules + exclusion matching (pure)

**Files:** `Shared/Sources/Core/Storage/FolderHistorySkipRules.swift`; test `Shared/Tests/CoreTests/Storage/FolderHistorySkipRulesTests.swift`

- [ ] Write failing test:
```swift
import XCTest
@testable import Core

final class FolderHistorySkipRulesTests: XCTestCase {
    private let rules = FolderHistorySkipRules(home: "/Users/me", exclusions: ["/Users/me/Secret"])

    func testSkipsDesktop() {
        XCTAssertTrue(rules.shouldSkip(path: "/Users/me/Desktop", isSearchWindow: false))
    }

    func testSkipsTrash() {
        XCTAssertTrue(rules.shouldSkip(path: "/Users/me/.Trash", isSearchWindow: false))
    }

    func testSkipsSearchWindow() {
        XCTAssertTrue(rules.shouldSkip(path: "/Users/me/Docs", isSearchWindow: true))
    }

    func testSkipsExcludedPrefix() {
        XCTAssertTrue(rules.shouldSkip(path: "/Users/me/Secret/inner", isSearchWindow: false))
    }

    func testKeepsNormalFolder() {
        XCTAssertFalse(rules.shouldSkip(path: "/Users/me/Projects", isSearchWindow: false))
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FolderHistorySkipRulesTests` → `cannot find 'FolderHistorySkipRules'`.
- [ ] Minimal impl:
```swift
import Foundation

public struct FolderHistorySkipRules: Sendable {
    private let home: String
    private let exclusions: [String]

    public init(home: String, exclusions: [String]) {
        self.home = home
        self.exclusions = exclusions
    }

    public func shouldSkip(path: String, isSearchWindow: Bool) -> Bool {
        if isSearchWindow { return true }
        if path == "\(home)/Desktop" { return true }
        if path == "\(home)/.Trash" || path.hasPrefix("\(home)/.Trash/") { return true }
        for ex in exclusions where path == ex || path.hasPrefix("\(ex)/") { return true }
        return false
    }
}
```
- [ ] Run-pass: `swift test --filter FolderHistorySkipRulesTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistorySkipRules.swift Shared/Tests/CoreTests/Storage/FolderHistorySkipRulesTests.swift && git commit -m "Add Finder history skip rules and exclusion matching

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 3 — Debounce / dedup coalescing decision (pure)

**Files:** `Shared/Sources/Core/Storage/FolderHistoryDedup.swift`; test `Shared/Tests/CoreTests/Storage/FolderHistoryDedupTests.swift`

Mirrors the clipboard 0.5s same-copy window (`LocalClipboardReader.deduplicate`, `MacAllYouNeed/App/LocalClipboardReader.swift:154`) but a 5s same-path window.

- [ ] Write failing test:
```swift
import XCTest
@testable import Core

final class FolderHistoryDedupTests: XCTestCase {
    func testSamePathWithinWindowCoalesces() {
        var d = FolderHistoryDedup(windowSeconds: 5)
        XCTAssertEqual(d.decide(path: "/a", at: Date(timeIntervalSince1970: 100)), .record)
        XCTAssertEqual(d.decide(path: "/a", at: Date(timeIntervalSince1970: 103)), .coalesce)
    }

    func testSamePathAfterWindowRecords() {
        var d = FolderHistoryDedup(windowSeconds: 5)
        _ = d.decide(path: "/a", at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(d.decide(path: "/a", at: Date(timeIntervalSince1970: 106)), .record)
    }

    func testDifferentPathWithinWindowRecords() {
        var d = FolderHistoryDedup(windowSeconds: 5)
        _ = d.decide(path: "/a", at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(d.decide(path: "/b", at: Date(timeIntervalSince1970: 101)), .record)
    }
}
```
- [ ] Run-fail: `swift test --filter FolderHistoryDedupTests` → `cannot find 'FolderHistoryDedup'`.
- [ ] Minimal impl:
```swift
import Foundation

public struct FolderHistoryDedup {
    public enum Decision: Equatable { case record, coalesce }

    private let windowSeconds: TimeInterval
    private var lastPath: String?
    private var lastTime: Date?

    public init(windowSeconds: TimeInterval) { self.windowSeconds = windowSeconds }

    /// A re-focus of the same path within the window updates lastVisited/visitCount
    /// (`coalesce`) instead of being a new conceptual visit (`record`).
    public mutating func decide(path: String, at time: Date) -> Decision {
        defer { lastPath = path; lastTime = time }
        if let lastPath, let lastTime, lastPath == path,
           time.timeIntervalSince(lastTime) < windowSeconds {
            return .coalesce
        }
        return .record
    }
}
```
- [ ] Run-pass: `swift test --filter FolderHistoryDedupTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryDedup.swift Shared/Tests/CoreTests/Storage/FolderHistoryDedupTests.swift && git commit -m "Add Finder history 5s same-path dedup decision

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 4 — `FolderHistoryRecord` model + envelope payload

**Files:** `Shared/Sources/Core/Storage/FolderHistoryRecord.swift`; tested indirectly via Task 5 (model has no behavior). Add a tiny Codable round-trip test here.

- [ ] Write failing test (append to `Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift`, new file):
```swift
import XCTest
@testable import Core

final class FolderHistoryStoreTests: XCTestCase {
    func testEnvelopePayloadRoundTrip() throws {
        let payload = FolderHistoryEnvelope(displayName: "Docs")
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(FolderHistoryEnvelope.self, from: data)
        XCTAssertEqual(back.displayName, "Docs")
    }
}
```
- [ ] Run-fail: `swift test --filter FolderHistoryStoreTests` → `cannot find 'FolderHistoryEnvelope'`.
- [ ] Minimal impl:
```swift
import Foundation

/// Decrypted, human-facing fields kept inside the encrypted envelope blob.
public struct FolderHistoryEnvelope: Codable, Equatable, Sendable {
    public var displayName: String
    public init(displayName: String) { self.displayName = displayName }
}

/// Fully materialized row as seen by read surfaces.
public struct FolderHistoryRow: Equatable, Sendable, Identifiable {
    public var path: String
    public var displayName: String
    public var firstVisited: Date
    public var lastVisited: Date
    public var visitCount: Int
    public var pinned: Bool
    public var exists: Bool
    public var id: String { path }

    public init(path: String, displayName: String, firstVisited: Date,
                lastVisited: Date, visitCount: Int, pinned: Bool, exists: Bool) {
        self.path = path; self.displayName = displayName
        self.firstVisited = firstVisited; self.lastVisited = lastVisited
        self.visitCount = visitCount; self.pinned = pinned; self.exists = exists
    }
}
```
- [ ] Run-pass: `swift test --filter FolderHistoryStoreTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryRecord.swift Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift && git commit -m "Add FolderHistory row + envelope models

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 5 — `FolderHistoryStore`: migration + upsert by path

**Files:** `Shared/Sources/Core/Storage/FolderHistoryStore.swift`; tests appended to `Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift`. Store shape follows `DownloadStore` (`Shared/Sources/Core/Storage/DownloadStore.swift:5-49`), DB opener `Database.swift:8-28`.

- [ ] Write failing test (append):
```swift
    private func makeStore() throws -> FolderHistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let db = try Database(url: dir.appendingPathComponent("fh.sqlite"),
                              migrations: FolderHistoryStore.migrations)
        return try FolderHistoryStore(database: db, deviceKey: .init(size: .bits256))
    }

    func testUpsertInsertsThenIncrements() throws {
        let store = try makeStore()
        let t0 = Date(timeIntervalSince1970: 100)
        try store.upsert(path: "/Users/me/Docs", displayName: "Docs", at: t0)
        let t1 = Date(timeIntervalSince1970: 200)
        try store.upsert(path: "/Users/me/Docs", displayName: "Docs", at: t1)
        let rows = try store.recent(limit: 10)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].visitCount, 2)
        XCTAssertEqual(rows[0].lastVisited, t1)
        XCTAssertEqual(rows[0].firstVisited, t0)
    }

    func testMigrationIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("fh.sqlite")
        _ = try Database(url: url, migrations: FolderHistoryStore.migrations)
        XCTAssertNoThrow(try Database(url: url, migrations: FolderHistoryStore.migrations))
    }
```
Need `import CryptoKit` at top of the test file.
- [ ] Run-fail: `swift test --filter FolderHistoryStoreTests` → `cannot find 'FolderHistoryStore'`.
- [ ] Minimal impl:
```swift
import CryptoKit
import Foundation
import GRDB

public final class FolderHistoryStore {
    private let db: Database
    private let key: SymmetricKey

    public init(database: Database, deviceKey: SymmetricKey) throws {
        db = database; key = deviceKey
    }

    public static let migrations: [Migration] = [
        Migration(identifier: "001-folder-history") { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS folder_history (
                    path TEXT NOT NULL UNIQUE,
                    first_visited INTEGER NOT NULL,
                    last_visited INTEGER NOT NULL,
                    visit_count INTEGER NOT NULL DEFAULT 1,
                    pinned INTEGER NOT NULL DEFAULT 0,
                    exists_flag INTEGER NOT NULL DEFAULT 1,
                    envelope BLOB NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_folder_history_last_visited
                    ON folder_history(last_visited);
            """)
        }
    ]

    private func ms(_ d: Date) -> Int { Int(d.timeIntervalSince1970 * 1000) }
    private func date(_ ms: Int) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    public func upsert(path: String, displayName: String, at time: Date) throws {
        let env = try Cipher.seal(JSONEncoder().encode(FolderHistoryEnvelope(displayName: displayName)), with: key)
        try db.queue.write { conn in
            try conn.execute(sql: """
                INSERT INTO folder_history (path, first_visited, last_visited, visit_count, pinned, exists_flag, envelope)
                VALUES (?, ?, ?, 1, 0, 1, ?)
                ON CONFLICT(path) DO UPDATE SET
                    last_visited = excluded.last_visited,
                    visit_count = visit_count + 1,
                    envelope = excluded.envelope
            """, arguments: [path, ms(time), ms(time), env.combined])
        }
    }

    public func recent(limit: Int) throws -> [FolderHistoryRow] {
        try db.queue.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT path, first_visited, last_visited, visit_count, pinned, exists_flag, envelope
                FROM folder_history ORDER BY pinned DESC, last_visited DESC LIMIT ?
            """, arguments: [limit])
            return try rows.map { try self.materialize($0) }
        }
    }

    private func materialize(_ row: Row) throws -> FolderHistoryRow {
        let env = Envelope(combined: row["envelope"])
        let payload = try JSONDecoder().decode(FolderHistoryEnvelope.self, from: Cipher.open(env, with: key))
        return FolderHistoryRow(
            path: row["path"], displayName: payload.displayName,
            firstVisited: date(row["first_visited"]), lastVisited: date(row["last_visited"]),
            visitCount: row["visit_count"], pinned: (row["pinned"] as Int) != 0,
            exists: (row["exists_flag"] as Int) != 0
        )
    }
}
```
- [ ] Run-pass: `swift test --filter FolderHistoryStoreTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryStore.swift Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift && git commit -m "Add FolderHistoryStore with path upsert and migration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 6 — Store: pin / remove / clear / exists refresh

**Files:** `Shared/Sources/Core/Storage/FolderHistoryStore.swift` (extend); tests appended to `FolderHistoryStoreTests.swift`.

- [ ] Write failing test (append):
```swift
    func testPinSortsOnTopAndExemptsOrder() throws {
        let store = try makeStore()
        try store.upsert(path: "/a", displayName: "a", at: Date(timeIntervalSince1970: 100))
        try store.upsert(path: "/b", displayName: "b", at: Date(timeIntervalSince1970: 200))
        try store.setPinned("/a", pinned: true)
        let rows = try store.recent(limit: 10)
        XCTAssertEqual(rows.map(\.path), ["/a", "/b"]) // pinned first despite older last_visited
    }

    func testRemoveAndClear() throws {
        let store = try makeStore()
        try store.upsert(path: "/a", displayName: "a", at: Date())
        try store.upsert(path: "/b", displayName: "b", at: Date())
        try store.remove("/a")
        XCTAssertEqual(try store.recent(limit: 10).map(\.path), ["/b"])
        try store.clear()
        XCTAssertTrue(try store.recent(limit: 10).isEmpty)
    }

    func testSetExists() throws {
        let store = try makeStore()
        try store.upsert(path: "/a", displayName: "a", at: Date())
        try store.setExists("/a", exists: false)
        XCTAssertFalse(try store.recent(limit: 10)[0].exists)
    }
```
- [ ] Run-fail: `swift test --filter FolderHistoryStoreTests` → `value of type 'FolderHistoryStore' has no member 'setPinned'`.
- [ ] Minimal impl (add methods):
```swift
    public func setPinned(_ path: String, pinned: Bool) throws {
        try db.queue.write { try $0.execute(
            sql: "UPDATE folder_history SET pinned = ? WHERE path = ?",
            arguments: [pinned ? 1 : 0, path]) }
    }

    public func setExists(_ path: String, exists: Bool) throws {
        try db.queue.write { try $0.execute(
            sql: "UPDATE folder_history SET exists_flag = ? WHERE path = ?",
            arguments: [exists ? 1 : 0, path]) }
    }

    public func remove(_ path: String) throws {
        try db.queue.write { try $0.execute(
            sql: "DELETE FROM folder_history WHERE path = ?", arguments: [path]) }
    }

    public func clear() throws {
        try db.queue.write { try $0.execute(sql: "DELETE FROM folder_history") }
    }
```
- [ ] Run-pass: `swift test --filter FolderHistoryStoreTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryStore.swift Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift && git commit -m "Add pin/remove/clear/exists ops to FolderHistoryStore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 7 — Retention eviction (pinned-exempt, pure)

**Files:** `Shared/Sources/Core/Storage/FolderHistoryRetention.swift`; test `Shared/Tests/CoreTests/Storage/FolderHistoryRetentionTests.swift`. Mirrors `RetentionPolicy.enforceItemCap`/`enforceMaxAge` (`RetentionPolicy.swift:15-46`) and pinned-exempt semantics (`:98-104`). Pure decision over rows so it is unit-testable; the store applies the result.

- [ ] Write failing test:
```swift
import XCTest
@testable import Core

final class FolderHistoryRetentionTests: XCTestCase {
    private func row(_ p: String, _ t: TimeInterval, pinned: Bool = false) -> FolderHistoryRow {
        FolderHistoryRow(path: p, displayName: p, firstVisited: Date(timeIntervalSince1970: t),
                         lastVisited: Date(timeIntervalSince1970: t), visitCount: 1, pinned: pinned, exists: true)
    }

    func testItemCapEvictsOldestUnpinned() {
        let rows = [row("/a", 300), row("/b", 200), row("/c", 100)]
        let victims = FolderHistoryRetention.victims(
            rows: rows, policy: .init(maxItems: 2, maxAgeSeconds: nil, maxImageBytes: nil), now: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(victims, ["/c"])
    }

    func testPinnedExemptFromCap() {
        let rows = [row("/a", 300), row("/b", 200), row("/c", 100, pinned: true)]
        let victims = FolderHistoryRetention.victims(
            rows: rows, policy: .init(maxItems: 1, maxAgeSeconds: nil, maxImageBytes: nil), now: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(victims, ["/b"]) // /c pinned, /a within cap
    }

    func testMaxAgeEvictsOldUnpinned() {
        let rows = [row("/a", 390), row("/old", 10), row("/pin", 10, pinned: true)]
        let victims = FolderHistoryRetention.victims(
            rows: rows, policy: .init(maxItems: nil, maxAgeSeconds: 100, maxImageBytes: nil), now: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(victims, ["/old"])
    }
}
```
- [ ] Run-fail: `swift test --filter FolderHistoryRetentionTests` → `cannot find 'FolderHistoryRetention'`.
- [ ] Minimal impl:
```swift
import Foundation

public enum FolderHistoryRetention {
    /// Returns paths to evict. Pinned rows are always exempt. `rows` may be any order.
    public static func victims(rows: [FolderHistoryRow], policy: RetentionPolicy, now: Date) -> [String] {
        let unpinned = rows.filter { !$0.pinned }.sorted { $0.lastVisited > $1.lastVisited }
        var victims = Set<String>()
        if let cap = policy.maxItems, unpinned.count > cap {
            for r in unpinned.suffix(unpinned.count - cap) { victims.insert(r.path) }
        }
        if let maxAge = policy.maxAgeSeconds {
            let cutoff = now.addingTimeInterval(-maxAge)
            for r in unpinned where r.lastVisited < cutoff { victims.insert(r.path) }
        }
        return unpinned.compactMap { victims.contains($0.path) ? $0.path : nil }
    }
}
```
- [ ] Run-pass: `swift test --filter FolderHistoryRetentionTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryRetention.swift Shared/Tests/CoreTests/Storage/FolderHistoryRetentionTests.swift && git commit -m "Add pinned-exempt retention eviction for Finder history

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 8 — Store: enforce retention (wires Task 7 into SQL deletes)

**Files:** `Shared/Sources/Core/Storage/FolderHistoryStore.swift` (extend); tests appended to `FolderHistoryStoreTests.swift`.

- [ ] Write failing test (append):
```swift
    func testEnforceRetentionDeletesVictims() throws {
        let store = try makeStore()
        try store.upsert(path: "/a", displayName: "a", at: Date(timeIntervalSince1970: 300))
        try store.upsert(path: "/b", displayName: "b", at: Date(timeIntervalSince1970: 200))
        try store.upsert(path: "/c", displayName: "c", at: Date(timeIntervalSince1970: 100))
        try store.enforceRetention(.init(maxItems: 2, maxAgeSeconds: nil, maxImageBytes: nil),
                                   now: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(try store.recent(limit: 10).map(\.path), ["/a", "/b"])
    }
```
- [ ] Run-fail: `swift test --filter FolderHistoryStoreTests` → `has no member 'enforceRetention'`.
- [ ] Minimal impl (add method):
```swift
    public func enforceRetention(_ policy: RetentionPolicy, now: Date = Date()) throws {
        let rows = try recent(limit: 100_000)
        let victims = FolderHistoryRetention.victims(rows: rows, policy: policy, now: now)
        guard !victims.isEmpty else { return }
        try db.queue.write { conn in
            for p in victims {
                try conn.execute(sql: "DELETE FROM folder_history WHERE path = ?", arguments: [p])
            }
        }
    }
```
- [ ] Run-pass: `swift test --filter FolderHistoryStoreTests` → green.
- [ ] Commit: `git add Shared/Sources/Core/Storage/FolderHistoryStore.swift Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift && git commit -m "Wire retention eviction into FolderHistoryStore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 9 — `FeatureID.finderHistory` + sidebar destination

**Files:** `Shared/Sources/FeatureCore/FeatureID.swift`; `MacAllYouNeed/App/MainAppDestination.swift`. Tests: a FeatureCore test in `Shared/Tests/` for the enum, app destination verified by build.

- [ ] Write failing test `Shared/Tests/FeatureCoreTests/FeatureIDFinderHistoryTests.swift`:
```swift
import XCTest
@testable import FeatureCore

final class FeatureIDFinderHistoryTests: XCTestCase {
    func testFinderHistoryCaseExists() {
        XCTAssertEqual(FeatureID(rawValue: "finderHistory"), .finderHistory)
        XCTAssertTrue(FeatureID.allCases.contains(.finderHistory))
    }
}
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureIDFinderHistoryTests` → `type 'FeatureID' has no member 'finderHistory'`.
- [ ] Minimal impl: add `case finderHistory` to `FeatureID.swift` (after `windowGrab`). Then in `MainAppDestination.swift`: add `case finderHistory` to the enum, append `.finderHistory` to `primarySidebarDestinations`, and add `title` ("Finder History"), `subtitle` ("Recently visited folders"), `symbolName` ("clock.arrow.circlepath") arms.
- [ ] Run-pass: `swift test --filter FeatureIDFinderHistoryTests` → green.
- [ ] Commit: `git add Shared/Sources/FeatureCore/FeatureID.swift Shared/Tests/FeatureCoreTests/FeatureIDFinderHistoryTests.swift MacAllYouNeed/App/MainAppDestination.swift && git commit -m "Add finderHistory FeatureID and sidebar destination

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 10 — AX reading seam (injectable protocol + live impl)

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryAXReading.swift`; tested via Task 11 (the seam is protocol + thin live impl). Live impl reuses the focused-window AX read shape from `WindowControlCoordinator.swift:358-383`.

- [ ] Write failing test (in `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift`, create file; this task only asserts the protocol exists via a fake):
```swift
import XCTest
@testable import MacAllYouNeed

final class FolderHistoryAXReadingTests: XCTestCase {
    func testFakeConformsToProtocol() {
        let fake = FakeFolderHistoryAXReader(documentPath: "/Users/me/Docs", isSearch: false)
        XCTAssertEqual(fake.focusedFolderPath(pid: 1)?.path, "/Users/me/Docs")
        XCTAssertEqual(fake.focusedFolderPath(pid: 1)?.isSearchWindow, false)
    }
}

final class FakeFolderHistoryAXReader: FolderHistoryAXReading {
    let documentPath: String?
    let isSearch: Bool
    init(documentPath: String?, isSearch: Bool) { self.documentPath = documentPath; self.isSearch = isSearch }
    func focusedFolderPath(pid: pid_t) -> FocusedFolder? {
        guard let documentPath else { return nil }
        return FocusedFolder(path: documentPath, isSearchWindow: isSearch)
    }
    func appleEventFolderPath() -> String? { nil }
}
```
- [ ] Run-fail: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/FolderHistoryAXReadingTests` → `cannot find type 'FolderHistoryAXReading'`.
- [ ] Minimal impl:
```swift
import ApplicationServices
import AppKit

public struct FocusedFolder: Equatable {
    public let path: String          // raw kAXDocumentAttribute value (file:// or POSIX)
    public let isSearchWindow: Bool
}

public protocol FolderHistoryAXReading {
    /// Reads the focused Finder window's document URL. Empty/missing → nil.
    func focusedFolderPath(pid: pid_t) -> FocusedFolder?
    /// Opt-in Apple Event fallback (front Finder window target → POSIX). nil if denied/empty.
    func appleEventFolderPath() -> String?
}

/// Live AX reader. Mirrors WindowControlCoordinator.resolveFocusedWindow (358-383).
struct LiveFolderHistoryAXReader: FolderHistoryAXReading {
    func focusedFolderPath(pid: pid_t) -> FocusedFolder? {
        let app = AXUIElementCreateApplication(pid)
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let window = win else { return nil }
        let axWindow = window as! AXUIElement
        var doc: CFTypeRef?
        let ok = AXUIElementCopyAttributeValue(axWindow, kAXDocumentAttribute as CFString, &doc) == .success
        var title: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &title)
        let isSearch = (title as? String).map { $0.localizedCaseInsensitiveContains("Search") } ?? false
        guard ok, let path = doc as? String, !path.isEmpty else { return nil }
        return FocusedFolder(path: path, isSearchWindow: isSearch)
    }

    func appleEventFolderPath() -> String? {
        // Lazy Apple Event ("front Finder window target → POSIX"). Implemented in
        // the live path only when the user enabled the fallback. See Task 12.
        FolderHistoryAppleEventResolver.frontWindowPOSIXPath()
    }
}
```
(`FolderHistoryAppleEventResolver` is a stub added in Task 12; for this task add a minimal `enum FolderHistoryAppleEventResolver { static func frontWindowPOSIXPath() -> String? { nil } }` in the same file so it builds.)
- [ ] Run-pass: same `-only-testing` command → green.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryAXReading.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift && git commit -m "Add injectable Finder history AX reading seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 11 — `FolderHistoryRecorder` capture pipeline (testable)

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryRecorder.swift`; tests appended to `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift`. State machine consumes S1 callbacks; AX/AppleEvent behind the Task-10 seam; storage behind a closure so it is testable without a live Finder.

- [ ] Write failing test (append):
```swift
import Core

@MainActor
final class FolderHistoryRecorderTests: XCTestCase {
    func testRecordsNormalFolderOnce() {
        var recorded: [(String, String)] = []
        let rec = FolderHistoryRecorder(
            ax: FakeFolderHistoryAXReader(documentPath: "file:///Users/me/Docs", isSearch: false),
            skipRules: FolderHistorySkipRules(home: "/Users/me", exclusions: []),
            dedupWindow: 5,
            appleEventsEnabled: false,
            onRecord: { recorded.append(($0, $1)) })
        rec.handleSignal(pid: 1, at: Date(timeIntervalSince1970: 100))
        rec.handleSignal(pid: 1, at: Date(timeIntervalSince1970: 102)) // within dedup → coalesce
        XCTAssertEqual(recorded.map(\.0), ["/Users/me/Docs"])
    }

    func testSkipsExcludedAndSearch() {
        var recorded: [String] = []
        let rec = FolderHistoryRecorder(
            ax: FakeFolderHistoryAXReader(documentPath: "/Users/me/Secret", isSearch: false),
            skipRules: FolderHistorySkipRules(home: "/Users/me", exclusions: ["/Users/me/Secret"]),
            dedupWindow: 5, appleEventsEnabled: false,
            onRecord: { p, _ in recorded.append(p) })
        rec.handleSignal(pid: 1, at: Date())
        XCTAssertTrue(recorded.isEmpty)
    }

    func testEmptyPathSkippedWhenFallbackOff() {
        var recorded: [String] = []
        let rec = FolderHistoryRecorder(
            ax: FakeFolderHistoryAXReader(documentPath: nil, isSearch: false),
            skipRules: FolderHistorySkipRules(home: "/Users/me", exclusions: []),
            dedupWindow: 5, appleEventsEnabled: false,
            onRecord: { p, _ in recorded.append(p) })
        rec.handleSignal(pid: 1, at: Date())
        XCTAssertTrue(recorded.isEmpty)
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderHistoryRecorderTests` → `cannot find 'FolderHistoryRecorder'`.
- [ ] Minimal impl (pipeline only — S1 wiring added in Task 13):
```swift
import AppKit
import Core
import Foundation

@MainActor
final class FolderHistoryRecorder {
    private let ax: FolderHistoryAXReading
    private let skipRules: FolderHistorySkipRules
    private var dedup: FolderHistoryDedup
    private let appleEventsEnabled: Bool
    private let onRecord: (String, String) -> Void

    init(ax: FolderHistoryAXReading,
         skipRules: FolderHistorySkipRules,
         dedupWindow: TimeInterval,
         appleEventsEnabled: Bool,
         onRecord: @escaping (String, String) -> Void) {
        self.ax = ax
        self.skipRules = skipRules
        self.dedup = FolderHistoryDedup(windowSeconds: dedupWindow)
        self.appleEventsEnabled = appleEventsEnabled
        self.onRecord = onRecord
    }

    /// Called from an S1 focused-window / title-changed callback for the Finder PID.
    func handleSignal(pid: pid_t, at time: Date = Date()) {
        var raw: String?
        var isSearch = false
        if let focused = ax.focusedFolderPath(pid: pid) {
            raw = focused.path
            isSearch = focused.isSearchWindow
        } else if appleEventsEnabled {
            raw = ax.appleEventFolderPath()
        }
        guard let raw, let path = FolderPathNormalizer.normalize(raw) else { return }
        guard !skipRules.shouldSkip(path: path, isSearchWindow: isSearch) else { return }
        switch dedup.decide(path: path, at: time) {
        case .coalesce, .record:
            // Both update the store (upsert handles count/lastVisited); coalesce
            // just means "no new conceptual visit" — store upsert is still safe.
            onRecord(path, (path as NSString).lastPathComponent)
        }
    }
}
```
> Note: per spec §4.1, coalesce maps to a lastVisited/visitCount bump and record to a new visit — the store's `upsert` already expresses both. The recorder calls `onRecord` for both; the distinction is preserved if a future caller needs it. Keep the `switch` so dedup wiring stays explicit.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryRecorder.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift && git commit -m "Add FolderHistoryRecorder capture pipeline with dedup and skip rules

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 12 — Opt-in lazy Apple Event resolver

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryAppleEventResolver.swift` (replace the stub from Task 10); test `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift` (append a fallback test). The Apple Event itself cannot run under XCTest (no live Finder / TCC) — the testable seam is "fallback only consulted when AX empty AND enabled"; the live AppleScript is manually verified.

- [ ] Write failing test (append):
```swift
    func testFallbackConsultedWhenEnabledAndAXEmpty() {
        var recorded: [String] = []
        let rec = FolderHistoryRecorder(
            ax: FakeFolderHistoryAXReader(documentPath: nil, isSearch: false, fallback: "/Users/me/Special"),
            skipRules: FolderHistorySkipRules(home: "/Users/me", exclusions: []),
            dedupWindow: 5, appleEventsEnabled: true,
            onRecord: { p, _ in recorded.append(p) })
        rec.handleSignal(pid: 1, at: Date())
        XCTAssertEqual(recorded, ["/Users/me/Special"])
    }
```
Extend `FakeFolderHistoryAXReader` with `fallback: String?` init param and return it from `appleEventFolderPath()`.
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderHistoryRecorderTests` → fails (extra init arg / nil fallback).
- [ ] Minimal impl: update the fake (test file) to honor `fallback`, then replace the stub resolver with a real AppleScript implementation:
```swift
import AppKit
import Foundation

/// Lazy, opt-in Apple Event fallback: asks Finder for the POSIX path of the
/// front window's target. Sent ONLY after the user enables the toggle and only
/// when kAXDocumentAttribute was empty (see FolderHistoryRecorder).
enum FolderHistoryAppleEventResolver {
    static func frontWindowPOSIXPath() -> String? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }       // denied / no Automation → degrade silently
        let path = result.stringValue ?? ""
        return path.isEmpty ? nil : path
    }
}
```
Add `NSAppleEventsUsageDescription` to the main app Info.plist (project.yml main-app `info.properties`) in this task: "Mac All You Need uses Apple Events to resolve the path of special Finder folders for your folder history. This is optional and off by default."
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Manual verification (noted, not automated): enable the fallback toggle, open a special/smart folder in Finder, accept the one-time Automation prompt, confirm the folder appears in history; deny once and confirm no crash and no re-prompt.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryAppleEventResolver.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift project.yml && git commit -m "Add opt-in lazy Apple Event folder path fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 13 — Wire recorder to S1 + Finder activation + pause/trust

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryRecorder.swift` (extend with start/stop). Tested via a small lifecycle unit test (attach/detach toggles a flag); live AX attach is manually verified.

- [ ] Write failing test (append to `FolderHistoryRecorderTests`):
```swift
    func testPauseStopsRecording() {
        var recorded: [String] = []
        let rec = FolderHistoryRecorder(
            ax: FakeFolderHistoryAXReader(documentPath: "/Users/me/Docs", isSearch: false),
            skipRules: FolderHistorySkipRules(home: "/Users/me", exclusions: []),
            dedupWindow: 5, appleEventsEnabled: false,
            onRecord: { p, _ in recorded.append(p) })
        rec.setActive(false)
        rec.handleSignal(pid: 1, at: Date())
        XCTAssertTrue(recorded.isEmpty)
        rec.setActive(true)
        rec.handleSignal(pid: 1, at: Date())
        XCTAssertEqual(recorded, ["/Users/me/Docs"])
    }
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderHistoryRecorderTests` → `has no member 'setActive'`.
- [ ] Minimal impl: add an `isActive` gate to `handleSignal` (early-return when inactive) and `setActive(_:)`. Add S1 wiring methods (not unit-tested; manual):
```swift
    private var isActive = true
    func setActive(_ active: Bool) { isActive = active; active ? attach() : detach() }

    // --- S1 wiring (manual-verified) ---
    private var finderObservation: AXObserverCoordinator.Subscription?
    func start(axCoordinator: AXObserverCoordinator) {
        self.axCoordinator = axCoordinator
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.finder" else { return }
            self?.attach()
        }
        attach() // if Finder already running
    }
    private weak var axCoordinator: AXObserverCoordinator?
    private func attach() {
        guard isActive, let coordinator = axCoordinator,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return }
        finderObservation = coordinator.observe(
            pid: finder.processIdentifier,
            notifications: [kAXFocusedWindowChangedNotification, kAXTitleChangedNotification]) { [weak self] in
                self?.handleSignal(pid: finder.processIdentifier)
        }
    }
    private func detach() { finderObservation = nil }
```
Add `private func handleSignal(pid:)` overload defaulting `at: Date()` (already present). Guard `handleSignal` body with `guard isActive else { return }`.
> `AXObserverCoordinator.observe(pid:notifications:onEvent:)` and `.Subscription` are S1's API (plan 00). If S1's signature differs, adapt the call but keep the same start/attach/detach lifecycle.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Manual verification: with the feature enabled and Accessibility granted, navigate several Finder folders and confirm rows appear; revoke Accessibility mid-session and confirm the recorder detaches (no crash); re-grant and confirm re-attach.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryRecorder.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistoryRecorderTests.swift && git commit -m "Wire FolderHistoryRecorder to S1 AX coordinator and pause gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 14 — Open/reveal action router (pure)

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryActions.swift`; test `MacAllYouNeedTests/Features/FinderHistory/FolderHistoryActionsTests.swift`. Routes to the same `NSWorkspace` calls as `BrowseFolderCoordinator.swift:9-15`; pure decision so the modifier mapping is testable.

- [ ] Write failing test:
```swift
import XCTest
@testable import MacAllYouNeed

final class FolderHistoryActionsTests: XCTestCase {
    func testReturnOpens() {
        XCTAssertEqual(FolderHistoryActions.action(optionHeld: false), .open)
    }
    func testOptionReturnReveals() {
        XCTAssertEqual(FolderHistoryActions.action(optionHeld: true), .reveal)
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderHistoryActionsTests` → `cannot find 'FolderHistoryActions'`.
- [ ] Minimal impl:
```swift
import AppKit

enum FolderHistoryActions {
    enum Kind: Equatable { case open, reveal }

    /// Return → open in Finder; Opt-Return / modifier-click → reveal/select.
    static func action(optionHeld: Bool) -> Kind { optionHeld ? .reveal : .open }

    /// Executes the action; returns false if the path no longer exists (caller
    /// marks exists_flag = 0 and shows the missing state). Mirrors BrowseFolderCoordinator.
    @discardableResult
    static func perform(_ kind: Kind, path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return false }
        switch kind {
        case .open: NSWorkspace.shared.open(url)
        case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        return true
    }
}
```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryActions.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistoryActionsTests.swift && git commit -m "Add Finder history open/reveal action router with existence check

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 15 — Switcher substring filter (pure)

**Files:** `MacAllYouNeed/FinderHistory/FolderHistorySwitcherView.swift` (add a static filter func first); test `MacAllYouNeedTests/Features/FinderHistory/FolderHistorySwitcherFilterTests.swift`. The full SwiftUI view comes in Task 16; filtering is pure and tested now.

- [ ] Write failing test:
```swift
import XCTest
import Core
@testable import MacAllYouNeed

final class FolderHistorySwitcherFilterTests: XCTestCase {
    private func row(_ name: String, _ path: String, pinned: Bool = false) -> FolderHistoryRow {
        FolderHistoryRow(path: path, displayName: name, firstVisited: .init(), lastVisited: .init(),
                         visitCount: 1, pinned: pinned, exists: true)
    }

    func testMatchesNameOrPath() {
        let rows = [row("Docs", "/Users/me/Docs"), row("Pics", "/Users/me/Photos")]
        XCTAssertEqual(FolderHistorySwitcherFilter.apply(rows, query: "photo").map(\.path), ["/Users/me/Photos"])
        XCTAssertEqual(FolderHistorySwitcherFilter.apply(rows, query: "doc").map(\.displayName), ["Docs"])
    }

    func testEmptyQueryReturnsAll() {
        let rows = [row("Docs", "/Users/me/Docs")]
        XCTAssertEqual(FolderHistorySwitcherFilter.apply(rows, query: "  ").count, 1)
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderHistorySwitcherFilterTests` → `cannot find 'FolderHistorySwitcherFilter'`.
- [ ] Minimal impl (new file `FolderHistorySwitcherView.swift` start with just the filter):
```swift
import Core
import Foundation

enum FolderHistorySwitcherFilter {
    /// Case-insensitive substring over display name + path. Preserves input order
    /// (caller supplies pinned-first, last_visited DESC).
    static func apply(_ rows: [FolderHistoryRow], query: String) -> [FolderHistoryRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return rows }
        return rows.filter {
            $0.displayName.lowercased().contains(q) || $0.path.lowercased().contains(q)
        }
    }
}
```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistorySwitcherView.swift MacAllYouNeedTests/Features/FinderHistory/FolderHistorySwitcherFilterTests.swift && git commit -m "Add Finder history switcher substring filter

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 16 — Switcher SwiftUI list + borderless panel

**Files:** `MacAllYouNeed/FinderHistory/FolderHistorySwitcherView.swift` (extend with the view); `MacAllYouNeed/FinderHistory/FolderHistorySwitcherPanel.swift`. UI-only (no new unit test; verified by build + manual). Borderless `[.borderless, .nonactivatingPanel]` per `KeyboardShortcutFloatingOverlayController.swift:8`; all chrome via `MAYNTheme`/`MAYNMotion`, search via `MAYNTextField`, rows via MAYN controls.

- [ ] Write failing test: none (pure UI). Instead, run the build to confirm it compiles after writing.
- [ ] Run-fail: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` BEFORE writing the view (referencing `FolderHistorySwitcherView(...)` from the panel) → expect compile error `cannot find 'FolderHistorySwitcherView'`.
- [ ] Minimal impl: implement `FolderHistorySwitcherView` (SwiftUI):
  - `MAYNTextField`-style search field, focused on open, bound to `@State query`.
  - List of `FolderHistorySwitcherFilter.apply(rows, query:)` rows: `NSWorkspace.shared.icon(forFile:)` thumbnail, `displayName`, dimmed middle-truncated `path`, relative time (`RelativeDateTimeFormatter`).
  - Arrow-key selection; `Return` → `FolderHistoryActions.perform(.open,...)`; `Opt-Return` → `.reveal`; `Esc` dismiss via callback.
  - Inline `MAYNButton` pin toggle + remove per row calling store closures.
  - Stale rows (`exists == false`) dimmed with a small "missing" affordance + remove.
  - All animation via `MAYNMotion.<kind>Animation(reduceMotion:)`; honor `@Environment(\.accessibilityReduceMotion)`.
  Implement `FolderHistorySwitcherPanel` as a `NonActivatingFloatingPanelController`-style controller using `KeyboardShortcutFloatingOverlayPresentation.styleMask` and `.origin(...)` for centering, hosting the SwiftUI view.
- [ ] Run-pass: `xcodebuild build ...` → succeeds. Manual: trigger the switcher hotkey, type to filter, Return opens, Opt-Return reveals, Esc dismisses; Reduce-Motion pass.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistorySwitcherView.swift MacAllYouNeed/FinderHistory/FolderHistorySwitcherPanel.swift && git commit -m "Add Finder history borderless switcher panel and list UI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 17 — Menu-bar / Command Center dropdown

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryMenuBarView.swift`. UI-only (build + manual). Supplied through `FeatureDescriptor.menuBarItemFactory` (`FeatureDescriptor.swift:54`), mirrors switcher data source; inline pin/remove, click-to-open, modifier-click reveals; no Pause footer (Clipboard-only per CLAUDE.md).

- [ ] Run-fail: reference `FolderHistoryMenuBarView()` from the descriptor (Task 20) — for this task, build after writing the view to confirm compile.
- [ ] Minimal impl: SwiftUI section listing `recent(limit:)` rows (pinned-first), reusing `FolderHistorySwitcherFilter`-free direct list; each row uses MAYN row chrome, icon, name, relative time; `onTap` → `FolderHistoryActions.perform(.open,...)`; option-modifier → `.reveal`; inline pin/remove buttons. Use `MAYNTheme`/`MAYNMotion` only.
- [ ] Run-pass: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → succeeds. Manual: open Command Center, confirm the dropdown lists recent/pinned, open/reveal/pin/remove work.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryMenuBarView.swift && git commit -m "Add Finder history Command Center dropdown

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 18 — Config/guidance main page

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryPageView.swift`. UI-only (build + manual). `FunctionPageShell`; header `ShortcutChip` (switcher hotkey); `PermissionCard`/`AccessibilityPermissionRow` for Accessibility; FinderSync enabled state; feature on/off + **Pause** toggle; retention (`MAYNNumericStepper`/`MAYNDropdown` → `RetentionPolicy`); path exclusion editor following `SettingsExclusionEditor.swift:6-241`; Apple-Events fallback toggle (labeled "triggers a one-time macOS permission prompt"); "Clear history" destructive `MAYNButton`; how-to `InstructionStrip`. **Never lists captured folders** (roadmap §6).

- [ ] Run-fail: build referencing the page from the destination router (Task 20); compile-fail until written.
- [ ] Minimal impl: build the page per the bullets above; wire toggles to a `FolderHistorySettings` UserDefaults-backed store (pause, appleEventsEnabled, maxItems, maxAge, exclusions). "Clear history" calls `store.clear()`.
- [ ] Run-pass: `xcodebuild build ...` → succeeds. Manual: page renders, pause toggles capture, exclusions persist, clear empties history, no folder list shown, Reduce-Motion pass.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryPageView.swift && git commit -m "Add Finder history config/guidance main page

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 19 — Onboarding consent step

**Files:** `MacAllYouNeed/FinderHistory/FolderHistoryOnboardingView.swift`. UI-only (build + manual). Wired via descriptor `onboardingSetupFactory` (`FeatureDescriptor.swift:53`). Plain-language consent (records folders you open in Finder; stays on-device in App Group; pause/clear anytime; nothing sent to cloud); affirmative Continue; shows Accessibility status; Apple-Events fallback presented as optional + off.

- [ ] Run-fail: build referencing the onboarding view from the descriptor (Task 20); compile-fail until written.
- [ ] Minimal impl: SwiftUI consent screen using MAYN components; a `MAYNButton(.primary)` "Continue" that only enables after the user acknowledges; an Accessibility status row; an optional, default-off Apple-Events explainer toggle.
- [ ] Run-pass: `xcodebuild build ...` → succeeds. Manual: enabling the feature shows consent; Continue gated on acknowledgement.
- [ ] Commit: `git add MacAllYouNeed/FinderHistory/FolderHistoryOnboardingView.swift && git commit -m "Add Finder history onboarding consent step

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 20 — `FinderHistoryDescriptor` + registration + destination routing

**Files:** `MacAllYouNeed/App/Descriptors/FinderHistoryDescriptor.swift`; `MacAllYouNeed/App/FeatureRegistryProvider.swift`; the destination→view router (wherever `MainAppDestination.folderPreview` maps to its page; mirror that). Mirrors `FolderPreviewDescriptor.swift:4-22`. Test: a descriptor unit test in `MacAllYouNeedTests/Features/FinderHistory/`.

- [ ] Write failing test `MacAllYouNeedTests/Features/FinderHistory/FinderHistoryDescriptorTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FinderHistoryDescriptorTests: XCTestCase {
    func testDescriptorShape() {
        let d = FinderHistoryDescriptor.descriptor()
        XCTAssertEqual(d.id, .finderHistory)
        XCTAssertTrue(d.hotkeys.contains { $0.identifier == "finderHistory.switcher" })
        XCTAssertNotNil(d.onboardingSetupFactory)
        XCTAssertNotNil(d.menuBarItemFactory)
        if case .staticBundleExtension(let cfg) = d.osExtensionPolicy {
            XCTAssertEqual(cfg.extensionBundleID, "com.macallyouneed.app.finderhistory")
            XCTAssertTrue(cfg.respectsFeatureFlag)
        } else { XCTFail("expected staticBundleExtension") }
    }

    func testRegistered() {
        let reg = FeatureRegistryProvider.makeRegistry()
        XCTAssertTrue(reg.descriptors.contains { $0.id == .finderHistory })
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FinderHistoryDescriptorTests` → `cannot find 'FinderHistoryDescriptor'`.
- [ ] Minimal impl:
```swift
import FeatureCore
import SwiftUI

enum FinderHistoryDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .finderHistory,
            displayName: "Finder History",
            icon: "clock.arrow.circlepath",
            summary: "Jump back to folders you recently opened in Finder.",
            detailDescription: "Records the folders you open in Finder so you can reopen any of them later, even after the window is closed.",
            requiredPermissions: [.accessibility],
            hotkeys: [HotkeyDescriptor(identifier: "finderHistory.switcher", displayName: "Recent folders switcher")],
            osExtensionPolicy: .staticBundleExtension(StaticExtensionConfig(
                extensionBundleID: "com.macallyouneed.app.finderhistory",
                runsRegardlessOfFeatureState: false,
                respectsFeatureFlag: true)),
            activator: FinderHistoryFeatureActivator(),
            onboardingSetupFactory: { AnyView(FolderHistoryOnboardingView()) },
            menuBarItemFactory: { AnyView(FolderHistoryMenuBarView()) }
        )
    }
}
```
  Add a minimal `FinderHistoryFeatureActivator` (mirror `FolderPreviewFeatureActivator`: start/stop the recorder + retention sweep on enable/disable). Add `.finderHistory` to `FeatureRegistryProvider.makeRegistry()`. Route `MainAppDestination.finderHistory` → `FolderHistoryPageView()` in the same place `folderPreview` is routed.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit: `git add MacAllYouNeed/App/Descriptors/FinderHistoryDescriptor.swift MacAllYouNeed/App/FeatureRegistryProvider.swift MacAllYouNeedTests/Features/FinderHistory/FinderHistoryDescriptorTests.swift && git commit -m "Register gated FinderHistory FeatureDescriptor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 21 — FinderSync `.appex` target in project.yml

**Files:** `project.yml` (add target ~after FolderPreview block, `:159-190`); `FinderHistoryExtension/Info.plist`; `FinderHistoryExtension/FinderHistoryExtension.entitlements`. Verified by `xcodegen generate` + build.

- [ ] Run-fail: `xcodegen generate` then `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` BEFORE adding the principal class → expect a missing-principal-class / no-sources build failure for the new target.
- [ ] Minimal impl: add to `project.yml` targets:
```yaml
  FinderHistoryExtension:
    type: app-extension
    platform: macOS
    sources:
      - path: FinderHistoryExtension
    info:
      path: FinderHistoryExtension/Info.plist
      properties:
        CFBundleName: FinderHistoryExtension
        NSExtension:
          NSExtensionPointIdentifier: com.apple.FinderSync
          NSExtensionPrincipalClass: "$(PRODUCT_MODULE_NAME).FinderHistoryFinderSync"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macallyouneed.app.finderhistory
        CODE_SIGN_ENTITLEMENTS: FinderHistoryExtension/FinderHistoryExtension.entitlements
    dependencies:
      - package: Shared
        product: Core
      - package: Shared
        product: FeatureCore
```
  Add the extension as a dependency/embed of the main `MacAllYouNeed` target (mirror how `FolderPreview` is embedded). Create the entitlements file (copy of `FolderPreview/FolderPreview.entitlements`: app-sandbox + `group.com.macallyouneed.shared`). Add a minimal `Info.plist`. Create a placeholder `FinderHistoryExtension/FinderHistoryFinderSync.swift` so the target has sources (real impl in Task 22):
```swift
import FinderSync
final class FinderHistoryFinderSync: FIFinderSync {}
```
- [ ] Run-pass: `xcodegen generate && xcodebuild build ...` → succeeds (target builds).
- [ ] Commit: `git add project.yml FinderHistoryExtension MacAllYouNeed.xcodeproj && git commit -m "Add FinderSync app-extension target via project.yml

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 22 — FinderSync "Recent Folders" toolbar button

**Files:** `FinderHistoryExtension/FinderHistoryFinderSync.swift` (replace placeholder). The store read is exercised by the existing `FolderHistoryStoreTests` (Task 5/6) in `Core`; the FinderSync glue is manually verified (extensions can't run under XCTest).

- [ ] Write failing test: reuse the store read path — add a `Core` test asserting an appex-style **read-only** open returns rows, in `FolderHistoryStoreTests.swift`:
```swift
    func testReadOnlyOpenReturnsRows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("fh.sqlite")
        let key = SymmetricKey(size: .bits256)
        let writer = try FolderHistoryStore(database: try Database(url: url, migrations: FolderHistoryStore.migrations), deviceKey: key)
        try writer.upsert(path: "/a", displayName: "a", at: Date())
        let reader = try FolderHistoryStore(database: try Database(url: url, migrations: FolderHistoryStore.migrations), deviceKey: key)
        XCTAssertEqual(try reader.recent(limit: 10).map(\.path), ["/a"])
    }
```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FolderHistoryStoreTests` → fails only if a regression; if already green (two openers on same WAL DB), proceed — this locks the appex read contract.
- [ ] Minimal impl: implement the FinderSync class:
```swift
import AppKit
import Core
import FinderSync

final class FinderHistoryFinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: NSHomeDirectory())]
    }

    override var toolbarItemName: String { "Recent Folders" }
    override var toolbarItemToolTip: String { "Recently visited folders" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent Folders")!
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        for row in loadRecent() {
            let item = NSMenuItem(title: row.displayName, action: #selector(openFolder(_:)), keyEquivalent: "")
            item.representedObject = row.path
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func loadRecent() -> [FolderHistoryRow] {
        // Read-only open of the shared store via App Group + device key.
        guard let store = try? FolderHistorySharedReader.open() else { return [] }
        return (try? store.recent(limit: 15)) ?? []
    }
}
```
  Add `FinderHistorySharedReader.open()` (shared helper resolving `AppGroup.containerURL()` + device key, returning a `FolderHistoryStore`). It opens the same WAL DB; readers coexist via `busy_timeout = 5000` (`Database.swift:13-14`).
- [ ] Run-pass: `swift test --filter FolderHistoryStoreTests` green; `xcodebuild build ...` succeeds.
- [ ] Manual verification: enable the extension in System Settings → Extensions; open a Finder window; click "Recent Folders"; confirm the menu lists recent folders and selecting one opens it.
- [ ] Commit: `git add FinderHistoryExtension/FinderHistoryFinderSync.swift Shared/Sources/Core/Storage/FolderHistoryStore.swift Shared/Tests/CoreTests/Storage/FolderHistoryStoreTests.swift && git commit -m "Implement FinderSync Recent Folders toolbar button

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 23 — Hotkey registration + activator wiring + retention sweep

**Files:** the hotkey registration site (mirror `HotkeyRegistry.declaredHotkeys`, `HotkeyRegistry.swift:139`, surfacing `finderHistory.switcher`) and `FinderHistoryFeatureActivator`. Verified via a unit test asserting the declared hotkey is surfaced + activator start/stop.

- [ ] Write failing test `MacAllYouNeedTests/Features/FinderHistory/FinderHistoryWiringTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import MacAllYouNeed

final class FinderHistoryWiringTests: XCTestCase {
    func testSwitcherHotkeyDeclared() {
        let declared = HotkeyRegistry.declaredHotkeys(from: FeatureRegistryProvider.makeRegistry())
        XCTAssertTrue(declared.contains { $0.identifier == "finderHistory.switcher" })
    }
}
```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/FinderHistoryWiringTests` → fails (hotkey not surfaced if `declaredHotkeys` excludes disabled/new features) OR passes if `declaredHotkeys` already enumerates all descriptor hotkeys. If it passes immediately, that confirms surfacing; keep the test as a regression guard and proceed.
- [ ] Minimal impl: ensure the switcher hotkey, when pressed, presents `FolderHistorySwitcherPanel`. In `FinderHistoryFeatureActivator.activate/deactivate`, start/stop `FolderHistoryRecorder` (via S1 coordinator) and run `store.enforceRetention(policy)` on activate and on a low-frequency cadence. Honor pause + Accessibility trust (reuse `WindowControlAccessibilityTrustMonitor` shape).
- [ ] Run-pass: same `-only-testing` → green; `xcodebuild build ...` succeeds.
- [ ] Manual verification: bind the switcher hotkey in Settings (`HotkeyRecorder`), press it, panel appears; disable the feature → recorder stops + observer detaches.
- [ ] Commit: `git add MacAllYouNeed/App/Descriptors/FinderHistoryDescriptor.swift MacAllYouNeedTests/Features/FinderHistory/FinderHistoryWiringTests.swift MacAllYouNeed/App && git commit -m "Wire Finder history switcher hotkey, activator, and retention sweep

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 24 — Full suite green + lint

**Files:** none new; verification gate.

- [ ] Run Shared suite: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` → all green.
- [ ] Run app suite: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → all green.
- [ ] Run lint/build gate: `./scripts/ci-build.sh` → `swiftlint --strict` passes (no raw colors/segmented pickers/animation durations in new UI).
- [ ] Commit (only if fixes were needed): `git add -A && git commit -m "Finder folder history: full suite green and lint clean

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

## Self-Review

Spec coverage check against `02-finder-folder-history.md`:

- **FolderHistoryRecorder** — AX capture pipeline (Task 11), S1 wiring + Finder-activation re-attach + pause/trust gate (Task 13), injectable AX seam (Task 10), opt-in lazy Apple Events fallback (Task 12). Debounce/dedup (Task 3), skip rules + exclusions (Task 2), path normalization/canonicalization incl. `/private/var` (Task 1). ✅ (§4.1, §9, open-Q1)
- **FolderHistoryStore** — GRDB store in App Group, `DownloadStore`-shaped (Task 5); schema + `001-folder-history` migration + index + idempotency (Task 5); upsert-by-path with visitCount/lastVisited/firstVisited (Task 5); pin/remove/clear/exists refresh (Task 6); encrypted `displayName` envelope, plaintext queryable `path` (Tasks 4–5); retention pure (Task 7) + wired (Task 8), pinned-exempt. ✅ (§5, §10, §11)
- **3 interactive surfaces** — hotkey quick-switcher: pure filter (Task 15) + borderless NSPanel UI with open/reveal/pin/remove/stale/Reduce-Motion (Task 16), open/reveal router (Task 14); menu-bar/Command Center dropdown via `menuBarItemFactory` (Task 17); FinderSync `.appex` via project.yml + xcodegen (Task 21) + "Recent Folders" toolbar button reading shared store read-only (Task 22). ✅ (§4.4, §4.5, §8.1–8.3)
- **Config/guidance-only main page** — `FunctionPageShell`, retention, exclusion editor, Apple-Events toggle, permission status, pause, clear-history, how-to; never lists folders (Task 18). ✅ (§8.4)
- **Disabled-by-default + onboarding consent** — gated descriptor not auto-enabled; explicit consent step (Task 19); Accessibility status + optional off Apple-Events. ✅ (§8.5, §1)
- **Gated FeatureDescriptor** — `FeatureID.finderHistory` + sidebar destination (Task 9); descriptor + registration + routing + activator + extension policy `respectsFeatureFlag` (Task 20); switcher hotkey declared/surfaced + activator start/stop + retention sweep (Task 23). ✅ (§4.6, §6)
- **Permissions** — Accessibility reused (no new prompt); Automation opt-in/lazy with `NSAppleEventsUsageDescription` (Task 12); FinderSync sandbox + App Group entitlements (Task 21). ✅ (§7)
- **Testing strategy** — pure logic (normalize, skip, dedup, retention, switcher filter, action routing) all unit-tested; AX capture + Apple Events + FinderSync behind injectable seams with explicit manual-verification notes; store CRUD + migration idempotency + read-only coexistence tested. ✅ (§10)
- **Design system** — every UI task pins MAYNTheme/MAYNMotion, FunctionSegmentedTabStrip (where segmented), ShortcutChip/MAYNHotkeyDisplay, HotkeyRecorder-in-settings-only, FunctionPageShell, borderless NSPanel, Reduce-Motion. ✅ (§8, design.md, CLAUDE.md)

Every TDD task is bite-sized with a failing XCTest (real code), exact run-fail command + expected message, minimal real Swift impl, run-pass, and a real `git commit` ending in the required Co-Authored-By trailer. Type names (`FolderHistoryStore`, `FolderHistoryRow`, `FolderHistoryEnvelope`, `FolderHistoryRecorder`, `FolderHistoryAXReading`/`FocusedFolder`, `FolderHistorySkipRules`, `FolderHistoryDedup`, `FolderHistoryRetention`, `FolderPathNormalizer`, `FolderHistoryActions`, `FolderHistorySwitcherFilter`, `FinderHistoryDescriptor`, `FinderHistoryFinderSync`) are consistent across tasks.
