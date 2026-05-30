# Shared Infrastructure (S1 + S2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two shared pieces the 2026 feature expansion depends on — a reusable `AXObserverCoordinator` (S1) and a reusable LLM intent service factored out of the Voice cleanup pipeline (S2) — without changing any existing Voice behavior.

**Architecture:** S1 lives in the `Platform` package alongside the existing AX helpers; its raw `AXObserverCreate`/run-loop machinery is hidden behind an injectable `AXObserverEngine` protocol so the registration/health-check logic is unit-testable while the real CoreFoundation path is exercised by a manual check. S2 introduces a thin `LLMIntentService` in the app target that reuses the existing `VoiceCleanupProviderFactory` + `VoiceCleanupSettings` (Groq default + local opt-in) and a named-template prompt builder, while the Voice cleanup path is refactored to route through the new prompt-template seam unchanged (proven by characterization runs of the existing `VoicePromptBuilder*` tests before and after).

**Tech Stack:** Swift 5.9+, AppKit, ApplicationServices (AX), XCTest, existing Voice/Groq infra

---

## File Structure

### S1 — `AXObserverCoordinator`

| File | Status | Responsibility |
|------|--------|----------------|
| `Shared/Sources/Platform/Accessibility/AXObserverEngine.swift` | Create | Protocol abstracting `AXObserverCreate` + run-loop source + add/remove notification, plus the live `SystemAXObserverEngine` implementation. The injectable seam. |
| `Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift` | Create | Reusable coordinator: owns one observer per target pid, subscribes to a set of notifications, fans out to a Swift callback, and re-subscribes on a periodic health-check timer when the target rebuilds its AX tree. No feature logic. |
| `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` | Create | Unit tests driving the coordinator with a fake `AXObserverEngine` (registration, health-check re-subscribe, callback fan-out, teardown). |

> S1 placement note: `Platform` already hosts AX code (`Shared/Sources/Platform/WindowControl/WindowAccessibilityElement.swift`) and is a dependency of the app target, so both Finder history (B) and Dock previews (F) can consume `AXObserverCoordinator` from there. Shared tests live under `Shared/Tests/CoreTests/` per the existing convention (the test target imports both `Core` and `Platform`).

### S2 — LLM intent layer

| File | Status | Responsibility |
|------|--------|----------------|
| `MacAllYouNeed/Voice/Cleanup/VoicePromptBuilder.swift` | Modify (~lines 49-55) | Add a named-template indirection (`LLMPromptTemplate`) so `systemPrompt(context:)` becomes one template among several, without changing its output. |
| `MacAllYouNeed/LLM/LLMIntentService.swift` | Create | Reusable service: given a named prompt template + input text + the user's configured cleanup provider (Groq default, local opt-in), returns a completion. Injectable provider factory for tests. Used by C and E. |
| `MacAllYouNeed/LLM/LLMIntentTemplate.swift` | Create | `LLMIntentTemplate` enum + a registry mapping each case to a `(system, user)` prompt pair. Voice cleanup is registered as the `.voiceCleanup` template delegating to `VoicePromptBuilder`. |
| `MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift` | Create | Unit tests: template selection, provider selection (Groq default / nil when disabled), input/output passthrough with an injected fake provider. |
| `MacAllYouNeedTests/LLM/LLMIntentTemplateTests.swift` | Create | Unit tests: each template renders a non-empty system prompt; `.voiceCleanup` output is byte-identical to `VoicePromptBuilder.systemPrompt`. |

> S2 placement note: `VoicePromptBuilder`, `VoiceCleanupPipeline`, the providers, and `VoiceCleanupProviderFactory` all live in the **app target** (`MacAllYouNeed/Voice/Cleanup/`), not in `Shared`. The new `LLMIntentService` therefore lives app-side too and is tested via `xcodebuild`. It deliberately reuses `VoiceCleanupProviderFactory.makeProvider(settings:keyStore:)` so the user's existing Groq/local configuration is honored with zero new model stack.

---

## S1 — `AXObserverCoordinator`

### Task 1: Define the `AXObserverEngine` seam (failing test first)

**Files:**
- Test: `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` (Create)
- Create: `Shared/Sources/Platform/Accessibility/AXObserverEngine.swift`

- [ ] Write the failing test. Create `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift`:

```swift
import ApplicationServices
import Foundation
@testable import Platform
import XCTest

/// Fake engine that records registration calls so we can assert the coordinator's
/// behavior without a live AXObserver / run loop.
final class FakeAXObserverEngine: AXObserverEngine, @unchecked Sendable {
    struct Subscription: Equatable {
        let pid: pid_t
        let notification: String
    }

    private(set) var created: [pid_t] = []
    private(set) var subscriptions: [Subscription] = []
    private(set) var removed: [Subscription] = []
    private(set) var torndown = 0
    var failNextCreate = false
    var failSubscribeForPID: pid_t?

    func makeObserver(pid: pid_t) -> AXObserverHandle? {
        if failNextCreate { return nil }
        created.append(pid)
        return AXObserverHandle(pid: pid, token: created.count)
    }

    func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool {
        if let failSubscribeForPID, failSubscribeForPID == handle.pid { return false }
        subscriptions.append(.init(pid: handle.pid, notification: notification))
        return true
    }

    func unsubscribe(_ handle: AXObserverHandle, notification: String) {
        removed.append(.init(pid: handle.pid, notification: notification))
    }

    func teardown(_ handle: AXObserverHandle) {
        torndown += 1
    }
}

final class AXObserverCoordinatorTests: XCTestCase {
    func testMakeObserverHandleCarriesPID() {
        let engine = FakeAXObserverEngine()
        let handle = engine.makeObserver(pid: 42)
        XCTAssertEqual(handle?.pid, 42)
        XCTAssertEqual(engine.created, [42])
    }
}
```

- [ ] Run to verify fail. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: compile error — `cannot find 'AXObserverEngine' in scope` / `cannot find 'AXObserverHandle' in scope`.

- [ ] Minimal implementation. Create `Shared/Sources/Platform/Accessibility/AXObserverEngine.swift`:

```swift
import ApplicationServices
import Foundation

/// Opaque handle to a created observer. The live engine stores the real
/// `AXObserver` + `AXUIElement`; the fake engine just carries identity.
public struct AXObserverHandle {
    public let pid: pid_t
    let token: Int
    var axObserver: AXObserver?
    var appElement: AXUIElement?

    public init(pid: pid_t, token: Int, axObserver: AXObserver? = nil, appElement: AXUIElement? = nil) {
        self.pid = pid
        self.token = token
        self.axObserver = axObserver
        self.appElement = appElement
    }
}

/// Injectable seam over the raw AX observer API so `AXObserverCoordinator`
/// can be unit-tested without a live run loop. The live implementation is
/// `SystemAXObserverEngine`; tests use a fake.
public protocol AXObserverEngine: Sendable {
    func makeObserver(pid: pid_t) -> AXObserverHandle?
    func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool
    func unsubscribe(_ handle: AXObserverHandle, notification: String)
    func teardown(_ handle: AXObserverHandle)
}
```

- [ ] Run to verify pass. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: `testMakeObserverHandleCarriesPID` passes (1 test, 0 failures).

- [ ] Commit. Command:
```
git add Shared/Sources/Platform/Accessibility/AXObserverEngine.swift Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift
git commit -m "$(printf 'S1: add AXObserverEngine seam + handle\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: Coordinator subscribes to all notifications on start

**Files:**
- Test: `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` (Modify — add method)
- Create: `Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift`

- [ ] Write the failing test. Append to `AXObserverCoordinatorTests`:

```swift
    @MainActor
    func testStartSubscribesToEveryNotification() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(
            engine: engine,
            healthCheckInterval: 999,
            now: { Date() }
        )
        var received: [String] = []
        coordinator.start(
            pid: 7,
            notifications: ["AXWindowCreated", "AXFocusedWindowChanged"]
        ) { notification, _ in
            received.append(notification)
        }

        XCTAssertEqual(engine.created, [7])
        XCTAssertEqual(
            engine.subscriptions,
            [.init(pid: 7, notification: "AXWindowCreated"),
             .init(pid: 7, notification: "AXFocusedWindowChanged")]
        )
        XCTAssertTrue(received.isEmpty, "no callbacks until the engine reports an event")
    }
```

- [ ] Run to verify fail. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: compile error — `cannot find 'AXObserverCoordinator' in scope`.

- [ ] Minimal implementation. Create `Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift`:

```swift
import ApplicationServices
import Foundation

/// Reusable Accessibility observation utility. Attaches an `AXObserver` to a
/// target process, subscribes to a set of notifications, fans out to a Swift
/// callback, and re-subscribes via a periodic health-check when the target
/// rebuilds its AX tree (the Dock and Finder both do this silently).
///
/// Owns no feature logic. Consumed by Finder history (B) and Dock previews (F).
@MainActor
public final class AXObserverCoordinator {
    public typealias EventCallback = (_ notification: String, _ pid: pid_t) -> Void

    private let engine: AXObserverEngine
    private let healthCheckInterval: TimeInterval
    private let now: () -> Date

    private var handle: AXObserverHandle?
    private var pid: pid_t?
    private var notifications: [String] = []
    private var callback: EventCallback?
    private var healthCheckTask: Task<Void, Never>?

    public init(
        engine: AXObserverEngine,
        healthCheckInterval: TimeInterval = 3,
        now: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.healthCheckInterval = healthCheckInterval
        self.now = now
    }

    public func start(
        pid: pid_t,
        notifications: [String],
        onEvent: @escaping EventCallback
    ) {
        stop()
        self.pid = pid
        self.notifications = notifications
        callback = onEvent
        subscribeAll()
    }

    public func stop() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        if let handle {
            for notification in notifications {
                engine.unsubscribe(handle, notification: notification)
            }
            engine.teardown(handle)
        }
        handle = nil
        pid = nil
        notifications = []
        callback = nil
    }

    /// Internal so tests can drive the engine's callback path directly.
    func dispatch(notification: String) {
        guard let pid else { return }
        callback?(notification, pid)
    }

    private func subscribeAll() {
        guard let pid else { return }
        guard let newHandle = engine.makeObserver(pid: pid) else {
            handle = nil
            return
        }
        var allOK = true
        for notification in notifications where !engine.subscribe(newHandle, notification: notification) {
            allOK = false
        }
        handle = newHandle
        _ = allOK
    }
}
```

- [ ] Run to verify pass. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: both tests pass (2 tests, 0 failures).

- [ ] Commit. Command:
```
git add Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift
git commit -m "$(printf 'S1: AXObserverCoordinator subscribes on start\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: Callback fan-out delivers engine events

**Files:**
- Test: `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` (Modify — add method)
- Modify: `Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift` (the `dispatch` path is already present; this task proves it)

- [ ] Write the failing test. Append to `AXObserverCoordinatorTests`:

```swift
    @MainActor
    func testEngineEventReachesCallbackWithPID() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(
            engine: engine,
            healthCheckInterval: 999,
            now: { Date() }
        )
        var received: [(String, pid_t)] = []
        coordinator.start(pid: 11, notifications: ["AXWindowCreated"]) { notification, pid in
            received.append((notification, pid))
        }

        coordinator.dispatch(notification: "AXWindowCreated")

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, "AXWindowCreated")
        XCTAssertEqual(received.first?.1, 11)
    }

    @MainActor
    func testDispatchAfterStopIsIgnored() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        var count = 0
        coordinator.start(pid: 1, notifications: ["AXWindowCreated"]) { _, _ in count += 1 }
        coordinator.stop()
        coordinator.dispatch(notification: "AXWindowCreated")
        XCTAssertEqual(count, 0)
        XCTAssertEqual(engine.torndown, 1)
    }
```

- [ ] Run to verify fail. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: `testDispatchAfterStopIsIgnored` fails — after `stop()`, `pid` is nil so `dispatch` returns early and `count == 0`, but `engine.torndown` assertion confirms teardown happened. (If the implementation from Task 2 already passes both, that is acceptable; the new assertions characterize the contract — proceed to commit.) The first run should show a failure only if Task 2's `dispatch`/`stop` differs; if green, treat this task as adding regression coverage and skip straight to the pass step.

- [ ] Run to verify pass. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: all 4 tests pass.

- [ ] Commit. Command:
```
git add Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift
git commit -m "$(printf 'S1: cover callback fan-out + stop teardown\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: Health-check re-subscribe when the AX tree is rebuilt

**Files:**
- Test: `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` (Modify — add method)
- Modify: `Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift` (add `healthCheckNow()` + timer wiring)

The Dock and Finder silently rebuild their AX trees, which invalidates the observer. The coordinator must detect a dead handle and re-create + re-subscribe. We expose a synchronous `healthCheckNow()` for deterministic testing and drive it from the timer in production.

- [ ] Write the failing test. Append to `AXObserverCoordinatorTests`:

```swift
    @MainActor
    func testHealthCheckReSubscribesWhenHandleIsStale() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        coordinator.start(pid: 5, notifications: ["AXWindowCreated"]) { _, _ in }

        XCTAssertEqual(engine.created, [5])
        XCTAssertEqual(engine.subscriptions.count, 1)

        // Simulate the target rebuilding its AX tree: the existing observer is dead.
        coordinator.markStaleForTesting()
        coordinator.healthCheckNow()

        // A fresh observer is created and re-subscribed to the same notifications.
        XCTAssertEqual(engine.created, [5, 5], "a second observer is created on re-subscribe")
        XCTAssertEqual(engine.subscriptions.count, 2)
        XCTAssertEqual(engine.torndown, 1, "the stale observer is torn down before re-create")
    }

    @MainActor
    func testHealthCheckIsNoOpWhenHandleIsHealthy() {
        let engine = FakeAXObserverEngine()
        let coordinator = AXObserverCoordinator(engine: engine, healthCheckInterval: 999)
        coordinator.start(pid: 5, notifications: ["AXWindowCreated"]) { _, _ in }
        coordinator.healthCheckNow()
        XCTAssertEqual(engine.created, [5], "no re-create while healthy")
        XCTAssertEqual(engine.subscriptions.count, 1)
        XCTAssertEqual(engine.torndown, 0)
    }
```

- [ ] Run to verify fail. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: compile error — `value of type 'AXObserverCoordinator' has no member 'markStaleForTesting'` / `healthCheckNow`.

- [ ] Minimal implementation. In `AXObserverCoordinator.swift`, add a liveness flag, a `healthCheckNow()`, a `markStaleForTesting()`, and start the timer in `start()`. Apply these edits:

  Add stored property after `private var healthCheckTask: Task<Void, Never>?`:
```swift
    private var isHandleLive = false
```

  In `start(...)`, after `subscribeAll()`, append:
```swift
        startHealthCheckTimer()
```

  In `subscribeAll()`, set liveness — replace the final `handle = newHandle` / `_ = allOK` lines with:
```swift
        handle = newHandle
        isHandleLive = allOK
```

  Add these methods before the closing brace:
```swift
    /// Re-creates and re-subscribes the observer if the previous handle has
    /// gone stale (target rebuilt its AX tree). Safe to call repeatedly.
    func healthCheckNow() {
        guard pid != nil else { return }
        guard !isHandleLive else { return }
        if let handle {
            for notification in notifications {
                engine.unsubscribe(handle, notification: notification)
            }
            engine.teardown(handle)
        }
        handle = nil
        subscribeAll()
    }

    /// Test hook: simulate the target invalidating the observer.
    func markStaleForTesting() {
        isHandleLive = false
    }

    private func startHealthCheckTimer() {
        healthCheckTask?.cancel()
        let interval = healthCheckInterval
        healthCheckTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self.healthCheckNow()
            }
        }
    }
```

- [ ] Run to verify pass. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: all 6 tests pass.

- [ ] Commit. Command:
```
git add Shared/Sources/Platform/Accessibility/AXObserverCoordinator.swift Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift
git commit -m "$(printf 'S1: health-check re-subscribe on stale AX tree\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 5: Live `SystemAXObserverEngine` (real AX path, manual verification)

**Files:**
- Test: `Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift` (Modify — add construction-only test)
- Modify: `Shared/Sources/Platform/Accessibility/AXObserverEngine.swift` (add `SystemAXObserverEngine`)

The raw `AXObserverCreate` + run-loop path cannot be unit-tested without a live, AX-trusted process and a focused target. We add the live engine and a construction smoke test; the real notification flow is verified manually.

- [ ] Write the failing test. Append to `AXObserverCoordinatorTests`:

```swift
    func testSystemEngineConstructs() {
        // Smoke test only: real AXObserverCreate requires AX trust + a live
        // target pid, exercised in the manual verification step below.
        let engine = SystemAXObserverEngine()
        XCTAssertNotNil(engine as AXObserverEngine)
    }
```

- [ ] Run to verify fail. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: compile error — `cannot find 'SystemAXObserverEngine' in scope`.

- [ ] Minimal implementation. Append to `Shared/Sources/Platform/Accessibility/AXObserverEngine.swift`:

```swift
/// Live engine backed by `AXObserverCreate` + a run-loop source. The observer
/// callback bridges back to the coordinator via the `refcon` pointer.
public final class SystemAXObserverEngine: AXObserverEngine, @unchecked Sendable {
    /// Routes the C callback to a Swift closure stored per handle token.
    private final class Box {
        let onEvent: (String) -> Void
        init(_ onEvent: @escaping (String) -> Void) { self.onEvent = onEvent }
    }

    private var boxes: [Int: Box] = [:]
    private var nextToken = 0
    private let onEventFactory: (pid_t) -> (String) -> Void

    /// `onEventFactory` returns, for a given pid, the closure invoked on each
    /// AX notification (the coordinator supplies one that calls `dispatch`).
    public init(onEventFactory: @escaping (pid_t) -> (String) -> Void = { _ in { _ in } }) {
        self.onEventFactory = onEventFactory
    }

    public func makeObserver(pid: pid_t) -> AXObserverHandle? {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let box = Unmanaged<Box>.fromOpaque(refcon).takeUnretainedValue()
            box.onEvent(notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
            return nil
        }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        nextToken += 1
        boxes[nextToken] = Box(onEventFactory(pid))
        let appElement = AXUIElementCreateApplication(pid)
        return AXObserverHandle(pid: pid, token: nextToken, axObserver: observer, appElement: appElement)
    }

    public func subscribe(_ handle: AXObserverHandle, notification: String) -> Bool {
        guard let observer = handle.axObserver,
              let element = handle.appElement,
              let box = boxes[handle.token]
        else { return false }
        let refcon = Unmanaged.passUnretained(box).toOpaque()
        return AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success
    }

    public func unsubscribe(_ handle: AXObserverHandle, notification: String) {
        guard let observer = handle.axObserver, let element = handle.appElement else { return }
        AXObserverRemoveNotification(observer, element, notification as CFString)
    }

    public func teardown(_ handle: AXObserverHandle) {
        if let observer = handle.axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        boxes[handle.token] = nil
    }
}
```

- [ ] Run to verify pass. Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter AXObserverCoordinatorTests`
  Expected: all 7 tests pass.

- [ ] **Manual verification (real AX path).** Add a temporary throwaway harness (do not commit it) in the app — e.g. in `AppController` debug code — that does:
```swift
let engine = SystemAXObserverEngine(onEventFactory: { _ in { n in print("AX:", n) } })
let coord = AXObserverCoordinator(engine: engine)
let dockPID = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.dock" }!.processIdentifier
coord.start(pid: dockPID, notifications: ["AXWindowCreated", "AXUIElementDestroyed"]) { n, _ in print("coord:", n) }
```
  Grant Accessibility, run the app, hover the Dock / open Mission Control, and confirm `AX:` / `coord:` lines print. Then quit and relaunch the Dock (`killall Dock`) and confirm events still arrive after ~3s (health-check re-subscribe). Remove the harness before committing.

- [ ] Commit. Command:
```
git add Shared/Sources/Platform/Accessibility/AXObserverEngine.swift Shared/Tests/CoreTests/Accessibility/AXObserverCoordinatorTests.swift
git commit -m "$(printf 'S1: live SystemAXObserverEngine over AXObserverCreate\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## S2 — LLM intent layer (refactor Voice cleanup into a reusable service)

> **CRITICAL:** Voice behavior must be byte-for-byte unchanged. Task 6 captures a characterization baseline of the existing Voice prompt/cleanup tests BEFORE any refactor; Task 10 re-runs the same suite AFTER the refactor to prove no regression.

### Task 6: Characterization baseline — existing Voice tests pass BEFORE refactor

**Files:**
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderPersonalizationTests.swift` (run only — no edit)

- [ ] Run the existing Voice prompt suite and record the baseline. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoicePromptBuilderPersonalizationTests 2>&1 | tail -30`
  Expected: `** TEST SUCCEEDED **`, 10 tests in `VoicePromptBuilderPersonalizationTests` all pass. Record the count (10) as the baseline — it must be identical after the refactor.

- [ ] Capture the exact current voice cleanup system prompt as a golden string (used by Task 9 to prove `.voiceCleanup` is identical). No file change yet; note the value produced by:
  `VoicePromptBuilder.systemPrompt(context: VoicePromptContext(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil))`
  Task 9 asserts equality against this exact call, so no manual transcription is needed.

- [ ] No commit (read-only baseline).

---

### Task 7: Add `LLMIntentTemplate` registry (`.voiceCleanup` delegates to `VoicePromptBuilder`)

**Files:**
- Test: `MacAllYouNeedTests/LLM/LLMIntentTemplateTests.swift` (Create)
- Create: `MacAllYouNeed/LLM/LLMIntentTemplate.swift`
- After adding the new source directory, regenerate the project.

- [ ] Write the failing test. Create `MacAllYouNeedTests/LLM/LLMIntentTemplateTests.swift`:

```swift
import Core
@testable import MacAllYouNeed
import XCTest

final class LLMIntentTemplateTests: XCTestCase {
    func testVoiceCleanupTemplateMatchesVoicePromptBuilder() {
        let ctx = VoicePromptContext(
            language: .english,
            appBundleID: nil,
            dictionaryEntries: [],
            translationTarget: nil
        )
        let expected = VoicePromptBuilder.systemPrompt(context: ctx)
        let rendered = LLMIntentTemplate.voiceCleanup.systemPrompt(voiceContext: ctx)
        XCTAssertEqual(rendered, expected, "voiceCleanup template must be byte-identical to VoicePromptBuilder")
    }

    func testUserPromptWrapsInput() {
        let user = LLMIntentTemplate.voiceCleanup.userPrompt(input: "hello")
        XCTAssertEqual(user, VoicePromptBuilder.userPrompt(transcript: "hello"))
    }
}
```

- [ ] Run to verify fail. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/LLMIntentTemplateTests 2>&1 | tail -20`
  Expected: compile failure — `cannot find 'LLMIntentTemplate' in scope`.

- [ ] Minimal implementation. Create `MacAllYouNeed/LLM/LLMIntentTemplate.swift`:

```swift
import Core
import Foundation

/// Named prompt templates for the reusable LLM intent layer. Each case knows
/// how to render a system prompt for its task. `.voiceCleanup` delegates to the
/// existing `VoicePromptBuilder` so Voice behavior is unchanged; new callers
/// (Voice Reminders, File Organizer) add their own cases without touching Voice.
enum LLMIntentTemplate {
    case voiceCleanup

    /// Voice cleanup renders from a `VoicePromptContext`. This overload keeps the
    /// existing voice call site identical.
    func systemPrompt(voiceContext: VoicePromptContext) -> String {
        switch self {
        case .voiceCleanup:
            return VoicePromptBuilder.systemPrompt(context: voiceContext)
        }
    }

    func userPrompt(input: String) -> String {
        switch self {
        case .voiceCleanup:
            return VoicePromptBuilder.userPrompt(transcript: input)
        }
    }
}
```

- [ ] Regenerate the project so the new `MacAllYouNeed/LLM/` directory is picked up. Command:
  `xcodegen generate`
  Expected: `Created project at .../MacAllYouNeed.xcodeproj`.

- [ ] Run to verify pass. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/LLMIntentTemplateTests 2>&1 | tail -20`
  Expected: `** TEST SUCCEEDED **`, both tests pass.

- [ ] Commit. Command:
```
git add MacAllYouNeed/LLM/LLMIntentTemplate.swift MacAllYouNeedTests/LLM/LLMIntentTemplateTests.swift MacAllYouNeed.xcodeproj/project.pbxproj
git commit -m "$(printf 'S2: LLMIntentTemplate registry delegating voice cleanup\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 8: `LLMIntentService` selects the configured provider (Groq default / local opt-in)

**Files:**
- Test: `MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift` (Create)
- Create: `MacAllYouNeed/LLM/LLMIntentService.swift`

The service reuses `VoiceCleanupProviderFactory.makeProvider(settings:keyStore:)` so it honors the exact Groq/local configuration the user already set for Voice. We inject the provider factory so tests never hit the network or keychain.

- [ ] Write the failing test. Create `MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift`:

```swift
import Core
@testable import MacAllYouNeed
import XCTest

/// Fake provider records the request it received and returns a canned response.
final class FakeLLMProvider: VoiceLLMProvider, @unchecked Sendable {
    let providerIdentifier = "fake"
    private(set) var lastRequest: VoiceLLMRequest?
    var response = "CLEANED"

    func clean(_ request: VoiceLLMRequest) async throws -> String {
        lastRequest = request
        return response
    }
}

final class LLMIntentServiceTests: XCTestCase {
    func testReturnsNilWhenNoProviderConfigured() async {
        let service = LLMIntentService(makeProvider: { nil })
        let result = await service.run(
            template: .voiceCleanup,
            input: "hello world this is a test",
            voiceContext: .init(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil)
        )
        XCTAssertNil(result, "no provider configured -> service yields nil, caller falls back")
    }

    func testRoutesInputThroughConfiguredProvider() async {
        let fake = FakeLLMProvider()
        let service = LLMIntentService(makeProvider: { fake })
        let result = await service.run(
            template: .voiceCleanup,
            input: "hello world this is a test",
            voiceContext: .init(language: .english, appBundleID: nil, dictionaryEntries: [], translationTarget: nil)
        )
        XCTAssertEqual(result, "CLEANED")
        XCTAssertEqual(fake.lastRequest?.text, "hello world this is a test")
    }
}
```

- [ ] Run to verify fail. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/LLMIntentServiceTests 2>&1 | tail -20`
  Expected: compile failure — `cannot find 'LLMIntentService' in scope`.

- [ ] Minimal implementation. Create `MacAllYouNeed/LLM/LLMIntentService.swift`:

```swift
import Core
import Foundation

/// Reusable LLM intent service. Runs `input` text through the user's configured
/// cleanup provider (Groq default + local opt-in — the same selection Voice
/// uses) with a named prompt template. Returns nil when no provider is
/// configured/enabled so the caller can fall back to local behavior.
///
/// `makeProvider` is injectable: production wires it to
/// `VoiceCleanupProviderFactory.makeProvider(settings:keyStore:)`; tests inject
/// a fake. This is the same provider seam `VoiceCoordinator` already uses.
struct LLMIntentService {
    private let makeProvider: () -> (any VoiceLLMProvider)?

    init(makeProvider: @escaping () -> (any VoiceLLMProvider)?) {
        self.makeProvider = makeProvider
    }

    /// Production initializer: reuse the user's voice cleanup configuration.
    init(
        settings: @escaping () -> VoiceCleanupSettings = { VoiceCleanupSettingsStore.load() },
        keyStore: VoiceCleanupKeyStore = VoiceCleanupKeyStore(keychain: SystemKeychain())
    ) {
        self.makeProvider = {
            (try? VoiceCleanupProviderFactory.makeProvider(settings: settings(), keyStore: keyStore)) ?? nil
        }
    }

    /// Renders the template, calls the provider, and returns the trimmed result.
    /// Returns nil when no provider is configured or the provider errors.
    func run(
        template: LLMIntentTemplate,
        input: String,
        voiceContext: VoicePromptContext
    ) async -> String? {
        guard let provider = makeProvider() else { return nil }
        let request = VoiceLLMRequest(
            text: input,
            rawText: input,
            appBundleID: voiceContext.appBundleID,
            language: voiceContext.language,
            dictionaryEntries: voiceContext.dictionaryEntries,
            translationTarget: voiceContext.translationTarget,
            appInstructions: voiceContext.appInstructions,
            personalStyleNotes: voiceContext.personalStyleNotes,
            personalizationSummary: voiceContext.personalizationSummary,
            recentExamples: voiceContext.recentExamples
        )
        do {
            let output = try await provider.clean(request)
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
```

> Note on `template`: for `.voiceCleanup` the provider's own `clean` already injects the voice prompt, so `voiceContext` carries the personalization. New non-voice templates added later will route their system/user prompts through `VoiceTextGenerationProvider.generate(systemPrompt:userText:)` instead — that is feature-local work for C/E and out of scope here. This task only proves the provider-selection + injection seam is reusable.

- [ ] Run to verify pass. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/LLMIntentServiceTests 2>&1 | tail -20`
  Expected: `** TEST SUCCEEDED **`, both tests pass.

- [ ] Commit. Command:
```
git add MacAllYouNeed/LLM/LLMIntentService.swift MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift
git commit -m "$(printf 'S2: LLMIntentService reuses voice provider selection\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 9: Prove the Groq default + local opt-in selection is the same the user configured

**Files:**
- Test: `MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift` (Modify — add method)
- Modify: none (asserts existing `VoiceCleanupProviderFactory` behavior through the service)

- [ ] Write the failing test. Append to `LLMIntentServiceTests`:

```swift
    func testDisabledCleanupSettingsYieldNoProvider() {
        // When the user has cleanup disabled, the factory returns nil and the
        // service must, too — i.e. it honors the existing voice configuration.
        var settings = VoiceCleanupSettings.default
        settings.isEnabled = false
        let provider = try? VoiceCleanupProviderFactory.makeProvider(
            settings: settings,
            keyStore: VoiceCleanupKeyStore(keychain: SystemKeychain())
        )
        XCTAssertNil(provider ?? nil, "disabled cleanup -> no provider, matching voice behavior")
    }

    func testGroqIsTheDefaultCleanupProviderKind() {
        // Locks the product decision: Groq is the default for the shared layer.
        XCTAssertEqual(VoiceCleanupSettings.default.provider, .groq)
    }
```

> Before running, confirm the two facts the test asserts: (a) `VoiceCleanupSettings` has a mutable `isEnabled` and a `.default`; (b) `VoiceCleanupSettings.default.provider == .groq`. If the default provider in `VoiceCleanupSettings.swift` is not `.groq`, change the second assertion to the actual default and note it in the Self-Review — do NOT change product settings to satisfy a test. (Grounding read shows the factory branches on `.groq`; verify the default value in `MacAllYouNeed/Voice/Cleanup/VoiceCleanupSettings.swift`.)

- [ ] Run to verify fail/pass. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/LLMIntentServiceTests 2>&1 | tail -20`
  Expected: compile error first if `isEnabled`/`.default` naming differs (fix the test to the real API names), then `** TEST SUCCEEDED **` with all 4 tests passing.

- [ ] Commit. Command:
```
git add MacAllYouNeedTests/LLM/LLMIntentServiceTests.swift
git commit -m "$(printf 'S2: lock Groq-default/local-opt-in provider selection\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 10: Regression gate — Voice behavior unchanged AFTER refactor

**Files:**
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderPersonalizationTests.swift` (run only)
- Test: any `Shared/Tests/CoreTests/Voice/` suites (run only)

This is the characterization close-out: the same Voice suites that passed in Task 6 must still pass identically, proving the S2 refactor did not alter Voice.

- [ ] Re-run the Voice prompt suite. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/VoicePromptBuilderPersonalizationTests 2>&1 | tail -30`
  Expected: `** TEST SUCCEEDED **`, exactly 10 tests pass — identical to the Task 6 baseline.

- [ ] Run the Shared Voice suites (unchanged code, sanity gate). Command:
  `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter Voice`
  Expected: all `Voice*Tests` pass (e.g. `VoiceWordReplacementTests`, `VoicePersonalizationStoreTests`, etc.), 0 failures.

- [ ] Full app test run to confirm no cross-suite breakage. Command:
  `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -30`
  Expected: `** TEST SUCCEEDED **`.

- [ ] Commit (no code change; this records the gate passing via an empty allow-empty marker only if your workflow requires it — otherwise skip). Command:
```
git commit --allow-empty -m "$(printf 'S2: regression gate — voice tests unchanged after refactor\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

## Self-Review

**S1 — `AXObserverCoordinator` (roadmap §S1):** Covered.
- `AXObserverCreate` + run-loop source + notification registration: `SystemAXObserverEngine` (Task 5) does `AXObserverCreate`, `AXObserverGetRunLoopSource` + `CFRunLoopAddSource`, and `AXObserverAddNotification`.
- Health-check re-subscribe when the target rebuilds its AX tree: `healthCheckNow()` + `startHealthCheckTimer()` (Task 4), unit-tested via `markStaleForTesting`.
- Clean Swift callback surface: `start(pid:notifications:onEvent:)` (Task 2), fan-out tested (Task 3).
- "Owns no feature logic": the coordinator only manages observer lifecycle; consumers (B, F) supply notifications + callback.
- Pure-AX path that can't be unit-tested: isolated behind the `AXObserverEngine` protocol (Task 1), with the live engine smoke-tested and a documented manual Dock/Finder verification (Task 5). WindowControl refactor is explicitly NOT done (roadmap calls it optional/out-of-scope).

**S2 — LLM intent layer (roadmap §S2):** Covered.
- Reusable service a non-voice caller can use: `LLMIntentService.run(template:input:voiceContext:)` (Task 8).
- Named prompt template + provider/prompt-variant seam: `LLMIntentTemplate` registry (Task 7), with `.voiceCleanup` delegating to `VoicePromptBuilder`.
- Same Groq-default + local-opt-in selection the user configured: service reuses `VoiceCleanupProviderFactory.makeProvider(settings:keyStore:)` and asserts the Groq default + disabled→nil contract (Task 9).
- Injectable for tests: `LLMIntentService(makeProvider:)` + `FakeLLMProvider` (Task 8).
- **Voice behavior unchanged:** characterization baseline captured BEFORE (Task 6) and the identical suite re-run AFTER (Task 10), plus a byte-identical assertion that `.voiceCleanup` equals `VoicePromptBuilder.systemPrompt` (Task 7).

**Known follow-ups (intentionally out of scope, feature-local):** wiring `AXObserverCoordinator` into B/F; adding non-voice `LLMIntentTemplate` cases (reminder extraction, file naming) that route via `VoiceTextGenerationProvider.generate`; these belong to the C/E/B/F plans.
