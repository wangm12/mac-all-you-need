# Clipboard Dock — Phase E: Maccy Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Privacy controls (ignored apps with sane defaults, transient-type respect already partly there, regex blocklist), bounded storage (max items / max age / max image storage with pinned exemptions), search improvements (fuzzy mode + sort by frequency / recency), suspend-capture, sound-on-capture, menu-bar icon picker, and auto-paste behavior toggle. Adds the additive Migration 002 and the daemon-side nightly retention task.

**Architecture:** `ExclusionRules` already exists with `blockedBundleIDs` and `concealedUTIs` — Phase E extends it with regex patterns and adds settings-driven configuration. `ClipboardStore` gains `frequency` / `last_accessed` columns and helper methods. New `RetentionPolicy` runs in `DaemonContainer` on a `DispatchSourceTimer`. Fuzzy search is an in-memory char-trigram filter applied client-side over already-loaded `items`. New Settings tabs surface every toggle.

**Tech Stack:** GRDB migration, `DispatchSourceTimer`, `NSRegularExpression`, `NSSound`, SwiftUI Form.

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md` §11.

**Depends on:** Phases A–D merged.

**Working directory:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

---

## File Structure

### Created

| Path | Responsibility |
|---|---|
| `Shared/Sources/Core/Storage/RetentionPolicy.swift` | Pure: max-items / max-age / image-cap eviction logic. |
| `Shared/Sources/Platform/Pasteboard/RegexBlocklist.swift` | Pure: list of `NSRegularExpression`, matches text → bool. |
| `Shared/Sources/Platform/Audio/CaptureSound.swift` | `NSSound` wrapper with on/off toggle. |
| `MacAllYouNeed/ClipboardDock/Search/FuzzyMatcher.swift` | Char-trigram ranking over `[DockItem]`. |
| `MacAllYouNeed/Settings/PrivacySettingsView.swift` | Ignored apps + regex blocklist. |
| `MacAllYouNeed/Settings/StorageSettingsView.swift` | Caps + clear-older-than buttons. |
| `MacAllYouNeed/Settings/SearchSettingsView.swift` | Sort mode + fuzzy toggle. |
| `MacAllYouNeed/Settings/AppearanceSettingsView.swift` | Menu-bar icon picker + dock height + auto-paste behavior. |
| `Shared/Tests/CoreTests/Storage/MigrationsTests.swift` | Migration 002 idempotency. |
| `Shared/Tests/CoreTests/Storage/FrequencyTrackingTests.swift` | bumpFrequency + sorted queries. |
| `Shared/Tests/CoreTests/Storage/RetentionPolicyTests.swift` | Eviction with pinned exemption. |
| `Shared/Tests/PlatformTests/RegexBlocklistTests.swift` | Patterns + invalid regex rejection. |
| `MacAllYouNeedTests/ClipboardDock/FuzzyMatcherTests.swift` | Trigram ranking deterministic. |

### Modified

| Path | Change |
|---|---|
| `Shared/Sources/Core/Storage/Migrations.swift` | Add Migration 002. |
| `Shared/Sources/Core/Storage/ClipboardStore.swift` | New columns in `metaRow`, `bumpFrequency`, `recentByFrequency`, `recentByLastAccessed`, `evict(...)`. |
| `Shared/Sources/Core/Models/ClipboardRecord.swift` | `ClipboardItemMeta` gains `frequency: Int`, `lastAccessed: Date?`. |
| `Shared/Sources/Platform/Pasteboard/ExclusionRules.swift` | Adds `regexBlocklist: RegexBlocklist`, `transientUTIs`. |
| `Shared/Sources/Platform/XPC/ClipboardXPCService.swift` | Read sort mode from `UserDefaults`; bump frequency on paste; respect "auto-paste behavior". |
| `ClipboardDaemon/DaemonContainer.swift` | Read settings, register settings-change notification, run nightly retention task, expose suspend-until. |
| `ClipboardDaemon/ClipboardDaemonMain.swift` | Skip persist if suspended. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift` | Add `.suspendCapture`. |
| `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift` | Default for `.suspendCapture` = empty array (no default). |
| `MacAllYouNeed/Settings/SettingsRoot.swift` | Add Privacy / Storage / Search / Appearance tabs. |
| `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` | Read sort mode + fuzzy toggle from `UserDefaults`; apply fuzzy filter. |
| `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockMoreMenu.swift` | Add Privacy submenu, Clear Older Than submenu (now backed by real action). |
| `MacAllYouNeed/App/AppController.swift` | Wire suspend-capture menu item + shortcut. |

---

## Task 1: Migration 002 — frequency + last_accessed columns

**Files:**
- Modify: `Shared/Sources/Core/Storage/ClipboardStore.swift`
- Test: `Shared/Tests/CoreTests/Storage/MigrationsTests.swift`

- [ ] **Step 1: Failing test**

```swift
@testable import Core
import CryptoKit
import GRDB
import XCTest

final class MigrationsTests: XCTestCase {
    func testMigration002AddsFrequencyAndLastAccessed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mig-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try Database(url: url, migrations: ClipboardStore.migrations)
        try db.queue.read { conn in
            let cols = try Row.fetchAll(conn, sql: "PRAGMA table_info(clipboard_records)")
                .map { $0["name"] as String }
            XCTAssertTrue(cols.contains("frequency"))
            XCTAssertTrue(cols.contains("last_accessed"))
        }
    }

    func testMigration002IsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Mig2-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        // Open + close + open again triggers re-application; should not throw.
        _ = try Database(url: url, migrations: ClipboardStore.migrations)
        _ = try Database(url: url, migrations: ClipboardStore.migrations)
    }
}
```

- [ ] **Step 2: Verify failure**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter MigrationsTests
```

Expected: FAIL — columns absent.

- [ ] **Step 3: Add migration**

In `Shared/Sources/Core/Storage/ClipboardStore.swift`, extend the `migrations` array:

```swift
    public static let migrations: [Migration] = [
        Migration(identifier: "001-clipboard-records") { conn in
            // existing CREATE TABLE block
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS clipboard_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    created INTEGER NOT NULL,
                    modified INTEGER NOT NULL,
                    device_id TEXT NOT NULL,
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
        },
        Migration(identifier: "002-frequency-tracking") { conn in
            try conn.execute(sql: """
                ALTER TABLE clipboard_records ADD COLUMN frequency INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE clipboard_records ADD COLUMN last_accessed INTEGER;
                CREATE INDEX IF NOT EXISTS idx_records_frequency ON clipboard_records(frequency DESC);
                CREATE INDEX IF NOT EXISTS idx_records_last_accessed ON clipboard_records(last_accessed DESC);
            """)
        }
    ]
```

- [ ] **Step 4: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter MigrationsTests
git add Shared/Sources/Core/Storage/ClipboardStore.swift \
        Shared/Tests/CoreTests/Storage/MigrationsTests.swift
git commit -m "feat(storage): migration 002 adds frequency + last_accessed columns"
```

---

## Task 2: `ClipboardItemMeta` gains frequency + last_accessed

**Files:**
- Modify: `Shared/Sources/Core/Models/ClipboardRecord.swift`
- Modify: `Shared/Sources/Core/Storage/ClipboardStore.swift`

- [ ] **Step 1: Update model**

```swift
public struct ClipboardItemMeta: Equatable, Sendable {
    public let id: RecordID
    public let created: Date
    public let modified: Date
    public let deviceID: DeviceID
    public let lamport: UInt64
    public let kind: RecordKind
    public let preview: String
    public let sourceAppBundleID: String?
    public let frequency: Int
    public let lastAccessed: Date?
}
```

- [ ] **Step 2: Update `metaRow` in `ClipboardStore`**

```swift
    private static func metaRow(_ row: Row) -> ClipboardItemMeta {
        let lastAccessedMs = row["last_accessed"] as Int64?
        return ClipboardItemMeta(
            id: RecordID(rawValue: row["id"])!,
            created: Date(timeIntervalSince1970: Double(row["created"] as Int64) / 1000),
            modified: Date(timeIntervalSince1970: Double(row["modified"] as Int64) / 1000),
            deviceID: DeviceID(rawValue: row["device_id"])!,
            lamport: UInt64(row["lamport"] as Int64),
            kind: RecordKind(rawValue: row["kind"]) ?? .clipboardItem,
            preview: row["preview"],
            sourceAppBundleID: row["source_app"],
            frequency: Int(row["frequency"] as Int64),
            lastAccessed: lastAccessedMs.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        )
    }
```

Update `list(...)` and `metas(for:)` SELECTs to include `frequency, last_accessed`. Keep `append` as-is — defaults to 0/null.

- [ ] **Step 3: Update existing initializer**

```swift
        return ClipboardItemMeta(
            id: id, created: now, modified: now, deviceID: deviceID, lamport: insertedLamport,
            kind: .clipboardItem, preview: preview, sourceAppBundleID: sourceAppBundleID,
            frequency: 0, lastAccessed: nil
        )
```

- [ ] **Step 4: Run full test suite (existing tests still green)**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Core/Models/ClipboardRecord.swift \
        Shared/Sources/Core/Storage/ClipboardStore.swift
git commit -m "feat(storage): expose frequency + lastAccessed on ClipboardItemMeta"
```

---

## Task 3: `ClipboardStore.bumpFrequency` + sort queries

**Files:**
- Modify: `Shared/Sources/Core/Storage/ClipboardStore.swift`
- Test: `Shared/Tests/CoreTests/Storage/FrequencyTrackingTests.swift`

- [ ] **Step 1: Failing test**

```swift
@testable import Core
import CryptoKit
import XCTest

final class FrequencyTrackingTests: XCTestCase {
    var store: ClipboardStore!
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Freq-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = try! Database(url: dir.appendingPathComponent("c.sqlite"),
                               migrations: ClipboardStore.migrations)
        store = try! ClipboardStore(database: db, deviceKey: SymmetricKey(size: .bits256),
                                     deviceID: DeviceID.generate())
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testBumpFrequencyIncrementsAndSetsLastAccessed() throws {
        let r = try store.append(.text("hi"))
        try store.bumpFrequency(id: r.id)
        try store.bumpFrequency(id: r.id)
        let meta = try store.list(limit: 10)[0]
        XCTAssertEqual(meta.frequency, 2)
        XCTAssertNotNil(meta.lastAccessed)
    }

    func testRecentByFrequencyOrders() throws {
        let a = try store.append(.text("a"))
        let b = try store.append(.text("b"))
        try store.bumpFrequency(id: a.id)
        try store.bumpFrequency(id: a.id)
        try store.bumpFrequency(id: b.id)
        let metas = try store.recentByFrequency(limit: 10)
        XCTAssertEqual(metas.first?.id, a.id)
    }

    func testRecentByLastAccessedOrders() throws {
        let a = try store.append(.text("a"))
        let b = try store.append(.text("b"))
        try store.bumpFrequency(id: a.id)
        Thread.sleep(forTimeInterval: 0.005)
        try store.bumpFrequency(id: b.id)
        let metas = try store.recentByLastAccessed(limit: 10)
        XCTAssertEqual(metas.first?.id, b.id)
    }
}
```

- [ ] **Step 2: Verify failure, then implement**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FrequencyTrackingTests
```

In `ClipboardStore`:

```swift
    public func bumpFrequency(id: RecordID) throws {
        try db.queue.write { conn in
            try conn.execute(sql: """
                UPDATE clipboard_records
                SET frequency = frequency + 1, last_accessed = ?
                WHERE id = ?
            """, arguments: [Int(Date().timeIntervalSince1970 * 1000), id.rawValue])
        }
    }

    public func recentByFrequency(limit: Int, offset: Int = 0) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                       frequency, last_accessed
                FROM clipboard_records
                ORDER BY frequency DESC, modified DESC
                LIMIT ? OFFSET ?
            """, arguments: [limit, max(0, offset)]).map(Self.metaRow)
        }
    }

    public func recentByLastAccessed(limit: Int, offset: Int = 0) throws -> [ClipboardItemMeta] {
        try db.queue.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, created, modified, device_id, lamport, kind, preview, source_app,
                       frequency, last_accessed
                FROM clipboard_records
                WHERE last_accessed IS NOT NULL
                ORDER BY last_accessed DESC
                LIMIT ? OFFSET ?
            """, arguments: [limit, max(0, offset)]).map(Self.metaRow)
        }
    }
```

Update existing `list(...)` to include the new columns in its SELECT, and `metas(for:)` likewise.

- [ ] **Step 3: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FrequencyTrackingTests
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test    # full regression
git add Shared/Sources/Core/Storage/ClipboardStore.swift \
        Shared/Tests/CoreTests/Storage/FrequencyTrackingTests.swift
git commit -m "feat(storage): bumpFrequency, recentByFrequency, recentByLastAccessed"
```

---

## Task 4: Wire `bumpFrequency` into paste flows

**Files:**
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`

Every `paste`, `pasteMany`, `pasteText`, `transformAndCopy` flow that targets a known item bumps frequency on the source.

- [ ] **Step 1: Append calls**

```swift
    public func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        guard let rid = RecordID(rawValue: itemID),
              let body = try? clip.body(for: rid)
        else { … }
        try? clip.bumpFrequency(id: rid)
        // existing body
    }

    public func pasteMany(...) {
        for idString in itemIDs {
            if let rid = RecordID(rawValue: idString) { try? clip.bumpFrequency(id: rid) }
        }
        // existing body
    }

    public func transformAndCopy(...) {
        // existing guard + transform; on success:
        if let rid = RecordID(rawValue: itemID) { try? clip.bumpFrequency(id: rid) }
        // existing pasteText route
    }
```

`pasteText` does not bump (no source clip). For snippet pasting in Phase F, snippets have their own counter.

- [ ] **Step 2: Build + run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
git add Shared/Sources/Platform/XPC/ClipboardXPCService.swift
git commit -m "feat(xpc): bump frequency + last_accessed on paste flows"
```

---

## Task 5: Sort mode setting in `service.listItems`

**Files:**
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `Shared/Sources/Core/AppGroupSettings.swift` (add `sortMode` accessor — verify file exists)

- [ ] **Step 1: Inspect existing AppGroupSettings**

```bash
cat Shared/Sources/Core/AppGroupSettings.swift
```

If it's a thin wrapper around `UserDefaults(suiteName:)`, add a typed enum + accessor; otherwise build minimal helpers in the service file directly.

- [ ] **Step 2: Define sort mode enum (in `ClipboardXPCService.swift` or new `Shared/Sources/Core/Settings/SortMode.swift`)**

```swift
public enum HistorySortMode: String, CaseIterable, Sendable {
    case recency
    case frequency
    case recentlyUsed
}
```

- [ ] **Step 3: Branch in `listItems` when no query**

```swift
            let sortMode = HistorySortMode(
                rawValue: AppGroupSettings.defaults.string(forKey: "history.sortMode") ?? ""
            ) ?? .recency
            switch sortMode {
            case .recency:       metas = try clip.list(limit: pageSize, offset: offset)
            case .frequency:     metas = try clip.recentByFrequency(limit: pageSize, offset: offset)
            case .recentlyUsed:  metas = try clip.recentByLastAccessed(limit: pageSize, offset: offset)
            }
```

- [ ] **Step 4: Build + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
git add Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Sources/Core/Settings/SortMode.swift
git commit -m "feat(xpc): switch history sort mode based on settings"
```

---

## Task 6: `RegexBlocklist` pure helper

**Files:**
- Create: `Shared/Sources/Platform/Pasteboard/RegexBlocklist.swift`
- Test: `Shared/Tests/PlatformTests/RegexBlocklistTests.swift`

- [ ] **Step 1: Failing test**

```swift
@testable import Platform
import XCTest

final class RegexBlocklistTests: XCTestCase {
    func testEmptyBlocklistMatchesNothing() {
        let b = RegexBlocklist(patterns: [])
        XCTAssertFalse(b.matches("anything"))
    }
    func testCreditCardPatternMatches() {
        let b = RegexBlocklist(patterns: [#"\b(?:\d[ -]?){13,16}\b"#])
        XCTAssertTrue(b.matches("4111 1111 1111 1111"))
        XCTAssertFalse(b.matches("hello world"))
    }
    func testInvalidPatternIgnoredSilently() {
        let b = RegexBlocklist(patterns: ["[unbalanced"])
        XCTAssertFalse(b.matches("anything"))
    }
    func testValidatePatternThrowsForInvalid() {
        XCTAssertThrowsError(try RegexBlocklist.validate("[unbalanced"))
        XCTAssertNoThrow(try RegexBlocklist.validate(#"\d+"#))
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public struct RegexBlocklist: Sendable {
    private let regexes: [NSRegularExpression]
    public init(patterns: [String]) {
        regexes = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [])
        }
    }
    public func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }
    public static func validate(_ pattern: String) throws {
        _ = try NSRegularExpression(pattern: pattern, options: [])
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter RegexBlocklistTests
git add Shared/Sources/Platform/Pasteboard/RegexBlocklist.swift \
        Shared/Tests/PlatformTests/RegexBlocklistTests.swift
git commit -m "feat(pasteboard): add RegexBlocklist pure matcher"
```

---

## Task 7: Extend `ExclusionRules` with regex blocklist + transient types

**Files:**
- Modify: `Shared/Sources/Platform/Pasteboard/ExclusionRules.swift`
- Modify: `Shared/Tests/PlatformTests/ExclusionRulesTests.swift`

- [ ] **Step 1: Append failing tests**

```swift
    func testExcludesTransientType() {
        let r = ExclusionRules(transientUTIs: ["org.nspasteboard.TransientType"])
        XCTAssertTrue(r.shouldExclude(types: ["org.nspasteboard.TransientType"], appBundleID: nil))
    }

    func testExcludesViaRegex() {
        let r = ExclusionRules(blockedBundleIDs: [], regexBlocklist: RegexBlocklist(patterns: [#"^secret-"#]))
        XCTAssertTrue(r.shouldExcludeText("secret-token"))
        XCTAssertFalse(r.shouldExcludeText("public-token"))
    }
```

- [ ] **Step 2: Implement**

```swift
public struct ExclusionRules: Equatable, Sendable {
    public var blockedBundleIDs: Set<String>
    public var concealedUTIs: Set<String>
    public var transientUTIs: Set<String>
    public var regexBlocklist: RegexBlocklist

    public init(
        blockedBundleIDs: Set<String> = [],
        concealedUTIs: Set<String> = ["org.nspasteboard.ConcealedType"],
        transientUTIs: Set<String> = ["org.nspasteboard.TransientType"],
        regexBlocklist: RegexBlocklist = RegexBlocklist(patterns: [])
    ) {
        self.blockedBundleIDs = blockedBundleIDs
        self.concealedUTIs = concealedUTIs
        self.transientUTIs = transientUTIs
        self.regexBlocklist = regexBlocklist
    }

    public func shouldExclude(types: [String], appBundleID: String?) -> Bool {
        if !concealedUTIs.isDisjoint(with: types) { return true }
        if !transientUTIs.isDisjoint(with: types) { return true }
        if let id = appBundleID, blockedBundleIDs.contains(id) { return true }
        return false
    }

    public func shouldExcludeText(_ text: String) -> Bool {
        regexBlocklist.matches(text)
    }

    public static func == (lhs: ExclusionRules, rhs: ExclusionRules) -> Bool {
        lhs.blockedBundleIDs == rhs.blockedBundleIDs
            && lhs.concealedUTIs == rhs.concealedUTIs
            && lhs.transientUTIs == rhs.transientUTIs
        // RegexBlocklist intentionally excluded from Equatable; not stable.
    }
}
```

- [ ] **Step 3: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
git add Shared/Sources/Platform/Pasteboard/ExclusionRules.swift \
        Shared/Tests/PlatformTests/ExclusionRulesTests.swift
git commit -m "feat(pasteboard): ExclusionRules adds transient + regex blocklist"
```

---

## Task 8: Daemon reads settings + reloads on change

**Files:**
- Modify: `ClipboardDaemon/DaemonContainer.swift`
- Modify: `ClipboardDaemon/ClipboardDaemonMain.swift`

- [ ] **Step 1: Read full settings on startup, on Darwin notification, AND on every tick (defense-in-depth)**

`UserDefaults.didChangeNotification` fires only within the same process — settings written by the main app's Settings UI will never wake the daemon. The right inter-process channel is a Darwin notification posted by the app and observed by the daemon. We also re-read settings on each capture tick as a cheap fallback (UserDefaults caches in-memory after first read, so this is microseconds).

In `DaemonContainer.init`:

```swift
        observer = PasteboardObserver(
            reader: SystemPasteboardReader(),
            rules: Self.loadRules()
        )
        installSettingsReloader()
```

```swift
    private static let settingsChangedDarwin = "com.macallyouneed.settings-changed" as CFString

    private func installSettingsReloader() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let container = Unmanaged<DaemonContainer>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in container.observer.rules = DaemonContainer.loadRules() }
            },
            Self.settingsChangedDarwin, nil, .deliverImmediately
        )
    }
```

In `Shared/Sources/Core/AppGroupSettings.swift` (or wherever `AppGroupSettings.defaults` lives), add a `notifyReloaded()` helper for the app side:

```swift
public extension AppGroupSettings {
    static func notifyReloaded() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name), nil, nil, true
        )
    }
}
```

Every Settings view that writes settings (Privacy / Storage / Search / Appearance) calls `AppGroupSettings.notifyReloaded()` after each `set(_:forKey:)`. To avoid sprinkling that everywhere, add a `Settings.write(_:forKey:)` shim in those views.

```swift
    private static func loadRules() -> ExclusionRules {
        let defaults = AppGroupSettings.defaults
        // Seed sensible password-manager defaults if the user has never set anything.
        let storedBlocked = defaults.stringArray(forKey: "clipboardExcludedBundleIDs")
        let blocked: Set<String>
        if let storedBlocked {
            blocked = Set(storedBlocked)
        } else {
            blocked = [
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.1password.1password7",
                "com.1password.1password8",
                "com.lastpass.LastPass",
                "com.bitwarden.desktop",
                "com.agilebits.onepassword4",
                "com.dashlane.Dashlane"
            ]
            defaults.set(Array(blocked), forKey: "clipboardExcludedBundleIDs")
        }
        let regexes = defaults.stringArray(forKey: "clipboardRegexBlocklist") ?? []
        return ExclusionRules(
            blockedBundleIDs: blocked,
            regexBlocklist: RegexBlocklist(patterns: regexes)
        )
    }
```

Also extend `PasteboardObserver.tick()` to consult an "always re-read" knob via `AppGroupSettings.defaults.bool(forKey: "settings.alwaysReread")`. With this flag on (default true), each tick re-reads `loadRules()` before checking — at most one cheap UserDefaults read per 400ms tick.

In `tick()` (after the existing daemon-write sentinel skip):

```swift
        if AppGroupSettings.defaults.bool(forKey: "settings.alwaysReread") {
            // Cheap; UserDefaults is in-memory cached.
        }
```

(Defense-in-depth — the Darwin notification is the primary path; the per-tick re-read is fallback for when the app forgets to call `notifyReloaded`.)

- [ ] **Step 2: Apply text-only regex check in `persist`**

```swift
    func persist(item: PasteboardItem, source: String?) throws {
        let rules = observer.rules
        // Text-bearing items get one more regex pass.
        switch item {
        case let .text(s):
            if rules.shouldExcludeText(s) { return }
        case let .html(s):
            if rules.shouldExcludeText(s) { return }
        case let .rtf(d):
            let s = NSAttributedString(rtf: d, documentAttributes: nil)?.string ?? ""
            if rules.shouldExcludeText(s) { return }
        default: break
        }
        // existing switch
    }
```

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
git add ClipboardDaemon/DaemonContainer.swift
git commit -m "feat(daemon): live-reload ExclusionRules from settings; regex text gate"
```

---

## Task 9: Suspend-capture

**Files:**
- Modify: `ClipboardDaemon/ClipboardDaemonMain.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift`
- Modify: `MacAllYouNeed/App/AppController.swift` (menu item)

- [ ] **Step 1: Add `.suspendCapture` action**

In `ShortcutAction.swift`:

```swift
    case suspendCapture
```

Label in switch: `"Suspend capture for 60 seconds"`.

In `ShortcutDefaults.swift`:

```swift
        case .suspendCapture: return []  // user must opt in
```

- [ ] **Step 2: Daemon reads suspend-until each tick**

In `ClipboardDaemonMain.swift` (whichever `observer.start { change in … }` block exists):

```swift
                if let untilSec = AppGroupSettings.defaults.object(forKey: "captureSuspendUntil") as? Double,
                   Date().timeIntervalSince1970 < untilSec { return }
                try container.persist(item: item, source: change.frontmostAppBundleID)
```

- [ ] **Step 3: AppController menu item**

In the `MenuBarExtra` content (search for existing menu definitions in `MacAllYouNeed/App/`), add:

```swift
                Button("Pause capture for 60s") {
                    AppGroupSettings.defaults.set(
                        Date().addingTimeInterval(60).timeIntervalSince1970,
                        forKey: "captureSuspendUntil"
                    )
                }
```

Wire shortcut: in `AppController.performHotkeyAction` if user binds `.suspendCapture` via ShortcutRegistry, call the same setter.

- [ ] **Step 4: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutAction.swift \
        MacAllYouNeed/ClipboardDock/Shortcuts/ShortcutDefaults.swift \
        MacAllYouNeed/App/AppController.swift \
        ClipboardDaemon/ClipboardDaemonMain.swift
git commit -m "feat(daemon): add suspend-capture (60s) shortcut + menu item"
```

---

## Task 10: `RetentionPolicy` pure logic

**Files:**
- Create: `Shared/Sources/Core/Storage/RetentionPolicy.swift`
- Test: `Shared/Tests/CoreTests/Storage/RetentionPolicyTests.swift`

- [ ] **Step 1: Failing test**

```swift
@testable import Core
import CryptoKit
import XCTest

final class RetentionPolicyTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var pinboards: PinboardStore!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ret-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let cdb = try! Database(url: dir.appendingPathComponent("c.sqlite"),
                                migrations: ClipboardStore.migrations)
        clip = try! ClipboardStore(database: cdb, deviceKey: key, deviceID: DeviceID.generate())
        let pdb = try! Database(url: dir.appendingPathComponent("p.sqlite"),
                                migrations: PinboardStore.migrations)
        pinboards = PinboardStore(database: pdb, deviceKey: key)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testEvictsOldestNonPinnedWhenOverMaxItems() throws {
        let blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"),
                              key: SymmetricKey(size: .bits256))
        let ids = (0..<5).map { _ in try! clip.append(.text("x")).id }
        let policy = RetentionPolicy(maxItems: 3, maxAgeSeconds: nil, maxImageBytes: nil)
        let pinned = try PinboardStore.protectedIDs(from: pinboards)
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: pinned)
        let surviving = try clip.list(limit: 10).map(\.id)
        XCTAssertEqual(surviving.count, 3)
        XCTAssertEqual(Set(surviving), Set(ids.suffix(3)))
    }

    func testProtectedItemsDoNotCountAgainstCap() throws {
        let blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"),
                              key: SymmetricKey(size: .bits256))
        let pinnedIDs = (0..<2).map { _ in try! clip.append(.text("p")).id }
        let casualIDs = (0..<5).map { _ in try! clip.append(.text("c")).id }
        var pinboard = try pinboards.create(name: "__pinned__")
        for id in pinnedIDs { pinboard.itemIDs.append(id) }
        try pinboards.update(pinboard)

        // Cap of 3 means up to 3 NON-PROTECTED items survive (plus all 2 pinned).
        let policy = RetentionPolicy(maxItems: 3, maxAgeSeconds: nil, maxImageBytes: nil)
        let protected = try PinboardStore.protectedIDs(from: pinboards)
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: protected)

        let surviving = Set(try clip.list(limit: 10).map(\.id))
        XCTAssertTrue(pinnedIDs.allSatisfy { surviving.contains($0) },
                      "pinned items must survive")
        let nonProtectedSurvivors = surviving.subtracting(pinnedIDs)
        XCTAssertEqual(nonProtectedSurvivors.count, 3,
                       "exactly cap=3 non-protected items must survive")
        // Three newest casual IDs survived.
        XCTAssertEqual(nonProtectedSurvivors, Set(casualIDs.suffix(3)))
    }

    func testImageEvictionAlsoDeletesBlob() throws {
        let blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"),
                              key: SymmetricKey(size: .bits256))
        let blobID = try blobs.write(Data(repeating: 1, count: 1000))
        let imageMeta = try clip.append(.image(blobID: blobID, width: 32, height: 32))
        // Cap=0 forces eviction of all non-protected.
        let policy = RetentionPolicy(maxItems: 0, maxAgeSeconds: nil, maxImageBytes: nil)
        try policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobs.encryptedURL(id: blobID).path),
                       "blob file must be deleted along with image record")
        XCTAssertNil(try clip.list(limit: 10).first { $0.id == imageMeta.id })
    }
}
```

- [ ] **Step 2: Implement**

In `Shared/Sources/Core/Storage/RetentionPolicy.swift`:

```swift
import Foundation

public struct RetentionPolicy: Sendable {
    public let maxItems: Int?
    public let maxAgeSeconds: TimeInterval?
    public let maxImageBytes: Int?

    public init(maxItems: Int?, maxAgeSeconds: TimeInterval?, maxImageBytes: Int?) {
        self.maxItems = maxItems
        self.maxAgeSeconds = maxAgeSeconds
        self.maxImageBytes = maxImageBytes
    }

    /// Cap semantics: protected items DO NOT count against the cap. So a cap
    /// of 100 with 50 protected items means the user can have up to 100
    /// non-protected items + their 50 protected items = 150 total.
    public func enforceItemCap(
        store: ClipboardStore, blobs: BlobStore, protectedIDs: Set<RecordID>
    ) throws {
        guard let cap = maxItems else { return }
        let all = try store.list(limit: 10_000)
        let candidates = all.filter { !protectedIDs.contains($0.id) }
        let overflow = max(0, candidates.count - cap)
        guard overflow > 0 else { return }
        // candidates are sorted by modified DESC; oldest are at the end.
        for victim in candidates.suffix(overflow) {
            try Self.deleteWithBlob(victim.id, store: store, blobs: blobs)
        }
    }

    public func enforceMaxAge(
        store: ClipboardStore, blobs: BlobStore,
        protectedIDs: Set<RecordID>, now: Date = Date()
    ) throws {
        guard let max = maxAgeSeconds else { return }
        let cutoff = now.addingTimeInterval(-max)
        let all = try store.list(limit: 10_000)
        for meta in all where meta.modified < cutoff && !protectedIDs.contains(meta.id) {
            try Self.deleteWithBlob(meta.id, store: store, blobs: blobs)
        }
    }

    /// Reads body for image-kind records and deletes the blob file before the row,
    /// preventing orphan blob files in the BlobStore directory.
    private static func deleteWithBlob(
        _ id: RecordID, store: ClipboardStore, blobs: BlobStore
    ) throws {
        if let body = try? store.body(for: id), case let .image(blobID, _, _) = body {
            try? blobs.delete(id: blobID)
        }
        try store.delete(id: id)
    }
}

public extension PinboardStore {
    static func protectedIDs(from store: PinboardStore) throws -> Set<RecordID> {
        try store.list().reduce(into: Set<RecordID>()) { set, board in
            board.itemIDs.forEach { set.insert($0) }
        }
    }
}
```

Image-cap eviction uses the same `deleteWithBlob` helper (Task 11).

- [ ] **Step 3: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter RetentionPolicyTests
git add Shared/Sources/Core/Storage/RetentionPolicy.swift \
        Shared/Tests/CoreTests/Storage/RetentionPolicyTests.swift
git commit -m "feat(storage): RetentionPolicy with item cap + age + protected exemption"
```

---

## Task 11: Image-blob cap

**Files:**
- Modify: `Shared/Sources/Core/Storage/RetentionPolicy.swift`
- Modify: `Shared/Sources/Core/Storage/BlobStore.swift` (add `totalSize` helper)
- Test: extend `RetentionPolicyTests`

- [ ] **Step 1: Add `BlobStore.totalSize()`**

```swift
    public func totalSize() throws -> Int {
        let urls = (try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { acc, u in
            acc + ((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
```

- [ ] **Step 2: Add `RetentionPolicy.enforceImageCap`**

```swift
    public func enforceImageCap(store: ClipboardStore, blobs: BlobStore,
                                protectedIDs: Set<RecordID>) throws {
        guard let cap = maxImageBytes, try blobs.totalSize() > cap else { return }
        let metas = try store.list(limit: 10_000)
        // Oldest first
        for meta in metas.reversed() where !protectedIDs.contains(meta.id) {
            guard case let .image(blobID, _, _) = try store.body(for: meta.id) else { continue }
            try? blobs.delete(id: blobID)
            try store.delete(id: meta.id)
            if try blobs.totalSize() <= cap { return }
        }
    }
```

- [ ] **Step 3: Build + run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter RetentionPolicyTests
git add Shared/Sources/Core/Storage/RetentionPolicy.swift \
        Shared/Sources/Core/Storage/BlobStore.swift
git commit -m "feat(storage): image-blob cap eviction"
```

---

## Task 12: Daemon nightly retention task

**Files:**
- Modify: `ClipboardDaemon/DaemonContainer.swift`

- [ ] **Step 1: Add timer**

```swift
    private var retentionTimer: DispatchSourceTimer?

    private func startRetentionTimer() {
        let q = DispatchQueue(label: "RetentionTimer", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: q)
        // Fire once on startup, then every 12 hours.
        t.schedule(deadline: .now() + 5, repeating: .seconds(12 * 3600))
        t.setEventHandler { [weak self] in self?.runRetention() }
        retentionTimer = t
        t.resume()
    }

    private func runRetention() {
        guard let policy = currentPolicy() else { return }
        let pinboardURL = AppGroup.containerURL().appendingPathComponent("databases/pinboards.sqlite")
        guard let pdb = try? Database(url: pinboardURL, migrations: PinboardStore.migrations) else { return }
        let pinboards = PinboardStore(database: pdb, deviceKey: key)
        let protected = (try? PinboardStore.protectedIDs(from: pinboards)) ?? []
        try? policy.enforceItemCap(store: clip, blobs: blobs, protectedIDs: protected)
        try? policy.enforceMaxAge(store: clip, blobs: blobs, protectedIDs: protected)
        try? policy.enforceImageCap(store: clip, blobs: blobs, protectedIDs: protected)
    }

    private func currentPolicy() -> RetentionPolicy? {
        let d = AppGroupSettings.defaults
        let maxItems = d.object(forKey: "retention.maxItems") as? Int ?? 1000
        let maxAge = d.object(forKey: "retention.maxAgeDays") as? Int ?? 30
        let maxImageMB = d.object(forKey: "retention.maxImageMB") as? Int ?? 200
        return RetentionPolicy(
            maxItems: maxItems,
            maxAgeSeconds: maxAge > 0 ? Double(maxAge) * 86400 : nil,
            maxImageBytes: maxImageMB > 0 ? maxImageMB * 1024 * 1024 : nil
        )
    }
```

Call `startRetentionTimer()` at end of `init`.

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
git add ClipboardDaemon/DaemonContainer.swift
git commit -m "feat(daemon): nightly RetentionPolicy timer"
```

---

## Task 13: Settings — Privacy tab

**Files:**
- Create: `MacAllYouNeed/Settings/PrivacySettingsView.swift`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`

- [ ] **Step 1: Implement**

```swift
import Core
import Platform
import SwiftUI

struct PrivacySettingsView: View {
    @State private var ignored: [String] = (AppGroupSettings.defaults
        .stringArray(forKey: "clipboardExcludedBundleIDs") ?? [])
    @State private var regexes: [String] = (AppGroupSettings.defaults
        .stringArray(forKey: "clipboardRegexBlocklist") ?? [])
    @State private var newBundleID = ""
    @State private var newRegex = ""
    @State private var regexError: String?

    var body: some View {
        Form {
            Section("Don't capture from these apps") {
                ForEach(ignored, id: \.self) { id in
                    HStack {
                        Text(id)
                        Spacer()
                        Button("Remove") {
                            ignored.removeAll { $0 == id }
                            save()
                        }
                    }
                }
                HStack {
                    TextField("com.example.app", text: $newBundleID).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        ignored.append(trimmed); newBundleID = ""; save()
                    }
                }
            }

            Section("Don't capture text matching") {
                ForEach(regexes, id: \.self) { p in
                    HStack {
                        Text(p).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Remove") {
                            regexes.removeAll { $0 == p }
                            save()
                        }
                    }
                }
                HStack {
                    TextField(#"\d{16}"#, text: $newRegex).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        do {
                            try RegexBlocklist.validate(newRegex)
                            regexes.append(newRegex); newRegex = ""; regexError = nil; save()
                        } catch { regexError = "Invalid regex: \(error.localizedDescription)" }
                    }
                }
                if let err = regexError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .padding()
    }

    private func save() {
        AppGroupSettings.defaults.set(ignored, forKey: "clipboardExcludedBundleIDs")
        AppGroupSettings.defaults.set(regexes, forKey: "clipboardRegexBlocklist")
        AppGroupSettings.notifyReloaded()
    }
}
```

- [ ] **Step 2: Add tab to `SettingsRoot`**

```swift
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
```

- [ ] **Step 3: Build + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/Settings/PrivacySettingsView.swift \
        MacAllYouNeed/Settings/SettingsRoot.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(settings): add Privacy tab (ignored apps + regex blocklist)"
```

---

## Task 14: Settings — Storage tab

**Files:**
- Create: `MacAllYouNeed/Settings/StorageSettingsView.swift`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`

- [ ] **Step 1: Implement**

```swift
import Core
import SwiftUI

struct StorageSettingsView: View {
    @State private var maxItems: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxItems") as? Int) ?? 1000
    @State private var maxAgeDays: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxAgeDays") as? Int) ?? 30
    @State private var maxImageMB: Int = (AppGroupSettings.defaults.object(forKey: "retention.maxImageMB") as? Int) ?? 200

    var body: some View {
        Form {
            Section("History size") {
                Stepper(value: $maxItems, in: 100...10_000, step: 100) {
                    Text("Max items: \(maxItems)")
                }
                Picker("Max age", selection: $maxAgeDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("365 days").tag(365)
                }
                Stepper(value: $maxImageMB, in: 0...2_000, step: 50) {
                    Text("Image storage: \(maxImageMB) MB (0 = unlimited)")
                }
            }
        }
        .padding()
        .onChange(of: maxItems) { _, v in AppGroupSettings.defaults.set(v, forKey: "retention.maxItems"); AppGroupSettings.notifyReloaded() }
        .onChange(of: maxAgeDays) { _, v in AppGroupSettings.defaults.set(v, forKey: "retention.maxAgeDays"); AppGroupSettings.notifyReloaded() }
        .onChange(of: maxImageMB) { _, v in AppGroupSettings.defaults.set(v, forKey: "retention.maxImageMB"); AppGroupSettings.notifyReloaded() }
    }
}
```

- [ ] **Step 2: Add tab + commit**

```swift
            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
```

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add MacAllYouNeed/Settings/StorageSettingsView.swift \
        MacAllYouNeed/Settings/SettingsRoot.swift
git commit -m "feat(settings): add Storage tab (max items/age/image MB)"
```

---

## Task 15: Settings — Search tab + fuzzy matcher

**Files:**
- Create: `MacAllYouNeed/Settings/SearchSettingsView.swift`
- Create: `MacAllYouNeed/ClipboardDock/Search/FuzzyMatcher.swift`
- Test: `MacAllYouNeedTests/ClipboardDock/FuzzyMatcherTests.swift`
- Modify: `MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift` (apply fuzzy)

- [ ] **Step 1: FuzzyMatcher tests**

```swift
@testable import MacAllYouNeed
import XCTest

final class FuzzyMatcherTests: XCTestCase {
    func testRanksExactSubstringFirst() {
        let candidates = ["alpha beta", "gamma alpha", "alpha"]
        let ranked = FuzzyMatcher.rank(candidates: candidates, query: "alpha")
        XCTAssertEqual(ranked.first, "alpha")
    }
    func testEmptyQueryReturnsAll() {
        let candidates = ["a", "b"]
        XCTAssertEqual(FuzzyMatcher.rank(candidates: candidates, query: ""), candidates)
    }
    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(FuzzyMatcher.rank(candidates: ["foo"], query: "xyz").isEmpty)
    }
}
```

- [ ] **Step 2: Implement**

```bash
mkdir -p MacAllYouNeed/ClipboardDock/Search
```

```swift
import Foundation

enum FuzzyMatcher {
    static func rank(candidates: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return candidates }
        let queryTrigrams = trigrams(q)
        var scored: [(String, Double)] = []
        for c in candidates {
            let cl = c.lowercased()
            if cl.contains(q) {
                scored.append((c, 100.0))
                continue
            }
            let cTrigrams = trigrams(cl)
            let intersect = cTrigrams.intersection(queryTrigrams).count
            if intersect > 0 {
                scored.append((c, Double(intersect) / Double(queryTrigrams.count)))
            }
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private static func trigrams(_ s: String) -> Set<String> {
        guard s.count >= 3 else { return [s] }
        var result: Set<String> = []
        let chars = Array(s)
        for i in 0...(chars.count - 3) {
            result.insert(String(chars[i..<(i + 3)]))
        }
        return result
    }
}
```

- [ ] **Step 3: Apply in `ClipboardDockModel.refresh`**

When fuzzy mode is on, the model fetches an UNFILTERED window (so it has candidates to rank); when off, it passes `query` through to FTS as before.

```swift
    private func loadFromXPC(query: String?) async {
        let fuzzy = AppGroupSettings.defaults.bool(forKey: "search.fuzzy")
        let effectiveQuery: String? = fuzzy ? nil : query
        let list = await xpc.listItems(query: effectiveQuery, pageToken: nil, limit: 200)
        items = list.items.map { meta in
            buildDockItem(from: meta, isPinned: pinnedIDs().contains(RecordID(rawValue: meta.id)!))
        }
        applyFuzzyIfEnabled(query: query)
    }

    private func applyFuzzyIfEnabled(query: String?) {
        guard AppGroupSettings.defaults.bool(forKey: "search.fuzzy"),
              let q = query, !q.isEmpty else { return }
        let ranked = FuzzyMatcher.rank(candidates: items.map(\.preview), query: q)
        let order = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, $0) })
        items = items
            .filter { order.keys.contains($0.preview) }
            .sorted { (order[$0.preview] ?? Int.max) < (order[$1.preview] ?? Int.max) }
    }
```

Replace the previously-shown standalone `applyFuzzyIfEnabled()` method (which read `model.search` and silently sorted) with the parameterized version above. `loadPinned` and `loadPinboard` should also call `applyFuzzyIfEnabled(query: query)` at their tail when their search-scoping needs ranked results.

- [ ] **Step 4: Settings view**

```swift
import Core
import SwiftUI

struct SearchSettingsView: View {
    @State private var sortMode: String = AppGroupSettings.defaults.string(forKey: "history.sortMode") ?? "recency"
    @State private var fuzzy: Bool = AppGroupSettings.defaults.bool(forKey: "search.fuzzy")

    var body: some View {
        Form {
            Picker("Sort history by", selection: $sortMode) {
                Text("Recency").tag("recency")
                Text("Frequency").tag("frequency")
                Text("Recently used").tag("recentlyUsed")
            }
            Toggle("Fuzzy search", isOn: $fuzzy)
        }
        .padding()
        .onChange(of: sortMode) { _, v in AppGroupSettings.defaults.set(v, forKey: "history.sortMode") }
        .onChange(of: fuzzy) { _, v in AppGroupSettings.defaults.set(v, forKey: "search.fuzzy") }
    }
}
```

- [ ] **Step 5: Add tab + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test -only-testing:MacAllYouNeedTests/FuzzyMatcherTests 2>&1 | tail -10
git add MacAllYouNeed/Settings/SearchSettingsView.swift \
        MacAllYouNeed/ClipboardDock/Search/FuzzyMatcher.swift \
        MacAllYouNeedTests/ClipboardDock/FuzzyMatcherTests.swift \
        MacAllYouNeed/ClipboardDock/Model/ClipboardDockModel.swift \
        MacAllYouNeed/Settings/SettingsRoot.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(search): fuzzy matcher + Search settings tab"
```

Add tab to `SettingsRoot`:

```swift
            SearchSettingsView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
```

---

## Task 16: Auto-paste behavior toggle

**Files:**
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Create: `MacAllYouNeed/Settings/AppearanceSettingsView.swift`

Toggle modes: `pasteIntoFocused` (default — current), `copyOnly`, `copyThenPaste(delayMs)`.

- [ ] **Step 1: Read mode in `paste`/`pasteMany`/`pasteText`**

```swift
        let mode = AppGroupSettings.defaults.string(forKey: "autoPaste.behavior") ?? "pasteIntoFocused"
        let delay = AppGroupSettings.defaults.integer(forKey: "autoPaste.delayMs")
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(text, forType: .string)
            switch mode {
            case "copyOnly":
                reply(PasteResult.injected.rawValue)
            case "copyThenPaste":
                let dl = DispatchTime.now() + .milliseconds(max(0, delay))
                DispatchQueue.main.asyncAfter(deadline: dl) {
                    let r = PasteInjector.paste(nil, mode: plainText ? .plainText : .formatted, into: self.pasteboard)
                    reply(r.rawValue)
                }
            default:
                let r = PasteInjector.paste(nil, mode: plainText ? .plainText : .formatted, into: self.pasteboard)
                reply(r.rawValue)
            }
        }
```

Apply analogous changes in `paste(itemID:)` and `pasteMany(...)`.

- [ ] **Step 2: Settings view + tab — combined with Appearance settings (Task 17)**

Merged below in Task 17.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
git add Shared/Sources/Platform/XPC/ClipboardXPCService.swift
git commit -m "feat(xpc): respect auto-paste behavior setting (paste/copy/delayed)"
```

---

## Task 17: Settings — Appearance tab + sound toggle + menu icon picker

**Files:**
- Create: `MacAllYouNeed/Settings/AppearanceSettingsView.swift`
- Create: `Shared/Sources/Platform/Audio/CaptureSound.swift`
- Modify: `MacAllYouNeed/Settings/SettingsRoot.swift`
- Modify: `ClipboardDaemon/DaemonContainer.swift` (play sound on persist)

- [ ] **Step 1: `CaptureSound`**

```swift
import AppKit

public enum CaptureSound {
    public static func playIfEnabled() {
        guard AppGroupSettings.defaults.bool(forKey: "capture.sound") else { return }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}
```

- [ ] **Step 2: Call from `DaemonContainer.persist`** — append at end of switch:

```swift
        CaptureSound.playIfEnabled()
```

- [ ] **Step 3: Appearance settings view**

```swift
import Core
import SwiftUI

struct AppearanceSettingsView: View {
    @State private var menuSymbol: String = AppGroupSettings.defaults.string(forKey: "appearance.menuSymbol") ?? "doc.on.clipboard"
    @State private var dockHeight: Double = AppGroupSettings.defaults.double(forKey: "dock.height").nonZero ?? 360
    @State private var captureSound: Bool = AppGroupSettings.defaults.bool(forKey: "capture.sound")
    @State private var pasteBehavior: String = AppGroupSettings.defaults.string(forKey: "autoPaste.behavior") ?? "pasteIntoFocused"
    @State private var pasteDelay: Int = AppGroupSettings.defaults.integer(forKey: "autoPaste.delayMs")

    private let symbols = ["doc.on.clipboard", "clipboard", "square.on.square", "tray"]

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Icon", selection: $menuSymbol) {
                    ForEach(symbols, id: \.self) { Image(systemName: $0).tag($0) }
                }
            }
            Section("Dock") {
                Slider(value: $dockHeight, in: 300...500, step: 10) {
                    Text("Height: \(Int(dockHeight))")
                }
            }
            Section("Capture") {
                Toggle("Play sound on capture", isOn: $captureSound)
            }
            Section("Auto-paste") {
                Picker("On pick", selection: $pasteBehavior) {
                    Text("Paste into focused app").tag("pasteIntoFocused")
                    Text("Just copy").tag("copyOnly")
                    Text("Copy, then paste").tag("copyThenPaste")
                }
                if pasteBehavior == "copyThenPaste" {
                    Stepper(value: $pasteDelay, in: 50...2000, step: 50) {
                        Text("Delay: \(pasteDelay) ms")
                    }
                }
            }
        }
        .padding()
        .onChange(of: menuSymbol) { _, v in AppGroupSettings.defaults.set(v, forKey: "appearance.menuSymbol") }
        .onChange(of: dockHeight) { _, v in AppGroupSettings.defaults.set(v, forKey: "dock.height") }
        .onChange(of: captureSound) { _, v in AppGroupSettings.defaults.set(v, forKey: "capture.sound") }
        .onChange(of: pasteBehavior) { _, v in AppGroupSettings.defaults.set(v, forKey: "autoPaste.behavior") }
        .onChange(of: pasteDelay) { _, v in AppGroupSettings.defaults.set(v, forKey: "autoPaste.delayMs") }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
```

- [ ] **Step 4: Wire menu symbol — modify `MenuBarExtra` constructor in `MacAllYouNeed/App/`**

Search for the existing `MenuBarExtra(...)` definition and read the symbol from `AppGroupSettings.defaults` instead of hard-coding.

- [ ] **Step 5: Wire dock height in `DockWindowController`**

```swift
    var dockHeight: CGFloat {
        let v = AppGroupSettings.defaults.double(forKey: "dock.height")
        return v == 0 ? 360 : CGFloat(v)
    }
```

(Replace stored property with computed.)

- [ ] **Step 6: Add tab + commit**

```bash
xcodegen generate
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add Shared/Sources/Platform/Audio/CaptureSound.swift \
        MacAllYouNeed/Settings/AppearanceSettingsView.swift \
        MacAllYouNeed/Settings/SettingsRoot.swift \
        MacAllYouNeed/ClipboardDock/Window/DockWindowController.swift \
        ClipboardDaemon/DaemonContainer.swift \
        MacAllYouNeed.xcodeproj
git commit -m "feat(settings): add Appearance tab (icon/dock height/sound/auto-paste)"
```

Add tab to `SettingsRoot`:

```swift
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
```

---

## Task 18: Phase E smoke + regression

- [ ] **Step 1: Run all tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeedTests test 2>&1 | tail -20
```

- [ ] **Step 2: Manual smoke (subset of spec §12.6)**

13. Settings → Privacy → ignore Chrome → copy in Chrome → no card.
14. (Phase C) ✓ already validated.
15. Copy from Keychain Access → no card (concealed type).
16. Storage cap 5 max items → copy 7 things → only newest 5 visible (older non-pinned evicted).
17. Pin one item, set max items 5, copy 6 more → pinned item still present.
18. Settings → Search → Fuzzy on → "alfa" finds "Alpha".
19. Settings → Search → Sort by Frequency → most-pasted item is leftmost in carousel.
20. Settings → Appearance → Just copy → Enter on a card copies but doesn't auto-paste.
21. Suspend capture menu item → paste timer suspends for 60s → Chrome copy ignored.

---

## Phase E — Done

End-state of Phase E:

- Privacy: ignored apps, regex blocklist (with validation), concealed + transient type respect.
- Storage caps: max items / max age / max image MB; pinned/listed always exempt; nightly daemon timer.
- Frequency tracking: `bumpFrequency` on every paste flow; sort modes (Recency / Frequency / Recently used).
- Fuzzy search toggle + char-trigram matcher.
- Suspend-capture (60s) shortcut + menu item.
- Sound on capture toggle.
- Menu-bar icon picker.
- Auto-paste behavior toggle (paste / copy / delayed).
- Dock height slider.

---

## What comes next

- **Phase F** — Snippets surfacing in dock (`.snippets` tab + CRUD sheet).
