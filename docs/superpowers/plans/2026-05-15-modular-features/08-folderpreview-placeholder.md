# Phase 08 — Folder Preview Placeholder

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Folder Preview Quick Look extension respect `FeatureManager`'s disabled state. The extension cannot be runtime-uninstalled — macOS launches it via the static `NSExtension` declaration in `FolderPreview/Info.plist`. So on every preview request the extension reads the feature's `activationState` from the shared App Group `UserDefaults` and short-circuits to a small placeholder ("Folder Preview is disabled — open Mac All You Need → Settings → Features to re-enable") when the feature is disabled. Per design spec § 3.3 this is the documented OS-extension policy (`runsRegardlessOfFeatureState: true`, `respectsFeatureFlag: true`).

**Architecture:** A new `FeatureStateReader` lives in `FeatureCore` and offers a synchronous, extension-safe read of one feature's `FeatureRuntimeState` directly from a `UserDefaults` instance, using the same persistence key (`feature.<id>.runtimeState`) that `FeatureManager` writes to. The Folder Preview extension does **not** instantiate `FeatureManager` (it's an actor with more dependencies than an extension needs); it just `JSONDecoder`-decodes the stored value. `PreviewViewController.preparePreviewOfFile(at:completionHandler:)` checks the value first; if `.disabled`, it routes to a new `configureDisabledPlaceholder()` chrome state on `QuickLookPreviewView` and completes immediately. If `.enabled` (or unknown / not yet persisted, which we treat as enabled to preserve current behavior on fresh installs), it falls through to the existing logic untouched. The Browse Folder window — a main-app surface, not an OS extension — is already toggled cleanly by `FolderPreviewFeatureActivator` from Phase 03 and is not in scope here. `FeatureCardView` (from Phase 05) gains a small honesty badge on Folder Preview's card explaining that the Quick Look extension stays installed with the app.

**Tech Stack:** Swift 5.9+, `Foundation.UserDefaults(suiteName:)`, `JSONDecoder`, AppKit (`NSAttributedString`, the existing `QuickLookPreviewView` chrome layer), `XCTest` for unit tests, `qlmanage` (gated; falls back to a direct extension call if flaky).

**Depends on:** Phase 05 (`FeatureCardView`, `FeatureStatePublisher`, `FolderPreviewFeatureActivator` descriptor wired into `FeatureRegistryProvider`).

---

## File structure

```
Shared/Sources/FeatureCore/
└── FeatureStateReader.swift                             ← NEW: extension-safe synchronous reader

Shared/Tests/FeatureCoreTests/
└── FeatureStateReaderTests.swift                        ← NEW: round-trip tests vs. FeatureManager

FolderPreview/
├── PreviewViewController.swift                          ← MODIFY: gate preparePreviewOfFile on feature state
└── DisabledPlaceholderRenderer.swift                    ← NEW: builds the placeholder NSAttributedString

MacAllYouNeed/App/
└── FeatureRegistryProvider.swift                        ← MODIFY: set folderPreviewDescriptor's osExtensionPolicy

MacAllYouNeed/Settings/Features/
└── FeatureCardView.swift                                ← MODIFY: render OS-extension info badge

MacAllYouNeedTests/Settings/
└── FeatureCardViewExtensionBadgeTests.swift             ← NEW: assert the badge appears for Folder Preview

FolderPreviewTests/
├── PreviewViewControllerDisabledStateTests.swift        ← NEW: direct preparePreviewOfFile assertion
└── DisabledPlaceholderRendererTests.swift               ← NEW: NSAttributedString text assertion

project.yml                                              ← MODIFY: add FeatureCore dependency to FolderPreview target
```

A new test target `FolderPreviewTests` is added in Task 1 if it doesn't already exist; the `qlmanage` integration test attempt and its fallback both live there because they import the extension's module.

---

### Task 1: Verify FolderPreview target wiring + add FeatureCore dependency

**Files:**
- Read: `FolderPreview/FolderPreview.entitlements`
- Modify (if needed): `project.yml`

- [ ] **Step 1: Confirm App Group entitlement is present**

```bash
cat /Users/mingjie.wang/Documents/personal/mac-all-you-need/FolderPreview/FolderPreview.entitlements
```

Expected — the file already contains:
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.macallyouneed.shared</string>
</array>
```

If it does not, add the array (do not change other keys). The extension MUST share `group.com.macallyouneed.shared` with the main app or it cannot read `FeatureManager`'s state.

- [ ] **Step 2: Confirm bundle ID and add `FeatureCore` dependency**

```bash
grep -n "FolderPreview:" -A 30 /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -40
```

Confirm `PRODUCT_BUNDLE_IDENTIFIER: com.macallyouneed.app.folderpreview` (this exact string is used in the descriptor in Task 5). The current `dependencies:` block lists `Core` and `Platform` from the `Shared` package. Add `FeatureCore`:

```yaml
    dependencies:
      - package: Shared
        product: Core
      - package: Shared
        product: Platform
      - package: Shared
        product: FeatureCore
```

`FeatureCore` is the SwiftPM product introduced in Phase 01 (`Shared/Package.swift`). It must already be exposed as a `library` product in `Shared/Package.swift`; if Phase 01 only exposed it as a `target` and not a `library` product, also edit `Shared/Package.swift` to add the product. (Phase 01 specifies it as a product; this task is just defensive.)

- [ ] **Step 3: Regenerate the Xcode project**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need
xcodegen generate
```

Expected: `Generated project successfully` with no warnings about `FolderPreview`.

- [ ] **Step 4: Verify build**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' build | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add project.yml MacAllYouNeed.xcodeproj Shared/Package.swift
git commit -m "feat(modular-features): add FeatureCore dependency to FolderPreview target"
```

(If only `project.yml` changed, drop the others from `git add`.)

---

### Task 2: `FeatureStateReader` — extension-safe synchronous reader

**Files:**
- Create: `Shared/Sources/FeatureCore/FeatureStateReader.swift`
- Create: `Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift`:

```swift
import XCTest
@testable import FeatureCore

final class FeatureStateReaderTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "FeatureStateReaderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testReadReturnsInitialDefaultWhenAbsent_assetNotRequired() {
        let state = FeatureStateReader.read(for: .folderPreview, defaults: defaults)
        XCTAssertEqual(state, .initialDefault(assetRequired: false))
    }

    func testReadReturnsInitialDefaultWhenAbsent_assetRequired() {
        // Folder Preview has no asset pack today, but the API must accept the assetRequired hint.
        let state = FeatureStateReader.read(for: .downloader, defaults: defaults, assetRequired: true)
        XCTAssertEqual(state, .initialDefault(assetRequired: true))
    }

    func testRoundTripWithFeatureManager() async throws {
        // Write via FeatureManager (the production write path).
        let descriptor = FeatureDescriptor(
            id: .folderPreview,
            displayName: "Folder Preview",
            icon: "folder",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let registry = FeatureRegistry(descriptors: [descriptor])
        let manager = FeatureManager(registry: registry, defaults: defaults)
        let target = FeatureRuntimeState(assetState: .notRequired, activationState: .disabled)
        try await manager.setState(target, for: .folderPreview)

        // Read via FeatureStateReader (the extension read path).
        let read = FeatureStateReader.read(for: .folderPreview, defaults: defaults)
        XCTAssertEqual(read, target, "FeatureStateReader and FeatureManager must agree on the persisted shape")
    }

    func testReadIgnoresGarbage() {
        defaults.set(Data([0xff, 0xfe, 0xfd]), forKey: FeatureManager.persistKey(for: .folderPreview))
        let state = FeatureStateReader.read(for: .folderPreview, defaults: defaults)
        XCTAssertEqual(state, .initialDefault(assetRequired: false),
                       "garbage in defaults must fall back to the initial default, never crash")
    }

    func testEnabledRoundTrip() async throws {
        let descriptor = FeatureDescriptor(
            id: .folderPreview,
            displayName: "Folder Preview",
            icon: "folder",
            summary: "",
            detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let manager = FeatureManager(
            registry: FeatureRegistry(descriptors: [descriptor]),
            defaults: defaults
        )
        let target = FeatureRuntimeState(assetState: .notRequired, activationState: .enabled)
        try await manager.setState(target, for: .folderPreview)
        XCTAssertEqual(FeatureStateReader.read(for: .folderPreview, defaults: defaults), target)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureStateReaderTests | tail -15
```

Expected: FAIL — `FeatureStateReader` not declared.

- [ ] **Step 3: Implement**

Create `Shared/Sources/FeatureCore/FeatureStateReader.swift`:

```swift
import Foundation

/// Synchronous, extension-safe reader for a single feature's persisted FeatureRuntimeState.
///
/// FeatureManager is an `actor` and brings non-trivial setup (registry, descriptors, posting
/// Darwin notifications). App extensions like Folder Preview cannot reasonably wait on async
/// actor hops on every preview request and don't need write capability. This helper reads
/// directly from the App Group `UserDefaults` using the SAME key format that
/// `FeatureManager.persistKey(for:)` writes to, so writes from the main app and reads from
/// any extension stay in lockstep.
public enum FeatureStateReader {
    /// Reads `FeatureRuntimeState` for `id` from `defaults`. If the key is missing or its
    /// value cannot be decoded, returns `FeatureRuntimeState.initialDefault(assetRequired:)`.
    /// `assetRequired` defaults to `false` because the only current consumer (Folder Preview)
    /// has no asset pack; pass `true` for asset-pack features.
    public static func read(
        for id: FeatureID,
        defaults: UserDefaults,
        assetRequired: Bool = false
    ) -> FeatureRuntimeState {
        let key = FeatureManager.persistKey(for: id)
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(FeatureRuntimeState.self, from: data)
        else {
            return .initialDefault(assetRequired: assetRequired)
        }
        return decoded
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureStateReaderTests | tail -15
```

Expected: PASS, 5/5 tests.

- [ ] **Step 5: Commit**

```bash
git add Shared/Sources/FeatureCore/FeatureStateReader.swift \
        Shared/Tests/FeatureCoreTests/FeatureStateReaderTests.swift
git commit -m "feat(modular-features): add FeatureStateReader for extension-safe state reads"
```

---

### Task 3: `DisabledPlaceholderRenderer` — builds the placeholder content

**Files:**
- Create: `FolderPreview/DisabledPlaceholderRenderer.swift`
- Create: `FolderPreviewTests/DisabledPlaceholderRendererTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FolderPreviewTests/DisabledPlaceholderRendererTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderPreview

final class DisabledPlaceholderRendererTests: XCTestCase {
    func testTitleStringContainsFeatureName() {
        let result = DisabledPlaceholderRenderer.render()
        XCTAssertTrue(result.title.contains("Folder Preview"),
                      "title must name the feature so the user knows what's disabled")
    }

    func testDetailMentionsHowToReEnable() {
        let result = DisabledPlaceholderRenderer.render()
        let body = result.body.string
        XCTAssertTrue(body.contains("Mac All You Need"),
                      "user must know which app to open")
        XCTAssertTrue(body.contains("Settings"), "must mention Settings")
        XCTAssertTrue(body.contains("Features"), "must mention the Features tab")
    }

    func testBodyIsNonEmpty() {
        let result = DisabledPlaceholderRenderer.render()
        XCTAssertFalse(result.body.string.isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderPreviewTests/DisabledPlaceholderRendererTests | tail -15
```

Expected: FAIL — `DisabledPlaceholderRenderer` not declared, or `FolderPreviewTests` target missing.

If the `FolderPreviewTests` target does not exist yet, add it to `project.yml`:

```yaml
  FolderPreviewTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: FolderPreviewTests
    dependencies:
      - target: FolderPreview
      - package: Shared
        product: FeatureCore
    settings:
      base:
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/FolderPreview.appex/Contents/MacOS/FolderPreview"
```

Then `xcodegen generate` and re-run.

- [ ] **Step 3: Implement**

Create `FolderPreview/DisabledPlaceholderRenderer.swift`:

```swift
import AppKit
import Foundation

/// Builds the chrome content shown when the Folder Preview feature is disabled.
/// The content is plain `NSAttributedString` (no `NSAttributedString(html:)` round-trip)
/// because the existing `QuickLookPreviewView` already renders text via `NSTextField`
/// — there is no `NSTextView`/HTML pipeline to feed into. A title and a body are returned
/// separately so the caller can route them into the existing chrome (`titleField`,
/// `summaryField`, body) without redesigning the view.
enum DisabledPlaceholderRenderer {
    struct Result {
        let title: String
        let body: NSAttributedString
        let badge: String
    }

    static func render() -> Result {
        let title = "Folder Preview is disabled"

        let bodyText =
            "Open Mac All You Need → Settings → Features to re-enable Folder Preview.\n\n" +
            "The Quick Look extension stays installed with the app, so this placeholder " +
            "appears whenever you press Space on a folder while the feature is off."

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 8

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        return Result(
            title: title,
            body: NSAttributedString(string: bodyText, attributes: attributes),
            badge: "Disabled"
        )
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderPreviewTests/DisabledPlaceholderRendererTests | tail -15
```

Expected: PASS, 3/3.

- [ ] **Step 5: Commit**

```bash
git add FolderPreview/DisabledPlaceholderRenderer.swift \
        FolderPreviewTests/DisabledPlaceholderRendererTests.swift \
        project.yml MacAllYouNeed.xcodeproj
git commit -m "feat(modular-features): add DisabledPlaceholderRenderer for Folder Preview"
```

---

### Task 4: Gate `PreviewViewController.preparePreviewOfFile` on feature state

**Files:**
- Modify: `FolderPreview/PreviewViewController.swift`
- Create: `FolderPreviewTests/PreviewViewControllerDisabledStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `FolderPreviewTests/PreviewViewControllerDisabledStateTests.swift`:

```swift
import XCTest
import AppKit
import FeatureCore
@testable import FolderPreview

final class PreviewViewControllerDisabledStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempFolder: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "FolderPreviewDisabledTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MAYN-FolderPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        try "hello".write(to: tempFolder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempFolder)
        try await super.tearDown()
    }

    @MainActor
    func testDisabledStateRendersPlaceholder() async throws {
        // Persist disabled state via FeatureManager so we exercise the same write path
        // the main app uses.
        let descriptor = FeatureDescriptor(
            id: .folderPreview, displayName: "Folder Preview", icon: "folder",
            summary: "", detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let manager = FeatureManager(
            registry: FeatureRegistry(descriptors: [descriptor]),
            defaults: defaults
        )
        try await manager.setState(
            FeatureRuntimeState(assetState: .notRequired, activationState: .disabled),
            for: .folderPreview
        )

        let vc = PreviewViewController(featureStateDefaults: defaults)
        _ = vc.view  // force loadView()

        let done = expectation(description: "preparePreviewOfFile completion")
        vc.preparePreviewOfFile(at: tempFolder) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)

        let chrome = vc.testHook_currentChromeSnapshot()
        XCTAssertTrue(chrome.title.contains("Folder Preview is disabled"),
                      "expected disabled placeholder title, got: \(chrome.title)")
    }

    @MainActor
    func testEnabledStateProceedsToNormalPreview() async throws {
        let descriptor = FeatureDescriptor(
            id: .folderPreview, displayName: "Folder Preview", icon: "folder",
            summary: "", detailDescription: "",
            activator: NoopFeatureActivator()
        )
        let manager = FeatureManager(
            registry: FeatureRegistry(descriptors: [descriptor]),
            defaults: defaults
        )
        try await manager.setState(
            FeatureRuntimeState(assetState: .notRequired, activationState: .enabled),
            for: .folderPreview
        )

        let vc = PreviewViewController(featureStateDefaults: defaults)
        _ = vc.view

        let done = expectation(description: "preparePreviewOfFile completion")
        vc.preparePreviewOfFile(at: tempFolder) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)

        let chrome = vc.testHook_currentChromeSnapshot()
        XCTAssertFalse(chrome.title.contains("disabled"),
                       "enabled state must NOT show the disabled placeholder")
    }

    @MainActor
    func testMissingStateDefaultsToEnabled() async throws {
        // No setState call — defaults are empty. Behavior must be the existing one
        // (preserve current behavior on fresh installs and during onboarding).
        let vc = PreviewViewController(featureStateDefaults: defaults)
        _ = vc.view

        let done = expectation(description: "preparePreviewOfFile completion")
        vc.preparePreviewOfFile(at: tempFolder) { error in
            XCTAssertNil(error)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)

        let chrome = vc.testHook_currentChromeSnapshot()
        XCTAssertFalse(chrome.title.contains("disabled"),
                       "missing state must default to enabled to avoid silent breakage")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderPreviewTests/PreviewViewControllerDisabledStateTests | tail -15
```

Expected: FAIL — `PreviewViewController(featureStateDefaults:)` initializer doesn't exist; `testHook_currentChromeSnapshot` not declared.

- [ ] **Step 3: Modify `PreviewViewController` and `QuickLookPreviewView`**

Edit `FolderPreview/PreviewViewController.swift`. Add the import at the top:

```swift
import Cocoa
import Core
import FeatureCore
import ImageIO
import Platform
import Quartz
import QuickLookThumbnailing
import UniformTypeIdentifiers
```

Replace the class declaration with:

```swift
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let previewView = QuickLookPreviewView()
    private var previewTask: Task<Void, Never>?
    private var previewID = UUID()
    private let featureStateDefaults: UserDefaults

    /// Production initializer used by macOS when it instantiates the principal class.
    /// Reads from the shared App Group defaults.
    convenience init() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
        self.init(featureStateDefaults: defaults)
    }

    /// Test/dependency-injection initializer.
    init(featureStateDefaults: UserDefaults) {
        self.featureStateDefaults = featureStateDefaults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used by Quick Look extensions")
    }

    override func loadView() {
        view = previewView
        preferredContentSize = NSSize(width: 1080, height: 640)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()

        // § 3.3 OS-extension policy: the extension is launched by macOS regardless of
        // FeatureManager.activationState, so it self-checks and short-circuits when the
        // feature is disabled. Missing/garbage state defaults to enabled (see FeatureStateReader).
        let state = FeatureStateReader.read(for: .folderPreview, defaults: featureStateDefaults)
        if state.activationState == .disabled {
            let placeholder = DisabledPlaceholderRenderer.render()
            previewView.configureDisabledPlaceholder(
                title: placeholder.title,
                body: placeholder.body,
                badge: placeholder.badge
            )
            handler(nil)
            return
        }

        let id = UUID()
        previewID = id

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        previewView.configureLoading(url: url, isDirectory: isDirectory)
        handler(nil)

        previewTask = Task {
            do {
                if isDirectory {
                    let cascade = FolderPreviewSettings.cascadeEnabled()
                    let inventory = try await FolderEnumerator.enumerateImmediate(url: url, maxEntries: 500)
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureFolder(url: url, inventory: inventory, cascade: cascade)
                    }
                } else {
                    let entries = try await Task.detached(priority: .userInitiated) {
                        try LibArchiveBackend().list(archiveURL: url, limits: .default)
                    }.value
                    try Task.checkCancellation()
                    await MainActor.run {
                        guard self.previewID == id else { return }
                        previewView.configureArchive(url: url, entries: entries)
                    }
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard self.previewID == id else { return }
                    previewView.configureError(title: url.lastPathComponent, error: error)
                }
            }
        }
    }

    // MARK: - Test hooks

    struct ChromeSnapshot {
        let title: String
        let subtitle: String
        let badge: String?
    }

    @MainActor
    func testHook_currentChromeSnapshot() -> ChromeSnapshot {
        previewView.currentChromeSnapshot()
    }
}
```

Then add the `configureDisabledPlaceholder` method and the test-hook accessor on `QuickLookPreviewView`. Inside that class (the `private final class QuickLookPreviewView`), add:

```swift
    /// Renders the placeholder used when Folder Preview is disabled in Settings → Features.
    /// Reuses the existing chrome (header title/subtitle/badge); the body uses the existing
    /// `emptyField` to display the explanation as plain text. No HTML, no WebView (the
    /// extension is sandboxed and cannot host WebContent — see CLAUDE.md macOS 26 notes).
    func configureDisabledPlaceholder(title: String, body: NSAttributedString, badge: String) {
        applyChrome(
            title: title,
            subtitle: "Open Mac All You Need to re-enable",
            icon: NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: nil)
                ?? NSWorkspace.shared.icon(for: .folder),
            badge: badge
        )
        contentMode = .table
        outlineDataSource.reset()
        scrollView.documentView = tableView
        tableDataSource.rows = []
        tableView.reloadData()
        showSelectionPreview(for: nil)

        emptyField.attributedStringValue = body
        emptyField.isHidden = false
        scrollView.isHidden = true
        setFilterBarVisible(false)
    }

    /// Read-only snapshot of the chrome state for tests.
    func currentChromeSnapshot() -> PreviewViewController.ChromeSnapshot {
        PreviewViewController.ChromeSnapshot(
            title: titleField.stringValue,
            subtitle: summaryField.stringValue,
            badge: statusBadge.isHidden ? nil : statusBadge.stringValue
        )
    }
```

> Note: `applyChrome`, `contentMode`, `outlineDataSource`, `scrollView`, `tableView`, `tableDataSource`, `showSelectionPreview`, `emptyField`, `setFilterBarVisible`, `titleField`, `summaryField`, and `statusBadge` are all existing members of `QuickLookPreviewView` (see the current `PreviewProvider.swift`). The test hook reads them; do not change their access level beyond what's already present (the hook is in the same file and so can see private members through the surrounding class — if the hook's call site is on `PreviewViewController`, declare `currentChromeSnapshot()` as `internal` since both classes share the same file).

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderPreviewTests/PreviewViewControllerDisabledStateTests | tail -20
```

Expected: PASS, 3/3.

- [ ] **Step 5: Commit**

```bash
git add FolderPreview/PreviewViewController.swift \
        FolderPreviewTests/PreviewViewControllerDisabledStateTests.swift
git commit -m "feat(modular-features): gate FolderPreview extension on feature activation state"
```

---

### Task 5: Update `folderPreviewDescriptor` with the real `osExtensionPolicy`

**Files:**
- Modify: `MacAllYouNeed/App/FeatureRegistryProvider.swift`

Phase 03 Task 3 already populated the `osExtensionPolicy` with `extensionBundleID: "FolderPreview"`. The actual bundle ID is `com.macallyouneed.app.folderpreview` (verified in Task 1 Step 2). Fix it.

- [ ] **Step 1: Read the current descriptor**

```bash
grep -n "folderPreviewDescriptor\|FolderPreview" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/FeatureRegistryProvider.swift
```

- [ ] **Step 2: Replace with the verified bundle ID**

In `MacAllYouNeed/App/FeatureRegistryProvider.swift`, replace `folderPreviewDescriptor()`'s `osExtensionPolicy` argument with:

```swift
        osExtensionPolicy: .staticBundleExtension(StaticExtensionConfig(
            extensionBundleID: "com.macallyouneed.app.folderpreview",
            runsRegardlessOfFeatureState: true,
            respectsFeatureFlag: true
        )),
```

The full descriptor after the change:

```swift
    static func folderPreviewDescriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .folderPreview,
            displayName: "Folder Preview",
            icon: "folder",
            summary: "Quick Look HTML preview of folders and archives.",
            detailDescription: "Press space on any folder or archive to see a browsable preview without opening Finder.",
            hotkeys: [HotkeyDescriptor(identifier: "folderPreview.browse", displayName: "Browse folder")],
            osExtensionPolicy: .staticBundleExtension(StaticExtensionConfig(
                extensionBundleID: "com.macallyouneed.app.folderpreview",
                runsRegardlessOfFeatureState: true,
                respectsFeatureFlag: true
            )),
            activator: FolderPreviewFeatureActivator(),
            settingsTabFactory: { AnyView(FolderPreviewSettingsView()) }
        )
    }
```

- [ ] **Step 3: Update `FeatureRegistryProviderTests` to assert the policy**

Append to `MacAllYouNeedTests/Features/FeatureRegistryProviderTests.swift`:

```swift
    func testFolderPreviewDescriptorHasStaticBundlePolicy() {
        let registry = FeatureRegistryProvider.makeRegistry()
        guard let descriptor = registry.descriptor(for: .folderPreview) else {
            return XCTFail("Folder Preview descriptor missing")
        }
        guard case let .staticBundleExtension(config) = descriptor.osExtensionPolicy else {
            return XCTFail("Folder Preview must declare staticBundleExtension policy")
        }
        XCTAssertEqual(config.extensionBundleID, "com.macallyouneed.app.folderpreview")
        XCTAssertTrue(config.runsRegardlessOfFeatureState,
                      "Quick Look extension is launched by macOS regardless of feature state")
        XCTAssertTrue(config.respectsFeatureFlag,
                      "extension self-checks and renders a placeholder when disabled")
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeatureRegistryProviderTests | tail -15
```

Expected: PASS, all FeatureRegistryProviderTests including the new one.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/App/FeatureRegistryProvider.swift \
        MacAllYouNeedTests/Features/FeatureRegistryProviderTests.swift
git commit -m "feat(modular-features): wire real Folder Preview OS extension policy"
```

---

### Task 6: `FeatureCardView` honesty badge for OS-extension features

**Files:**
- Modify: `MacAllYouNeed/Settings/Features/FeatureCardView.swift`
- Create: `MacAllYouNeedTests/Settings/FeatureCardViewExtensionBadgeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `MacAllYouNeedTests/Settings/FeatureCardViewExtensionBadgeTests.swift`:

```swift
import XCTest
import SwiftUI
import FeatureCore
@testable import MacAllYouNeed

final class FeatureCardViewExtensionBadgeTests: XCTestCase {
    func testFolderPreviewCardShowsExtensionInfoBadge() {
        let descriptor = FeatureRegistryProvider.folderPreviewDescriptor()
        let view = FeatureCardView(
            descriptor: descriptor,
            state: .init(assetState: .notRequired, activationState: .enabled),
            onAction: { _ in }
        )

        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let text = host.descendantText()

        XCTAssertTrue(text.contains("Quick Look extension stays installed"),
                      "Folder Preview card must explain that disabling hides previews; got: \(text)")
    }

    func testNonExtensionCardDoesNotShowBadge() {
        let descriptor = FeatureRegistryProvider.clipboardDescriptor()
        let view = FeatureCardView(
            descriptor: descriptor,
            state: .init(assetState: .notRequired, activationState: .enabled),
            onAction: { _ in }
        )

        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let text = host.descendantText()

        XCTAssertFalse(text.contains("Quick Look extension"),
                       "Clipboard card must not mention the OS extension info")
    }
}

private extension NSView {
    func descendantText() -> String {
        var pieces: [String] = []
        if let textView = self as? NSTextField { pieces.append(textView.stringValue) }
        for sub in subviews { pieces.append(sub.descendantText()) }
        return pieces.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeatureCardViewExtensionBadgeTests | tail -15
```

Expected: FAIL — text not present.

- [ ] **Step 3: Modify `FeatureCardView`**

In `MacAllYouNeed/Settings/Features/FeatureCardView.swift`, add an `osExtensionInfo` view inside the card body, between the summary line and the action row:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: descriptor.icon).font(.title2)
                Text(descriptor.displayName).font(.headline)
                Spacer()
                statusBadge
            }
            Text(descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
            if !descriptor.requiredPermissions.isEmpty {
                Text(permissionsDescription).font(.caption).foregroundStyle(.tertiary)
            }
            if let osExtensionNote {
                osExtensionInfoBadge(text: osExtensionNote)
            }
            FeatureCardActionView(
                descriptor: descriptor,
                state: state,
                onInstall: { onAction(.install) },
                onEnable: { onAction(.enable) },
                onDisable: { onAction(.disable) },
                onUninstall: { onAction(.uninstall) },
                onCancelDownload: { onAction(.cancelDownload) },
                onRetryInstall: { onAction(.retryInstall) }
            )
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(MAYNTheme.cardBackground))
    }

    private var osExtensionNote: String? {
        guard case let .staticBundleExtension(config) = descriptor.osExtensionPolicy,
              config.runsRegardlessOfFeatureState else { return nil }
        return "The Quick Look extension stays installed with the app. " +
               "Disabling here hides it from previews; full removal requires uninstalling Mac All You Need."
    }

    private func osExtensionInfoBadge(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/FeatureCardViewExtensionBadgeTests | tail -15
```

Expected: PASS, 2/2.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/Settings/Features/FeatureCardView.swift \
        MacAllYouNeedTests/Settings/FeatureCardViewExtensionBadgeTests.swift
git commit -m "feat(modular-features): show OS extension info badge on Folder Preview card"
```

---

### Task 7: `qlmanage` end-to-end smoke (gated; falls back to direct call)

**Files:**
- Create: `FolderPreviewTests/QLManageDisabledStateSmokeTest.swift`

This task tries the spec's preferred verification (drive the real Quick Look extension via `qlmanage`). On CI machines and sandboxed runs `qlmanage` can be flaky or refuse to render Quick Look extensions registered in DerivedData. The test detects that, marks the run as skipped, and emits a notice — the in-process tests from Task 4 remain the source of truth.

- [ ] **Step 1: Implement**

```swift
import XCTest
import FeatureCore
@testable import FolderPreview

final class QLManageDisabledStateSmokeTest: XCTestCase {
    /// Optional smoke test. Skipped when `qlmanage` is unavailable, when the extension
    /// is not registered with Launch Services for the test runner, or when the
    /// `MAYN_QLMANAGE_SMOKE` env var is unset.
    func testQLManageRendersPlaceholderWhenDisabled() throws {
        guard ProcessInfo.processInfo.environment["MAYN_QLMANAGE_SMOKE"] != nil else {
            throw XCTSkip("Set MAYN_QLMANAGE_SMOKE=1 to run; not part of default CI lane.")
        }
        let qlmanage = URL(fileURLWithPath: "/usr/bin/qlmanage")
        guard FileManager.default.isExecutableFile(atPath: qlmanage.path) else {
            throw XCTSkip("qlmanage not available on this host")
        }

        // Persist disabled state in the App Group defaults the extension reads.
        let suite = UserDefaults(suiteName: "group.com.macallyouneed.shared")!
        let target = FeatureRuntimeState(assetState: .notRequired, activationState: .disabled)
        let data = try JSONEncoder().encode(target)
        suite.set(data, forKey: FeatureManager.persistKey(for: .folderPreview))
        defer { suite.removeObject(forKey: FeatureManager.persistKey(for: .folderPreview)) }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MAYN-qlmanage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MAYN-qlmanage-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outDir) }

        let proc = Process()
        proc.executableURL = qlmanage
        proc.arguments = ["-t", "-s", "1080", "-o", outDir.path, folder.path]
        let stderr = Pipe()
        proc.standardError = stderr
        proc.standardOutput = stderr
        try proc.run()
        proc.waitUntilExit()
        let log = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard proc.terminationStatus == 0 else {
            throw XCTSkip("qlmanage refused to render in this environment: \(log)")
        }

        // qlmanage writes a thumbnail image; we cannot grep text from a PNG. Instead, assert
        // a thumbnail file appeared (proving the extension produced *something*) and rely on
        // the in-process test for content correctness.
        let outputs = try FileManager.default.contentsOfDirectory(atPath: outDir.path)
        XCTAssertFalse(outputs.isEmpty,
                       "qlmanage produced no output; the extension may not be registered")
    }
}
```

- [ ] **Step 2: Run with the env var explicitly to verify the path locally**

```bash
MAYN_QLMANAGE_SMOKE=1 xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderPreviewTests/QLManageDisabledStateSmokeTest | tail -20
```

Expected (on a developer machine with the extension registered): PASS. On CI without the env var: SKIPPED.

- [ ] **Step 3: Commit**

```bash
git add FolderPreviewTests/QLManageDisabledStateSmokeTest.swift
git commit -m "feat(modular-features): add gated qlmanage smoke for Folder Preview placeholder"
```

---

### Task 8: Phase verification

- [ ] **Step 1: Full Shared package test suite**

```bash
cd /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared && \
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test | tail -30
```

Expected: all green, including `FeatureStateReaderTests`.

- [ ] **Step 2: Full Xcode workspace test suite**

```bash
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' | tail -30
xcodebuild test -workspace MacAllYouNeed.xcworkspace -scheme FolderPreview \
  -destination 'platform=macOS,arch=arm64' | tail -30
```

Expected: all green.

- [ ] **Step 3: Manual smoke**

1. Build and run MAYN. Open Settings → Features.
2. Folder Preview card shows the gray info note: "The Quick Look extension stays installed with the app…"
3. Toggle Folder Preview off. The card flips to "Disabled".
4. In Finder, select any folder and press Space (Quick Look). The preview shows the placeholder: "Folder Preview is disabled — Open Mac All You Need → Settings → Features…".
5. In Settings → Features, toggle Folder Preview back on. Press Space on a folder again — the normal HTML-style preview returns.
6. Confirm the Browse Folder window (⌘⇧F) is independently controlled by `FolderPreviewFeatureActivator` (Phase 03): when the feature is disabled, the hotkey does not open the window. (This is not changed by Phase 08; verify it still works as Phase 03 left it.)

- [ ] **Step 4: CI build**

```bash
/Users/mingjie.wang/Documents/personal/mac-all-you-need/scripts/ci-build.sh
```

Expected: pass.

- [ ] **Step 5: Mark phase complete + PR**

Edit `docs/superpowers/plans/2026-05-15-modular-features.md` to mark Phase 08 complete:

```bash
sed -i '' 's/- \[ \] Phase 08 — Folder Preview placeholder/- [x] Phase 08 — Folder Preview placeholder/' \
  /Users/mingjie.wang/Documents/personal/mac-all-you-need/docs/superpowers/plans/2026-05-15-modular-features.md
git add docs/superpowers/plans/2026-05-15-modular-features.md
git commit -m "feat(modular-features): mark Phase 08 complete"
git push -u origin <branch>
gh pr create --title "Phase 08 — Folder Preview placeholder" \
  --body "Implements docs/superpowers/plans/2026-05-15-modular-features/08-folderpreview-placeholder.md"
```
