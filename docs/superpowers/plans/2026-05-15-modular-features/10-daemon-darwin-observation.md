# Phase 10 — Daemon Darwin Observation + Worker Gating

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `ClipboardDaemon` observe the `com.macallyouneed.featureStateDidChange` Darwin notification posted by the main app's `FeatureManager`, diff per-feature `activationState` against a snapshot, and start/stop the daemon's per-feature workers (pasteboard poller, snippet expander, and any future daemon-side worker tied to a feature) in response. Also gate worker creation on launch so workers only spin up for features whose state is `.enabled`. Today the daemon unconditionally instantiates `PasteboardObserver` and `SnippetExpander` in `DaemonContainer.init()`; after this phase, both are conditional on `featureState(.clipboard).activationState == .enabled` and are restarted/torn down live as the user toggles the feature.

**Architecture:** Three new types live in `ClipboardDaemon/`:
- `FeatureStateReader` (in `Shared/Sources/FeatureCore/`) — a synchronous, read-only helper that decodes a single feature's `FeatureRuntimeState` out of `AppGroupSettings`. Mirrors the JSON shape `FeatureManager.setState` writes (Phase 01).
- `FeatureStateDarwinObserver` — registers a `CFNotificationCenterAddObserver` on `CFNotificationCenterGetDarwinNotifyCenter()` for `DarwinNotification.featureStateDidChange`, holds a per-`FeatureID` snapshot, diffs on each fire, and calls a delegate's `featureDidEnable(_:)` / `featureDidDisable(_:)`. Cleans up its observer in `deinit`.
- `PerFeatureWorkerHost` — owns per-feature worker objects, exposes idempotent `startWorkers(for:)` / `stopWorkers(for:)` / `stopAllWorkers()`, and is the delegate of `FeatureStateDarwinObserver`. Worker types are injected, so tests can substitute fakes.

`DaemonContainer.init()` is refactored: instead of unconditionally starting `PasteboardObserver`/`SnippetExpander`, it (a) reads each feature's state via `FeatureStateReader`, (b) calls `PerFeatureWorkerHost.startWorkers(for:)` for each `.enabled` feature, and (c) installs the Darwin observer for subsequent live changes. The existing `installSettingsReloader()` Darwin-notification pattern around `DaemonContainer.swift:149` is preserved unchanged — Phase 10 is purely additive.

**Tech Stack:** Swift, `CFNotificationCenterAddObserver`/`Remove`, `Unmanaged`, `UserDefaults` (cross-process via App Group suite), `XCTestExpectation` for cross-process tests, `Process` for spawning a child binary, `swift run` of a tiny test executable target.

**Depends on:** Phase 04 (`FeatureRuntime` exists in main app and writes feature state via `FeatureManager`, which already posts the Darwin notification from Phase 01). Optionally depends on Phase 08 — if Phase 08 has not landed yet when Phase 10 runs (they are parallelizable per the index plan), this phase adds `FeatureStateReader` to `Shared/Sources/FeatureCore/`. If Phase 08 has already landed, **skip Task 1 — it is a no-op**.

---

## File structure

```
Shared/Sources/FeatureCore/
└── FeatureStateReader.swift               ← NEW (or already added by Phase 08; see Task 1 note)

Shared/Tests/FeatureCoreTests/
└── FeatureStateReaderTests.swift          ← NEW (round-trip with FeatureManager writes)

ClipboardDaemon/
├── DaemonContainer.swift                  ← MODIFY: gate worker creation, install FeatureStateDarwinObserver
├── FeatureStateDarwinObserver.swift       ← NEW
└── PerFeatureWorkerHost.swift             ← NEW

ClipboardDaemonTests/                      ← NEW test target (see Task 5 if it doesn't already exist)
├── FeatureStateDarwinObserverTests.swift
├── PerFeatureWorkerHostTests.swift
└── DaemonContainerStartupGatingTests.swift

ClipboardDaemonCrossProcessTests/          ← NEW test target wrapping a child-process binary
├── ChildDaemonProbe/                      ← tiny `swift run` executable simulating the daemon
│   └── main.swift
├── CrossProcessDarwinNotificationTests.swift
└── Package.swift                          ← if a separate SPM package is needed; otherwise wire into Shared/Package.swift
```

> Why two test targets: `ClipboardDaemonTests` is in-process and uses fakes for workers + a controllable `UserDefaults(suiteName:)`. `ClipboardDaemonCrossProcessTests` actually spawns a child process, because Darwin notifications are inherently cross-process — verifying their semantics in-process gives false confidence.

---

### Task 1: `FeatureStateReader` (skip if Phase 08 has landed)

> **If Phase 08 has already landed in `main` and `Shared/Sources/FeatureCore/FeatureStateReader.swift` exists, skip this entire task — it is a no-op.** Verify with: `test -f /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/FeatureCore/FeatureStateReader.swift && echo present || echo absent`. If `present`, jump to Task 2.

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureStateReader.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift`:
```swift
import XCTest
@testable import FeatureCore
@testable import Core

final class FeatureStateReaderTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "FeatureStateReaderTests-\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testReturnsInitialDefaultWhenUnset() {
        let state = FeatureStateReader.state(for: .clipboard, defaults: defaults, assetRequired: false)
        XCTAssertEqual(state, .init(assetState: .notRequired, activationState: .disabled))
    }

    func testReadsStateWrittenByFeatureManager() async throws {
        let registry = FeatureRegistry(descriptors: [
            FeatureDescriptor(id: .clipboard, displayName: "Clipboard", icon: "doc",
                              summary: "", detailDescription: "",
                              activator: NoopFeatureActivator())
        ])
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await manager.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)

        let read = FeatureStateReader.state(for: .clipboard, defaults: defaults, assetRequired: false)
        XCTAssertEqual(read, .init(assetState: .notRequired, activationState: .enabled))
    }

    func testReadsAllFeaturesIndependently() async throws {
        let registry = FeatureRegistry(descriptors: [
            FeatureDescriptor(id: .clipboard, displayName: "Clipboard", icon: "doc",
                              summary: "", detailDescription: "",
                              activator: NoopFeatureActivator()),
            FeatureDescriptor(id: .voice, displayName: "Voice", icon: "mic",
                              summary: "", detailDescription: "",
                              activator: NoopFeatureActivator()),
        ])
        let manager = FeatureManager(registry: registry, defaults: defaults)
        try await manager.setState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        try await manager.setState(.init(assetState: .notRequired, activationState: .disabled), for: .voice)

        XCTAssertEqual(FeatureStateReader.state(for: .clipboard, defaults: defaults, assetRequired: false).activationState, .enabled)
        XCTAssertEqual(FeatureStateReader.state(for: .voice, defaults: defaults, assetRequired: false).activationState, .disabled)
    }

    func testIgnoresMalformedJSON() {
        defaults.set(Data("not json".utf8), forKey: FeatureManager.persistKey(for: .clipboard))
        let state = FeatureStateReader.state(for: .clipboard, defaults: defaults, assetRequired: false)
        XCTAssertEqual(state, .init(assetState: .notRequired, activationState: .disabled),
                       "malformed JSON must fall back to initial default, not crash")
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureStateReaderTests
```
Expected: FAIL with "type 'FeatureStateReader' not in scope".

- [ ] **Step 3: Implement**

Create `Shared/Sources/FeatureCore/FeatureStateReader.swift`:
```swift
import Foundation

/// Synchronous, read-only access to FeatureRuntimeState across processes.
///
/// FeatureManager (an actor) is the single writer; FeatureStateReader is the cross-process
/// reader, used by the daemon (which has no FeatureRegistry available — it only needs to
/// know the per-feature activation state to gate its workers).
public enum FeatureStateReader {
    /// Reads `FeatureRuntimeState` for `id` from `defaults`. Falls back to
    /// `FeatureRuntimeState.initialDefault(assetRequired:)` if no state is persisted
    /// or if the persisted JSON is malformed.
    public static func state(
        for id: FeatureID,
        defaults: UserDefaults,
        assetRequired: Bool
    ) -> FeatureRuntimeState {
        guard let data = defaults.data(forKey: FeatureManager.persistKey(for: id)),
              let decoded = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data) else {
            return .initialDefault(assetRequired: assetRequired)
        }
        return decoded
    }

    /// Snapshot of every known FeatureID's state. Used by the daemon's diff loop.
    public static func snapshot(
        defaults: UserDefaults,
        assetRequiredByID: [FeatureID: Bool]
    ) -> [FeatureID: FeatureRuntimeState] {
        Dictionary(uniqueKeysWithValues: FeatureID.allCases.map {
            ($0, state(for: $0, defaults: defaults, assetRequired: assetRequiredByID[$0] ?? false))
        })
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureStateReaderTests
```
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureStateReader.swift Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift
git commit -m "feat(modular-features): add FeatureStateReader for cross-process reads"
```

---

### Task 2: Wire `FeatureCore` into the `ClipboardDaemon` Xcode target

**Files:**
- Modify: `project.yml`

The daemon must import `FeatureCore`. If Phase 01 already added `FeatureCore` to the daemon's dependency list (Phase 01 Task 12 includes this), skip — confirm with grep.

- [ ] **Step 1: Verify current state**

```bash
grep -n -A 3 "ClipboardDaemon:" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -40
```

Look for `package: Shared\n\s+product: FeatureCore` under `ClipboardDaemon` `dependencies:`. If present, skip to Task 3.

- [ ] **Step 2: Add the dependency if missing**

In `project.yml`, locate the `ClipboardDaemon` target's `dependencies:` block and add:
```yaml
      - package: Shared
        product: FeatureCore
```

- [ ] **Step 3: Regenerate the Xcode project**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && xcodegen generate
```
Expected: `Generated project successfully`.

- [ ] **Step 4: Verify daemon still builds**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && \
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemon \
  -destination 'platform=macOS,arch=arm64' build | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit (only if changed)**

```bash
git add project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): wire FeatureCore into ClipboardDaemon target"
```

---

### Task 3: `FeatureStateDarwinObserver` — observe + diff

**Files:**
- Create: `ClipboardDaemon/FeatureStateDarwinObserver.swift`
- Create: `ClipboardDaemonTests/FeatureStateDarwinObserverTests.swift` (and the test target if it doesn't exist; see Task 5 note)

- [ ] **Step 1: Write the failing test**

Create `ClipboardDaemonTests/FeatureStateDarwinObserverTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import ClipboardDaemon

private final class RecordingDelegate: FeatureStateObserverDelegate {
    var enabled: [FeatureID] = []
    var disabled: [FeatureID] = []
    let lock = NSLock()
    func featureDidEnable(_ id: FeatureID) {
        lock.lock(); enabled.append(id); lock.unlock()
    }
    func featureDidDisable(_ id: FeatureID) {
        lock.lock(); disabled.append(id); lock.unlock()
    }
}

final class FeatureStateDarwinObserverTests: XCTestCase {
    private var writerDefaults: UserDefaults!
    private var readerDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FeatureStateDarwinObserverTests-\(UUID().uuidString)"
        writerDefaults = UserDefaults(suiteName: suiteName)!
        readerDefaults = UserDefaults(suiteName: suiteName)!
        writerDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        writerDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFiresEnableWhenStateFlipsToEnabled() {
        let delegate = RecordingDelegate()
        let observer = FeatureStateDarwinObserver(
            defaults: readerDefaults,
            assetRequiredByID: [:],
            delegate: delegate
        )
        defer { _ = observer }  // hold for test duration

        // Simulate the main-app side writing state via FeatureManager's persist key.
        let state = FeatureRuntimeState(assetState: .notRequired, activationState: .enabled)
        let data = try! JSONEncoder().encode(state)
        writerDefaults.set(data, forKey: FeatureManager.persistKey(for: .clipboard))

        // Trigger the observer manually (Darwin notifications are delivered async; in tests
        // we exercise the diff-and-fire path directly).
        let exp = expectation(description: "delegate fired")
        observer.onDidProcessNotification = { exp.fulfill() }
        observer.fireForTesting()
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(delegate.enabled, [.clipboard])
        XCTAssertTrue(delegate.disabled.isEmpty)
    }

    func testFiresDisableWhenStateFlipsToDisabled() {
        // Pre-seed enabled so the snapshot starts at .enabled.
        let enabled = FeatureRuntimeState(assetState: .notRequired, activationState: .enabled)
        writerDefaults.set(try! JSONEncoder().encode(enabled), forKey: FeatureManager.persistKey(for: .clipboard))

        let delegate = RecordingDelegate()
        let observer = FeatureStateDarwinObserver(
            defaults: readerDefaults,
            assetRequiredByID: [:],
            delegate: delegate
        )
        defer { _ = observer }

        // Now flip to disabled.
        let disabled = FeatureRuntimeState(assetState: .notRequired, activationState: .disabled)
        writerDefaults.set(try! JSONEncoder().encode(disabled), forKey: FeatureManager.persistKey(for: .clipboard))

        let exp = expectation(description: "delegate fired")
        observer.onDidProcessNotification = { exp.fulfill() }
        observer.fireForTesting()
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(delegate.enabled.isEmpty)
        XCTAssertEqual(delegate.disabled, [.clipboard])
    }

    func testIgnoresUnchangedState() {
        let enabled = FeatureRuntimeState(assetState: .notRequired, activationState: .enabled)
        writerDefaults.set(try! JSONEncoder().encode(enabled), forKey: FeatureManager.persistKey(for: .clipboard))

        let delegate = RecordingDelegate()
        let observer = FeatureStateDarwinObserver(
            defaults: readerDefaults,
            assetRequiredByID: [:],
            delegate: delegate
        )
        defer { _ = observer }

        let exp = expectation(description: "delegate fired (no-op)")
        observer.onDidProcessNotification = { exp.fulfill() }
        observer.fireForTesting()
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(delegate.enabled.isEmpty)
        XCTAssertTrue(delegate.disabled.isEmpty)
    }

    func testDeinitRemovesObserver() {
        // Smoke: just ensure no crash when an observer is deinit'd while a notification fires.
        weak var weakObs: FeatureStateDarwinObserver?
        autoreleasepool {
            let obs = FeatureStateDarwinObserver(
                defaults: readerDefaults,
                assetRequiredByID: [:],
                delegate: RecordingDelegate()
            )
            weakObs = obs
            _ = obs  // hold until end of autoreleasepool
        }
        XCTAssertNil(weakObs, "observer should be released after autoreleasepool")
        // Posting a Darwin notification now must not crash.
        DarwinNotification.post(DarwinNotification.featureStateDidChange)
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' \
  -only-testing:ClipboardDaemonTests/FeatureStateDarwinObserverTests | tail -20
```
Expected: FAIL with "no such module" or "FeatureStateDarwinObserver not in scope".

- [ ] **Step 3: Implement**

Create `ClipboardDaemon/FeatureStateDarwinObserver.swift`:
```swift
import CoreFoundation
import FeatureCore
import Foundation

public protocol FeatureStateObserverDelegate: AnyObject {
    func featureDidEnable(_ id: FeatureID)
    func featureDidDisable(_ id: FeatureID)
}

/// Listens on `DarwinNotification.featureStateDidChange`, re-reads every feature's state via
/// `FeatureStateReader`, diffs against an internal snapshot, and notifies the delegate of
/// per-feature enable/disable transitions. Designed for the daemon — single-process, single
/// observer instance per process. Thread-safe wrt the CFNotificationCenter callback thread.
public final class FeatureStateDarwinObserver {
    private let defaults: UserDefaults
    private let assetRequiredByID: [FeatureID: Bool]
    private weak var delegate: FeatureStateObserverDelegate?
    private let snapshotLock = NSLock()
    private var snapshot: [FeatureID: FeatureRuntimeState]

    /// Test-only hook fired after each notification has been processed.
    public var onDidProcessNotification: (() -> Void)?

    public init(
        defaults: UserDefaults,
        assetRequiredByID: [FeatureID: Bool],
        delegate: FeatureStateObserverDelegate
    ) {
        self.defaults = defaults
        self.assetRequiredByID = assetRequiredByID
        self.delegate = delegate
        self.snapshot = FeatureStateReader.snapshot(
            defaults: defaults,
            assetRequiredByID: assetRequiredByID
        )
        registerObserver()
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(
            center,
            me,
            CFNotificationName(rawValue: DarwinNotification.featureStateDidChange as CFString),
            nil
        )
    }

    /// Test entry point. Production callers receive notifications via the registered observer.
    public func fireForTesting() {
        processNotification()
    }

    private func registerObserver() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let me = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            me,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<FeatureStateDarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                me.processNotification()
            },
            DarwinNotification.featureStateDidChange as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func processNotification() {
        let fresh = FeatureStateReader.snapshot(
            defaults: defaults,
            assetRequiredByID: assetRequiredByID
        )
        snapshotLock.lock()
        let previous = snapshot
        snapshot = fresh
        snapshotLock.unlock()

        for id in FeatureID.allCases {
            let was = previous[id]?.activationState ?? .disabled
            let now = fresh[id]?.activationState ?? .disabled
            guard was != now else { continue }
            switch now {
            case .enabled:  delegate?.featureDidEnable(id)
            case .disabled: delegate?.featureDidDisable(id)
            }
        }
        onDidProcessNotification?()
    }
}
```

> **Why `weak var delegate`:** the host (`PerFeatureWorkerHost`) and the observer have a containment cycle if both retain each other; the observer is owned by the host (or the daemon container), so weak is correct.
>
> **Why a single `processNotification()` is called from both `fireForTesting()` and the C callback:** Darwin notifications coalesce — multiple posts in quick succession may deliver as one. The observer's job is to compare snapshots, not count notifications, so this is correct.

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' \
  -only-testing:ClipboardDaemonTests/FeatureStateDarwinObserverTests | tail -20
```
Expected: PASS, 4/4 tests.

- [ ] **Step 5: Commit**

```bash
git add ClipboardDaemon/FeatureStateDarwinObserver.swift ClipboardDaemonTests/FeatureStateDarwinObserverTests.swift
git commit -m "feat(modular-features): add FeatureStateDarwinObserver in daemon"
```

---

### Task 4: `PerFeatureWorkerHost` — coordinator with idempotent start/stop

**Files:**
- Create: `ClipboardDaemon/PerFeatureWorkerHost.swift`
- Create: `ClipboardDaemonTests/PerFeatureWorkerHostTests.swift`

- [ ] **Step 1: Identify the existing daemon-side workers**

Read `ClipboardDaemon/DaemonContainer.swift` (especially init at lines 37-71). The daemon currently instantiates and starts:
- `PasteboardObserver` — the clipboard pasteboard poller.
- `SnippetExpander` — the snippet text-replace event tap.

Both are tied to the **clipboard** feature. Other features (`.downloader`, `.folderPreview`, `.voice`) **do not** have daemon-side workers today: `DispatchServer` runs in the main app's `DownloadCoordinator`, the FolderPreview Quick Look extension is a separate XPC bundle managed by macOS, and Voice runs entirely in the main app. Phase 10 codifies this mapping in `PerFeatureWorkerHost`; if a future feature gains a daemon-side worker, it adds a case here.

> **If you find that the daemon code has grown an additional worker between Phase 01 and now (e.g., a daemon-side dispatch server was added), include it in the appropriate feature's mapping.** The mapping is the source of truth.

- [ ] **Step 2: Write the failing test**

Create `ClipboardDaemonTests/PerFeatureWorkerHostTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import ClipboardDaemon

private final class FakeWorker: DaemonWorker {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

final class PerFeatureWorkerHostTests: XCTestCase {
    private var pasteboard: FakeWorker!
    private var snippet: FakeWorker!
    private var host: PerFeatureWorkerHost!

    override func setUp() {
        super.setUp()
        pasteboard = FakeWorker()
        snippet = FakeWorker()
        host = PerFeatureWorkerHost(workers: [
            .clipboard: [pasteboard, snippet],
        ])
    }

    func testStartWorkersForFeature() {
        host.startWorkers(for: .clipboard)
        XCTAssertEqual(pasteboard.startCount, 1)
        XCTAssertEqual(snippet.startCount, 1)
    }

    func testStartIsIdempotent() {
        host.startWorkers(for: .clipboard)
        host.startWorkers(for: .clipboard)
        XCTAssertEqual(pasteboard.startCount, 1, "double-start must not double-invoke worker.start()")
        XCTAssertEqual(snippet.startCount, 1)
    }

    func testStopWorkersForFeature() {
        host.startWorkers(for: .clipboard)
        host.stopWorkers(for: .clipboard)
        XCTAssertEqual(pasteboard.stopCount, 1)
        XCTAssertEqual(snippet.stopCount, 1)
    }

    func testStopWithoutStartIsNoOp() {
        host.stopWorkers(for: .clipboard)
        XCTAssertEqual(pasteboard.stopCount, 0)
        XCTAssertEqual(snippet.stopCount, 0)
    }

    func testStopIsIdempotent() {
        host.startWorkers(for: .clipboard)
        host.stopWorkers(for: .clipboard)
        host.stopWorkers(for: .clipboard)
        XCTAssertEqual(pasteboard.stopCount, 1)
    }

    func testFeaturesWithNoMappingAreNoOp() {
        // No mapping for .voice — should be a silent no-op, not a crash.
        host.startWorkers(for: .voice)
        host.stopWorkers(for: .voice)
        XCTAssertEqual(pasteboard.startCount, 0)
        XCTAssertEqual(snippet.startCount, 0)
    }

    func testStopAllWorkersStopsAllStarted() {
        host.startWorkers(for: .clipboard)
        host.stopAllWorkers()
        XCTAssertEqual(pasteboard.stopCount, 1)
        XCTAssertEqual(snippet.stopCount, 1)
    }

    func testDelegateProtocolForwardsToStartStop() {
        host.featureDidEnable(.clipboard)
        XCTAssertEqual(pasteboard.startCount, 1)
        host.featureDidDisable(.clipboard)
        XCTAssertEqual(pasteboard.stopCount, 1)
    }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' \
  -only-testing:ClipboardDaemonTests/PerFeatureWorkerHostTests | tail -20
```
Expected: FAIL ("type 'PerFeatureWorkerHost' not in scope" / "type 'DaemonWorker' not in scope").

- [ ] **Step 3: Implement**

Create `ClipboardDaemon/PerFeatureWorkerHost.swift`:
```swift
import FeatureCore
import Foundation

/// Anything the daemon spins up to provide a feature's runtime behavior. Both
/// PasteboardObserver and SnippetExpander adapt to this protocol via small wrapper
/// adapters in DaemonContainer.
public protocol DaemonWorker: AnyObject {
    func start()
    func stop()
}

/// Owns per-feature worker objects and starts/stops them in response to feature-state
/// changes. Idempotent: starting twice or stopping without starting is a no-op.
public final class PerFeatureWorkerHost: FeatureStateObserverDelegate {
    private let workers: [FeatureID: [DaemonWorker]]
    private var running: Set<FeatureID> = []
    private let lock = NSLock()

    public init(workers: [FeatureID: [DaemonWorker]]) {
        self.workers = workers
    }

    public func startWorkers(for id: FeatureID) {
        lock.lock(); defer { lock.unlock() }
        guard !running.contains(id), let group = workers[id] else { return }
        for w in group { w.start() }
        running.insert(id)
    }

    public func stopWorkers(for id: FeatureID) {
        lock.lock(); defer { lock.unlock() }
        guard running.contains(id), let group = workers[id] else { return }
        for w in group { w.stop() }
        running.remove(id)
    }

    public func stopAllWorkers() {
        lock.lock(); let snapshot = running; lock.unlock()
        for id in snapshot { stopWorkers(for: id) }
    }

    public func isRunning(_ id: FeatureID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running.contains(id)
    }

    // MARK: FeatureStateObserverDelegate
    public func featureDidEnable(_ id: FeatureID) { startWorkers(for: id) }
    public func featureDidDisable(_ id: FeatureID) { stopWorkers(for: id) }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' \
  -only-testing:ClipboardDaemonTests/PerFeatureWorkerHostTests | tail -20
```
Expected: PASS, 8/8 tests.

- [ ] **Step 5: Commit**

```bash
git add ClipboardDaemon/PerFeatureWorkerHost.swift ClipboardDaemonTests/PerFeatureWorkerHostTests.swift
git commit -m "feat(modular-features): add PerFeatureWorkerHost coordinator"
```

---

### Task 5: Set up `ClipboardDaemonTests` xcodebuild scheme (skip if it exists)

**Files:**
- Modify: `project.yml`

The previous tasks reference `-scheme ClipboardDaemonTests`. If the project doesn't already have a unit-test target for the daemon, add one.

- [ ] **Step 1: Check if it exists**

```bash
grep -n "ClipboardDaemonTests" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml || echo "absent"
```

If output is `absent`, continue. If present, skip to Task 6.

- [ ] **Step 2: Add the test target**

In `project.yml`, append a new target under `targets:`:
```yaml
  ClipboardDaemonTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: 14.0
    sources:
      - path: ClipboardDaemonTests
    dependencies:
      - target: ClipboardDaemon
      - package: Shared
        product: FeatureCore
```

And add a scheme entry under `schemes:` (mirroring the existing daemon scheme pattern):
```yaml
  ClipboardDaemonTests:
    build:
      targets:
        ClipboardDaemonTests: test
    test:
      targets: [ClipboardDaemonTests]
```

- [ ] **Step 3: Regenerate**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && xcodegen generate
```

- [ ] **Step 4: Verify the empty test target builds**

```bash
xcodebuild build -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): add ClipboardDaemonTests target"
```

---

### Task 6: Refactor `DaemonContainer` to use `PerFeatureWorkerHost`

**Files:**
- Modify: `ClipboardDaemon/DaemonContainer.swift`
- Modify: `ClipboardDaemon/ClipboardDaemonMain.swift`

The goal: `DaemonContainer.init()` no longer unconditionally starts the pasteboard poller and snippet expander. Instead it (a) constructs them but does **not** start them, (b) builds a `PerFeatureWorkerHost` whose `.clipboard` mapping points to small adapters wrapping them, (c) reads each feature's state via `FeatureStateReader`, (d) calls `startWorkers(for:)` for each `.enabled` feature, (e) installs `FeatureStateDarwinObserver` for live changes. The existing `installSettingsReloader()` Darwin observation around line 149 is preserved unchanged — Phase 10 is purely additive.

- [ ] **Step 1: Add adapters that bridge existing worker types to `DaemonWorker`**

Append to `ClipboardDaemon/DaemonContainer.swift` (or in a new file `ClipboardDaemon/WorkerAdapters.swift`):

```swift
import Platform

/// Bridges PasteboardObserver into the DaemonWorker protocol. Hosts the start handler
/// closure passed by ClipboardDaemonMain so that start() can wire it back up after a
/// disable→enable cycle.
final class PasteboardObserverAdapter: DaemonWorker {
    private let observer: PasteboardObserver
    private let onChange: (PasteboardChange) -> Void
    private var started = false

    init(observer: PasteboardObserver, onChange: @escaping (PasteboardChange) -> Void) {
        self.observer = observer
        self.onChange = onChange
    }

    func start() {
        guard !started else { return }
        observer.start(handler: onChange)
        started = true
    }

    func stop() {
        guard started else { return }
        observer.stop()  // see Step 1a below — may need to be added
        started = false
    }
}

/// Bridges SnippetExpander into the DaemonWorker protocol.
final class SnippetExpanderAdapter: DaemonWorker {
    private let expander: SnippetExpander
    private var started = false

    init(expander: SnippetExpander) { self.expander = expander }

    func start() {
        guard !started else { return }
        expander.start()
        started = true
    }

    func stop() {
        guard started else { return }
        expander.stop()  // see Step 1a below — may need to be added
        started = false
    }
}
```

- [ ] **Step 1a: Add `stop()` methods to existing workers if missing**

Check the Platform module for existing `stop()`:
```bash
grep -n "func stop" /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift
grep -n "func stop" /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/Platform/Paste/SnippetExpander.swift
```

If either lacks a `stop()`, add it:

For `PasteboardObserver`: stop should cancel the polling timer and clear the handler closure. Add:
```swift
public func stop() {
    timer?.cancel()
    timer = nil
    handler = nil
}
```
(Adjust to match the actual property names — read the source first.)

For `SnippetExpander`: stop should disable the CGEventTap and release the run-loop source:
```swift
public func stop() {
    if let tap {
        CGEvent.tapEnable(tap: tap, enable: false)
    }
    tap = nil
}
```

Each addition needs a unit test in the existing `Shared/Tests/PlatformTests/` for the change. Mirror the existing tests in `PasteboardObserverTests.swift` — write a test that asserts `start()` then `stop()` then `start()` works correctly.

> Skip Step 1a entirely if both already have `stop()`.

- [ ] **Step 2: Refactor `DaemonContainer.init()` to defer start + build the host**

Edit `ClipboardDaemon/DaemonContainer.swift`. Replace the lines that start the workers:

```swift
// BEFORE (existing, ~lines 64-68):
observer = PasteboardObserver(reader: SystemPasteboardReader(), rules: Self.loadRules())
expander = SnippetExpander { [snippets] trigger in
    try? snippets.find(trigger: trigger)?.body
}
expander.start()
installSettingsReloader()
startRetentionTimer()
```

with:

```swift
// AFTER:
observer = PasteboardObserver(reader: SystemPasteboardReader(), rules: Self.loadRules())
expander = SnippetExpander { [snippets] trigger in
    try? snippets.find(trigger: trigger)?.body
}
// Workers are now started lazily via PerFeatureWorkerHost — see installFeatureStateGating().
installSettingsReloader()
startRetentionTimer()
```

Add a new property and an installer method to `DaemonContainer`:

```swift
private(set) var workerHost: PerFeatureWorkerHost!
private var featureStateObserver: FeatureStateDarwinObserver?

/// Called from ClipboardDaemonMain after init, after the pasteboard handler closure is known.
func installFeatureStateGating(onPasteboardChange: @escaping (PasteboardChange) -> Void) {
    let host = PerFeatureWorkerHost(workers: [
        .clipboard: [
            PasteboardObserverAdapter(observer: observer, onChange: onPasteboardChange),
            SnippetExpanderAdapter(expander: expander),
        ],
        // .downloader: no daemon-side workers (DispatchServer runs in main app)
        // .folderPreview: no daemon-side workers (extension is OS-managed)
        // .voice: no daemon-side workers (runs in main app)
    ])
    self.workerHost = host

    // Start workers for whatever features are enabled right now.
    let assetRequiredByID: [FeatureID: Bool] = [
        .clipboard: false,
        .downloader: true,
        .folderPreview: false,
        .voice: false,
    ]
    for id in FeatureID.allCases {
        let state = FeatureStateReader.state(
            for: id,
            defaults: AppGroupSettings.defaults,
            assetRequired: assetRequiredByID[id] ?? false
        )
        if state.activationState == .enabled {
            host.startWorkers(for: id)
        }
    }

    // Observe future state changes from the main app.
    featureStateObserver = FeatureStateDarwinObserver(
        defaults: AppGroupSettings.defaults,
        assetRequiredByID: assetRequiredByID,
        delegate: host
    )
}

func shutdown() {
    workerHost?.stopAllWorkers()
}
```

- [ ] **Step 3: Update `ClipboardDaemonMain.swift` to call the installer**

Edit `ClipboardDaemon/ClipboardDaemonMain.swift`:

```swift
@main
struct ClipboardDaemonMain {
    static func main() throws {
        let container = try DaemonContainer()
        let server = ClipboardXPCServer(container: container)
        container.installFeatureStateGating { change in
            if container.isCaptureSuspended() { return }
            for item in change.historyCaptureItems {
                do {
                    try container.persist(item: item, source: change.frontmostAppBundleID)
                } catch {
                    container.log.error("persist failed: \(error.localizedDescription)")
                }
            }
            server.notifyInvalidated()
        }
        NSLog("ClipboardDaemon ready, container=\(AppGroup.containerURL().path)")
        RunLoop.main.run()
    }
}
```

> **Note:** the previous `container.observer.start { … }` call is gone — `installFeatureStateGating` now owns the start, conditional on the clipboard feature being enabled. If `.clipboard` is disabled at launch, no pasteboard polling happens at all.

- [ ] **Step 4: Verify the daemon still launches and the app still captures clipboard items**

```bash
xcodebuild build -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' | tail -10
```
Expected: `BUILD SUCCEEDED`.

Manual: launch the app fresh (Phase 04's `BootstrapDefaults` defaults all features to `.enabled`), copy text from a couple of apps, open the clipboard popup (`⌘⇧V`), confirm new entries appear. Behavior should be indistinguishable from before this phase.

- [ ] **Step 5: Commit**

```bash
git add ClipboardDaemon/DaemonContainer.swift ClipboardDaemon/ClipboardDaemonMain.swift \
        Shared/Sources/Platform/Pasteboard/PasteboardObserver.swift \
        Shared/Sources/Platform/Paste/SnippetExpander.swift \
        Shared/Tests/PlatformTests/PasteboardObserverTests.swift
git commit -m "feat(modular-features): gate daemon workers on feature state"
```

---

### Task 7: Daemon startup gating tests

**Files:**
- Create: `ClipboardDaemonTests/DaemonContainerStartupGatingTests.swift`

This test exercises `installFeatureStateGating` directly with a controllable `UserDefaults` and fake workers. It does **not** start the real `PasteboardObserver` (which would touch `NSPasteboard`); it asserts the correct `startWorkers(for:)` calls happen for each pre-set state combination.

- [ ] **Step 1: Make worker injection testable**

Refactor `installFeatureStateGating` to accept the workers map externally, defaulting to the production mapping. Add an overload to `DaemonContainer`:

```swift
#if DEBUG
/// Test-only: installs gating with an explicit worker map (bypasses production
/// PasteboardObserver/SnippetExpander construction so tests don't require an event tap).
func installFeatureStateGating(
    workers: [FeatureID: [DaemonWorker]],
    defaults: UserDefaults,
    assetRequiredByID: [FeatureID: Bool]
) {
    let host = PerFeatureWorkerHost(workers: workers)
    self.workerHost = host
    for id in FeatureID.allCases {
        let state = FeatureStateReader.state(
            for: id, defaults: defaults,
            assetRequired: assetRequiredByID[id] ?? false
        )
        if state.activationState == .enabled {
            host.startWorkers(for: id)
        }
    }
    featureStateObserver = FeatureStateDarwinObserver(
        defaults: defaults,
        assetRequiredByID: assetRequiredByID,
        delegate: host
    )
}
#endif
```

> **Why an overload instead of injecting `defaults` everywhere:** the production daemon should keep using `AppGroupSettings.defaults` directly — there's no production reason to swap that. The test-only overload is the minimal seam.
>
> However, this still requires a `DaemonContainer` instance, which currently always opens GRDB databases. For the gating tests we don't need a real container — we test `PerFeatureWorkerHost` + `FeatureStateReader` interaction directly, see the test below.

- [ ] **Step 2: Write the test**

Create `ClipboardDaemonTests/DaemonContainerStartupGatingTests.swift`:
```swift
import XCTest
import FeatureCore
@testable import ClipboardDaemon

private final class FakeWorker: DaemonWorker {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

/// Exercises the same logic that `DaemonContainer.installFeatureStateGating` uses
/// to decide which workers to start, but without spinning up GRDB / NSPasteboard /
/// CGEventTap. Test parity with production is enforced by Task 6 Step 1's adapter
/// implementations being thin wrappers — the start-decision logic itself is here.
final class DaemonContainerStartupGatingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var pasteboard: FakeWorker!
    private var snippet: FakeWorker!

    override func setUp() {
        super.setUp()
        suiteName = "DaemonContainerStartupGatingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = FakeWorker()
        snippet = FakeWorker()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func writeState(_ state: FeatureRuntimeState, for id: FeatureID) {
        let data = try! JSONEncoder().encode(state)
        defaults.set(data, forKey: FeatureManager.persistKey(for: id))
    }

    /// Mirrors DaemonContainer.installFeatureStateGating's decision logic.
    private func bootGating(host: PerFeatureWorkerHost, assetRequiredByID: [FeatureID: Bool]) {
        for id in FeatureID.allCases {
            let s = FeatureStateReader.state(
                for: id, defaults: defaults,
                assetRequired: assetRequiredByID[id] ?? false
            )
            if s.activationState == .enabled {
                host.startWorkers(for: id)
            }
        }
    }

    func testNoStateWritten_NoWorkersStart() {
        // FeatureRuntimeState.initialDefault has activationState == .disabled.
        let host = PerFeatureWorkerHost(workers: [.clipboard: [pasteboard, snippet]])
        bootGating(host: host, assetRequiredByID: [:])
        XCTAssertEqual(pasteboard.startCount, 0)
        XCTAssertEqual(snippet.startCount, 0)
    }

    func testClipboardEnabled_StartsClipboardWorkers() {
        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        let host = PerFeatureWorkerHost(workers: [.clipboard: [pasteboard, snippet]])
        bootGating(host: host, assetRequiredByID: [:])
        XCTAssertEqual(pasteboard.startCount, 1)
        XCTAssertEqual(snippet.startCount, 1)
    }

    func testClipboardDisabled_NoWorkersStart() {
        writeState(.init(assetState: .notRequired, activationState: .disabled), for: .clipboard)
        let host = PerFeatureWorkerHost(workers: [.clipboard: [pasteboard, snippet]])
        bootGating(host: host, assetRequiredByID: [:])
        XCTAssertEqual(pasteboard.startCount, 0)
        XCTAssertEqual(snippet.startCount, 0)
    }

    func testFeatureWithNoMapping_DoesNotCrash() {
        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .voice)
        let host = PerFeatureWorkerHost(workers: [.clipboard: [pasteboard, snippet]])
        bootGating(host: host, assetRequiredByID: [:])
        // .voice is enabled but has no daemon-side workers — silent no-op.
        XCTAssertEqual(pasteboard.startCount, 0)
    }

    func testLiveTransition_DisableThenEnable() {
        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        let host = PerFeatureWorkerHost(workers: [.clipboard: [pasteboard, snippet]])
        bootGating(host: host, assetRequiredByID: [:])
        XCTAssertEqual(pasteboard.startCount, 1)

        // Simulate a Darwin-notification-driven disable.
        host.featureDidDisable(.clipboard)
        XCTAssertEqual(pasteboard.stopCount, 1)

        // ...and then a re-enable.
        host.featureDidEnable(.clipboard)
        XCTAssertEqual(pasteboard.startCount, 2)
    }
}
```

- [ ] **Step 3: Run test to verify it passes**

```bash
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonTests -destination 'platform=macOS,arch=arm64' \
  -only-testing:ClipboardDaemonTests/DaemonContainerStartupGatingTests | tail -20
```
Expected: PASS, 5/5 tests.

- [ ] **Step 4: Commit**

```bash
git add ClipboardDaemonTests/DaemonContainerStartupGatingTests.swift ClipboardDaemon/DaemonContainer.swift
git commit -m "feat(modular-features): add daemon startup gating tests"
```

---

### Task 8: Cross-process Darwin-notification round-trip test

This is the load-bearing test for Phase 10: it proves cross-process observation actually works. We can't fake this in-process — Darwin notifications are inherently cross-process and have subtle delivery semantics (coalescing, deliver-immediately vs. on-suspend, run-loop integration).

**Approach:** Build a tiny standalone Swift executable (`ChildDaemonProbe`) that mimics the daemon's observation pattern: opens `UserDefaults(suiteName:)`, installs `FeatureStateDarwinObserver` with a `PerFeatureWorkerHost` whose worker is an "echo to stdout" fake, and runs `RunLoop.main.run()`. The XCTest spawns it with `Process`, writes feature state via `UserDefaults`, posts the Darwin notification, reads stdout from the child, and asserts the expected start/stop messages appear.

**Files:**
- Create: `ClipboardDaemonCrossProcessTests/ChildDaemonProbe/main.swift`
- Create: `ClipboardDaemonCrossProcessTests/CrossProcessDarwinNotificationTests.swift`
- Modify: `Shared/Package.swift` (add the probe executable target) **OR** add the probe as a separate Xcode target — choose whichever fits the project layout (Shared package is simpler).

- [ ] **Step 1: Add the probe executable target to `Shared/Package.swift`**

Read the current Package.swift to find the targets array:
```bash
cat /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Package.swift
```

Append to `targets:`:
```swift
.executableTarget(
    name: "ChildDaemonProbe",
    dependencies: ["FeatureCore"],
    path: "Sources/ChildDaemonProbe"
),
```

And to `products:`:
```swift
.executable(name: "ChildDaemonProbe", targets: ["ChildDaemonProbe"]),
```

- [ ] **Step 2: Create the probe**

Create `Shared/Sources/ChildDaemonProbe/main.swift`:
```swift
import FeatureCore
import Foundation

/// A minimal stand-in for the daemon. Reads the App Group suite name from argv[1],
/// installs FeatureStateDarwinObserver with a PerFeatureWorkerHost whose workers
/// echo "start <id>" / "stop <id>" to stdout. Used by the cross-process integration
/// test to prove that Darwin notifications + AppGroupSettings reads work across
/// process boundaries.
///
/// Inlines a tiny copy of PerFeatureWorkerHost + DaemonWorker rather than depend on
/// the ClipboardDaemon target (which is an Xcode target, not an SPM target). The
/// production logic is exercised by the in-process tests in Task 7; this binary
/// only needs to faithfully exercise FeatureStateReader + FeatureStateDarwinObserver.

protocol Worker: AnyObject {
    func start()
    func stop()
}

final class EchoWorker: Worker {
    let id: FeatureID
    init(_ id: FeatureID) { self.id = id }
    func start() {
        print("start \(id.rawValue)")
        FileHandle.standardOutput.synchronizeFile()
    }
    func stop() {
        print("stop \(id.rawValue)")
        FileHandle.standardOutput.synchronizeFile()
    }
}

final class Host: FeatureStateObserverDelegate {
    let workers: [FeatureID: Worker]
    init(workers: [FeatureID: Worker]) { self.workers = workers }
    func featureDidEnable(_ id: FeatureID) { workers[id]?.start() }
    func featureDidDisable(_ id: FeatureID) { workers[id]?.stop() }
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: ChildDaemonProbe <suiteName>\n".utf8))
    exit(2)
}
let suiteName = CommandLine.arguments[1]
guard let defaults = UserDefaults(suiteName: suiteName) else {
    FileHandle.standardError.write(Data("could not open suite \(suiteName)\n".utf8))
    exit(3)
}

let host = Host(workers: [
    .clipboard: EchoWorker(.clipboard),
    .voice: EchoWorker(.voice),
])
let observer = FeatureStateDarwinObserver(
    defaults: defaults,
    assetRequiredByID: [:],
    delegate: host
)
_ = observer  // hold for process lifetime

// Apply current state on launch.
for id in FeatureID.allCases {
    let s = FeatureStateReader.state(for: id, defaults: defaults, assetRequired: false)
    if s.activationState == .enabled { host.workers[id]?.start() }
}

print("ready")
FileHandle.standardOutput.synchronizeFile()

RunLoop.main.run()
```

> **`FeatureStateDarwinObserver` lives in `ClipboardDaemon/`, not `Shared/`.** That's a problem for the SPM probe. Two options:
> 1. Move `FeatureStateDarwinObserver` to `Shared/Sources/FeatureCore/` so both the daemon and the probe can import it. **Preferred** — the type is reusable and has no daemon-specific dependencies.
> 2. Duplicate the observer code in the probe.
>
> Choose option 1. Move `ClipboardDaemon/FeatureStateDarwinObserver.swift` to `Shared/Sources/FeatureCore/FeatureStateDarwinObserver.swift`, and update the existing daemon-side imports to use it from `FeatureCore`. The Task 3 unit tests stay in `ClipboardDaemonTests` — they still exercise the same behavior. Move `FeatureStateObserverDelegate` along with it.

- [ ] **Step 3: Move `FeatureStateDarwinObserver` to `FeatureCore`**

```bash
git mv /Users/mingjie.wang/Documents/personal/mac-all-you-need/ClipboardDaemon/FeatureStateDarwinObserver.swift \
       /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/FeatureCore/FeatureStateDarwinObserver.swift
```

Update the file's `import` block to remove `import FeatureCore` (it's now part of FeatureCore). Verify no daemon-only types are referenced.

Re-run the daemon build to confirm the move worked:
```bash
xcodebuild build -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemon -destination 'platform=macOS,arch=arm64' | tail -5
```

Re-run the FeatureStateDarwinObserver tests; they may need their `@testable import ClipboardDaemon` swapped to `@testable import FeatureCore`.

- [ ] **Step 4: Write the cross-process test**

Create `ClipboardDaemonCrossProcessTests/CrossProcessDarwinNotificationTests.swift`:
```swift
import XCTest
import FeatureCore

final class CrossProcessDarwinNotificationTests: XCTestCase {
    private var process: Process!
    private var stdoutPipe: Pipe!
    private var probeURL: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CrossProcDarwinTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        // Resolve the probe binary path. `swift build` outputs to .build/<config>/.
        let sharedDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // CrossProcessDarwinNotificationTests dir
            .deletingLastPathComponent()  // ClipboardDaemonCrossProcessTests parent
            .appendingPathComponent("Shared")
        let candidate = sharedDir
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
            .appendingPathComponent("ChildDaemonProbe")
        if !FileManager.default.fileExists(atPath: candidate.path) {
            // Build it on demand.
            let build = Process()
            build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            build.arguments = ["swift", "build", "--product", "ChildDaemonProbe"]
            build.currentDirectoryURL = sharedDir
            build.environment = ProcessInfo.processInfo.environment.merging([
                "PKG_CONFIG_PATH": "/opt/homebrew/opt/libarchive/lib/pkgconfig"
            ]) { $1 }
            try! build.run()
            build.waitUntilExit()
            XCTAssertEqual(build.terminationStatus, 0, "swift build of ChildDaemonProbe failed")
        }
        probeURL = candidate
    }

    override func tearDown() {
        if process?.isRunning == true { process.terminate() }
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func writeState(_ state: FeatureRuntimeState, for id: FeatureID) {
        let data = try! JSONEncoder().encode(state)
        defaults.set(data, forKey: FeatureManager.persistKey(for: id))
        defaults.synchronize()
    }

    private func startProbe() throws -> AsyncStream<String> {
        process = Process()
        process.executableURL = probeURL
        process.arguments = [suiteName]
        stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        try process.run()

        // Read line-by-line from stdoutPipe asynchronously.
        return AsyncStream { continuation in
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty { continuation.finish(); return }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0a) {
                    let lineData = buffer.prefix(upTo: nl)
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if let line = String(data: lineData, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }

    private func waitForLine(_ expected: String, in stream: AsyncStream<String>, timeout: TimeInterval = 5) async {
        let exp = expectation(description: "saw \(expected)")
        Task {
            for await line in stream {
                if line.contains(expected) { exp.fulfill(); return }
            }
        }
        await fulfillment(of: [exp], timeout: timeout)
    }

    func testProbeEchoesStartOnEnable() async throws {
        let stream = try startProbe()
        await waitForLine("ready", in: stream)

        // Write enabled state for clipboard.
        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        DarwinNotification.post(DarwinNotification.featureStateDidChange)

        await waitForLine("start clipboard", in: stream)
    }

    func testProbeEchoesStopOnDisable() async throws {
        // Pre-seed enabled.
        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)

        let stream = try startProbe()
        await waitForLine("ready", in: stream)
        await waitForLine("start clipboard", in: stream)  // applied at probe launch

        // Now disable.
        writeState(.init(assetState: .notRequired, activationState: .disabled), for: .clipboard)
        DarwinNotification.post(DarwinNotification.featureStateDidChange)

        await waitForLine("stop clipboard", in: stream)
    }

    func testProbeHandlesMultipleFeaturesIndependently() async throws {
        let stream = try startProbe()
        await waitForLine("ready", in: stream)

        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .voice)
        DarwinNotification.post(DarwinNotification.featureStateDidChange)
        await waitForLine("start voice", in: stream)

        writeState(.init(assetState: .notRequired, activationState: .enabled), for: .clipboard)
        DarwinNotification.post(DarwinNotification.featureStateDidChange)
        await waitForLine("start clipboard", in: stream)

        writeState(.init(assetState: .notRequired, activationState: .disabled), for: .voice)
        DarwinNotification.post(DarwinNotification.featureStateDidChange)
        await waitForLine("stop voice", in: stream)
    }
}
```

> **About the suite name:** the cross-process test uses a per-test `UserDefaults(suiteName:)` rather than the production App Group identifier — both processes can open a non-App-Group suite by name and they share the same backing plist (`~/Library/Preferences/<suite>.plist`). This avoids polluting the real App Group state and works without entitlements. Darwin notifications are unaffected by App Group membership; they're a system-wide IPC channel keyed only on string name.
>
> **About `defaults.synchronize()`:** deprecated for general use, but explicitly required here because the writer and reader processes need their `UserDefaults` caches to flush to disk before the Darwin notification fires. `defaults.set` followed by an in-process `synchronize` ensures the child sees fresh data on its next read.

- [ ] **Step 5: Add the cross-process test target to `project.yml`**

```yaml
  ClipboardDaemonCrossProcessTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: 14.0
    sources:
      - path: ClipboardDaemonCrossProcessTests
        excludes: ["ChildDaemonProbe/**"]
    dependencies:
      - package: Shared
        product: FeatureCore
```

And a scheme:
```yaml
  ClipboardDaemonCrossProcessTests:
    build:
      targets:
        ClipboardDaemonCrossProcessTests: test
    test:
      targets: [ClipboardDaemonCrossProcessTests]
```

Regenerate:
```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need && xcodegen generate
```

- [ ] **Step 6: Run the test**

```bash
# First, ensure the probe is built.
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift build --product ChildDaemonProbe

# Then run the test.
xcodebuild test -workspace /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed.xcworkspace \
  -scheme ClipboardDaemonCrossProcessTests -destination 'platform=macOS,arch=arm64' | tail -25
```
Expected: PASS, 3/3 tests. Each test should take under 5 seconds — if any times out, the most likely cause is that `defaults.synchronize()` was missed (writer didn't flush before the reader process read).

- [ ] **Step 7: Commit**

```bash
git add Shared/Sources/ChildDaemonProbe/main.swift Shared/Package.swift \
        ClipboardDaemonCrossProcessTests/ project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): add cross-process Darwin notification test"
```

---

### Task 9: Verify the existing settings-reload Darwin pattern still works

Phase 10 is **purely additive** to the existing Darwin-notification observation in `DaemonContainer.installSettingsReloader()` (around line 149). The existing pattern observes `com.macallyouneed.settings-changed` and reloads exclusion rules + runs retention. We must not break it.

- [ ] **Step 1: Identify how the existing notification gets posted**

```bash
grep -rn "settings-changed\|settingsChangedDarwin" /Users/mingjie.wang/Documents/personal/mac-all-you-need --include="*.swift"
```

The main app posts this when the user edits clipboard exclusion rules or retention settings. Find the call site:
```bash
grep -rn "CFNotificationCenterPostNotification\|DarwinNotification.post" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed --include="*.swift"
```

- [ ] **Step 2: Add a regression test**

If a settings-reload test doesn't already exist, add one to `ClipboardDaemonTests/`. The test confirms that posting `com.macallyouneed.settings-changed` (separate from `com.macallyouneed.featureStateDidChange`) still triggers `loadRules()` reading. If the daemon's `installSettingsReloader` is internal-only, exercise it via a smoke test that constructs `DaemonContainer`, mutates `AppGroupSettings.defaults`, posts the notification, and waits for `container.observer.rules` to update.

If writing this test is hard (DaemonContainer touches GRDB which requires file paths), accept a manual verification:

```bash
# Manual:
# 1. Launch the app fresh.
# 2. Open Settings → Clipboard → Excluded Applications, add "com.example.test".
# 3. Tail Console.app filtered to "ClipboardDaemon".
# 4. Confirm "loadRules" or equivalent log line fires within ~1s of the change.
```

- [ ] **Step 3: Confirm both observers coexist by inspection**

Read the modified `DaemonContainer.swift` and confirm:
- `installSettingsReloader()` is still called from `init()`.
- `installFeatureStateGating()` is the only new caller of `CFNotificationCenterAddObserver`.
- The two observers have **different** observation names (`com.macallyouneed.settings-changed` vs. `com.macallyouneed.featureStateDidChange`) and different opaque pointers (one is `self`, the other is the `FeatureStateDarwinObserver` instance), so they cannot collide.

- [ ] **Step 4: Commit (regression test only)**

```bash
git add ClipboardDaemonTests/  # any new regression test files
git commit -m "feat(modular-features): regression-test settings-reload Darwin pattern" || true
```
(`|| true` because if Step 2 was deferred to manual verification, there's nothing to commit.)

---

### Task 10: Manual end-to-end smoke

Verify the full main-app → daemon pipeline live, with no test mocks.

- [ ] **Step 1: Reset state**

```bash
# Identify the App Group identifier:
grep -n "AppGroup.identifier\|let identifier =" /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared/Sources/Core/AppGroup.swift | head -5
# Then (replace <id> with the value found above):
defaults delete <id> || true
```

- [ ] **Step 2: Launch the app**

```bash
open /Applications/MacAllYouNeed.app  # or wherever the local debug build lives
```

Confirm in Console.app (filtered to "ClipboardDaemon"):
- "ClipboardDaemon ready" log line appears.
- The pasteboard polling logs (e.g., NSPasteboard change-count messages, if instrumented) appear, indicating the clipboard worker started.

Copy text from another app, verify it lands in the clipboard popup (`⌘⇧V`).

- [ ] **Step 3: Disable Clipboard in Settings → Features (Phase 05 UI)**

Use the Features tab to flip Clipboard to disabled.

Within ~1 second, confirm in Console.app:
- A log line indicating the daemon received the notification and stopped the pasteboard worker. (Add an `NSLog("[FeatureStateDarwinObserver] disabled \(id)")` in `featureDidDisable` if logging isn't already there.)

Then:
- Copy text from another app.
- Open the popup. New copies should **not** appear (because the worker stopped).
- Activity Monitor: ClipboardDaemon process CPU drops to ~0%.

- [ ] **Step 4: Re-enable Clipboard**

Toggle back on. Confirm:
- "[FeatureStateDarwinObserver] enabled clipboard" log.
- New copies start appearing again.

- [ ] **Step 5: Disable Voice (no daemon-side workers)**

Toggle Voice off. The daemon log should show the notification fired (the observer always processes), but `PerFeatureWorkerHost.featureDidDisable(.voice)` is a silent no-op since `.voice` has no entry in the workers map. No errors should appear.

---

### Task 11: Phase verification

- [ ] **Step 1: Full Shared test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureCore
```
Expected: all tests pass (FeatureStateReaderTests + FeatureStateDarwinObserverTests if you moved them).

- [ ] **Step 2: Full Xcode test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemonTests \
  -destination 'platform=macOS,arch=arm64' | tail -30
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme ClipboardDaemonCrossProcessTests \
  -destination 'platform=macOS,arch=arm64' | tail -30
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
```
Expected: all green.

- [ ] **Step 3: Run CI**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```
Expected: pass.

- [ ] **Step 4: Mark phase complete in index plan**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md`, change:
```markdown
- [ ] Phase 10 — Daemon Darwin observation
```
to:
```markdown
- [x] Phase 10 — Daemon Darwin observation
```

- [ ] **Step 5: Commit + open PR**

```bash
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 10 complete"
git push -u origin <branch>
gh pr create --title "Phase 10 — Daemon Darwin observation + worker gating" --body "Implements docs/superpowers/plans/2026-05-15-modular-features/10-daemon-darwin-observation.md"
```
