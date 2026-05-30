# Dock-Hover Window Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a DockDoor-style floating preview panel that appears when the user hovers an app's Dock icon, showing thumbnails of all that app's windows and raising the exact window on click, shipped as an opt-in gated feature that degrades to a title-only list when Screen Recording is denied.

**Architecture:** A `@MainActor @Observable DockPreviewCoordinator` (static let on `AppController`, mirroring `WindowControlCoordinator`) wires a Dock hover observer (built on shared **S1 `AXObserverCoordinator`**) → a per-PID window enumerator/cache (ScreenCaptureKit on-screen + AX off-screen, merged) → a thumbnail/live-capture service → a borderless non-activating `NSPanel` (`MAYNTheme`-styled, click-to-raise). All private CGS/SkyLight symbols are isolated behind one `DockPreviewPrivateAPI` seam, and every hard-to-test boundary (AX observer, capture, raise, SCStream) sits behind an injectable protocol so the pure logic (cache, concurrency cap, AX↔SC matching, positioning math, permission gating, enum additions) is unit-tested in CI.

**Tech Stack:** Swift 5.9+, SwiftUI/AppKit (NSPanel), ScreenCaptureKit, ApplicationServices (AX), private CGS/SkyLight (dlopen), XCTest

---

## File Structure

```
Shared/Sources/FeatureCore/
  FeatureID.swift                                  # + .dockPreviews case
  FeatureDescriptor.swift                          # + Permission.screenRecording case
Shared/Tests/FeatureCoreTests/
  DockPreviewsFeatureCoreTests.swift               # NEW — enum additions

MacAllYouNeed/DockPreviews/                         # NEW directory
  DockPreviewPrivateAPI.swift                      # @_silgen_name + dlopen loader (seam)
  DockPreviewWindowEntry.swift                     # value model
  DockPreviewWindowCache.swift                     # per-PID cache + diff
  DockPreviewWindowMatcher.swift                   # AX↔SC merge logic (pure)
  DockPreviewCaptureScheduler.swift               # concurrency-cap queue (pure-ish)
  DockPreviewThumbnailCache.swift                  # lifespan cache + injected clock
  DockPreviewPanelGeometry.swift                   # Quartz↔Cocoa flip + anchoring (pure)
  DockPreviewPermissionGate.swift                  # denied → title-only decision (pure)
  DockHoverObserver.swift                          # S1 consumer + protocol seam
  DockPreviewWindowEnumerator.swift                # SCK + AX enumeration (protocol seam)
  DockPreviewThumbnailService.swift               # CGSHWCaptureWindowList (seam)
  DockPreviewLiveCaptureManager.swift             # optional SCStream (seam)
  DockPreviewRaiseService.swift                    # un-minimize + SkyLight + activate (seam)
  DockPreviewSeeder.swift                          # launch-time cache seed
  DockPreviewCoordinator.swift                     # @MainActor @Observable owner
  DockPreviewPanel.swift                           # borderless NSPanel + SwiftUI
  DockPreviewPanelView.swift                       # SwiftUI card strip (MAYNTheme)
  DockPreviewSettings.swift                        # settings model + store
  DockPreviewSettingsView.swift                    # tool page (FunctionPageShell)
  DockPreviewsFeatureActivator.swift              # FeatureActivator

MacAllYouNeed/App/Descriptors/
  DockPreviewsDescriptor.swift                     # NEW — gated descriptor
MacAllYouNeed/Settings/
  PermissionsSettingsView.swift                    # + screenRecordingStatus provider
MacAllYouNeed/Settings/Permissions/
  ScreenRecordingPermissionRow.swift               # NEW — PermissionCard wrapper

MacAllYouNeed/MacAllYouNeed.entitlements           # Screen Recording usage note (Info.plist)
project.yml                                         # NSScreenRecordingUsageDescription / file refs

MacAllYouNeedTests/DockPreviews/                    # NEW
  DockPreviewWindowCacheTests.swift
  DockPreviewWindowMatcherTests.swift
  DockPreviewCaptureSchedulerTests.swift
  DockPreviewThumbnailCacheTests.swift
  DockPreviewPanelGeometryTests.swift
  DockPreviewPermissionGateTests.swift
  DockPreviewCoordinatorTests.swift
```

> **Assumption (S1):** shared `AXObserverCoordinator` already exists and exposes
> child-element notification subscription (`kAXSelectedChildrenChangedNotification`
> on an arbitrary `AXUIElement` such as the Dock `AXList`) plus a health-check
> re-subscribe + target-PID-change rebuild. `DockHoverObserver` consumes it; it
> does not re-implement AX run-loop plumbing.

**Test commands:**
- App: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- Shared: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- After `project.yml`/entitlement changes: `xcodegen generate`

---

### Task 1 — Add `Permission.screenRecording` case

**Files:** `Shared/Sources/FeatureCore/FeatureDescriptor.swift:4-9`; test `Shared/Tests/FeatureCoreTests/DockPreviewsFeatureCoreTests.swift` (new).

- [ ] Write failing test asserting the new case round-trips through `Codable`:
  ```swift
  import XCTest
  @testable import FeatureCore

  final class DockPreviewsFeatureCoreTests: XCTestCase {
      func testScreenRecordingPermissionRawValueIsStable() throws {
          XCTAssertEqual(Permission.screenRecording.rawValue, "screenRecording")
          let data = try JSONEncoder().encode(Permission.screenRecording)
          let decoded = try JSONDecoder().decode(Permission.self, from: data)
          XCTAssertEqual(decoded, .screenRecording)
      }
  }
  ```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter DockPreviewsFeatureCoreTests` → expected: compile error, `type 'Permission' has no member 'screenRecording'`.
- [ ] Minimal impl: add `case screenRecording` to the `Permission` enum:
  ```swift
  public enum Permission: String, Sendable, Codable, Hashable {
      case accessibility
      case fullDiskAccess
      case microphone
      case notifications
      case screenRecording
  }
  ```
- [ ] Run-pass: same `swift test --filter DockPreviewsFeatureCoreTests` → green.
- [ ] Commit:
  ```
  git add Shared/Sources/FeatureCore/FeatureDescriptor.swift Shared/Tests/FeatureCoreTests/DockPreviewsFeatureCoreTests.swift && git commit -m "feat(featurecore): add screenRecording permission case

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 2 — Add `FeatureID.dockPreviews` case

**Files:** `Shared/Sources/FeatureCore/FeatureID.swift:3-10`; test `Shared/Tests/FeatureCoreTests/DockPreviewsFeatureCoreTests.swift`.

- [ ] Add failing test (append to existing test file):
  ```swift
  func testDockPreviewsFeatureIDIsRegistered() throws {
      XCTAssertEqual(FeatureID.dockPreviews.rawValue, "dockPreviews")
      XCTAssertTrue(FeatureID.allCases.contains(.dockPreviews))
      let decoded = try JSONDecoder().decode(
          FeatureID.self, from: try JSONEncoder().encode(FeatureID.dockPreviews))
      XCTAssertEqual(decoded, .dockPreviews)
  }
  ```
- [ ] Run-fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter DockPreviewsFeatureCoreTests` → expected: `type 'FeatureID' has no member 'dockPreviews'`.
- [ ] Minimal impl: add `case dockPreviews` after `case windowGrab` in `FeatureID`.
- [ ] Run-pass: same filter → green.
- [ ] Commit:
  ```
  git add Shared/Sources/FeatureCore/FeatureID.swift Shared/Tests/FeatureCoreTests/DockPreviewsFeatureCoreTests.swift && git commit -m "feat(featurecore): add dockPreviews feature id

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 3 — `DockPreviewWindowEntry` value model

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowEntry.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewWindowCacheTests.swift` (new, model section).

- [ ] Failing test — identity is keyed on `windowID`, equatable by id, hashable:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import MacAllYouNeed

  final class DockPreviewWindowCacheTests: XCTestCase {
      private func entry(_ id: CGWindowID, pid: pid_t = 100, title: String = "W") -> DockPreviewWindowEntry {
          DockPreviewWindowEntry(windowID: id, pid: pid, title: title,
                                 frame: .zero, isMinimized: false, isHidden: false,
                                 spaceIDs: [], lastAccessed: Date(timeIntervalSince1970: 0))
      }
      func testEntryEqualityKeyedOnWindowID() {
          XCTAssertEqual(entry(1, title: "A"), entry(1, title: "B"))
          XCTAssertNotEqual(entry(1), entry(2))
          XCTAssertEqual(Set([entry(1, title: "A"), entry(1, title: "B")]).count, 1)
      }
  }
  ```
- [ ] Run-fail: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/DockPreviewWindowCacheTests` → expected: `cannot find 'DockPreviewWindowEntry'`.
- [ ] Minimal impl:
  ```swift
  import CoreGraphics
  import Foundation

  struct DockPreviewWindowEntry: Hashable {
      let windowID: CGWindowID
      var pid: pid_t
      var title: String
      var frame: CGRect
      var isMinimized: Bool
      var isHidden: Bool
      var spaceIDs: [Int]
      var lastAccessed: Date

      static func == (lhs: Self, rhs: Self) -> Bool { lhs.windowID == rhs.windowID }
      func hash(into hasher: inout Hasher) { hasher.combine(windowID) }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewWindowEntry.swift MacAllYouNeedTests/DockPreviews/DockPreviewWindowCacheTests.swift && git commit -m "feat(dockpreviews): add window entry value model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 4 — `DockPreviewWindowCache` insert/lookup/evict + change signal

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowCache.swift` (new); test append to `MacAllYouNeedTests/DockPreviews/DockPreviewWindowCacheTests.swift`.

- [ ] Failing tests — diff-on-write emits one "changed PID" signal, lookup returns set, replace updates:
  ```swift
  func testReplaceEmitsChangeAndStoresWindows() {
      let cache = DockPreviewWindowCache()
      var changed: [pid_t] = []
      cache.onChange = { changed.append($0) }
      cache.replace(pid: 100, windows: [entry(1), entry(2)])
      XCTAssertEqual(cache.windows(for: 100).count, 2)
      XCTAssertEqual(changed, [100])
  }
  func testReplaceWithIdenticalSetDoesNotSignal() {
      let cache = DockPreviewWindowCache()
      cache.replace(pid: 100, windows: [entry(1)])
      var changed: [pid_t] = []
      cache.onChange = { changed.append($0) }
      cache.replace(pid: 100, windows: [entry(1)])
      XCTAssertTrue(changed.isEmpty)
  }
  func testEvictRemovesPID() {
      let cache = DockPreviewWindowCache()
      cache.replace(pid: 100, windows: [entry(1)])
      cache.evict(pid: 100)
      XCTAssertTrue(cache.windows(for: 100).isEmpty)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewWindowCacheTests` → expected: `cannot find 'DockPreviewWindowCache'`.
- [ ] Minimal impl: lock-guarded `[pid_t: Set<DockPreviewWindowEntry>]`; `replace` diffs against existing set (equality on `windowID` only, so also compare a content fingerprint of titles/minimized to detect updates) and fires `onChange(pid)` only when the merged set changes; `windows(for:)` and `evict(pid:)`:
  ```swift
  import Foundation

  final class DockPreviewWindowCache {
      var onChange: ((pid_t) -> Void)?
      private let lock = NSLock()
      private var store: [pid_t: Set<DockPreviewWindowEntry>] = [:]

      func windows(for pid: pid_t) -> Set<DockPreviewWindowEntry> {
          lock.lock(); defer { lock.unlock() }
          return store[pid] ?? []
      }
      func replace(pid: pid_t, windows: [DockPreviewWindowEntry]) {
          let new = Set(windows)
          lock.lock()
          let changed = !Self.equalContent(store[pid] ?? [], new)
          store[pid] = new
          lock.unlock()
          if changed { onChange?(pid) }
      }
      func evict(pid: pid_t) {
          lock.lock(); let had = store.removeValue(forKey: pid) != nil; lock.unlock()
          if had { onChange?(pid) }
      }
      private static func equalContent(_ a: Set<DockPreviewWindowEntry>, _ b: Set<DockPreviewWindowEntry>) -> Bool {
          guard a.count == b.count else { return false }
          let byID = Dictionary(uniqueKeysWithValues: a.map { ($0.windowID, $0) })
          for w in b {
              guard let old = byID[w.windowID],
                    old.title == w.title, old.isMinimized == w.isMinimized,
                    old.isHidden == w.isHidden, old.frame == w.frame else { return false }
          }
          return true
      }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewWindowCache.swift MacAllYouNeedTests/DockPreviews/DockPreviewWindowCacheTests.swift && git commit -m "feat(dockpreviews): add per-pid window cache with diff signal

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 5 — Cache thread safety under parallel writes

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowCache.swift` (verify, no new code expected); test append to `DockPreviewWindowCacheTests.swift`.

- [ ] Failing/regression test — concurrent writers and readers do not crash and end consistent:
  ```swift
  func testConcurrentWritesAreSafe() {
      let cache = DockPreviewWindowCache()
      let group = DispatchGroup()
      for pid in 0..<50 {
          group.enter()
          DispatchQueue.global().async {
              cache.replace(pid: pid_t(pid), windows: [self.entry(CGWindowID(pid), pid: pid_t(pid))])
              _ = cache.windows(for: pid_t(pid))
              group.leave()
          }
      }
      XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
      XCTAssertEqual(cache.windows(for: 10).count, 1)
  }
  ```
- [ ] Run-fail: run under TSan once locally — `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewWindowCacheTests -enableThreadSanitizer YES`. If `onChange` reentrancy under lock causes issues, the test surfaces it.
- [ ] Minimal impl: ensure `onChange` is invoked **outside** the lock (already true in Task 4) — adjust only if TSan flags. No new code if green.
- [ ] Run-pass: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewWindowCacheTests` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeedTests/DockPreviews/DockPreviewWindowCacheTests.swift && git commit -m "test(dockpreviews): cover cache concurrency safety

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 6 — `DockPreviewWindowMatcher` AX↔SC merge logic

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowMatcher.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewWindowMatcherTests.swift` (new).

- [ ] Failing tests — dedupe by `windowID`; fall back to title+frame fingerprint when an AX source has no id; AX state (minimized/hidden) wins over SC for matched windows:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import MacAllYouNeed

  final class DockPreviewWindowMatcherTests: XCTestCase {
      func testMergeDedupesByWindowID() {
          let sc = [DockPreviewSourceWindow(windowID: 1, title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10), isMinimized: false, isHidden: false)]
          let ax = [DockPreviewSourceWindow(windowID: 1, title: "A", frame: CGRect(x: 0, y: 0, width: 10, height: 10), isMinimized: true, isHidden: false)]
          let merged = DockPreviewWindowMatcher.merge(pid: 7, sc: sc, ax: ax)
          XCTAssertEqual(merged.count, 1)
          XCTAssertTrue(merged[0].isMinimized) // AX state wins
      }
      func testMergeFallsBackToTitleFrameWhenAXHasNoWindowID() {
          let sc = [DockPreviewSourceWindow(windowID: 5, title: "Doc", frame: CGRect(x: 1, y: 2, width: 3, height: 4), isMinimized: false, isHidden: false)]
          let ax = [DockPreviewSourceWindow(windowID: 0, title: "Doc", frame: CGRect(x: 1, y: 2, width: 3, height: 4), isMinimized: true, isHidden: false)]
          let merged = DockPreviewWindowMatcher.merge(pid: 7, sc: sc, ax: ax)
          XCTAssertEqual(merged.count, 1)
          XCTAssertEqual(merged[0].windowID, 5)
          XCTAssertTrue(merged[0].isMinimized)
      }
      func testMergeKeepsAXOnlyWindows() {
          let ax = [DockPreviewSourceWindow(windowID: 9, title: "Off", frame: .zero, isMinimized: true, isHidden: false)]
          XCTAssertEqual(DockPreviewWindowMatcher.merge(pid: 7, sc: [], ax: ax).count, 1)
      }
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewWindowMatcherTests` → expected: `cannot find 'DockPreviewSourceWindow'`.
- [ ] Minimal impl: define `DockPreviewSourceWindow` (raw source value, `windowID == 0` means "id unknown") and pure `merge`:
  ```swift
  import CoreGraphics
  import Foundation

  struct DockPreviewSourceWindow {
      var windowID: CGWindowID
      var title: String
      var frame: CGRect
      var isMinimized: Bool
      var isHidden: Bool
  }

  enum DockPreviewWindowMatcher {
      static func merge(pid: pid_t, sc: [DockPreviewSourceWindow], ax: [DockPreviewSourceWindow]) -> [DockPreviewWindowEntry] {
          var byID: [CGWindowID: DockPreviewSourceWindow] = [:]
          for w in sc where w.windowID != 0 { byID[w.windowID] = w }
          func fingerprint(_ w: DockPreviewSourceWindow) -> String { "\(w.title)|\(w.frame.integral)" }
          var fpToID: [String: CGWindowID] = [:]
          for w in sc where w.windowID != 0 { fpToID[fingerprint(w)] = w.windowID }

          for a in ax {
              if a.windowID != 0, var base = byID[a.windowID] {
                  base.isMinimized = a.isMinimized; base.isHidden = a.isHidden
                  byID[a.windowID] = base
              } else if a.windowID == 0, let id = fpToID[fingerprint(a)], var base = byID[id] {
                  base.isMinimized = a.isMinimized; base.isHidden = a.isHidden
                  byID[id] = base
              } else if a.windowID != 0 {
                  byID[a.windowID] = a
              }
              // AX windows with windowID == 0 and no SC match are dropped (no stable key).
          }
          return byID.values.map {
              DockPreviewWindowEntry(windowID: $0.windowID, pid: pid, title: $0.title,
                                     frame: $0.frame, isMinimized: $0.isMinimized,
                                     isHidden: $0.isHidden, spaceIDs: [], lastAccessed: Date())
          }
      }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewWindowMatcher.swift MacAllYouNeedTests/DockPreviews/DockPreviewWindowMatcherTests.swift && git commit -m "feat(dockpreviews): add AX/SC window merge logic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 7 — `DockPreviewCaptureScheduler` concurrency-cap queue

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewCaptureScheduler.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewCaptureSchedulerTests.swift` (new).

- [ ] Failing tests — never more than N concurrent in flight, all tasks complete, results returned:
  ```swift
  import XCTest
  @testable import MacAllYouNeed

  final class DockPreviewCaptureSchedulerTests: XCTestCase {
      func testNeverExceedsConcurrencyCap() async {
          let scheduler = DockPreviewCaptureScheduler(maxConcurrent: 4)
          let counter = ConcurrencyCounter()
          let results = await scheduler.run(items: Array(0..<20)) { i -> Int in
              await counter.enter()
              try? await Task.sleep(nanoseconds: 1_000_000)
              await counter.leave()
              return i * 2
          }
          XCTAssertEqual(results.sorted(), (0..<20).map { $0 * 2 })
          let peak = await counter.peak
          XCTAssertLessThanOrEqual(peak, 4)
      }
  }

  actor ConcurrencyCounter {
      private var current = 0
      private(set) var peak = 0
      func enter() { current += 1; peak = max(peak, current) }
      func leave() { current -= 1 }
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCaptureSchedulerTests` → expected: `cannot find 'DockPreviewCaptureScheduler'`.
- [ ] Minimal impl: bounded fan-out over a `TaskGroup`, capping live children at `maxConcurrent`:
  ```swift
  import Foundation

  struct DockPreviewCaptureScheduler {
      let maxConcurrent: Int

      func run<Item: Sendable, Output: Sendable>(
          items: [Item],
          operation: @escaping @Sendable (Item) async -> Output
      ) async -> [Output] {
          guard maxConcurrent > 0 else { return [] }
          var results: [Output] = []
          results.reserveCapacity(items.count)
          var iterator = items.makeIterator()
          await withTaskGroup(of: Output.self) { group in
              var inFlight = 0
              while inFlight < maxConcurrent, let next = iterator.next() {
                  group.addTask { await operation(next) }
                  inFlight += 1
              }
              while let r = await group.next() {
                  results.append(r)
                  if let next = iterator.next() { group.addTask { await operation(next) } }
              }
          }
          return results
      }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewCaptureScheduler.swift MacAllYouNeedTests/DockPreviews/DockPreviewCaptureSchedulerTests.swift && git commit -m "feat(dockpreviews): add concurrency-capped capture scheduler

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 8 — `DockPreviewThumbnailCache` lifespan with injected clock

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewThumbnailCache.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewThumbnailCacheTests.swift` (new).

- [ ] Failing tests — fresh entries reuse, expired entries report stale, store overwrites timestamp:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import MacAllYouNeed

  final class DockPreviewThumbnailCacheTests: XCTestCase {
      private func image() -> CGImage {
          let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          return ctx.makeImage()!
      }
      func testFreshEntryIsReused() {
          var now = Date(timeIntervalSince1970: 0)
          let cache = DockPreviewThumbnailCache(lifespan: 5, now: { now })
          cache.store(windowID: 1, image: image())
          now = Date(timeIntervalSince1970: 3)
          XCTAssertNotNil(cache.valid(windowID: 1))
      }
      func testExpiredEntryReturnsNil() {
          var now = Date(timeIntervalSince1970: 0)
          let cache = DockPreviewThumbnailCache(lifespan: 5, now: { now })
          cache.store(windowID: 1, image: image())
          now = Date(timeIntervalSince1970: 6)
          XCTAssertNil(cache.valid(windowID: 1))
          XCTAssertNotNil(cache.lastKnown(windowID: 1)) // kept for minimized fallback
      }
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewThumbnailCacheTests` → expected: `cannot find 'DockPreviewThumbnailCache'`.
- [ ] Minimal impl: keyed by `CGWindowID`, stores image + timestamp; `valid` returns image only within lifespan, `lastKnown` always returns the last stored image:
  ```swift
  import CoreGraphics
  import Foundation

  final class DockPreviewThumbnailCache {
      private struct Item { let image: CGImage; let at: Date }
      private let lifespan: TimeInterval
      private let now: () -> Date
      private let lock = NSLock()
      private var store: [CGWindowID: Item] = [:]

      init(lifespan: TimeInterval, now: @escaping () -> Date = Date.init) {
          self.lifespan = lifespan; self.now = now
      }
      func store(windowID: CGWindowID, image: CGImage) {
          lock.lock(); store[windowID] = Item(image: image, at: now()); lock.unlock()
      }
      func valid(windowID: CGWindowID) -> CGImage? {
          lock.lock(); defer { lock.unlock() }
          guard let item = store[windowID], now().timeIntervalSince(item.at) <= lifespan else { return nil }
          return item.image
      }
      func lastKnown(windowID: CGWindowID) -> CGImage? {
          lock.lock(); defer { lock.unlock() }
          return store[windowID]?.image
      }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewThumbnailCache.swift MacAllYouNeedTests/DockPreviews/DockPreviewThumbnailCacheTests.swift && git commit -m "feat(dockpreviews): add thumbnail cache with lifespan

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 9 — `DockPreviewPanelGeometry` Quartz↔Cocoa flip + anchoring

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewPanelGeometry.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewPanelGeometryTests.swift` (new).

- [ ] Failing tests — flip from top-left (AX) to bottom-left (Cocoa) on a fixture screen; anchor offsets toward interior per Dock edge; clamp to screen:
  ```swift
  import XCTest
  import CoreGraphics
  @testable import MacAllYouNeed

  final class DockPreviewPanelGeometryTests: XCTestCase {
      // Screen 1440x900 at Cocoa origin (0,0). AX rect uses top-left origin.
      let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

      func testFlipTopLeftAXRectToCocoa() {
          // AX item: 40pt tall at top-left y=860 (near bottom of screen visually).
          let axItem = CGRect(x: 700, y: 860, width: 64, height: 40)
          let cocoa = DockPreviewPanelGeometry.cocoaRect(fromAXRect: axItem, onScreen: screen)
          // Cocoa y = screenHeight - (axY + height) = 900 - 900 = 0
          XCTAssertEqual(cocoa.origin.y, 0, accuracy: 0.01)
          XCTAssertEqual(cocoa.origin.x, 700, accuracy: 0.01)
      }

      func testBottomDockPanelSitsAboveItemAndClamps() {
          let item = CGRect(x: 700, y: 0, width: 64, height: 40) // Cocoa, bottom Dock
          let panel = CGSize(width: 320, height: 200)
          let origin = DockPreviewPanelGeometry.panelOrigin(
              dockEdge: .bottom, itemRectCocoa: item, panelSize: panel, screen: screen)
          XCTAssertEqual(origin.y, 40, accuracy: 0.01)        // above the item
          XCTAssertEqual(origin.x, 700 + 32 - 160, accuracy: 0.01) // centered on item
      }

      func testLeftDockPanelSitsRightOfItem() {
          let item = CGRect(x: 0, y: 400, width: 40, height: 64) // Cocoa, left Dock
          let panel = CGSize(width: 320, height: 200)
          let origin = DockPreviewPanelGeometry.panelOrigin(
              dockEdge: .left, itemRectCocoa: item, panelSize: panel, screen: screen)
          XCTAssertEqual(origin.x, 40, accuracy: 0.01)
      }

      func testClampKeepsPanelOnScreen() {
          let item = CGRect(x: 1430, y: 0, width: 10, height: 40)
          let panel = CGSize(width: 320, height: 200)
          let origin = DockPreviewPanelGeometry.panelOrigin(
              dockEdge: .bottom, itemRectCocoa: item, panelSize: panel, screen: screen)
          XCTAssertLessThanOrEqual(origin.x + panel.width, screen.maxX)
      }
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewPanelGeometryTests` → expected: `cannot find 'DockPreviewPanelGeometry'`.
- [ ] Minimal impl: `DockEdge { case bottom, left, right }`; `cocoaRect(fromAXRect:onScreen:)` does `y = screen.maxY - (axRect.origin.y + axRect.height)`; `panelOrigin` centers along the Dock axis, offsets toward interior off the edge, then clamps to `screen`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewPanelGeometry.swift MacAllYouNeedTests/DockPreviews/DockPreviewPanelGeometryTests.swift && git commit -m "feat(dockpreviews): add panel positioning geometry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 10 — `DockPreviewPermissionGate` denied→title-only decision

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewPermissionGate.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewPermissionGateTests.swift` (new).

- [ ] Failing tests — accessibility required hard; screen-recording denied → title-only; live requires SR:
  ```swift
  import XCTest
  @testable import MacAllYouNeed

  final class DockPreviewPermissionGateTests: XCTestCase {
      func testAccessibilityDeniedDisablesFeature() {
          let mode = DockPreviewPermissionGate.mode(accessibility: false, screenRecording: true, liveRequested: true)
          XCTAssertEqual(mode, .disabled)
      }
      func testScreenRecordingDeniedFallsBackToTitleOnly() {
          let mode = DockPreviewPermissionGate.mode(accessibility: true, screenRecording: false, liveRequested: false)
          XCTAssertEqual(mode, .titleOnly)
      }
      func testGrantedAllowsThumbnails() {
          XCTAssertEqual(
              DockPreviewPermissionGate.mode(accessibility: true, screenRecording: true, liveRequested: false), .thumbnails)
      }
      func testLiveOnlyWhenGrantedAndRequested() {
          XCTAssertEqual(
              DockPreviewPermissionGate.mode(accessibility: true, screenRecording: true, liveRequested: true), .live)
          XCTAssertEqual(
              DockPreviewPermissionGate.mode(accessibility: true, screenRecording: false, liveRequested: true), .titleOnly)
      }
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewPermissionGateTests` → expected: `cannot find 'DockPreviewPermissionGate'`.
- [ ] Minimal impl:
  ```swift
  enum DockPreviewMode: Equatable { case disabled, titleOnly, thumbnails, live }

  enum DockPreviewPermissionGate {
      static func mode(accessibility: Bool, screenRecording: Bool, liveRequested: Bool) -> DockPreviewMode {
          guard accessibility else { return .disabled }
          guard screenRecording else { return .titleOnly }
          return liveRequested ? .live : .thumbnails
      }
  }
  ```
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewPermissionGate.swift MacAllYouNeedTests/DockPreviews/DockPreviewPermissionGateTests.swift && git commit -m "feat(dockpreviews): add permission-mode gating logic

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 11 — Screen Recording status provider

**Files:** `MacAllYouNeed/Settings/PermissionsSettingsView.swift` (add provider near line 30-90); test `MacAllYouNeedTests/DockPreviews/DockPreviewPermissionGateTests.swift` (append) or reuse existing permission test target.

- [ ] Failing test — `PermissionStatusProvider.screenRecordingStatus(isGranted:)` maps to display state like microphone:
  ```swift
  func testScreenRecordingStatusMapping() {
      XCTAssertEqual(PermissionStatusProvider.screenRecordingStatus(isGranted: true), .granted)
      XCTAssertEqual(PermissionStatusProvider.screenRecordingStatus(isGranted: false), .denied)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewPermissionGateTests` → expected: `type 'PermissionStatusProvider' has no member 'screenRecordingStatus'`.
- [ ] Minimal impl: add to `PermissionStatusProvider`:
  ```swift
  static func screenRecordingStatus(isGranted: Bool) -> PermissionDisplayState {
      isGranted ? .granted : .denied
  }
  static func currentScreenRecordingStatus() -> PermissionDisplayState {
      screenRecordingStatus(isGranted: CGPreflightScreenCaptureAccess())
  }
  ```
  Add `import CoreGraphics` if not present.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/Settings/PermissionsSettingsView.swift MacAllYouNeedTests/DockPreviews/DockPreviewPermissionGateTests.swift && git commit -m "feat(permissions): add screen recording status provider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 12 — `ScreenRecordingPermissionRow` (PermissionCard)

**Files:** `MacAllYouNeed/Settings/Permissions/ScreenRecordingPermissionRow.swift` (new). Manual/visual verification only (SwiftUI view); compile-gated by the app build.

- [ ] Failing check: reference `ScreenRecordingPermissionRow` from `DockPreviewSettingsView` later (Task 21). For now, write the row and verify it compiles via the app build.
- [ ] Minimal impl, modeled on `MicrophonePermissionRow`:
  ```swift
  import SwiftUI

  struct ScreenRecordingPermissionRow: View {
      let status: PermissionDisplayState
      let isHighlighted: Bool
      let onAction: () -> Void

      var body: some View {
          PermissionCard(
              title: "Screen Recording",
              reason: "Allows Dock-hover previews to show window thumbnails. Without it, previews show a title-only window list.",
              state: status.cardState,
              actionTitle: actionTitle,
              isHighlighted: isHighlighted,
              action: onAction
          )
      }
      private var actionTitle: String {
          switch status {
          case .granted: "Granted"
          case .denied: "Open"
          default: "Request"
          }
      }
  }
  ```
- [ ] Run-pass: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/DockPreviewPermissionGateTests` (confirms target compiles with the new file).
- [ ] Commit:
  ```
  git add MacAllYouNeed/Settings/Permissions/ScreenRecordingPermissionRow.swift && git commit -m "feat(permissions): add screen recording permission row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 13 — `DockPreviewPrivateAPI` seam (dlopen loader)

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewPrivateAPI.swift` (new). **Manual verification** (private symbols cannot run in CI); only the loader's nil-safety is unit-tested.

- [ ] Failing test (loader degrades, never crashes) — append to `DockPreviewCoordinatorTests.swift` (created in Task 19) or a dedicated tiny test; assert `availability` is a `Bool` and accessing it twice is stable:
  ```swift
  func testPrivateAPIAvailabilityIsStable() {
      let a = DockPreviewPrivateAPI.shared.isCaptureAvailable
      let b = DockPreviewPrivateAPI.shared.isCaptureAvailable
      XCTAssertEqual(a, b)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewPrivateAPI'`.
- [ ] Minimal impl: single file declaring `@_silgen_name`/`dlsym`-loaded function pointers for `CGSMainConnectionID`, `CGSHWCaptureWindowList`, `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo`, `_AXUIElementGetWindow`, `CGSCopySpacesForWindows`, `CGSCopyManagedDisplaySpaces`, `CGSGetWindowLevel`. Load SkyLight lazily from `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`; expose `isCaptureAvailable`, `isRaiseAvailable` computed from non-nil symbol pointers. Thin wrappers: `captureImage(windowID:) -> CGImage?`, `axWindowID(_:) -> CGWindowID?`, `raise(psn:windowID:) -> Bool`, `spaces(forWindowIDs:) -> [CGWindowID: [Int]]`. All return nil/false when a symbol fails to load.
- [ ] Run-pass: same `-only-testing` → green (only the loader test runs in CI).
- [ ] **Manual verification (documented):** on a real machine with Screen Recording granted, confirm `captureImage` returns a non-nil `CGImage` for a known window id and `raise` brings a specific window forward. Note macOS version tested.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewPrivateAPI.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add private CGS/SkyLight API seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 14 — `DockHoverObserver` protocol + S1 consumer

**Files:** `MacAllYouNeed/DockPreviews/DockHoverObserver.swift` (new). Logic seam is a protocol; the AX wiring is manual-verified.

- [ ] Failing test — define `DockHoverObserving` protocol + event enum; assert a fake observer drives a sink (append to `DockPreviewCoordinatorTests.swift`):
  ```swift
  func testFakeHoverObserverEmitsAppChanged() {
      let observer = FakeDockHoverObserver()
      var received: [DockHoverEvent] = []
      observer.onEvent = { received.append($0) }
      observer.emit(.appHovered(pid: 42, bundleID: "com.example"))
      observer.emit(.hoverEnded)
      XCTAssertEqual(received, [.appHovered(pid: 42, bundleID: "com.example"), .hoverEnded])
  }
  ```
  with a `FakeDockHoverObserver` test double conforming to `DockHoverObserving`.
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find type 'DockHoverEvent'`.
- [ ] Minimal impl:
  ```swift
  enum DockHoverEvent: Equatable {
      case appHovered(pid: pid_t, bundleID: String)
      case hoverEnded
  }

  @MainActor protocol DockHoverObserving: AnyObject {
      var onEvent: ((DockHoverEvent) -> Void)? { get set }
      func start()
      func stop()
  }
  ```
  Plus the real `DockHoverObserver: DockHoverObserving` that, on `start()`: resolves `com.apple.dock` PID, asks the injected `AXObserverCoordinator` (S1) to subscribe to `kAXSelectedChildrenChangedNotification` on the Dock `AXList`, and on each callback resolves the hovered `AXApplicationDockItem` → `kAXURLAttribute` → bundle id → `NSRunningApplication` and emits `.appHovered`/`.hoverEnded`. Skips MAYN's own bundle id. Suppresses when `DockUtils`-equivalent reports the Dock hidden.
- [ ] Run-pass: same `-only-testing` → green (fake path).
- [ ] **Manual verification:** hover bottom/left/right Dock; confirm correct app resolves; relaunch Dock (`killall Dock`) and confirm S1 re-subscribes and hover resumes.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockHoverObserver.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add dock hover observer on S1 coordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 15 — `DockPreviewWindowEnumerator` protocol + SCK/AX impl

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowEnumerator.swift` (new). Protocol seam; the real SCK/AX path is manual-verified.

- [ ] Failing test — protocol returns merged entries; a fake enumerator feeds `merge`:
  ```swift
  func testEnumeratorProtocolReturnsMergedWindows() async {
      let fake = FakeWindowEnumerator(result: [
          DockPreviewWindowEntry(windowID: 1, pid: 9, title: "A", frame: .zero,
                                 isMinimized: false, isHidden: false, spaceIDs: [], lastAccessed: Date())
      ])
      let windows = await fake.windows(forPID: 9)
      XCTAssertEqual(windows.map(\.windowID), [1])
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find type 'DockPreviewWindowEnumerating'`.
- [ ] Minimal impl: `protocol DockPreviewWindowEnumerating { func windows(forPID: pid_t) async -> [DockPreviewWindowEntry] }`. Real impl: `SCShareableContent.current` filtered by PID → `[DockPreviewSourceWindow]` (sc), `AXUIElementCreateApplication(pid).windows()` → `[DockPreviewSourceWindow]` with `windowID` from `DockPreviewPrivateAPI.axWindowID`, then `DockPreviewWindowMatcher.merge`. Spaces filled via `DockPreviewPrivateAPI.spaces(forWindowIDs:)`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** open an app with on-screen + minimized + off-Space windows; confirm all appear once each.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewWindowEnumerator.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add SCK+AX window enumerator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 16 — `DockPreviewThumbnailService` (static capture seam)

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewThumbnailService.swift` (new). Capture is manual-verified; the downscale + cache-reuse decision is tested.

- [ ] Failing test — service reuses a fresh cached thumbnail and only calls capture for expired/missing ids:
  ```swift
  func testThumbnailServiceReusesFreshAndCapturesMissing() async {
      var now = Date(timeIntervalSince1970: 0)
      let cache = DockPreviewThumbnailCache(lifespan: 5, now: { now })
      var captured: [CGWindowID] = []
      let service = DockPreviewThumbnailService(
          cache: cache,
          scheduler: DockPreviewCaptureScheduler(maxConcurrent: 4),
          capture: { id in captured.append(id); return TestImage.one() })
      _ = await service.thumbnails(for: [1, 2])
      now = Date(timeIntervalSince1970: 3)
      _ = await service.thumbnails(for: [1, 2]) // fresh → no recapture
      XCTAssertEqual(captured.sorted(), [1, 2])
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewThumbnailService'`.
- [ ] Minimal impl: takes injected `capture: (CGWindowID) async -> CGImage?` (real default = `DockPreviewPrivateAPI.captureImage` + downscale). `thumbnails(for:)` returns `valid` cache hits immediately, schedules `capture` for the rest via `DockPreviewCaptureScheduler`, stores results, falls back to `lastKnown` for minimized.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** confirm captures are downscaled (panel-size) and minimized windows still show last good thumbnail.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewThumbnailService.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add thumbnail service with cache reuse

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 17 — `DockPreviewRaiseService` (un-minimize + SkyLight + activate)

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewRaiseService.swift` (new). Raise path is manual-verified; the fallback-ladder ordering is tested via injected steps.

- [ ] Failing test — raise tries un-minimize (when minimized) then SkyLight then activate; on SkyLight failure it still calls AX raise fallback:
  ```swift
  func testRaiseLadderFallsBackWhenSkyLightFails() {
      var calls: [String] = []
      let service = DockPreviewRaiseService(
          unminimize: { _ in calls.append("unminimize"); return true },
          unhideApp: { _ in calls.append("unhide") },
          skyLightFocus: { _, _ in calls.append("skylight"); return false },
          axRaise: { _ in calls.append("axraise"); return true },
          activate: { _ in calls.append("activate") })
      service.raise(entry: minimizedEntry, app: fakeApp)
      XCTAssertEqual(calls, ["unminimize", "skylight", "axraise", "activate"])
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewRaiseService'`.
- [ ] Minimal impl: closures injected (defaults call AX `kAXMinimizedAttribute=false`, `app.unhide()`, `DockPreviewPrivateAPI.raise`, AX `kAXRaiseAction`, `app.activate()`). `raise(entry:app:)`: if `isMinimized` call `unminimize`; if app `isHidden` call `unhideApp`; call `skyLightFocus`; if it returns false call `axRaise`; always finish with `activate`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** click a minimized, a hidden, and an off-Space window's card; each is restored, raised, and its app activated.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewRaiseService.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add window raise/restore ladder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 18 — `DockPreviewSeeder` launch-time seeding

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewSeeder.swift` (new); test append to `DockPreviewCoordinatorTests.swift`.

- [ ] Failing test — seeder enumerates regular apps (excluding self), populates cache via injected enumerator with bounded fan-out:
  ```swift
  func testSeederPopulatesCacheForRegularApps() async {
      let cache = DockPreviewWindowCache()
      let enumerator = FakeWindowEnumerator(perPID: [
          7: [entry(1, pid: 7)], 8: [entry(2, pid: 8)]
      ])
      let seeder = DockPreviewSeeder(
          cache: cache, enumerator: enumerator,
          scheduler: DockPreviewCaptureScheduler(maxConcurrent: 2),
          regularAppPIDs: { [7, 8] }, selfPID: 99)
      await seeder.run()
      XCTAssertEqual(cache.windows(for: 7).count, 1)
      XCTAssertEqual(cache.windows(for: 8).count, 1)
  }
  func testSeederSkipsSelf() async {
      let cache = DockPreviewWindowCache()
      let seeder = DockPreviewSeeder(
          cache: cache, enumerator: FakeWindowEnumerator(perPID: [99: [entry(1, pid: 99)]]),
          scheduler: DockPreviewCaptureScheduler(maxConcurrent: 2),
          regularAppPIDs: { [99] }, selfPID: 99)
      await seeder.run()
      XCTAssertTrue(cache.windows(for: 99).isEmpty)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewSeeder'`.
- [ ] Minimal impl: `run()` reads `regularAppPIDs()` (real default: `NSWorkspace.shared.runningApplications` filtered `.activationPolicy == .regular`), drops `selfPID`, and fans out via `DockPreviewCaptureScheduler.run` calling `enumerator.windows(forPID:)` then `cache.replace`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewSeeder.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add launch-time cache seeder

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 19 — `DockPreviewCoordinator` state machine

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewCoordinator.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift` (state-machine section). Mirrors `WindowControlCoordinator` + `WindowControlPresentationTests`.

- [ ] Failing tests — transitions off → needsAccessibility → active → suspended, and mode reflects permission gate:
  ```swift
  @MainActor
  func testCoordinatorEntersNeedsAccessibilityWhenUntrusted() {
      let coord = DockPreviewCoordinator(
          observer: FakeDockHoverObserver(),
          accessibilityTrust: { false },
          screenRecordingTrust: { true })
      coord.start()
      XCTAssertEqual(coord.state, .needsAccessibility)
  }
  @MainActor
  func testCoordinatorActiveWhenTrusted() {
      let coord = DockPreviewCoordinator(
          observer: FakeDockHoverObserver(),
          accessibilityTrust: { true },
          screenRecordingTrust: { false })
      coord.start()
      XCTAssertEqual(coord.state, .active)
      XCTAssertEqual(coord.mode, .titleOnly) // SR denied
  }
  @MainActor
  func testStopReturnsToOff() {
      let coord = DockPreviewCoordinator(
          observer: FakeDockHoverObserver(), accessibilityTrust: { true }, screenRecordingTrust: { true })
      coord.start(); coord.stop()
      XCTAssertEqual(coord.state, .off)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewCoordinator'`.
- [ ] Minimal impl: `@MainActor @Observable final class DockPreviewCoordinator` with `State { off, needsAccessibility, active, suspended(reason), error(String) }` and `mode: DockPreviewMode`. Injected: `observer`, `accessibilityTrust`, `screenRecordingTrust`, settings, cache, enumerator, thumbnail/raise services, panel. `start()` computes trust → state; on `.active` starts observer and wires `onEvent` to show/refresh/dismiss the panel; recomputes `mode` via `DockPreviewPermissionGate`. `reconcileLifecycle()` re-derives state on trust change (driven by a reused `WindowControlAccessibilityTrustMonitor`-style monitor). `stop()` tears down observer + panel → `.off`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewCoordinator.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add coordinator state machine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 20 — `DockPreviewPanel` + `DockPreviewPanelView` (MAYNTheme)

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewPanel.swift`, `MacAllYouNeed/DockPreviews/DockPreviewPanelView.swift` (new). SwiftUI/AppKit — compile-gated + manual visual verification; the show/dismiss generation guard is the only unit-tested logic.

- [ ] Failing test — repeated `show` then `dismiss` doesn't strand a stale dismiss (generation guard), mirroring `WindowSnapOverlayPanel`:
  ```swift
  @MainActor
  func testPanelDismissGenerationGuard() {
      let panel = DockPreviewPanel()
      panel.show(model: .empty, origin: .zero) // generation 1
      panel.show(model: .empty, origin: .zero) // generation 2
      panel.dismiss()
      XCTAssertFalse(panel.isVisibleForTest)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewPanel'`.
- [ ] Minimal impl: `DockPreviewPanel` reuses `NonActivatingFloatingPanelController` + `FloatingHUDWindowLayering` from `WindowSnapOverlayPanel.swift`, with `ignoresMouseEvents = false`, `hidesOnDeactivate = false`, fades via `MAYNMotionBridge.effectiveDuration(.toastIn/.toastOut)`, `dismissGeneration` guard. `DockPreviewPanelView` renders an app-name header + a row/column of cards (thumbnail or title-only fallback + truncated title + minimized/hidden badge), styled with `MAYNTheme`/`MAYNControlMetrics`/`MAYNMotion` and the OS-version-aware corner radius from `WindowSnapOverlayPresentation`; card tap calls a `onSelect(entry)` closure. `targetScreen` lock captured on first show.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification (design.md §13):** hover across bottom/left/right Dock; confirm anchoring, MAYNTheme tokens, hover highlight, click-to-raise dismiss, Reduce Motion collapses fades, title-only fallback renders when SR denied.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewPanel.swift MacAllYouNeed/DockPreviews/DockPreviewPanelView.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add floating preview panel UI

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 21 — `DockPreviewSettings` model + store + tool page

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewSettings.swift`, `MacAllYouNeed/DockPreviews/DockPreviewSettingsView.swift` (new); test `MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift` (settings round-trip section).

- [ ] Failing test — settings store persists/loads defaults (live off, current-space off, current-monitor off, include minimized/hidden on, lifespan 5, gestures off):
  ```swift
  func testSettingsStoreRoundTrip() {
      let defaults = UserDefaults(suiteName: "dockpreviews.test")!
      defaults.removePersistentDomain(forName: "dockpreviews.test")
      var s = DockPreviewSettings.default
      XCTAssertFalse(s.livePreviews)
      XCTAssertEqual(s.thumbnailLifespan, 5, accuracy: 0.01)
      s.livePreviews = true
      DockPreviewSettingsStore.save(s, into: defaults)
      XCTAssertTrue(DockPreviewSettingsStore.load(from: defaults).livePreviews)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewSettings'`.
- [ ] Minimal impl: `struct DockPreviewSettings: Codable, Equatable` with `livePreviews`, `currentSpaceOnly`, `currentMonitorOnly`, `includeMinimized`, `includeHidden`, `thumbnailLifespan`, `gestureExtras`; `.default`; `DockPreviewSettingsStore` JSON to `UserDefaults`. `DockPreviewSettingsView` uses `FunctionPageShell` + `FunctionPageScrollContent`: enable toggle, `ScreenRecordingPermissionRow` status, and the settings rows (live toggle disabled when SR denied), no hotkey recorder. Follows design.md (no raw colors/animations/segmented pickers).
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** toggle each setting; confirm live toggle disabled without SR; confirm "Enable previews" routes to the permission step.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewSettings.swift MacAllYouNeed/DockPreviews/DockPreviewSettingsView.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add settings store and tool page

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 22 — `DockPreviewLiveCaptureManager` (optional SCStream, ≤4 cap)

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewLiveCaptureManager.swift` (new). SCStream is manual-verified; the start/stop bookkeeping + cap is tested behind a protocol.

- [ ] Failing test — manager starts at most 4 streams, stops on disappear:
  ```swift
  func testLiveManagerCapsConcurrentStreams() {
      let factory = FakeStreamFactory()
      let manager = DockPreviewLiveCaptureManager(maxConcurrent: 4, streamFactory: factory)
      for id in 0..<10 { manager.start(windowID: CGWindowID(id)) }
      XCTAssertEqual(manager.activeCount, 4)
      manager.stopAll()
      XCTAssertEqual(manager.activeCount, 0)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewLiveCaptureManager'`.
- [ ] Minimal impl: `protocol DockPreviewStreamFactory { func makeStream(windowID:) -> DockPreviewStreamHandle }`; manager keeps `[CGWindowID: handle]`, refuses to start past `maxConcurrent`, `stop(windowID:)`/`stopAll()`. Real factory builds `SCStream` + `SCContentFilter(desktopIndependentWindow:)` at low FPS/reduced dimensions; gated behind `settings.livePreviews && mode == .live`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** enable live previews; confirm ≤4 streams run, low frame rate, and all stop on panel dismiss.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewLiveCaptureManager.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add capped live capture manager

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 23 — `DockPreviewsFeatureActivator` + `DockPreviewsDescriptor`

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewsFeatureActivator.swift`, `MacAllYouNeed/App/Descriptors/DockPreviewsDescriptor.swift` (new); test append to `DockPreviewCoordinatorTests.swift`.

- [ ] Failing test — descriptor wiring (id, permissions, factories present):
  ```swift
  func testDescriptorWiring() {
      let d = DockPreviewsDescriptor.descriptor()
      XCTAssertEqual(d.id, .dockPreviews)
      XCTAssertTrue(d.requiredPermissions.contains(.accessibility))
      XCTAssertTrue(d.requiredPermissions.contains(.screenRecording))
      XCTAssertNotNil(d.settingsTabFactory)
      XCTAssertNotNil(d.onboardingSetupFactory)
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → `cannot find 'DockPreviewsDescriptor'`.
- [ ] Minimal impl: `DockPreviewsFeatureActivator: FeatureActivator` actor (mirrors `WindowControlFeatureActivator`, flips `isActive`; AppController applies the gate to the static coordinator). `DockPreviewsDescriptor.descriptor()` returns a `FeatureDescriptor(id: .dockPreviews, displayName: "Dock Previews", icon: "rectangle.on.rectangle", summary:…, detailDescription:…, requiredPermissions: [.accessibility, .screenRecording], activator: DockPreviewsFeatureActivator(), settingsTabFactory: { AnyView(DockPreviewSettingsView()) }, onboardingSetupFactory: { AnyView(DockPreviewSetupView()) })`. (The one-step onboarding view is a thin wrapper requesting Screen Recording via `CGRequestScreenCaptureAccess()` and showing status; skippable.)
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewsFeatureActivator.swift MacAllYouNeed/App/Descriptors/DockPreviewsDescriptor.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): add gated feature descriptor and activator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 24 — Register descriptor + static coordinator in `AppController`

**Files:** `MacAllYouNeed/App/AppController.swift` (descriptor registry list + `static let dockPreviewCoordinator`); the existing feature-registry test, or a new assertion in `DockPreviewCoordinatorTests.swift`.

- [ ] Failing test — the registered feature set contains `.dockPreviews`:
  ```swift
  func testFeatureRegistryContainsDockPreviews() {
      XCTAssertTrue(AppController.registeredFeatureIDs.contains(.dockPreviews))
  }
  ```
  (Expose `registeredFeatureIDs` as a small static computed property over the descriptor list if not already present.)
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewCoordinatorTests` → assertion fails / member missing.
- [ ] Minimal impl: add `DockPreviewsDescriptor.descriptor()` to the descriptor array; add `static let dockPreviewCoordinator = DockPreviewCoordinator()` (per CLAUDE.md static-let rule); wire enable/disable from the activator gate to `start()/stop()` and call `DockPreviewSeeder.run()` on enable.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] Commit:
  ```
  git add MacAllYouNeed/App/AppController.swift MacAllYouNeedTests/DockPreviews/DockPreviewCoordinatorTests.swift && git commit -m "feat(dockpreviews): register feature and static coordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 25 — Screen Recording usage string + notarization check

**Files:** `project.yml` (Info.plist `NSScreenRecordingUsageDescription`; ensure new `DockPreviews/` sources are picked up by the glob — verify, no change if globbed); regenerate with `xcodegen generate`.

- [ ] Add `NSScreenRecordingUsageDescription` to the main app target's `info.properties` (or `Info.plist`) in `project.yml`:
  `"Mac All You Need shows window thumbnails when you hover an app's Dock icon."`
- [ ] Run `xcodegen generate`.
- [ ] Run-pass (full suite, confirms project still builds with new sources + plist):
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- [ ] **Notarization check (manual, documented):** confirm `MacAllYouNeed.entitlements` has **no** App Sandbox key and **no** `com.apple.security.cs.disable-library-validation` that would block `dlopen` of `SkyLight.framework` — the existing entitlements (App Groups, audio-input, keychain) do not block PrivateFramework `dlopen` under Hardened Runtime. No new entitlement key is added for Screen Recording (it is a TCC consent). Note the macOS version verified.
- [ ] Commit:
  ```
  git add project.yml MacAllYouNeed.xcodeproj/project.pbxproj && git commit -m "build(dockpreviews): add screen recording usage string

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 26 — Per-Space / multi-monitor filtering

**Files:** `MacAllYouNeed/DockPreviews/DockPreviewWindowMatcher.swift` (add pure filter fn) or a new `DockPreviewWindowFilter.swift`; test append to `DockPreviewWindowMatcherTests.swift`.

- [ ] Failing tests — filter to current Space and current display when settings on; drop non-normal window levels:
  ```swift
  func testCurrentSpaceFilter() {
      let entries = [entryS(1, spaces: [5]), entryS(2, spaces: [6])]
      let out = DockPreviewWindowFilter.apply(entries, currentSpaceOnly: true, currentSpaceID: 5,
                                              currentMonitorOnly: false, displayFrame: nil)
      XCTAssertEqual(out.map(\.windowID), [1])
  }
  func testCurrentMonitorFilter() {
      let entries = [entryF(1, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
                     entryF(2, frame: CGRect(x: 2000, y: 0, width: 10, height: 10))]
      let out = DockPreviewWindowFilter.apply(entries, currentSpaceOnly: false, currentSpaceID: nil,
                                              currentMonitorOnly: true,
                                              displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
      XCTAssertEqual(out.map(\.windowID), [1])
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewWindowMatcherTests` → `cannot find 'DockPreviewWindowFilter'`.
- [ ] Minimal impl: pure `DockPreviewWindowFilter.apply(_:currentSpaceOnly:currentSpaceID:currentMonitorOnly:displayFrame:)` filtering by `spaceIDs.contains(currentSpaceID)` and `displayFrame.intersects(entry.frame)`. The coordinator supplies current space/display from `DockPreviewPrivateAPI` (manual-verified) and applies this pure filter before building the panel model.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** multi-monitor + multiple Spaces; toggle each filter and confirm panel contents.
- [ ] Commit:
  ```
  git add MacAllYouNeed/DockPreviews/DockPreviewWindowFilter.swift MacAllYouNeedTests/DockPreviews/DockPreviewWindowMatcherTests.swift && git commit -m "feat(dockpreviews): add per-space and per-monitor filtering

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 27 — Onboarding permission step + permissions page row wiring

**Files:** `MacAllYouNeed/Settings/PermissionsSettingsView.swift` (add `ScreenRecordingPermissionRow` to the optional section + status state), `DockPreviewSetupView` (created in Task 23) reused by the descriptor. Manual/visual verification + a small mapping test if logic added.

- [ ] Failing test (if a mapping helper is added for the optional-list inclusion) — Screen Recording appears as an optional permission entry:
  ```swift
  func testScreenRecordingListedAsOptionalPermission() {
      let optional = PermissionsSettingsView.optionalPermissionTargets()
      XCTAssertTrue(optional.contains(.screenRecording))
  }
  ```
- [ ] Run-fail: `xcodebuild test ... -only-testing:MacAllYouNeedTests/DockPreviewPermissionGateTests` → member missing / case missing in `PermissionInstructionTarget`.
- [ ] Minimal impl: add `.screenRecording` to `PermissionInstructionTarget`, render `ScreenRecordingPermissionRow` in the optional section driven by `PermissionStatusProvider.currentScreenRecordingStatus()`, request via `CGRequestScreenCaptureAccess()` on tap, refresh on `didBecomeActive`.
- [ ] Run-pass: same `-only-testing` → green.
- [ ] **Manual verification:** run onboarding for Dock Previews; deny SR → feature still enables in title-only mode; grant later → thumbnails appear without restart.
- [ ] Commit:
  ```
  git add MacAllYouNeed/Settings/PermissionsSettingsView.swift && git commit -m "feat(dockpreviews): wire screen recording onboarding and row

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

### Task 28 — Full suite + lint green gate

**Files:** none (verification task).

- [ ] Run full app tests: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → all green.
- [ ] Run Shared tests: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` → all green.
- [ ] Run `swiftlint --strict` → no violations (no raw colors/animations/segmented pickers in new UI).
- [ ] **Manual verification (design.md §13 checklist):** Reduce Motion run-through of the panel; confirm all tokens map to `MAYN*`.
- [ ] Commit (if lint autofixes only):
  ```
  git add -A && git commit -m "chore(dockpreviews): satisfy lint and full test gate

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
  ```

---

## Self-Review

Spec coverage confirmation (spec §-by-§):

- **§3.1 Dock-hover observer (S1 + health-check):** Task 14 (`DockHoverObserver` consumes S1; PID-change/health-check owned by S1, manual-verified).
- **§3.2 Window enumeration (SCK + AX merged, `_AXUIElementGetWindow`):** Task 6 (pure merge incl. title/frame fallback) + Task 15 (SCK/AX impl) + Task 13 (`axWindowID`).
- **§3.3 Static thumbnails (`CGSHWCaptureWindowList`, downscale, lifespan):** Task 13 (capture symbol) + Task 8 (lifespan cache) + Task 16 (service, downscale + reuse).
- **§3.4 Live previews (optional SCStream, ≤4):** Task 22.
- **§3.5 Floating panel (borderless non-activating NSPanel, MAYNTheme, anchoring, screen-lock, dismiss):** Task 20 + Task 9 (positioning math).
- **§3.6 Raise/restore (un-minimize, SkyLight, activate, AX fallback):** Task 17 + Task 13 (SkyLight symbols).
- **§3.7 Per-Space/multi-monitor + gesture extras:** Task 26 (filtering); gesture extras noted as opt-in Phase 2 in settings (Task 21) — off by default, no always-on tap.
- **§4 Architecture/components:** every component table row has a task (observer 14, enumerator 15, cache 4, seeder 18, thumbnail 16, live 22, panel 20, raise 17, private API 13, coordinator 19, descriptor/activator 23, settings 21).
- **§5 Data model/caching (per-PID cache insert/lookup/evict/diff, seeding, thumbnail lifespan, concurrency caps):** Tasks 3, 4, 5, 8, 7, 18.
- **§6 Integration seams:** S1 (Task 14), coordinator template (19), trust monitor (19/24), panel reuse (20), descriptor/enum (1, 2, 23), permission UI (11, 12, 27).
- **§7 Permissions & entitlements (Permission + FeatureID additions, no sandbox, dlopen, usage string):** Tasks 1, 2, 25.
- **§8 UI/UX (panel layout, positioning, click-to-raise, title-only fallback, onboarding/settings):** Tasks 20, 9, 17, 21, 23, 27.
- **§9 Edge cases:** SR-denied degradation (10/19/27), AX revoke/suspend (19/24), Dock rebuild/relaunch (14 via S1), minimized-restore failure ladder (17), SkyLight load failure (13/17), stale window id (15 re-enumerate), multi-monitor flip (9/26), Dock-hidden suppress (14), hover-ends-before-refresh (19), skip self (14/18).
- **§10 Performance plan:** seeding (18), show-cached-then-refresh (19), concurrency caps (7, 16, 22), downscaling + lifespan (8, 16), event-driven observer (14), no always-on tap (Phase 2 only), `_AXUIElementGetWindow` matching (6/13).
- **§11 Testing strategy:** coordinator state machine (19), cache diffing + concurrency (4, 5), AX↔SC merge (6), permission gating (10, 11), positioning math (9), thumbnail lifespan (8), enum recompilation (1, 2); private-API/live/raise behind protocol seams with documented manual verification (13–17, 22).

All pure-testable logic listed in the brief (per-PID cache, concurrency cap, AX↔SC matching, positioning flip, permission degradation, FeatureID/Permission additions, thumbnail lifespan) has a dedicated failing-test-first task. The AX observer, private-API capture/raise, and SCStream each have a thin protocol seam plus explicit manual-verification notes (they cannot run in CI). Design-system compliance (MAYNTheme/MAYNMotion panel, PermissionCard onboarding, no raw colors/animations/segmented pickers) is enforced in Tasks 20, 21, 12, 27, and the lint gate in Task 28.
