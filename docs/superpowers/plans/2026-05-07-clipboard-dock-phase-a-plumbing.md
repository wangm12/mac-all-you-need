# Clipboard Dock — Phase A: Plumbing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the XPC additions, daemon-side implementations, and supporting pure helpers needed by the new clipboard dock UI. Phase A ships no UI changes — the existing centered popup keeps working — but every wire-format change, every new RPC, every pure-Swift helper that later phases depend on lands here behind contract tests.

**Architecture:** Extract a pure `ClipboardXPCService` class in `Platform` module that implements the XPC protocol against injectable dependencies (`ClipboardStore`, `BlobStore`, `SearchStore`, `SnippetStore`, `NSPasteboard`). The existing `ClipboardXPCServer` in `ClipboardDaemon/` becomes a thin NSXPCListener delegate that holds a service instance and forwards each call. Tests instantiate the service directly with in-memory stores and a private `NSPasteboard(name:)`, no XPC machinery required.

**Tech Stack:** Swift 5.9, SwiftPM (`Shared/`), GRDB, CryptoKit, AppKit, Core Image (for `CIImage`-based thumbnail resize), `XCTest`.

**Spec:** `docs/superpowers/specs/2026-05-07-clipboard-dock-redesign-design.md`

**Working directory for all commands:** `/Users/mingjie.wang/Documents/personal/mac-all-you-need`

**Test command (used everywhere):**
```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```
To filter to a single test class: append `--filter ClassName`. To filter to a single method: `--filter ClassName/methodName`.

**App build verification (run after Tasks 7, 8, 10, 11):**
```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -10
```

---

## File Structure

### Created files

| Path | Responsibility |
|---|---|
| `Shared/Sources/Platform/XPC/ClipboardXPCService.swift` | Pure implementation of `ClipboardXPCProtocol` against injectable deps; no XPC connection state. |
| `Shared/Sources/Platform/Image/ThumbnailRenderer.swift` | Pure: `(imageData: Data, maxDim: Int) -> Data?` returning JPEG. |
| `Shared/Sources/Platform/Image/ThumbnailCache.swift` | NSCache wrapper keyed by `(blobID, maxDim)`. |
| `Shared/Sources/Platform/Transforms/TextTransforms.swift` | Pure: enum of transforms + `apply(_:to:) -> String?`. |
| `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift` | Async/await protocol over the XPC client surface, used by view-models for mockability. |
| `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift` | Tests for `ClipboardXPCService` against in-memory stores + private pasteboard. |
| `Shared/Tests/PlatformTests/Image/ThumbnailRendererTests.swift` | Resize + JPEG-encode tests. |
| `Shared/Tests/PlatformTests/Image/ThumbnailCacheTests.swift` | Cache hit/miss, eviction. |
| `Shared/Tests/PlatformTests/Transforms/TextTransformsTests.swift` | One test per transform. |
| `Shared/Tests/CoreTests/XPC/ClipboardXPCInteractingTests.swift` | Verifies the protocol surface compiles and a mock can satisfy it. |

### Modified files

| Path | Change |
|---|---|
| `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift` | Add 4 fields to `ClipboardXPCMeta`; add 4 new RPC methods to `ClipboardXPCProtocol`. |
| `Shared/Sources/Core/XPC/ClipboardXPCClient.swift` | Update `allowed` `NSSet` for new types; conform to `ClipboardXPCInteracting`. |
| `ClipboardDaemon/ClipboardXPCServer.swift` | Delegate to `ClipboardXPCService`; keep XPC-connection-state methods (`registerCallback`, `notifyInvalidated`, listener delegate). |
| `Shared/Tests/CoreTests/XPC/ClipboardXPCContractTests.swift` | Add backward-decoding test (legacy payload → new fields are nil/0) and forward-roundtrip test. |

---

## Task 1: Extract `ClipboardXPCService` (refactor, no behavior change)

**Files:**
- Create: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

This task introduces no new behavior — it pulls every XPC method body that does NOT depend on `NSXPCConnection.current()` out of `ClipboardXPCServer` and into a pure class. The server keeps its NSXPCListener delegate role and `registerCallback` / `notifyInvalidated`.

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`:

```swift
@testable import Platform
import Core
import CryptoKit
import XCTest

final class ClipboardXPCServiceTests: XCTestCase {
    var dir: URL!
    var clip: ClipboardStore!
    var blobs: BlobStore!
    var search: SearchStore!
    var snippets: SnippetStore!
    var pasteboard: NSPasteboard!
    var service: ClipboardXPCService!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XPCSvc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = SymmetricKey(size: .bits256)
        let device = DeviceID.generate()
        let clipDB = try! Database(
            url: dir.appendingPathComponent("c.sqlite"),
            migrations: ClipboardStore.migrations
        )
        clip = try! ClipboardStore(database: clipDB, deviceKey: key, deviceID: device)
        blobs = BlobStore(rootURL: dir.appendingPathComponent("blobs"), key: key)
        let searchDB = try! Database(
            url: dir.appendingPathComponent("s.sqlite"),
            migrations: SearchStore.migrations
        )
        search = SearchStore(database: searchDB)
        let snippetDB = try! Database(
            url: dir.appendingPathComponent("snip.sqlite"),
            migrations: SnippetStore.migrations
        )
        snippets = SnippetStore(database: snippetDB, deviceKey: key)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("test-\(UUID().uuidString)"))
        service = ClipboardXPCService(
            clip: clip, blobs: blobs, search: search, snippets: snippets, pasteboard: pasteboard
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testListItemsReturnsEmptyWhenStoreEmpty() {
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 0)
            XCTAssertNil(list.nextPageToken)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsReturnsAppendedRecord() throws {
        _ = try clip.append(.text("hello"))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.count, 1)
            XCTAssertEqual(list.items.first?.preview, "hello")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — `ClipboardXPCService` doesn't exist; compile error.

- [ ] **Step 3: Create the service**

Create `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`:

```swift
import AppKit
import Core
import Foundation

@objc public final class ClipboardXPCService: NSObject {
    private let clip: ClipboardStore
    private let blobs: BlobStore
    private let search: SearchStore
    private let snippets: SnippetStore
    private let pasteboard: NSPasteboard

    public init(
        clip: ClipboardStore,
        blobs: BlobStore,
        search: SearchStore,
        snippets: SnippetStore,
        pasteboard: NSPasteboard = .general
    ) {
        self.clip = clip
        self.blobs = blobs
        self.search = search
        self.snippets = snippets
        self.pasteboard = pasteboard
    }

    public func listItems(
        query: String?, pageToken: String?, limit: Int,
        reply: @escaping (ClipboardXPCList) -> Void
    ) {
        do {
            let pageSize = max(1, min(limit, 100))
            let offset = max(0, Int(pageToken ?? "") ?? 0)
            let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
            let metas: [ClipboardItemMeta]
            if let trimmedQuery, !trimmedQuery.isEmpty {
                let hits = try search.search(query: trimmedQuery, limit: pageSize, offset: offset)
                metas = try clip.metas(for: hits.map(\.id))
            } else {
                metas = try clip.list(limit: pageSize, offset: offset)
            }
            let items = metas.map {
                ClipboardXPCMeta(
                    id: $0.id.rawValue,
                    modified: $0.modified,
                    kind: $0.kind.rawValue,
                    preview: $0.preview
                )
            }
            let nextPageToken = items.count == pageSize ? String(offset + items.count) : nil
            reply(ClipboardXPCList(items: items, nextPageToken: nextPageToken))
        } catch {
            reply(ClipboardXPCList(items: [], nextPageToken: nil))
        }
    }

    public func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        guard let rid = RecordID(rawValue: id) else { reply(nil); return }
        switch try? clip.body(for: rid) {
        case let .text(s), let .html(s): reply(s)
        default: reply(nil)
        }
    }

    public func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        let url = blobs.encryptedURL(id: blobID)
        guard FileManager.default.fileExists(atPath: url.path) else { reply(nil); return }
        reply(ClipboardXPCBlobRef(blobID: blobID, encryptedFilePath: url.path, kind: "encrypted"))
    }

    public func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        guard let rid = RecordID(rawValue: itemID),
              let body = try? clip.body(for: rid)
        else {
            reply(PasteResult.manualPasteRequired.rawValue)
            return
        }
        DispatchQueue.main.async {
            if plainText {
                if let text = Self.plainText(from: body) {
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(text, forType: .string)
                }
            } else {
                Self.restoreToPasteboard(body: body, blobs: self.blobs, pasteboard: self.pasteboard)
            }
            self.markAsDaemonWrite()
            // Always pass .formatted: the service has already written exactly what it wants
            // on the pasteboard. PasteInjector(.plainText) would clearContents() again and
            // strip our sentinel UTI, re-enabling the duplicate-history bug.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }

    public func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
        let rows = (try? snippets.list()) ?? []
        reply(rows.map { SnippetXPCDTO(id: $0.id.rawValue, name: $0.name, trigger: $0.trigger) })
    }

    static func plainText(from body: ClipboardRecord) -> String? {
        switch body {
        case let .text(s): return s
        case let .html(s):
            if let data = s.data(using: .utf8),
               let attributed = NSAttributedString(html: data, documentAttributes: nil) {
                return attributed.string
            }
            return s
        case let .rtf(data): return NSAttributedString(rtf: data, documentAttributes: nil)?.string
        case let .files(urls): return urls.map(\.path).joined(separator: "\n")
        case .image: return nil
        }
    }

    static func restoreToPasteboard(body: ClipboardRecord, blobs: BlobStore, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        switch body {
        case let .text(s): pasteboard.setString(s, forType: .string)
        case let .html(s):
            pasteboard.setString(s, forType: NSPasteboard.PasteboardType.html)
            pasteboard.setString(s, forType: .string)
        case let .rtf(data):
            pasteboard.setData(data, forType: .rtf)
            if let s = NSAttributedString(rtf: data, documentAttributes: nil)?.string {
                pasteboard.setString(s, forType: .string)
            }
        case let .image(blobID, _, _):
            if let data = try? blobs.read(id: blobID) { pasteboard.setData(data, forType: .png) }
        case let .files(urls): pasteboard.writeObjects(urls as [NSURL])
        }
    }
}
```

- [ ] **Step 4: Modify `ClipboardXPCServer` to delegate to the service**

Replace the body of `ClipboardDaemon/ClipboardXPCServer.swift`:

```swift
import AppKit
import Core
import Foundation
import Platform

final class ClipboardXPCServer: NSObject, ClipboardXPCProtocol, NSXPCListenerDelegate {
    let container: DaemonContainer
    let listener: NSXPCListener
    let service: ClipboardXPCService
    private var callbacks: [pid_t: ClipboardXPCClientCallback] = [:]
    private let callbackLock = NSLock()

    init(container: DaemonContainer) {
        self.container = container
        listener = NSXPCListener(machServiceName: ClipboardXPCClient.machServiceName)
        service = ClipboardXPCService(
            clip: container.clip,
            blobs: container.blobs,
            search: container.search,
            snippets: container.snippets
        )
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isAllowedClient(newConnection) else {
            container.log.warning("Rejected XPC client pid=\(newConnection.processIdentifier)")
            return false
        }
        let iface = NSXPCInterface(with: ClipboardXPCProtocol.self)
        let allowed: NSSet = [
            ClipboardXPCList.self,
            ClipboardXPCBlobRef.self,
            NSArray.self,
            ClipboardXPCMeta.self,
            NSString.self,
            NSDate.self
        ]
        iface.setClasses(
            allowed as! Set<AnyHashable>,
            for: #selector(ClipboardXPCProtocol.listItems(query:pageToken:limit:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        iface.setClasses(
            allowed as! Set<AnyHashable>,
            for: #selector(ClipboardXPCProtocol.resolveBlob(blobID:reply:)),
            argumentIndex: 0,
            ofReply: true
        )
        newConnection.exportedInterface = iface
        newConnection.exportedObject = self
        newConnection.remoteObjectInterface = NSXPCInterface(with: ClipboardXPCClientCallback.self)
        let pid = newConnection.processIdentifier
        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            callbackLock.lock(); callbacks.removeValue(forKey: pid); callbackLock.unlock()
        }
        newConnection.resume()
        return true
    }

    static func isAllowedClient(_ connection: NSXPCConnection) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier) else { return false }
        return app.bundleIdentifier == "com.macallyouneed.app"
    }

    func notifyInvalidated() {
        callbackLock.lock(); let snapshot = Array(callbacks.values); callbackLock.unlock()
        for cb in snapshot { cb.itemsInvalidated() }
    }

    // ClipboardXPCProtocol — delegate to service except registerCallback (XPC-connection state)
    func listItems(query: String?, pageToken: String?, limit: Int, reply: @escaping (ClipboardXPCList) -> Void) {
        service.listItems(query: query, pageToken: pageToken, limit: limit, reply: reply)
    }
    func bodyText(forID id: String, reply: @escaping (String?) -> Void) {
        service.bodyText(forID: id, reply: reply)
    }
    func resolveBlob(blobID: String, reply: @escaping (ClipboardXPCBlobRef?) -> Void) {
        service.resolveBlob(blobID: blobID, reply: reply)
    }
    func paste(itemID: String, plainText: Bool, reply: @escaping (String) -> Void) {
        service.paste(itemID: itemID, plainText: plainText, reply: reply)
    }
    func listSnippets(reply: @escaping ([SnippetXPCDTO]) -> Void) {
        service.listSnippets(reply: reply)
    }

    func registerCallback(reply: @escaping (Bool) -> Void) {
        if let conn = NSXPCConnection.current(),
           let proxy = conn.remoteObjectProxy as? ClipboardXPCClientCallback {
            callbackLock.lock()
            callbacks[conn.processIdentifier] = proxy
            callbackLock.unlock()
            reply(true)
        } else { reply(false) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — both `testListItemsReturnsEmptyWhenStoreEmpty` and `testListItemsReturnsAppendedRecord` green.

- [ ] **Step 6: Verify the daemon target still builds**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`. If `xcodegen generate` is needed (`project.yml` is unchanged so it shouldn't be), run it: `xcodegen generate`.

- [ ] **Step 7: Commit**

```bash
git add Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        ClipboardDaemon/ClipboardXPCServer.swift
git commit -m "$(cat <<'EOF'
refactor(xpc): extract ClipboardXPCService for testability

Pull every method that doesn't depend on NSXPCConnection.current()
out of ClipboardXPCServer into a pure Platform-module class with
injectable stores and pasteboard. Server keeps the listener delegate
role and connection-scoped registerCallback/notifyInvalidated.
No behavior change.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 1.5: Self-write suppression sentinel

**Files:**
- Modify: `Shared/Sources/Platform/Pasteboard/PasteboardTypes.swift`
- Modify: `Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Test: `Shared/Tests/PlatformTests/PasteboardObserverTests.swift`

**Why this lands here:** every paste flow in Phase A — including the existing `paste(itemID:)` we just relocated — writes to the pasteboard, which the daemon's `PasteboardObserver` will then re-record as a brand-new clip with the wrong source app. Without suppression, every snippet paste / transformation / multi-paste produces a duplicate history entry. Subsequent Phase A tasks rely on this fix being present before they ship.

**Mechanism:** every service-initiated pasteboard write also sets a sentinel `daemonWrite` pasteboard type. The observer's tick reads `currentTypes()` and skips any change containing that type. When another app overwrites the pasteboard, the sentinel is gone and capture resumes normally.

- [ ] **Step 1: Failing test**

Append to `Shared/Tests/PlatformTests/PasteboardObserverTests.swift`:

```swift
    func testTickSkipsChangesContainingDaemonWriteSentinel() {
        let pb = NSPasteboard(name: NSPasteboard.Name("test-\(UUID())"))
        let reader = PrivatePasteboardReader(pb: pb)
        let obs = PasteboardObserver(reader: reader, rules: ExclusionRules(), pollInterval: 0.05)

        var fired = false
        obs.start { _ in fired = true }
        defer { obs.stop() }

        pb.clearContents()
        pb.setString("hello", forType: .string)
        pb.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertFalse(fired, "observer must skip changes carrying the daemonWrite sentinel")
    }
```

`PrivatePasteboardReader` already exists in this file (used by other observer tests); if not, add a tiny conforming wrapper around an `NSPasteboard` instance.

- [ ] **Step 2: Verify failure**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter PasteboardObserverTests/testTickSkipsChangesContainingDaemonWriteSentinel
```

Expected: FAIL — `PasteboardUTI.daemonWrite` doesn't exist; observer doesn't filter.

- [ ] **Step 3: Add the sentinel UTI**

In `Shared/Sources/Platform/Pasteboard/PasteboardTypes.swift`:

```swift
    public static let daemonWrite = NSPasteboard.PasteboardType("com.macallyouneed.shared.daemon-write")
```

- [ ] **Step 4: Update observer tick**

In `Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift`, in `tick()`:

```swift
    private func tick() {
        let count = reader.currentChangeCount()
        guard count != lastCount else { return }
        lastCount = count
        let types = reader.currentTypes()
        if types.contains(PasteboardUTI.daemonWrite.rawValue) { return }
        let bundleID = reader.frontmostBundleID()
        if rules.shouldExclude(types: types, appBundleID: bundleID) { return }
        let items = reader.currentItems()
        guard !items.isEmpty else { return }
        callback?(PasteboardChange(changeCount: count, frontmostAppBundleID: bundleID, items: items))
    }
```

- [ ] **Step 5: Mark every service-initiated pasteboard write**

In `ClipboardXPCService.swift`, add a small helper:

```swift
    private func markAsDaemonWrite() {
        pasteboard.setData(Data([0]), forType: PasteboardUTI.daemonWrite)
    }
```

Call it after every place the service writes to `self.pasteboard`. In `paste(itemID:plainText:reply:)`'s `DispatchQueue.main.async` block — both branches (plainText and formatted) — add `self.markAsDaemonWrite()` after the `setString`/`restoreToPasteboard` call but before `PasteInjector.paste`. Same for `restoreToPasteboard` static method — add a parameter to mark, or call `markAsDaemonWrite` from the caller after invoking it.

For the static `restoreToPasteboard(body:blobs:pasteboard:)`, simplest is: after calling it, add `pasteboard.setData(Data([0]), forType: PasteboardUTI.daemonWrite)` at the call site.

- [ ] **Step 6: Run tests + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
git add Shared/Sources/Platform/Pasteboard/PasteboardTypes.swift \
        Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/PasteboardObserverTests.swift
git commit -m "$(cat <<'EOF'
feat(pasteboard): self-write suppression via daemonWrite sentinel UTI

Every service-initiated pasteboard write now also sets a sentinel
type. PasteboardObserver tick skips changes carrying it. Prevents
duplicate history rows + wrong source-app provenance on every paste/
pasteText/pasteMany/transformAndCopy flow.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

**Note for subsequent tasks:** every new RPC that writes to the pasteboard (`pasteMany`, `pasteText`, `transformAndCopy`) MUST call `markAsDaemonWrite()` after writing content, before `PasteInjector.paste`. Their task code blocks below assume this helper exists.

---

## Task 2: Extend `ClipboardXPCMeta` wire format with new fields

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Test: `Shared/Tests/CoreTests/XPC/ClipboardXPCContractTests.swift`

Adds `sourceAppBundleID: String?`, `imageWidth: Int`, `imageHeight: Int`, `imageBlobID: String?` to the wire format. Decoder must tolerate legacy payloads missing these keys. This is the cornerstone of XPC backward compatibility (spec §14).

- [ ] **Step 1: Write the failing tests**

Replace `Shared/Tests/CoreTests/XPC/ClipboardXPCContractTests.swift` body:

```swift
@testable import Core
import XCTest

final class ClipboardXPCContractTests: XCTestCase {
    func testProtocolHasRequiredSelectors() {
        let p = ClipboardXPCProtocol.self as Protocol
        XCTAssertNotNil(p)
        _ = ClipboardXPCList(items: [], nextPageToken: nil)
    }

    func testMetaForwardRoundtripPreservesAllFields() throws {
        let original = ClipboardXPCMeta(
            id: "abc",
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            kind: "clipboardItem",
            preview: "hi",
            sourceAppBundleID: "com.apple.Safari",
            imageWidth: 320,
            imageHeight: 200,
            imageBlobID: "blob-1"
        )
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        original.encode(with: coder)
        let data = coder.encodedData

        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = true
        guard let decoded = ClipboardXPCMeta(coder: decoder) else {
            XCTFail("decode failed"); return
        }
        XCTAssertEqual(decoded.id, "abc")
        XCTAssertEqual(decoded.modified, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(decoded.kind, "clipboardItem")
        XCTAssertEqual(decoded.preview, "hi")
        XCTAssertEqual(decoded.sourceAppBundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.imageWidth, 320)
        XCTAssertEqual(decoded.imageHeight, 200)
        XCTAssertEqual(decoded.imageBlobID, "blob-1")
    }

    func testMetaDecodesLegacyPayloadMissingNewFields() throws {
        // Simulate a payload from the old wire format: only id/modified/kind/preview.
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        coder.encode("legacy" as NSString, forKey: "id")
        coder.encode(Date(timeIntervalSince1970: 1) as NSDate, forKey: "modified")
        coder.encode("clipboardItem" as NSString, forKey: "kind")
        coder.encode("legacy preview" as NSString, forKey: "preview")
        let data = coder.encodedData

        let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
        decoder.requiresSecureCoding = true
        guard let decoded = ClipboardXPCMeta(coder: decoder) else {
            XCTFail("legacy decode failed"); return
        }
        XCTAssertEqual(decoded.id, "legacy")
        XCTAssertEqual(decoded.preview, "legacy preview")
        XCTAssertNil(decoded.sourceAppBundleID)
        XCTAssertEqual(decoded.imageWidth, 0)
        XCTAssertEqual(decoded.imageHeight, 0)
        XCTAssertNil(decoded.imageBlobID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCContractTests
```

Expected: FAIL — `ClipboardXPCMeta` init does not accept new args; compile error.

- [ ] **Step 3: Replace `ClipboardXPCMeta` in `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`**

Replace the existing `ClipboardXPCMeta` class (top ~37 lines of file) with:

```swift
@objc public class ClipboardXPCMeta: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public let id: String
    @objc public let modified: Date
    @objc public let kind: String
    @objc public let preview: String
    @objc public let sourceAppBundleID: String?
    @objc public let imageWidth: Int
    @objc public let imageHeight: Int
    @objc public let imageBlobID: String?

    public init(
        id: String,
        modified: Date,
        kind: String,
        preview: String,
        sourceAppBundleID: String? = nil,
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        imageBlobID: String? = nil
    ) {
        self.id = id
        self.modified = modified
        self.kind = kind
        self.preview = preview
        self.sourceAppBundleID = sourceAppBundleID
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageBlobID = imageBlobID
    }

    public required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
              let kind = coder.decodeObject(of: NSString.self, forKey: "kind") as String?,
              let preview = coder.decodeObject(of: NSString.self, forKey: "preview") as String?,
              let modified = coder.decodeObject(of: NSDate.self, forKey: "modified") as Date?
        else { return nil }
        self.id = id
        self.modified = modified
        self.kind = kind
        self.preview = preview
        sourceAppBundleID = coder.decodeObject(of: NSString.self, forKey: "sourceAppBundleID") as String?
        imageWidth = coder.decodeInteger(forKey: "imageWidth")
        imageHeight = coder.decodeInteger(forKey: "imageHeight")
        imageBlobID = coder.decodeObject(of: NSString.self, forKey: "imageBlobID") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id as NSString, forKey: "id")
        coder.encode(modified as NSDate, forKey: "modified")
        coder.encode(kind as NSString, forKey: "kind")
        coder.encode(preview as NSString, forKey: "preview")
        if let sourceAppBundleID {
            coder.encode(sourceAppBundleID as NSString, forKey: "sourceAppBundleID")
        }
        coder.encode(imageWidth, forKey: "imageWidth")
        coder.encode(imageHeight, forKey: "imageHeight")
        if let imageBlobID {
            coder.encode(imageBlobID as NSString, forKey: "imageBlobID")
        }
    }
}
```

`decodeInteger(forKey:)` returns `0` for missing keys — exactly what the legacy-payload test expects. `decodeObject(of:NSString.self, forKey:)` returns `nil` for missing optional keys.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCContractTests
```

Expected: PASS — all three tests green.

- [ ] **Step 5: Run the full Shared test suite to confirm nothing else broke**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```

Expected: PASS — entire suite green. Existing call sites that construct `ClipboardXPCMeta(id:modified:kind:preview:)` still compile because the new args have default values.

- [ ] **Step 6: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Tests/CoreTests/XPC/ClipboardXPCContractTests.swift
git commit -m "$(cat <<'EOF'
feat(xpc): extend ClipboardXPCMeta with sourceApp + image fields

Adds sourceAppBundleID, imageWidth, imageHeight, imageBlobID to the
NSSecureCoding wire format. Defaults on init keep existing call sites
compiling. Decoder treats missing keys as nil/0, so a stale daemon's
payload still decodes cleanly.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Populate new fields in `service.listItems`

**Files:**
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

`ClipboardItemMeta` already carries `sourceAppBundleID`. Image dimensions and `blobID` live inside the encrypted body and must be peeked when kind is `clipboardItem` AND the body decodes to `.image`. Peek is cheap (one decrypt per image item) and only happens for items the UI is about to render.

- [ ] **Step 1: Add the failing tests**

Append to `ClipboardXPCServiceTests.swift`:

```swift
    func testListItemsCarriesSourceAppBundleID() throws {
        _ = try clip.append(.text("hi"), sourceAppBundleID: "com.apple.Terminal")
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            XCTAssertEqual(list.items.first?.sourceAppBundleID, "com.apple.Terminal")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsCarriesImageDimensionsAndBlobID() throws {
        let pixels = Data(repeating: 0xAB, count: 32)
        let blobID = try blobs.write(pixels)
        _ = try clip.append(.image(blobID: blobID, width: 800, height: 600))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            let meta = list.items.first
            XCTAssertEqual(meta?.imageWidth, 800)
            XCTAssertEqual(meta?.imageHeight, 600)
            XCTAssertEqual(meta?.imageBlobID, blobID)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testListItemsLeavesImageFieldsZeroForTextRecords() throws {
        _ = try clip.append(.text("plain"))
        let exp = expectation(description: "list")
        service.listItems(query: nil, pageToken: nil, limit: 10) { list in
            let meta = list.items.first
            XCTAssertEqual(meta?.imageWidth, 0)
            XCTAssertEqual(meta?.imageHeight, 0)
            XCTAssertNil(meta?.imageBlobID)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — three new tests fail; new fields come back as nil/0 because `service.listItems` doesn't populate them.

- [ ] **Step 3: Update `service.listItems`**

In `ClipboardXPCService.swift`, replace the `items = metas.map { … }` line inside `listItems` with:

```swift
            let items = metas.map { meta -> ClipboardXPCMeta in
                var imgWidth = 0
                var imgHeight = 0
                var imgBlobID: String? = nil
                if meta.kind == .clipboardItem,
                   let body = try? clip.body(for: meta.id),
                   case let .image(blobID, w, h) = body {
                    imgBlobID = blobID
                    imgWidth = w
                    imgHeight = h
                }
                return ClipboardXPCMeta(
                    id: meta.id.rawValue,
                    modified: meta.modified,
                    kind: meta.kind.rawValue,
                    preview: meta.preview,
                    sourceAppBundleID: meta.sourceAppBundleID,
                    imageWidth: imgWidth,
                    imageHeight: imgHeight,
                    imageBlobID: imgBlobID
                )
            }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — all five tests green.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift
git commit -m "$(cat <<'EOF'
feat(xpc): populate sourceApp + image fields in listItems

Service now peeks decrypted image bodies to surface blobID and
dimensions to the client, and forwards sourceAppBundleID from
ClipboardItemMeta. Text items leave image fields zero/nil.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `ThumbnailRenderer` (pure resize + JPEG encode)

**Files:**
- Create: `Shared/Sources/Platform/Image/ThumbnailRenderer.swift`
- Test: `Shared/Tests/PlatformTests/Image/ThumbnailRendererTests.swift`

Pure function takes raw image bytes + maxDim and returns JPEG bytes resized so the longest edge is `maxDim`. `maxDim == 0` returns the source data passed through (lets `imageThumbnail(maxDim: 0)` mean "original" per spec §10.2).

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/PlatformTests/Image/ThumbnailRendererTests.swift`:

```swift
@testable import Platform
import AppKit
import XCTest

final class ThumbnailRendererTests: XCTestCase {
    private func makePNG(width: Int, height: Int) -> Data {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testReturnsNilForUnreadableData() {
        XCTAssertNil(ThumbnailRenderer.render(data: Data([0xDE, 0xAD]), maxDim: 100))
    }

    func testZeroMaxDimReturnsOriginalDataPassthrough() {
        let png = makePNG(width: 50, height: 50)
        let out = ThumbnailRenderer.render(data: png, maxDim: 0)
        XCTAssertEqual(out, png)
    }

    func testLandscapeImageResizedToMaxDimOnLongestEdge() {
        let png = makePNG(width: 800, height: 400)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 200)!
        let img = NSImage(data: jpeg)!
        XCTAssertEqual(Int(img.size.width), 200)
        XCTAssertEqual(Int(img.size.height), 100)
    }

    func testPortraitImageResizedToMaxDimOnLongestEdge() {
        let png = makePNG(width: 300, height: 900)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 300)!
        let img = NSImage(data: jpeg)!
        XCTAssertEqual(Int(img.size.height), 300)
        XCTAssertEqual(Int(img.size.width), 100)
    }

    func testReturnsJPEGBytes() {
        let png = makePNG(width: 64, height: 64)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 32)!
        // JPEG SOI marker
        XCTAssertEqual(jpeg.prefix(2), Data([0xFF, 0xD8]))
    }

    func testSmallImageNotUpscaled() {
        let png = makePNG(width: 50, height: 50)
        let jpeg = ThumbnailRenderer.render(data: png, maxDim: 200)!
        let img = NSImage(data: jpeg)!
        XCTAssertLessThanOrEqual(Int(img.size.width), 50)
        XCTAssertLessThanOrEqual(Int(img.size.height), 50)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ThumbnailRendererTests
```

Expected: FAIL — `ThumbnailRenderer` doesn't exist.

- [ ] **Step 3: Implement the renderer**

Create `Shared/Sources/Platform/Image/ThumbnailRenderer.swift`:

```swift
import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ThumbnailRenderer {
    public static func render(data: Data, maxDim: Int) -> Data? {
        if maxDim <= 0 { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDim
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            outData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return outData as Data
    }
}
```

`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` does not upscale by default — small images stay small (matches `testSmallImageNotUpscaled`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ThumbnailRendererTests
```

Expected: PASS — six tests green.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Platform/Image/ThumbnailRenderer.swift \
        Shared/Tests/PlatformTests/Image/ThumbnailRendererTests.swift
git commit -m "$(cat <<'EOF'
feat(image): add ThumbnailRenderer pure resize + JPEG encode

Wraps ImageIO's CGImageSource thumbnail API. Preserves aspect ratio,
caps longest edge at maxDim, emits JPEG bytes at quality 0.85, never
upscales. maxDim=0 returns input data unchanged (used for "original"
size requests).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `ThumbnailCache`

**Files:**
- Create: `Shared/Sources/Platform/Image/ThumbnailCache.swift`
- Test: `Shared/Tests/PlatformTests/Image/ThumbnailCacheTests.swift`

NSCache wrapper keyed by `(blobID, maxDim)`. Cap at 64 MB total cost (NSCache evicts based on cost). Per-blob+size invalidation when underlying blob changes (rare — blobs are immutable, so this is mostly a defensive API).

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/PlatformTests/Image/ThumbnailCacheTests.swift`:

```swift
@testable import Platform
import XCTest

final class ThumbnailCacheTests: XCTestCase {
    func testReturnsNilForUnknownKey() {
        let cache = ThumbnailCache()
        XCTAssertNil(cache.value(blobID: "nope", maxDim: 100))
    }

    func testStoresAndRetrievesByBlobIDAndMaxDim() {
        let cache = ThumbnailCache()
        let small = Data(repeating: 1, count: 10)
        let big = Data(repeating: 2, count: 100)
        cache.set(small, blobID: "abc", maxDim: 100)
        cache.set(big, blobID: "abc", maxDim: 500)
        XCTAssertEqual(cache.value(blobID: "abc", maxDim: 100), small)
        XCTAssertEqual(cache.value(blobID: "abc", maxDim: 500), big)
        XCTAssertNil(cache.value(blobID: "abc", maxDim: 999))
    }

    func testRemoveDropsEntryButLeavesOthers() {
        let cache = ThumbnailCache()
        cache.set(Data([1]), blobID: "a", maxDim: 100)
        cache.set(Data([2]), blobID: "b", maxDim: 100)
        cache.remove(blobID: "a")
        XCTAssertNil(cache.value(blobID: "a", maxDim: 100))
        XCTAssertEqual(cache.value(blobID: "b", maxDim: 100), Data([2]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ThumbnailCacheTests
```

Expected: FAIL — `ThumbnailCache` doesn't exist.

- [ ] **Step 3: Implement the cache**

Create `Shared/Sources/Platform/Image/ThumbnailCache.swift`:

```swift
import Foundation

public final class ThumbnailCache {
    private let cache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var keysByBlob: [String: Set<String>] = [:]

    public init(totalCostLimitBytes: Int = 64 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimitBytes
    }

    public func value(blobID: String, maxDim: Int) -> Data? {
        cache.object(forKey: Self.key(blobID, maxDim) as NSString) as Data?
    }

    public func set(_ data: Data, blobID: String, maxDim: Int) {
        let k = Self.key(blobID, maxDim)
        cache.setObject(data as NSData, forKey: k as NSString, cost: data.count)
        lock.lock()
        keysByBlob[blobID, default: []].insert(k)
        lock.unlock()
    }

    public func remove(blobID: String) {
        lock.lock()
        let keys = keysByBlob.removeValue(forKey: blobID) ?? []
        lock.unlock()
        for k in keys { cache.removeObject(forKey: k as NSString) }
    }

    private static func key(_ blobID: String, _ maxDim: Int) -> String {
        "\(blobID)|\(maxDim)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ThumbnailCacheTests
```

Expected: PASS — three tests green.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Platform/Image/ThumbnailCache.swift \
        Shared/Tests/PlatformTests/Image/ThumbnailCacheTests.swift
git commit -m "$(cat <<'EOF'
feat(image): add ThumbnailCache (blobID, maxDim) -> Data

NSCache-backed, 64 MB cost cap. Keys composite of blobID and maxDim
so the same blob can be cached at multiple sizes. remove(blobID:)
sweeps every cached size for that blob.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `imageThumbnail` RPC — protocol + service + client allowed-classes

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ClipboardXPCServiceTests.swift`:

```swift
    func testImageThumbnailReturnsJPEGForImageRecord() throws {
        // Build a real PNG, store as encrypted blob, register clip record.
        let img = NSImage(size: NSSize(width: 200, height: 100))
        img.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        let png = rep.representation(using: .png, properties: [:])!

        let blobID = try blobs.write(png)
        let meta = try clip.append(.image(blobID: blobID, width: 200, height: 100))

        let exp = expectation(description: "thumb")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 50) { data in
            XCTAssertNotNil(data)
            XCTAssertEqual(data?.prefix(2), Data([0xFF, 0xD8]))
            let thumb = NSImage(data: data!)!
            XCTAssertEqual(Int(thumb.size.width), 50)
            XCTAssertEqual(Int(thumb.size.height), 25)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testImageThumbnailReturnsNilForNonImageRecord() throws {
        let meta = try clip.append(.text("not an image"))
        let exp = expectation(description: "thumb")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 50) { data in
            XCTAssertNil(data)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testImageThumbnailCachesByBlobIDAndMaxDim() throws {
        let img = NSImage(size: NSSize(width: 32, height: 32))
        img.lockFocus(); NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill(); img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        let blobID = try blobs.write(png)
        let meta = try clip.append(.image(blobID: blobID, width: 32, height: 32))

        let first = expectation(description: "first")
        var firstBytes: Data?
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 16) { firstBytes = $0; first.fulfill() }
        wait(for: [first], timeout: 1)

        // Delete the blob from disk; cache hit should still return bytes.
        try blobs.delete(id: blobID)

        let second = expectation(description: "second")
        service.imageThumbnail(forID: meta.id.rawValue, maxDim: 16) {
            XCTAssertEqual($0, firstBytes); second.fulfill()
        }
        wait(for: [second], timeout: 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — `imageThumbnail` method doesn't exist.

- [ ] **Step 3: Add to protocol**

In `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`, inside `@objc public protocol ClipboardXPCProtocol`, add:

```swift
    func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void)
```

- [ ] **Step 4: Implement on the service**

In `ClipboardXPCService.swift`, add stored property:

```swift
    private let thumbnailCache = ThumbnailCache()
```

And add this method (after `resolveBlob`):

```swift
    public func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void) {
        guard let rid = RecordID(rawValue: id),
              let body = try? clip.body(for: rid),
              case let .image(blobID, _, _) = body
        else { reply(nil); return }

        if let cached = thumbnailCache.value(blobID: blobID, maxDim: maxDim) {
            reply(cached); return
        }
        guard let raw = try? blobs.read(id: blobID),
              let rendered = ThumbnailRenderer.render(data: raw, maxDim: maxDim)
        else { reply(nil); return }
        thumbnailCache.set(rendered, blobID: blobID, maxDim: maxDim)
        reply(rendered)
    }
```

Also conform `ClipboardXPCService` to `ClipboardXPCProtocol` so the daemon can hand it off as the exported object — change the class declaration:

```swift
@objc public final class ClipboardXPCService: NSObject, ClipboardXPCProtocol {
```

Note: `registerCallback` is in the protocol but is still implemented by `ClipboardXPCServer`, not the service. To satisfy the compiler, add a default no-op on the service:

```swift
    public func registerCallback(reply: @escaping (Bool) -> Void) {
        // Connection-state RPC; only meaningful when called via NSXPCConnection.
        reply(false)
    }
```

- [ ] **Step 5: Add forwarding stub in `ClipboardXPCServer`**

In `ClipboardDaemon/ClipboardXPCServer.swift`, add to the `ClipboardXPCProtocol` delegation block:

```swift
    func imageThumbnail(forID id: String, maxDim: Int, reply: @escaping (Data?) -> Void) {
        service.imageThumbnail(forID: id, maxDim: maxDim, reply: reply)
    }
```

- [ ] **Step 6: Update client allowed classes for `Data` reply**

`Data` arrives as `NSData`. In `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`, add `NSData.self` to the `allowed` `NSSet` array, then add an `iface.setClasses` call:

```swift
        iface.setClasses(
            allowed,
            for: #selector(ClipboardXPCProtocol.imageThumbnail(forID:maxDim:reply:)),
            argumentIndex: 0, ofReply: true
        )
```

The `allowed` array becomes:

```swift
        let allowed = NSSet(array: [
            ClipboardXPCList.self,
            ClipboardXPCMeta.self,
            ClipboardXPCBlobRef.self,
            SnippetXPCDTO.self,
            NSArray.self,
            NSString.self,
            NSDate.self,
            NSNumber.self,
            NSData.self
        ]) as! Set<AnyHashable>
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — three new image-thumbnail tests green; existing tests still green.

- [ ] **Step 8: Verify the daemon and main app build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 9: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Core/XPC/ClipboardXPCClient.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        ClipboardDaemon/ClipboardXPCServer.swift
git commit -m "$(cat <<'EOF'
feat(xpc): add imageThumbnail RPC for image cards

Daemon decrypts blob, renders via ThumbnailRenderer, caches by
(blobID, maxDim). UI-side image cards will request thumbnails at
~220pt for cards and 0 (original) for Quick Look. JPEG payloads stay
small enough to ship over XPC efficiently.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `pasteMany` RPC — protocol + service implementation

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

Joins each item's plain-text representation in the requested order, writes once to the pasteboard, then triggers paste. Image kinds are skipped silently. Tests use the private pasteboard injected at setUp.

The service's existing `paste` calls `PasteInjector.paste` which fires a real ⌘V key event — this would actually paste into whatever app has focus during the test. The test will assert on the pasteboard content (which we can verify deterministically) and tolerate that no actual key event is sent because `AXIsProcessTrusted()` returns false in the test process. `PasteInjector` already returns `.manualPasteRequired` in that case without erroring.

- [ ] **Step 1: Write the failing test**

Append to `ClipboardXPCServiceTests.swift`:

```swift
    func testPasteManyJoinsTextWithDelimiterAndWritesPasteboard() throws {
        let a = try clip.append(.text("alpha"))
        let b = try clip.append(.text("beta"))
        let c = try clip.append(.text("gamma"))

        let exp = expectation(description: "pasteMany")
        service.pasteMany(
            itemIDs: [a.id.rawValue, b.id.rawValue, c.id.rawValue],
            delimiter: " | ",
            plainText: true
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)

        // Allow the DispatchQueue.main.async write to flush.
        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "alpha | beta | gamma")
    }

    func testPasteManySkipsImageKindsAndPreservesOrder() throws {
        let a = try clip.append(.text("first"))
        let blobID = try blobs.write(Data([0]))
        let img = try clip.append(.image(blobID: blobID, width: 1, height: 1))
        let c = try clip.append(.text("third"))

        let exp = expectation(description: "pasteMany")
        service.pasteMany(
            itemIDs: [a.id.rawValue, img.id.rawValue, c.id.rawValue],
            delimiter: "\n",
            plainText: true
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let mainExp = expectation(description: "main")
        DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "first\nthird")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — `pasteMany` method doesn't exist.

- [ ] **Step 3: Add to protocol**

In `ClipboardXPCProtocol.swift`, inside `ClipboardXPCProtocol`:

```swift
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool,
                   reply: @escaping (String) -> Void)
```

- [ ] **Step 4: Implement on the service**

In `ClipboardXPCService.swift`, add:

```swift
    public func pasteMany(
        itemIDs: [String], delimiter: String, plainText: Bool,
        reply: @escaping (String) -> Void
    ) {
        let parts: [String] = itemIDs.compactMap { idString in
            guard let rid = RecordID(rawValue: idString),
                  let body = try? clip.body(for: rid)
            else { return nil }
            return Self.plainText(from: body)
        }
        let joined = parts.joined(separator: delimiter)
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(joined, forType: .string)
            self.markAsDaemonWrite()
            // Always .formatted — the service already wrote .string only, so no
            // formatting to strip. .plainText would clearContents() and erase the sentinel.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }
```

`plainText` arg controls only the paste-mode hint; for joined text it's always treated as plain text since there's no meaningful merged formatted representation. The bool stays in the signature for API symmetry with `paste(itemID:plainText:)` and future-proofs RTF-merge if we ever add it.

- [ ] **Step 5: Add forwarding in the server**

In `ClipboardXPCServer.swift`:

```swift
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool,
                   reply: @escaping (String) -> Void) {
        service.pasteMany(itemIDs: itemIDs, delimiter: delimiter, plainText: plainText, reply: reply)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — both new tests green.

- [ ] **Step 7: Verify daemon + app build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        ClipboardDaemon/ClipboardXPCServer.swift
git commit -m "$(cat <<'EOF'
feat(xpc): add pasteMany RPC for stack-paste / merge-paste

Joins each item's plain-text representation in the requested order
with the supplied delimiter, writes the joined string to the
pasteboard once, then fires a single paste injection. Non-text kinds
(image) are skipped silently; order of remaining items is preserved.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `pasteText` RPC — protocol + service implementation

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

`pasteText` is the building block for snippet pasting and "Apply" transformations — it accepts raw text, writes to pasteboard, optionally appends to history.

- [ ] **Step 1: Write the failing tests**

Append to `ClipboardXPCServiceTests.swift`:

```swift
    func testPasteTextWritesPasteboardWithoutSavingByDefault() throws {
        let exp = expectation(description: "pasteText")
        service.pasteText(text: "hello world", plainText: true, saveAsNew: false) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main"); DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
        XCTAssertEqual(try clip.list(limit: 10).count, 0)
    }

    func testPasteTextWithSaveAsNewAppendsHistoryRecord() throws {
        let exp = expectation(description: "pasteText")
        service.pasteText(text: "saved snippet", plainText: true, saveAsNew: true) { _ in
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main"); DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        let items = try clip.list(limit: 10)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.preview, "saved snippet")
        XCTAssertEqual(items.first?.sourceAppBundleID, "com.macallyouneed.app")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — `pasteText` method doesn't exist.

- [ ] **Step 3: Add to protocol**

In `ClipboardXPCProtocol.swift`:

```swift
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool,
                   reply: @escaping (String) -> Void)
```

- [ ] **Step 4: Implement on the service**

In `ClipboardXPCService.swift`:

```swift
    public func pasteText(
        text: String, plainText: Bool, saveAsNew: Bool,
        reply: @escaping (String) -> Void
    ) {
        if saveAsNew, let meta = try? clip.append(.text(text), sourceAppBundleID: "com.macallyouneed.app") {
            // Index for FTS so the new clip is searchable. Without this the row is
            // findable by recency only — searching for words in it would miss because
            // self-write suppression now correctly prevents observer recapture.
            try? search.upsert(kind: .clipboardItem, id: meta.id, text: text)
        }
        DispatchQueue.main.async {
            self.pasteboard.clearContents()
            self.pasteboard.setString(text, forType: .string)
            self.markAsDaemonWrite()
            // Always .formatted; the service wrote plain .string already. .plainText
            // would clearContents() and remove the sentinel.
            let result = PasteInjector.paste(nil, mode: .formatted, into: self.pasteboard)
            reply(result.rawValue)
        }
    }
```

- [ ] **Step 5: Add forwarding in the server**

In `ClipboardXPCServer.swift`:

```swift
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool,
                   reply: @escaping (String) -> Void) {
        service.pasteText(text: text, plainText: plainText, saveAsNew: saveAsNew, reply: reply)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — both new tests green.

- [ ] **Step 7: Verify daemon + app build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        ClipboardDaemon/ClipboardXPCServer.swift
git commit -m "$(cat <<'EOF'
feat(xpc): add pasteText RPC for snippet + transform pasting

Writes raw text to pasteboard, fires paste injection, optionally
appends a clipboard record with com.macallyouneed.app as source app
so the action shows up in history with the correct provenance.
Building block for snippet pasting (Phase F) and transformation
"Apply" (Task 10).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `TextTransforms` (pure transformations)

**Files:**
- Create: `Shared/Sources/Platform/Transforms/TextTransforms.swift`
- Test: `Shared/Tests/PlatformTests/Transforms/TextTransformsTests.swift`

Enum of every transform from spec §10.3. Each case has a closed-form pure implementation; impossible inputs (e.g. malformed JSON, malformed Base64) return `nil` so callers can show a user-facing failure toast.

- [ ] **Step 1: Write the failing tests**

Create `Shared/Tests/PlatformTests/Transforms/TextTransformsTests.swift`:

```swift
@testable import Platform
import XCTest

final class TextTransformsTests: XCTestCase {
    func testLowercase() { XCTAssertEqual(TextTransforms.apply(.lowercase, to: "HeLLo"), "hello") }
    func testUppercase() { XCTAssertEqual(TextTransforms.apply(.uppercase, to: "Hello"), "HELLO") }
    func testTitleCase() {
        XCTAssertEqual(TextTransforms.apply(.titleCase, to: "the quick brown fox"),
                       "The Quick Brown Fox")
    }
    func testTrim() {
        XCTAssertEqual(TextTransforms.apply(.trim, to: "  hi\n\t"), "hi")
    }
    func testStripHTML() {
        XCTAssertEqual(TextTransforms.apply(.stripHTML, to: "<b>bold</b>"), "bold")
    }
    func testPrettyJSON() {
        XCTAssertEqual(
            TextTransforms.apply(.prettyJSON, to: #"{"a":1,"b":[2,3]}"#),
            "{\n  \"a\" : 1,\n  \"b\" : [\n    2,\n    3\n  ]\n}"
        )
    }
    func testPrettyJSONFailsOnInvalid() {
        XCTAssertNil(TextTransforms.apply(.prettyJSON, to: "not json"))
    }
    func testMinifyJSON() {
        XCTAssertEqual(
            TextTransforms.apply(.minifyJSON, to: "{\n  \"a\": 1\n}"),
            "{\"a\":1}"
        )
    }
    func testBase64Encode() {
        XCTAssertEqual(TextTransforms.apply(.base64Encode, to: "hi"), "aGk=")
    }
    func testBase64Decode() {
        XCTAssertEqual(TextTransforms.apply(.base64Decode, to: "aGk="), "hi")
    }
    func testBase64DecodeFailsOnInvalid() {
        XCTAssertNil(TextTransforms.apply(.base64Decode, to: "@@@"))
    }
    func testURLEncode() {
        XCTAssertEqual(TextTransforms.apply(.urlEncode, to: "a b/c"), "a%20b%2Fc")
    }
    func testURLDecode() {
        XCTAssertEqual(TextTransforms.apply(.urlDecode, to: "a%20b%2Fc"), "a b/c")
    }
    func testSortLines() {
        XCTAssertEqual(TextTransforms.apply(.sortLines, to: "b\na\nc"), "a\nb\nc")
    }
    func testDedupeLines() {
        XCTAssertEqual(TextTransforms.apply(.dedupeLines, to: "a\nb\na\nc\nb"), "a\nb\nc")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter TextTransformsTests
```

Expected: FAIL — `TextTransforms` doesn't exist.

- [ ] **Step 3: Implement transforms**

Create `Shared/Sources/Platform/Transforms/TextTransforms.swift`:

```swift
import AppKit
import Foundation

public enum TextTransform: String, CaseIterable, Sendable {
    case lowercase
    case uppercase
    case titleCase
    case trim
    case stripHTML
    case prettyJSON
    case minifyJSON
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case sortLines
    case dedupeLines
}

public enum TextTransforms {
    /// Component-style URL encoding allowed set: alphanumerics + `-_.~` only.
    /// Mirrors JavaScript's encodeURIComponent. Slash IS encoded (unlike Foundation's
    /// `.urlPathAllowed`, which permits `/` and would leave path separators raw).
    private static let componentEncodingAllowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789-_.~")
        return set
    }()

    public static func apply(_ transform: TextTransform, to text: String) -> String? {
        switch transform {
        case .lowercase: return text.lowercased()
        case .uppercase: return text.uppercased()
        case .titleCase: return text.capitalized
        case .trim: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .stripHTML: return stripHTML(text)
        case .prettyJSON: return rewriteJSON(text, options: [.prettyPrinted, .sortedKeys])
        case .minifyJSON: return rewriteJSON(text, options: [])
        case .base64Encode: return text.data(using: .utf8)?.base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        case .urlEncode: return text.addingPercentEncoding(withAllowedCharacters: componentEncodingAllowed)
        case .urlDecode: return text.removingPercentEncoding
        case .sortLines:
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .sorted().joined(separator: "\n")
        case .dedupeLines:
            var seen = Set<Substring>()
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")
        }
    }

    private static func stripHTML(_ html: String) -> String? {
        guard let data = html.data(using: .utf8),
              let attr = NSAttributedString(html: data, documentAttributes: nil)
        else { return nil }
        return attr.string
    }

    private static func rewriteJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: options),
              let s = String(data: out, encoding: .utf8)
        else { return nil }
        return s
    }
}
```

Note: `JSONSerialization` writes pretty JSON with two-space indent and a space after colons; the `testPrettyJSON` expectation matches that format.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter TextTransformsTests
```

Expected: PASS — all 15 tests green.

If `testStripHTML` fails because `NSAttributedString(html:)` adds a trailing newline, switch the assertion to `.hasPrefix("bold")` and trim — but check the actual output first by adding `print(actual)` and re-running.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/Platform/Transforms/TextTransforms.swift \
        Shared/Tests/PlatformTests/Transforms/TextTransformsTests.swift
git commit -m "$(cat <<'EOF'
feat(transforms): add TextTransforms pure transformation library

Implements every text transform from spec §10.3: case shifts, trim,
HTML strip, JSON pretty/minify, Base64 +/-, URL encode/decode, line
sort, line dedupe. Each transform returns nil on invalid input so
callers can show a failure toast rather than write garbage.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `transformAndCopy` RPC — protocol + service implementation

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

Reads an item's text body, applies the named transform, and routes the result through `pasteText`. Reply is the transformed string (or nil if transform failed / item is non-text). The `saveAsNew` flag is passed through to `pasteText` — default UI behavior is `true` (Apply produces a new history clip).

- [ ] **Step 1: Write the failing tests**

Append to `ClipboardXPCServiceTests.swift`:

```swift
    func testTransformAndCopyAppliesTransformAndPastes() throws {
        let item = try clip.append(.text("Hello WORLD"))
        let exp = expectation(description: "transform")
        var reply: String?
        service.transformAndCopy(
            itemID: item.id.rawValue, transform: "lowercase", saveAsNew: false
        ) { reply = $0; exp.fulfill() }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main"); DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        XCTAssertEqual(reply, "hello world")
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testTransformAndCopyReturnsNilForUnknownTransform() throws {
        let item = try clip.append(.text("hi"))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue, transform: "doesNotExist", saveAsNew: false
        ) { XCTAssertNil($0); exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func testTransformAndCopyReturnsNilForNonTextItem() throws {
        let blobID = try blobs.write(Data([0]))
        let item = try clip.append(.image(blobID: blobID, width: 1, height: 1))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue, transform: "lowercase", saveAsNew: false
        ) { XCTAssertNil($0); exp.fulfill() }
        wait(for: [exp], timeout: 1)
    }

    func testTransformAndCopySaveAsNewAppendsHistoryRecord() throws {
        let item = try clip.append(.text("Hello"))
        let exp = expectation(description: "transform")
        service.transformAndCopy(
            itemID: item.id.rawValue, transform: "uppercase", saveAsNew: true
        ) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        let mainExp = expectation(description: "main"); DispatchQueue.main.async { mainExp.fulfill() }
        wait(for: [mainExp], timeout: 1)

        let items = try clip.list(limit: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.preview, "HELLO")
        XCTAssertEqual(items.first?.sourceAppBundleID, "com.macallyouneed.app")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: FAIL — `transformAndCopy` method doesn't exist.

- [ ] **Step 3: Add to protocol**

In `ClipboardXPCProtocol.swift`:

```swift
    func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool,
                          reply: @escaping (String?) -> Void)
```

- [ ] **Step 4: Implement on the service**

In `ClipboardXPCService.swift`:

```swift
    public func transformAndCopy(
        itemID: String, transform: String, saveAsNew: Bool,
        reply: @escaping (String?) -> Void
    ) {
        guard let kind = TextTransform(rawValue: transform),
              let rid = RecordID(rawValue: itemID),
              let body = try? clip.body(for: rid),
              let sourceText = Self.plainText(from: body),
              let transformed = TextTransforms.apply(kind, to: sourceText)
        else { reply(nil); return }

        pasteText(text: transformed, plainText: true, saveAsNew: saveAsNew) { _ in
            reply(transformed)
        }
    }
```

- [ ] **Step 5: Add forwarding in the server**

In `ClipboardXPCServer.swift`:

```swift
    func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool,
                          reply: @escaping (String?) -> Void) {
        service.transformAndCopy(itemID: itemID, transform: transform, saveAsNew: saveAsNew, reply: reply)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
```

Expected: PASS — all four new tests green.

- [ ] **Step 7: Verify daemon + app build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift \
        ClipboardDaemon/ClipboardXPCServer.swift
git commit -m "$(cat <<'EOF'
feat(xpc): add transformAndCopy RPC

Reads source clip's text body, applies named TextTransform, routes
result through pasteText. Returns the transformed string to the
caller (or nil if the transform/item is invalid). saveAsNew controls
whether a history record is appended.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Extract `ClipboardXPCInteracting` async protocol

**Files:**
- Create: `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift`
- Create: `Shared/Tests/CoreTests/XPC/ClipboardXPCInteractingTests.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`

Async/await protocol the new `ClipboardDockModel` (Phase B) holds. Wraps the callback-based `ClipboardXPCProtocol` proxy. Tests verify the protocol exists and a mock conforms to it (real client is exercised end-to-end in Phase B integration).

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/CoreTests/XPC/ClipboardXPCInteractingTests.swift`:

```swift
@testable import Core
import XCTest

final class ClipboardXPCInteractingTests: XCTestCase {
    final class MockClient: ClipboardXPCInteracting {
        var listed = false
        func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
            listed = true
            return ClipboardXPCList(items: [], nextPageToken: nil)
        }
        func bodyText(forID id: String) async -> String? { nil }
        func paste(itemID: String, plainText: Bool) async -> String { "injected" }
        func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String { "injected" }
        func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String { "injected" }
        func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? { nil }
        func imageThumbnail(forID id: String, maxDim: Int) async -> Data? { nil }
        func listSnippets() async -> [SnippetXPCDTO] { [] }
    }

    func testMockSatisfiesProtocol() async {
        let m = MockClient()
        let list = await m.listItems(query: nil, pageToken: nil, limit: 10)
        XCTAssertEqual(list.items.count, 0)
        XCTAssertTrue(m.listed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCInteractingTests
```

Expected: FAIL — `ClipboardXPCInteracting` doesn't exist.

- [ ] **Step 3: Define the protocol**

Create `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift`:

```swift
import Foundation

public protocol ClipboardXPCInteracting: Sendable {
    func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList
    func bodyText(forID id: String) async -> String?
    func paste(itemID: String, plainText: Bool) async -> String
    func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String
    func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String
    func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String?
    func imageThumbnail(forID id: String, maxDim: Int) async -> Data?
    func listSnippets() async -> [SnippetXPCDTO]
}
```

- [ ] **Step 4: Conform `ClipboardXPCClient`**

Append to `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`, after the closing brace of the existing class:

```swift
extension ClipboardXPCClient: ClipboardXPCInteracting {
    public func listItems(query: String?, pageToken: String?, limit: Int) async -> ClipboardXPCList {
        await withCheckedContinuation { cont in
            let empty = ClipboardXPCList(items: [], nextPageToken: nil)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: empty)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: empty); return }
            proxy.listItems(query: query, pageToken: pageToken, limit: limit) { cont.resume(returning: $0) }
        }
    }

    public func bodyText(forID id: String) async -> String? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: nil); return }
            proxy.bodyText(forID: id) { cont.resume(returning: $0) }
        }
    }

    public func paste(itemID: String, plainText: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired"); return
            }
            proxy.paste(itemID: itemID, plainText: plainText) { cont.resume(returning: $0) }
        }
    }

    public func pasteMany(itemIDs: [String], delimiter: String, plainText: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired"); return
            }
            proxy.pasteMany(itemIDs: itemIDs, delimiter: delimiter, plainText: plainText) {
                cont.resume(returning: $0)
            }
        }
    }

    public func pasteText(text: String, plainText: Bool, saveAsNew: Bool) async -> String {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: "manualPasteRequired")
            }) as? ClipboardXPCProtocol else {
                cont.resume(returning: "manualPasteRequired"); return
            }
            proxy.pasteText(text: text, plainText: plainText, saveAsNew: saveAsNew) {
                cont.resume(returning: $0)
            }
        }
    }

    public func transformAndCopy(itemID: String, transform: String, saveAsNew: Bool) async -> String? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: nil); return }
            proxy.transformAndCopy(itemID: itemID, transform: transform, saveAsNew: saveAsNew) {
                cont.resume(returning: $0)
            }
        }
    }

    public func imageThumbnail(forID id: String, maxDim: Int) async -> Data? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: nil); return }
            proxy.imageThumbnail(forID: id, maxDim: maxDim) { cont.resume(returning: $0) }
        }
    }

    public func listSnippets() async -> [SnippetXPCDTO] {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: [])
            }) as? ClipboardXPCProtocol else { cont.resume(returning: []); return }
            proxy.listSnippets { cont.resume(returning: $0) }
        }
    }
}
```

`ClipboardXPCClient` already has reference semantics (`final class`); marking it `Sendable` would require `@unchecked Sendable` because `NSXPCConnection` is non-Sendable. The protocol's `Sendable` requirement allows callers to pass instances across actor boundaries; callers that need that will wrap in an actor or use `@unchecked Sendable`. For Phase A this is unused, so leave it — Phase B picks it up.

Actually to make `ClipboardXPCClient` itself satisfy the `Sendable` requirement on the protocol, add to the class declaration:

```swift
public final class ClipboardXPCClient: @unchecked Sendable {
```

This is the standard approach for AppKit/XPC types that are reference-semantics safe in practice.

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
```

Expected: PASS — `ClipboardXPCInteractingTests` green; full Shared suite still green.

- [ ] **Step 6: Verify daemon + app build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 7: Commit**

```bash
git add Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift \
        Shared/Sources/Core/XPC/ClipboardXPCClient.swift \
        Shared/Tests/CoreTests/XPC/ClipboardXPCInteractingTests.swift
git commit -m "$(cat <<'EOF'
feat(xpc): extract ClipboardXPCInteracting async protocol

Async/await wrapper over the callback-based XPC proxy. Real
ClipboardXPCClient conforms via withCheckedContinuation bridges that
return safe defaults on connection error. View-models in Phase B
hold any ClipboardXPCInteracting and unit tests pass mocks.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11.1: `bodyFileURLs` RPC

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

The UI layer needs file URLs for `FileCard` rendering, drag-out, and Quick Look. `bodyText` only handles text/html. Add a parallel RPC for `.files([URL])` records.

- [ ] **Step 1: Failing test**

```swift
    func testBodyFileURLsReturnsURLsForFilesRecord() throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        let item = try clip.append(.files(urls))
        let exp = expectation(description: "files")
        service.bodyFileURLs(forID: item.id.rawValue) { result in
            XCTAssertEqual(result, urls.map(\.path))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testBodyFileURLsReturnsNilForNonFilesRecord() throws {
        let item = try clip.append(.text("not files"))
        let exp = expectation(description: "files")
        service.bodyFileURLs(forID: item.id.rawValue) { result in
            XCTAssertNil(result)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
```

- [ ] **Step 2: Add to protocol**

```swift
    func bodyFileURLs(forID id: String, reply: @escaping ([String]?) -> Void)
```

(`[String]` of paths; UI converts back to URL.)

- [ ] **Step 3: Implement in service**

```swift
    public func bodyFileURLs(forID id: String, reply: @escaping ([String]?) -> Void) {
        guard let rid = RecordID(rawValue: id),
              let body = try? clip.body(for: rid),
              case let .files(urls) = body
        else { reply(nil); return }
        reply(urls.map(\.path))
    }
```

- [ ] **Step 4: Forward in server, add to interacting protocol + client extension**

In `ClipboardXPCInteracting`:

```swift
    func bodyFileURLs(forID id: String) async -> [String]?
```

In `ClipboardXPCClient` extension:

```swift
    public func bodyFileURLs(forID id: String) async -> [String]? {
        await withCheckedContinuation { cont in
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: nil)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: nil); return }
            proxy.bodyFileURLs(forID: id) { cont.resume(returning: $0) }
        }
    }
```

In `ClipboardXPCServer`:

```swift
    func bodyFileURLs(forID id: String, reply: @escaping ([String]?) -> Void) {
        service.bodyFileURLs(forID: id, reply: reply)
    }
```

- [ ] **Step 5: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift \
        Shared/Sources/Core/XPC/ClipboardXPCClient.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        ClipboardDaemon/ClipboardXPCServer.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift
git commit -m "feat(xpc): add bodyFileURLs RPC for file-kind records"
```

- [ ] **Step 6: Update MockClient in `ClipboardXPCInteractingTests.swift` to satisfy the extended protocol**

Add to that file's MockClient:

```swift
        func bodyFileURLs(forID id: String) async -> [String]? { nil }
```

Run `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` to confirm the suite still compiles, then amend the previous commit with `git commit --amend --no-edit`.

---

## Task 11.2: `metasByIDs` RPC

**Files:**
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift`
- Modify: `Shared/Sources/Platform/XPC/ClipboardXPCService.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Test: `Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift`

Phase C's Pinned and Pinboard tabs need to load specific item IDs regardless of recency. `ClipboardStore.metas(for:)` already supports arbitrary IDs; this RPC exposes it.

- [ ] **Step 1: Failing test**

```swift
    func testMetasByIDsReturnsRequestedItemsRegardlessOfRecency() throws {
        // Make 5 records, request the oldest two by ID.
        var metas: [ClipboardItemMeta] = []
        for i in 0..<5 {
            metas.append(try clip.append(.text("v\(i)")))
            Thread.sleep(forTimeInterval: 0.002)
        }
        let oldestTwo = [metas[0].id.rawValue, metas[1].id.rawValue]
        let exp = expectation(description: "metas")
        service.metasByIDs(ids: oldestTwo) { list in
            XCTAssertEqual(list.items.count, 2)
            XCTAssertEqual(Set(list.items.map(\.id)), Set(oldestTwo))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testMetasByIDsSkipsUnknownIDs() {
        let exp = expectation(description: "metas")
        service.metasByIDs(ids: ["01HFAKEFAKEFAKEFAKEFAKEFAK"]) { list in
            XCTAssertEqual(list.items.count, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
```

- [ ] **Step 2: Add to protocol**

```swift
    func metasByIDs(ids: [String], reply: @escaping (ClipboardXPCList) -> Void)
```

- [ ] **Step 3: Implement in service**

```swift
    public func metasByIDs(ids: [String], reply: @escaping (ClipboardXPCList) -> Void) {
        let recordIDs = ids.compactMap { RecordID(rawValue: $0) }
        let metas = (try? clip.metas(for: recordIDs)) ?? []
        let items = metas.map { meta -> ClipboardXPCMeta in
            var imgWidth = 0
            var imgHeight = 0
            var imgBlobID: String? = nil
            if meta.kind == .clipboardItem,
               let body = try? clip.body(for: meta.id),
               case let .image(blobID, w, h) = body {
                imgBlobID = blobID; imgWidth = w; imgHeight = h
            }
            return ClipboardXPCMeta(
                id: meta.id.rawValue, modified: meta.modified,
                kind: meta.kind.rawValue, preview: meta.preview,
                sourceAppBundleID: meta.sourceAppBundleID,
                imageWidth: imgWidth, imageHeight: imgHeight, imageBlobID: imgBlobID
            )
        }
        reply(ClipboardXPCList(items: items, nextPageToken: nil))
    }
```

- [ ] **Step 4: Forward, async wrapper, allowed classes**

`ClipboardXPCInteracting`:

```swift
    func metasByIDs(ids: [String]) async -> ClipboardXPCList
```

`ClipboardXPCClient` extension:

```swift
    public func metasByIDs(ids: [String]) async -> ClipboardXPCList {
        await withCheckedContinuation { cont in
            let empty = ClipboardXPCList(items: [], nextPageToken: nil)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                cont.resume(returning: empty)
            }) as? ClipboardXPCProtocol else { cont.resume(returning: empty); return }
            proxy.metasByIDs(ids: ids) { cont.resume(returning: $0) }
        }
    }
```

`ClipboardXPCServer`:

```swift
    func metasByIDs(ids: [String], reply: @escaping (ClipboardXPCList) -> Void) {
        service.metasByIDs(ids: ids, reply: reply)
    }
```

- [ ] **Step 5: Run + commit**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ClipboardXPCServiceTests
git add Shared/Sources/Core/XPC/ClipboardXPCProtocol.swift \
        Shared/Sources/Core/XPC/ClipboardXPCInteracting.swift \
        Shared/Sources/Core/XPC/ClipboardXPCClient.swift \
        Shared/Sources/Platform/XPC/ClipboardXPCService.swift \
        ClipboardDaemon/ClipboardXPCServer.swift \
        Shared/Tests/PlatformTests/XPC/ClipboardXPCServiceTests.swift
git commit -m "feat(xpc): add metasByIDs RPC for bulk-by-ID lookup (Pinned tabs)"
```

- [ ] **Step 6: Update MockClient in `ClipboardXPCInteractingTests.swift` to satisfy the extended protocol**

Add to that file's MockClient:

```swift
        func metasByIDs(ids: [String]) async -> ClipboardXPCList {
            ClipboardXPCList(items: [], nextPageToken: nil)
        }
```

Run `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`; amend with `git commit --amend --no-edit`.

---

## Task 12: Complete server-side `iface.setClasses` for all new RPCs

**Files:**
- Modify: `ClipboardDaemon/ClipboardXPCServer.swift`
- Modify: `Shared/Sources/Core/XPC/ClipboardXPCClient.swift`

Phase A's earlier tasks added new RPCs but the server's `iface.setClasses(...)` registrations only cover `listItems` and `resolveBlob` (inherited from before the redesign). Without complete registration, NSXPC will reject decodes at runtime. The Phase A tests don't catch this because they bypass the XPC machinery — only manual smoke or daemon-vs-app integration would reveal it. This task adds every missing entry on both sides.

- [ ] **Step 1: Update server `iface.setClasses` block**

In `ClipboardDaemon/ClipboardXPCServer.swift`, in `listener(_:shouldAcceptNewConnection:)`, replace the `allowed` set + `iface.setClasses` calls with the complete set:

```swift
        let iface = NSXPCInterface(with: ClipboardXPCProtocol.self)
        let allowed: Set<AnyHashable> = [
            ClipboardXPCList.self,
            ClipboardXPCBlobRef.self,
            NSArray.self,
            ClipboardXPCMeta.self,
            SnippetXPCDTO.self,
            NSString.self,
            NSDate.self,
            NSNumber.self,
            NSData.self
        ]
        // Replies that decode rich object graphs.
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.listItems(query:pageToken:limit:reply:)),
            argumentIndex: 0, ofReply: true)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.metasByIDs(ids:reply:)),
            argumentIndex: 0, ofReply: true)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.resolveBlob(blobID:reply:)),
            argumentIndex: 0, ofReply: true)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.imageThumbnail(forID:maxDim:reply:)),
            argumentIndex: 0, ofReply: true)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.bodyFileURLs(forID:reply:)),
            argumentIndex: 0, ofReply: true)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.listSnippets(reply:)),
            argumentIndex: 0, ofReply: true)
        // Arguments that arrive as collections.
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.pasteMany(itemIDs:delimiter:plainText:reply:)),
            argumentIndex: 0, ofReply: false)
        iface.setClasses(allowed,
            for: #selector(ClipboardXPCProtocol.metasByIDs(ids:reply:)),
            argumentIndex: 0, ofReply: false)
```

- [ ] **Step 2: Mirror on client**

In `ClipboardXPCClient.swift`, the `allowed` `NSSet` already includes `NSData` from Task 6. Add `iface.setClasses` calls for every new RPC's reply (same pattern as server). The client-side `setClasses(...)` calls live in the `init(serviceName:resumesImmediately:)` block.

- [ ] **Step 3: Build + commit**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
git add ClipboardDaemon/ClipboardXPCServer.swift Shared/Sources/Core/XPC/ClipboardXPCClient.swift
git commit -m "$(cat <<'EOF'
fix(xpc): complete iface.setClasses for every new RPC, both sides

Previously only listItems + resolveBlob had explicit class
registration. NSXPC would reject runtime decodes for imageThumbnail
(Data/NSData reply), pasteMany ([String] arg), metasByIDs
(both arg + reply), bodyFileURLs (NSArray<NSString> reply). Now
covers every method on both server (request side) and client
(reply side).

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Phase A — Done

End-state of Phase A:

- New XPC wire format ships with `sourceAppBundleID`, `imageWidth/Height`, `imageBlobID`. Backward-compatible decode verified by contract test.
- New RPCs: `imageThumbnail`, `pasteMany`, `pasteText`, `transformAndCopy`, `bodyFileURLs`, `metasByIDs`. All implemented daemon-side with unit-test coverage.
- Self-write suppression sentinel UTI prevents the daemon from re-recording its own pasteboard writes.
- Helpers `ThumbnailRenderer`, `ThumbnailCache`, `TextTransforms` live in `Shared/Sources/Platform/`.
- `ClipboardXPCService` cleanly extracted from the daemon's listener — pure, testable.
- `ClipboardXPCInteracting` async protocol ready for Phase B's `ClipboardDockModel`.
- Complete `iface.setClasses` registration on both client and server for every new RPC.
- Existing UI (centered floating popup) unchanged; user experience unchanged.

Run the full test suite and a clean build to confirm green:

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build 2>&1 | tail -5
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon -configuration Debug build 2>&1 | tail -5
```

Expected: all tests green, both targets build.

---

## What comes next

Phases B–F each get their own plan document, written when the previous phase lands. They are listed in spec §15 and proceed in order:

- **Phase B — Visual overhaul.** New `ClipboardDock` module, `BottomDockWindow`, slide-up animation, polymorphic `ClipCard`, source-app gradient. Depends on Phase A's `imageThumbnail` and `ClipboardXPCInteracting`.
- **Phase C — Top bar & Pinboards.** `DockTopBar`, list tabs, `+` new list, `ShortcutRegistry` + Settings tab.
- **Phase D — Power features.** Multi-select bar, `pasteMany` wiring, Quick Look, transformations menu (uses Phase A's `transformAndCopy`), drag-out, color-picker actions.
- **Phase E — Maccy improvements.** Privacy controls, regex blocklist, storage caps, fuzzy search, sort-by-frequency, suspend-capture, auto-paste behavior toggle. Includes the `frequency`/`last_accessed` migration.
- **Phase F — Snippets surfacing.** `.snippets` tab, snippet CRUD sheet (uses Phase A's `pasteText`).

Each subsequent plan will reference specific Phase A artifacts (the new RPC methods, helpers, protocols) by name.
