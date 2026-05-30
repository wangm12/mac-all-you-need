# AI File Organizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the gated AI File Organizer feature that renames and re-files messy folders from on-device-extracted file content via the shared S2 LLM layer, behind a mandatory preview/approve diff pane with a fully reversible operation manifest.

**Architecture:** Pure, testable Swift value types live in `Shared/Sources/Core` (extraction model, sanitization, collision/de-dup, naming patterns, planning data structures, manifest/undo, encrypted GRDB stores) so they run under `swift test` with an injected fake LLM. App-target code (`MacAllYouNeed/FileOrganizer/`) hosts the `ContentExtractor` (Vision/PDFKit seams), `FileMutator` (temp-dir integration tests), `WatchDaemon`, the `FunctionPageShell` tool page, and the diff pane. The feature reuses the S2 LLM intent layer (Groq default + local opt-in) through an injectable `OrganizerLLMService` seam mirroring Voice's `cleanupPipelineFactoryOverride`; the cloud only ever sees extracted snippets + metadata, never file bytes.

**Tech Stack:** Swift 5.9+, SwiftUI/AppKit, Vision, PDFKit, UniformTypeIdentifiers, GRDB, security-scoped bookmarks, existing Groq pipeline (S2), XCTest

---

## File Structure

```
Shared/Sources/Core/FileOrganizer/
  ExtractedContent.swift            # ExtractedContent, ContentKind, metadata
  FilenameSanitizer.swift           # illegal-char / length / extension rules
  CollisionResolver.swift           # deterministic " (2)" suffixing batch+dir
  NamingPattern.swift               # date/text/sequence/case-style rendering
  OrganizationProposal.swift        # ProposedOperation, OrganizationProposal, FolderPlan
  OrganizerLLMService.swift         # protocol + request/response DTOs (S2 seam)
  OrganizerEngine.swift             # extract-list -> sanitize -> de-dup -> plan
  ManifestOperation.swift           # codable op record inside the envelope
Shared/Sources/Core/Storage/
  OrganizerManifestStore.swift      # encrypted manifests + state transitions
  OrganizerPreferenceStore.swift    # corrections (learn-from-edits) + bookmarks
Shared/Tests/CoreTests/FileOrganizer/
  FilenameSanitizerTests.swift
  CollisionResolverTests.swift
  NamingPatternTests.swift
  OrganizerEngineTests.swift        # uses FakeOrganizerLLMService
  ManifestOperationTests.swift
Shared/Tests/CoreTests/Storage/
  OrganizerManifestStoreTests.swift
  OrganizerPreferenceStoreTests.swift

MacAllYouNeed/FileOrganizer/
  ContentExtractor.swift            # UTType routing + Vision/PDFKit/text seams
  FileMutator.swift                 # apply/rollback against filesystem
  FolderBookmark.swift              # bookmarkData persist/resolve + staleness
  WatchDaemon.swift                 # FSEvents/DispatchSource debounced proposals
  FileOrganizerCoordinator.swift    # composition root owned by AppController
  UI/FileOrganizerPage.swift        # FunctionPageShell + FunctionSegmentedTabStrip
  UI/OrganizerDiffPane.swift        # mandatory preview/approve sheet
  UI/OrganizerHistoryView.swift     # manifest list + undo
MacAllYouNeed/App/Descriptors/
  FileOrganizerDescriptor.swift     # FeatureDescriptor wiring
MacAllYouNeedTests/FileOrganizer/
  ContentExtractorTests.swift       # fixture files
  FileMutatorTests.swift            # temp-dir apply + undo + partial rollback
  FolderBookmarkTests.swift
  WatchDaemonTests.swift

Shared/Sources/FeatureCore/FeatureID.swift   # add .aiFileOrganizer
MacAllYouNeed/App/Coordinators/AppStoreContainer.swift  # register new stores
```

Test commands referenced throughout:

- Shared: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- App: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`

---

### Task 1 — `ExtractedContent` value model

**Files:** `Shared/Sources/Core/FileOrganizer/ExtractedContent.swift`, test `Shared/Tests/CoreTests/FileOrganizer/ExtractedContentTests.swift`

- [ ] Write a failing test asserting the model exists and round-trips:

```swift
import XCTest
@testable import Core

final class ExtractedContentTests: XCTestCase {
    func testCodableRoundTripPreservesFields() throws {
        let content = ExtractedContent(
            originalURL: URL(fileURLWithPath: "/tmp/IMG_001.png"),
            utTypeIdentifier: "public.png",
            kind: .image,
            snippet: "INVOICE 2026",
            metadata: ["width": "1024", "pageCount": "0"]
        )
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(ExtractedContent.self, from: data)
        XCTAssertEqual(decoded.kind, .image)
        XCTAssertEqual(decoded.snippet, "INVOICE 2026")
        XCTAssertEqual(decoded.metadata["width"], "1024")
    }
}
```

- [ ] Run (expect FAIL — `ExtractedContent` undefined): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ExtractedContentTests`
- [ ] Implement the minimal model:

```swift
import Foundation

public enum ContentKind: String, Codable, Sendable, CaseIterable {
    case image, pdf, text, source, archive, media, unknown
}

public struct ExtractedContent: Codable, Sendable, Equatable {
    public let originalURL: URL
    public let utTypeIdentifier: String
    public let kind: ContentKind
    public let snippet: String
    public let metadata: [String: String]

    public init(originalURL: URL, utTypeIdentifier: String, kind: ContentKind,
                snippet: String, metadata: [String: String]) {
        self.originalURL = originalURL
        self.utTypeIdentifier = utTypeIdentifier
        self.kind = kind
        self.snippet = snippet
        self.metadata = metadata
    }
}
```

- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ExtractedContentTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/ExtractedContent.swift Shared/Tests/CoreTests/FileOrganizer/ExtractedContentTests.swift && git commit -m "Add ExtractedContent model for AI File Organizer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 2 — Filename sanitization (illegal chars, length, extension preservation)

**Files:** `Shared/Sources/Core/FileOrganizer/FilenameSanitizer.swift`, test `Shared/Tests/CoreTests/FileOrganizer/FilenameSanitizerTests.swift`

- [ ] Write failing tests covering spec §3.2 rules:

```swift
import XCTest
@testable import Core

final class FilenameSanitizerTests: XCTestCase {
    func testStripsIllegalCharacters() {
        XCTAssertEqual(
            FilenameSanitizer.sanitizeBase("Q1/Report:2026\u{0007}", maxLength: 120),
            "Q1-Report-2026")
    }

    func testCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(FilenameSanitizer.sanitizeBase("  hello   world  ", maxLength: 120),
                       "hello world")
    }

    func testStripsLeadingDotHiddenFileTrap() {
        XCTAssertEqual(FilenameSanitizer.sanitizeBase(".secret", maxLength: 120), "secret")
    }

    func testEnforcesMaxLength() {
        XCTAssertEqual(FilenameSanitizer.sanitizeBase(String(repeating: "a", count: 200), maxLength: 10).count, 10)
    }

    func testEmptyResultFallsBackToPlaceholder() {
        XCTAssertEqual(FilenameSanitizer.sanitizeBase("///", maxLength: 120), "untitled")
    }

    func testComposeWithExtensionPreservesExtension() {
        XCTAssertEqual(FilenameSanitizer.compose(base: "Tax Return", ext: "pdf"), "Tax Return.pdf")
        XCTAssertEqual(FilenameSanitizer.compose(base: "notes", ext: ""), "notes")
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FilenameSanitizerTests`
- [ ] Implement:

```swift
import Foundation

public enum FilenameSanitizer {
    private static let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")

    public static func sanitizeBase(_ raw: String, maxLength: Int) -> String {
        var s = raw
        s = String(s.unicodeScalars.map { scalar -> Character in
            if scalar.value < 0x20 || illegal.contains(scalar) { return " " }
            return Character(scalar)
        })
        s = s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        // Re-map standalone illegal substitutions left as separators when adjacent to text.
        s = s.replacingOccurrences(of: " - ", with: "-")
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > maxLength { s = String(s.prefix(maxLength)) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "untitled" : s
    }

    public static func compose(base: String, ext: String) -> String {
        ext.isEmpty ? base : "\(base).\(ext)"
    }
}
```

> Note: the engine passes the raw AI base name; `sanitizeBase` is the single choke point. Adjust the `replacingOccurrences` collapse only if `testStripsIllegalCharacters` needs the exact `Q1-Report-2026` shape — keep the test as the contract.

- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FilenameSanitizerTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/FilenameSanitizer.swift Shared/Tests/CoreTests/FileOrganizer/FilenameSanitizerTests.swift && git commit -m "Add filename sanitizer for AI File Organizer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 3 — Collision / de-dup resolver (batch + target dir)

**Files:** `Shared/Sources/Core/FileOrganizer/CollisionResolver.swift`, test `Shared/Tests/CoreTests/FileOrganizer/CollisionResolverTests.swift`

- [ ] Write failing tests for deterministic suffixing (spec §3.2 / §9):

```swift
import XCTest
@testable import Core

final class CollisionResolverTests: XCTestCase {
    func testResolvesIntraBatchCollisions() {
        var r = CollisionResolver(existing: [])
        XCTAssertEqual(r.unique("report.pdf"), "report.pdf")
        XCTAssertEqual(r.unique("report.pdf"), "report (2).pdf")
        XCTAssertEqual(r.unique("report.pdf"), "report (3).pdf")
    }

    func testResolvesAgainstExistingTargetDirectory() {
        var r = CollisionResolver(existing: ["invoice.pdf", "invoice (2).pdf"])
        XCTAssertEqual(r.unique("invoice.pdf"), "invoice (3).pdf")
    }

    func testExtensionlessNamesGetSuffix() {
        var r = CollisionResolver(existing: ["README"])
        XCTAssertEqual(r.unique("README"), "README (2)")
    }

    func testCaseInsensitiveCollision() {
        var r = CollisionResolver(existing: ["Photo.PNG"])
        XCTAssertEqual(r.unique("photo.png"), "photo (2).png")
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter CollisionResolverTests`
- [ ] Implement:

```swift
import Foundation

public struct CollisionResolver {
    private var taken: Set<String>

    public init(existing: [String]) {
        taken = Set(existing.map { $0.lowercased() })
    }

    public mutating func unique(_ filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let base = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        var candidate = filename
        var n = 2
        while taken.contains(candidate.lowercased()) {
            let newBase = "\(base) (\(n))"
            candidate = ext.isEmpty ? newBase : "\(newBase).\(ext)"
            n += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }
}
```

- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter CollisionResolverTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/CollisionResolver.swift Shared/Tests/CoreTests/FileOrganizer/CollisionResolverTests.swift && git commit -m "Add collision resolver for AI File Organizer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 4 — Custom naming-pattern rendering

**Files:** `Shared/Sources/Core/FileOrganizer/NamingPattern.swift`, test `Shared/Tests/CoreTests/FileOrganizer/NamingPatternTests.swift`

- [ ] Write failing tests covering date/text/sequence/case-style (spec §3.4):

```swift
import XCTest
@testable import Core

final class NamingPatternTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC

    func testDatePrefix() {
        var p = NamingPattern.identity
        p.dateSource = .created
        p.dateFormat = "yyyy-MM-dd"
        p.datePosition = .prefix
        XCTAssertEqual(p.render(base: "Invoice", created: date, modified: date, index: 0, total: 1),
                       "2026-01-01 Invoice")
    }

    func testCustomSuffixAndSequence() {
        var p = NamingPattern.identity
        p.customSuffix = "draft"
        p.sequence = .init(enabled: true, padding: 3)
        XCTAssertEqual(p.render(base: "Memo", created: date, modified: date, index: 0, total: 5),
                       "Memo draft 001")
    }

    func testKebabCase() {
        var p = NamingPattern.identity
        p.caseStyle = .kebab
        XCTAssertEqual(p.render(base: "My Tax Return", created: date, modified: date, index: 0, total: 1),
                       "my-tax-return")
    }

    func testSnakeCase() {
        var p = NamingPattern.identity
        p.caseStyle = .snake
        XCTAssertEqual(p.render(base: "My Tax Return", created: date, modified: date, index: 0, total: 1),
                       "my_tax_return")
    }

    func testIdentityIsAIBaseNameUntouched() {
        XCTAssertEqual(NamingPattern.identity.render(base: "Just A Name",
                       created: date, modified: date, index: 0, total: 1), "Just A Name")
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter NamingPatternTests`
- [ ] Implement `NamingPattern` (Codable, persisted per feature) with `DateSource{none,created,modified}`, `Position{prefix,suffix}`, `CaseStyle{asIs,title,kebab,snake}`, a `Sequence{enabled,padding}`, `customPrefix`/`customSuffix`, a `static let identity`, and a `render(base:created:modified:index:total:)` that: applies case style to the base, joins prefix/date/base/suffix/sequence with single spaces (sequence as `String(format:"%0\(padding)d", index+1)`), and uses a fixed-`en_US_POSIX`, UTC `DateFormatter`. Kebab/snake replace inter-word spaces in the whole composed string.
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter NamingPatternTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/NamingPattern.swift Shared/Tests/CoreTests/FileOrganizer/NamingPatternTests.swift && git commit -m "Add naming pattern rendering for AI File Organizer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 5 — Proposal data structures + LLM service seam DTOs

**Files:** `Shared/Sources/Core/FileOrganizer/OrganizationProposal.swift`, `Shared/Sources/Core/FileOrganizer/OrganizerLLMService.swift`, test `Shared/Tests/CoreTests/FileOrganizer/OrganizationProposalTests.swift`

- [ ] Write failing tests for the proposal model + computed selection counts (spec §4, §3.5):

```swift
import XCTest
@testable import Core

final class OrganizationProposalTests: XCTestCase {
    func testSelectedOperationCount() {
        let ops = [
            ProposedOperation(id: "1", sourceURL: URL(fileURLWithPath: "/a/x.pdf"),
                              originalName: "x.pdf", proposedName: "Invoice.pdf",
                              targetFolder: "Invoices", reason: "invoice text",
                              isRenameApproved: true, isFolderApproved: true),
            ProposedOperation(id: "2", sourceURL: URL(fileURLWithPath: "/a/y.png"),
                              originalName: "y.png", proposedName: "Screenshot.png",
                              targetFolder: nil, reason: "ocr",
                              isRenameApproved: true, isFolderApproved: false)
        ]
        let proposal = OrganizationProposal(rootURL: URL(fileURLWithPath: "/a"), operations: ops)
        XCTAssertEqual(proposal.approvedRenameCount, 2)
        XCTAssertEqual(proposal.approvedFolderCount, 1)
    }

    func testStaysHereWhenTargetFolderNil() {
        let op = ProposedOperation(id: "1", sourceURL: URL(fileURLWithPath: "/a/x.pdf"),
                                   originalName: "x.pdf", proposedName: "x.pdf",
                                   targetFolder: nil, reason: "", isRenameApproved: false,
                                   isFolderApproved: false)
        XCTAssertTrue(op.staysInPlaceFolder)
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizationProposalTests`
- [ ] Implement `ProposedOperation` (Codable, Identifiable: id, sourceURL, originalName, proposedName, targetFolder: String?, reason, isRenameApproved, isFolderApproved; computed `staysInPlaceFolder`), `OrganizationProposal` (rootURL, operations; computed `approvedRenameCount`/`approvedFolderCount`), and `FolderPlan` (assignments: `[String: String]`, maxDepth, maxFolders).
- [ ] In `OrganizerLLMService.swift` define the injection seam + DTOs (no implementation):

```swift
import Foundation

public struct RenameRequest: Sendable {
    public let content: ExtractedContent
    public let recentExamples: [(before: String, after: String)]
    public init(content: ExtractedContent, recentExamples: [(before: String, after: String)]) {
        self.content = content
        self.recentExamples = recentExamples
    }
}

public struct FolderPlanRequest: Sendable {
    public let items: [(name: String, kind: ContentKind, gist: String)]
    public let maxDepth: Int
    public let maxFolders: Int
    public init(items: [(name: String, kind: ContentKind, gist: String)], maxDepth: Int, maxFolders: Int) {
        self.items = items; self.maxDepth = maxDepth; self.maxFolders = maxFolders
    }
}

public protocol OrganizerLLMService: Sendable {
    func proposeName(_ request: RenameRequest) async throws -> String
    func proposeFolders(_ request: FolderPlanRequest) async throws -> [String: String]
}
```

- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizationProposalTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/OrganizationProposal.swift Shared/Sources/Core/FileOrganizer/OrganizerLLMService.swift Shared/Tests/CoreTests/FileOrganizer/OrganizationProposalTests.swift && git commit -m "Add organizer proposal model and LLM service seam

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 6 — `OrganizerEngine` planning with a fake LLM (sanitize + de-dup + pattern)

**Files:** `Shared/Sources/Core/FileOrganizer/OrganizerEngine.swift`, test `Shared/Tests/CoreTests/FileOrganizer/OrganizerEngineTests.swift`

- [ ] Write a failing test with a fake LLM asserting the full per-file pipeline (spec §3.2, §9):

```swift
import XCTest
@testable import Core

private final class FakeLLM: OrganizerLLMService, @unchecked Sendable {
    var names: [String]
    var folderPlan: [String: String]
    private(set) var lastRenameRequests: [RenameRequest] = []
    init(names: [String], folderPlan: [String: String] = [:]) {
        self.names = names; self.folderPlan = folderPlan
    }
    func proposeName(_ request: RenameRequest) async throws -> String {
        lastRenameRequests.append(request)
        return names.removeFirst()
    }
    func proposeFolders(_ request: FolderPlanRequest) async throws -> [String: String] { folderPlan }
}

final class OrganizerEngineTests: XCTestCase {
    private func content(_ name: String, _ kind: ContentKind = .pdf) -> ExtractedContent {
        ExtractedContent(originalURL: URL(fileURLWithPath: "/in/\(name)"),
                         utTypeIdentifier: "com.adobe.pdf", kind: kind, snippet: "x", metadata: [:])
    }

    func testSanitizesAndPreservesExtension() async throws {
        let llm = FakeLLM(names: ["Q1/Report:2026"])
        let engine = OrganizerEngine(llm: llm, pattern: .identity, maxNameLength: 120)
        let proposal = try await engine.plan(contents: [content("a.pdf")],
                                             existingNames: [], recentExamples: [], includeFolders: false)
        XCTAssertEqual(proposal.operations[0].proposedName, "Q1-Report-2026.pdf")
    }

    func testDeterministicCollisionAcrossBatch() async throws {
        let llm = FakeLLM(names: ["Receipt", "Receipt"])
        let engine = OrganizerEngine(llm: llm, pattern: .identity, maxNameLength: 120)
        let proposal = try await engine.plan(contents: [content("a.pdf"), content("b.pdf")],
                                             existingNames: [], recentExamples: [], includeFolders: false)
        XCTAssertEqual(proposal.operations.map(\.proposedName), ["Receipt.pdf", "Receipt (2).pdf"])
    }

    func testFolderPlanDepthAndCountCaps() async throws {
        let llm = FakeLLM(names: ["A", "B"],
                          folderPlan: ["A.pdf": "x/y/z/deep", "B.pdf": "Invoices"])
        let engine = OrganizerEngine(llm: llm, pattern: .identity, maxNameLength: 120,
                                     maxFolderDepth: 2, maxFolders: 5)
        let proposal = try await engine.plan(contents: [content("a.pdf"), content("b.pdf")],
                                             existingNames: [], recentExamples: [], includeFolders: true)
        // Depth is measured as the number of path separators (`/`).
        // "x/y/z/deep" has 3 separators → depth 3 → rejected when maxFolderDepth is 2.
        // "x/y" has 1 separator → depth 1 → allowed.
        // "Invoices" has 0 separators → depth 0 → allowed.
        // Implementation: path.filter { $0 == "/" }.count
        // Over-deep assignment is rejected -> stays in place (nil); valid one kept.
        XCTAssertNil(proposal.operations[0].targetFolder)
        XCTAssertEqual(proposal.operations[1].targetFolder, "Invoices")
    }

    func testRecentExamplesForwardedToLLM() async throws {
        let llm = FakeLLM(names: ["A"])
        let engine = OrganizerEngine(llm: llm, pattern: .identity, maxNameLength: 120)
        _ = try await engine.plan(contents: [content("a.pdf")], existingNames: [],
                                  recentExamples: [(before: "bad", after: "good")], includeFolders: false)
        XCTAssertEqual(llm.lastRenameRequests[0].recentExamples.count, 1)
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerEngineTests`
- [ ] Implement `OrganizerEngine` (`init(llm:pattern:maxNameLength:maxFolderDepth:maxFolders:)`, depth/folders default 2/12). `plan(...)`: for each content call `llm.proposeName` with `RenameRequest(content:recentExamples:)`, `FilenameSanitizer.sanitizeBase` → `NamingPattern.render` → `FilenameSanitizer.compose(base:ext:)` preserving the original extension, then a single `CollisionResolver(existing: existingNames)` shared across the batch. If `includeFolders`, call `llm.proposeFolders` once; sanitize each folder component with `FilenameSanitizer.sanitizeBase`, reject assignments exceeding `maxFolderDepth` using `path.filter { $0 == "/" }.count` (e.g. `"x/y/z/deep"` → 3 separators → rejected at maxFolderDepth 2), cap distinct folders to `maxFolders`. No UI, no file mutation.
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerEngineTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/OrganizerEngine.swift Shared/Tests/CoreTests/FileOrganizer/OrganizerEngineTests.swift && git commit -m "Add OrganizerEngine planning with injectable LLM

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 7 — `ManifestOperation` record + reverse-replay model (pure)

**Files:** `Shared/Sources/Core/FileOrganizer/ManifestOperation.swift`, test `Shared/Tests/CoreTests/FileOrganizer/ManifestOperationTests.swift`

- [ ] Write failing tests for the undo data structure (spec §5.1, §3.6):

```swift
import XCTest
@testable import Core

final class ManifestOperationTests: XCTestCase {
    func testReverseReplayOrdersOpsLastFirst() {
        let a = ManifestOperation(sourceURL: URL(fileURLWithPath: "/r/a.pdf"),
                                  destinationURL: URL(fileURLWithPath: "/r/Invoices/Inv.pdf"),
                                  originalName: "a.pdf", newName: "Inv.pdf", kind: .both,
                                  appliedAt: Date(), createdFolders: ["Invoices"], status: .applied)
        let b = ManifestOperation(sourceURL: URL(fileURLWithPath: "/r/b.pdf"),
                                  destinationURL: URL(fileURLWithPath: "/r/Note.pdf"),
                                  originalName: "b.pdf", newName: "Note.pdf", kind: .rename,
                                  appliedAt: Date(), createdFolders: [], status: .applied)
        let manifest = OrganizerManifest(id: "M1", state: .applied,
                                         rootPath: "/r", operations: [a, b])
        XCTAssertEqual(manifest.reverseApplied().map(\.newName), ["Note.pdf", "Inv.pdf"])
    }

    func testCreatedFoldersAggregatedForCleanup() {
        let a = ManifestOperation(sourceURL: URL(fileURLWithPath: "/r/a"),
                                  destinationURL: URL(fileURLWithPath: "/r/X/a"),
                                  originalName: "a", newName: "a", kind: .move,
                                  appliedAt: Date(), createdFolders: ["X"], status: .applied)
        let manifest = OrganizerManifest(id: "M", state: .applied, rootPath: "/r", operations: [a])
        XCTAssertEqual(manifest.allCreatedFolders, ["X"])
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ManifestOperationTests`
- [ ] Implement `ManifestOperation` (Codable: sourceURL, destinationURL, originalName, newName, `kind: OperationKind{rename,move,both}`, appliedAt, createdFolders, `status: OperationStatus{applied,failed,reverted}`) and `OrganizerManifest` (Codable: id, `state: ManifestState{applied,reverted,partial}`, rootPath, operations; `reverseApplied()` returns applied ops in reverse order; `allCreatedFolders` is the unique union, deepest-first).
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter ManifestOperationTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/ManifestOperation.swift Shared/Tests/CoreTests/FileOrganizer/ManifestOperationTests.swift && git commit -m "Add operation manifest model with reverse-replay

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 8 — `OrganizerManifestStore` (encrypted GRDB, op-by-op append)

**Files:** `Shared/Sources/Core/Storage/OrganizerManifestStore.swift`, test `Shared/Tests/CoreTests/Storage/OrganizerManifestStoreTests.swift`

- [ ] Write failing tests modeled on existing store tests (spec §5.1):

```swift
import CryptoKit
import XCTest
@testable import Core

final class OrganizerManifestStoreTests: XCTestCase {
    private func makeStore() throws -> OrganizerManifestStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("m.sqlite")
        let db = try Database(url: url, migrations: OrganizerManifestStore.migrations)
        return OrganizerManifestStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    func testInsertFetchRoundTrip() throws {
        let store = try makeStore()
        let op = ManifestOperation(sourceURL: URL(fileURLWithPath: "/r/a.pdf"),
                                   destinationURL: URL(fileURLWithPath: "/r/Inv.pdf"),
                                   originalName: "a.pdf", newName: "Inv.pdf", kind: .rename,
                                   appliedAt: Date(), createdFolders: [], status: .applied)
        let m = OrganizerManifest(id: "M1", state: .applied, rootPath: "/r", operations: [op])
        try store.insert(m)
        XCTAssertEqual(try store.fetch(id: "M1").operations.count, 1)
    }

    func testAppendOperationGrowsManifest() throws {
        let store = try makeStore()
        try store.insert(OrganizerManifest(id: "M2", state: .partial, rootPath: "/r", operations: []))
        let op = ManifestOperation(sourceURL: URL(fileURLWithPath: "/r/b"),
                                   destinationURL: URL(fileURLWithPath: "/r/B"),
                                   originalName: "b", newName: "B", kind: .rename,
                                   appliedAt: Date(), createdFolders: [], status: .applied)
        try store.appendOperation(op, to: "M2")
        XCTAssertEqual(try store.fetch(id: "M2").operations.count, 1)
    }

    func testUpdateStateAndList() throws {
        let store = try makeStore()
        try store.insert(OrganizerManifest(id: "M3", state: .applied, rootPath: "/r", operations: []))
        try store.updateState(id: "M3", to: .reverted)
        XCTAssertEqual(try store.fetch(id: "M3").state, .reverted)
        XCTAssertEqual(try store.list().count, 1)
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerManifestStoreTests`
- [ ] Implement `OrganizerManifestStore` mirroring `DownloadStore`: `static let migrations` creating `organizer_manifests(id TEXT PRIMARY KEY, state TEXT, created INTEGER, modified INTEGER, root_path TEXT, envelope BLOB)` + `idx_organizer_manifests_state`; `insert`, `fetch(id:)`, `appendOperation(_:to:)` (fetch → append → re-seal), `updateState(id:to:)`, `list()` ordered by `modified DESC`. Encrypt the `[ManifestOperation]` (full `OrganizerManifest`) via `Cipher.seal`/`Cipher.open`.

  > **Performance note:** `appendOperation` reads the entire manifest, appends one op, and re-writes — O(N) per append → O(N²) for a batch. This is acceptable for expected batch sizes (hundreds of files, not millions). If batches grow large, migrate to an append-only log format in a future iteration.
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerManifestStoreTests`
- [ ] Commit: `git add Shared/Sources/Core/Storage/OrganizerManifestStore.swift Shared/Tests/CoreTests/Storage/OrganizerManifestStoreTests.swift && git commit -m "Add encrypted OrganizerManifestStore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 9 — `OrganizerPreferenceStore` (learn-from-edits + bookmarks)

**Files:** `Shared/Sources/Core/Storage/OrganizerPreferenceStore.swift`, test `Shared/Tests/CoreTests/Storage/OrganizerPreferenceStoreTests.swift`

- [ ] Write failing tests (spec §5.2, §3.9): record corrections, fetch recent N newest-first, bounded retention, and bookmark blob round-trip.

```swift
import CryptoKit
import XCTest
@testable import Core

final class OrganizerPreferenceStoreTests: XCTestCase {
    private func makeStore() throws -> OrganizerPreferenceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("p.sqlite")
        let db = try Database(url: url, migrations: OrganizerPreferenceStore.migrations)
        return OrganizerPreferenceStore(database: db, deviceKey: SymmetricKey(size: .bits256))
    }

    func testRecentCorrectionsNewestFirst() throws {
        let store = try makeStore()
        try store.recordCorrection(.init(kind: .pdf, gist: "g1", proposed: "A", corrected: "B"))
        try store.recordCorrection(.init(kind: .pdf, gist: "g2", proposed: "C", corrected: "D"))
        let recent = try store.recentCorrections(limit: 1)
        XCTAssertEqual(recent.first?.corrected, "D")
    }

    func testBoundedRetention() throws {
        let store = try makeStore()
        for i in 0..<250 {
            try store.recordCorrection(.init(kind: .text, gist: "g\(i)", proposed: "p", corrected: "c\(i)"))
        }
        XCTAssertLessThanOrEqual(try store.recentCorrections(limit: 1000).count, 200)
    }

    func testBookmarkRoundTrip() throws {
        let store = try makeStore()
        let data = Data([0x01, 0x02, 0x03])
        try store.saveBookmark(data, forKey: "/Users/me/Downloads", watchEnabled: true)
        let entry = try store.bookmark(forKey: "/Users/me/Downloads")
        XCTAssertEqual(entry?.data, data)
        XCTAssertEqual(entry?.watchEnabled, true)
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerPreferenceStoreTests`
- [ ] Implement `OrganizerPreferenceStore`: `Correction{kind,gist,proposed,corrected}`, `BookmarkEntry{data,watchEnabled}`. Two tables — `organizer_corrections(id,created,envelope)` and `organizer_bookmarks(folder_key TEXT PRIMARY KEY, watch_enabled INTEGER, created INTEGER, envelope BLOB)`. `recordCorrection` inserts (encrypted) then prunes to the newest 200; `recentCorrections(limit:)` returns newest-first; `saveBookmark`/`bookmark(forKey:)` upsert/read the encrypted bookmark blob + flag.
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerPreferenceStoreTests`
- [ ] Commit: `git add Shared/Sources/Core/Storage/OrganizerPreferenceStore.swift Shared/Tests/CoreTests/Storage/OrganizerPreferenceStoreTests.swift && git commit -m "Add OrganizerPreferenceStore for learn-from-edits and bookmarks

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 10 — Learn-from-edits feeds the next batch's prompt

**Files:** `Shared/Sources/Core/FileOrganizer/OrganizerEngine.swift` (extend), test append to `Shared/Tests/CoreTests/FileOrganizer/OrganizerEngineTests.swift`

- [ ] Write a failing test: corrections from the store become `recentExamples` on the next `plan` (spec §3.9). Add a convenience `plan(contents:existingNames:corrections:includeFolders:)` overload that maps `[Correction]` → `[(before, after)]` and forwards to the LLM.

```swift
func testCorrectionsBecomeRecentExamples() async throws {
    let llm = FakeLLM(names: ["X"])
    let engine = OrganizerEngine(llm: llm, pattern: .identity, maxNameLength: 120)
    let corrections = [Correction(kind: .pdf, gist: "g", proposed: "Bad", corrected: "Good")]
    _ = try await engine.plan(contents: [content("a.pdf")], existingNames: [],
                              corrections: corrections, includeFolders: false)
    XCTAssertEqual(llm.lastRenameRequests[0].recentExamples.first?.before, "Bad")
    XCTAssertEqual(llm.lastRenameRequests[0].recentExamples.first?.after, "Good")
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerEngineTests`
- [ ] Implement the overload mapping `Correction.proposed`→`before`, `Correction.corrected`→`after`.
- [ ] Run (expect PASS): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter OrganizerEngineTests`
- [ ] Commit: `git add Shared/Sources/Core/FileOrganizer/OrganizerEngine.swift Shared/Tests/CoreTests/FileOrganizer/OrganizerEngineTests.swift && git commit -m "Feed learn-from-edits corrections into rename prompt

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 11 — `FileMutator` apply (temp-dir integration) + op-by-op manifest

**Files:** `MacAllYouNeed/FileOrganizer/FileMutator.swift`, test `MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift`

- [ ] Write a failing temp-dir integration test (spec §3.6, §9 — no-overwrite, op-by-op):

```swift
import XCTest
import Core
@testable import MacAllYouNeed

final class FileMutatorTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testRenameAndMoveCreatesTargetAndManifest() throws {
        let root = try tempDir()
        let src = root.appendingPathComponent("a.pdf")
        try Data("pdf".utf8).write(to: src)
        let op = ProposedOperation(id: "1", sourceURL: src, originalName: "a.pdf",
                                   proposedName: "Invoice.pdf", targetFolder: "Invoices",
                                   reason: "", isRenameApproved: true, isFolderApproved: true)
        let mutator = FileMutator()
        let manifest = try mutator.apply(operations: [op], rootURL: root, manifestID: "M1")
        let dest = root.appendingPathComponent("Invoices/Invoice.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertEqual(manifest.operations.first?.status, .applied)
        XCTAssertEqual(manifest.operations.first?.createdFolders, ["Invoices"])
    }

    func testNeverOverwritesExistingTarget() throws {
        let root = try tempDir()
        let src = root.appendingPathComponent("a.pdf")
        try Data("new".utf8).write(to: src)
        let existing = root.appendingPathComponent("Taken.pdf")
        try Data("old".utf8).write(to: existing)
        let op = ProposedOperation(id: "1", sourceURL: src, originalName: "a.pdf",
                                   proposedName: "Taken.pdf", targetFolder: nil,
                                   reason: "", isRenameApproved: true, isFolderApproved: false)
        let manifest = try FileMutator().apply(operations: [op], rootURL: root, manifestID: "M2")
        XCTAssertEqual(try String(contentsOf: existing), "old")     // untouched
        XCTAssertEqual(manifest.operations.first?.status, .failed)  // skipped, flagged
        XCTAssertEqual(manifest.state, .partial)
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Implement `FileMutator.apply(operations:rootURL:manifestID:)`: for each approved op, compute the destination (root + targetFolder + proposedName), create needed folders (recording new ones in `createdFolders`), and use `FileManager.default.moveItem(at:to:)` which **fails closed** if the destination exists — on the existing-target case set status `.failed`, mark the manifest `.partial`, and stop. Build and return an `OrganizerManifest`, recording each op as it completes. (Persistence to the store happens in the coordinator; the mutator returns the in-memory manifest.)
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/FileMutator.swift MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift && git commit -m "Add FileMutator apply with no-overwrite and op-by-op manifest

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 12 — `FileMutator` undo + partial-apply rollback (temp-dir integration)

**Files:** `MacAllYouNeed/FileOrganizer/FileMutator.swift` (extend), test append to `MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift`

- [ ] Write a failing test: undo restores byte-for-byte original layout incl. empty-folder removal, and a partial manifest reverts only what succeeded (spec §3.6, §9, §11):

```swift
func testUndoRestoresOriginalLayout() throws {
    let root = try tempDir()
    let src = root.appendingPathComponent("a.pdf")
    try Data("pdf".utf8).write(to: src)
    let op = ProposedOperation(id: "1", sourceURL: src, originalName: "a.pdf",
                               proposedName: "Invoice.pdf", targetFolder: "Invoices",
                               reason: "", isRenameApproved: true, isFolderApproved: true)
    let mutator = FileMutator()
    let manifest = try mutator.apply(operations: [op], rootURL: root, manifestID: "M1")
    let reverted = try mutator.undo(manifest: manifest)
    XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Invoices").path))
    XCTAssertEqual(reverted.state, .reverted)
}

func testPartialUndoRevertsOnlyApplied() throws {
    let root = try tempDir()
    let a = root.appendingPathComponent("a.pdf"); try Data("a".utf8).write(to: a)
    let b = root.appendingPathComponent("b.pdf"); try Data("b".utf8).write(to: b)
    let taken = root.appendingPathComponent("B.pdf"); try Data("x".utf8).write(to: taken)
    let ops = [
        ProposedOperation(id: "1", sourceURL: a, originalName: "a.pdf", proposedName: "A.pdf",
                          targetFolder: nil, reason: "", isRenameApproved: true, isFolderApproved: false),
        ProposedOperation(id: "2", sourceURL: b, originalName: "b.pdf", proposedName: "B.pdf",
                          targetFolder: nil, reason: "", isRenameApproved: true, isFolderApproved: false)
    ]
    let mutator = FileMutator()
    let manifest = try mutator.apply(operations: ops, rootURL: root, manifestID: "M2") // op2 fails
    _ = try mutator.undo(manifest: manifest)
    XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))   // op1 reverted
    XCTAssertEqual(try String(contentsOf: taken), "x")             // never clobbered
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Implement `FileMutator.undo(manifest:)`: replay `manifest.reverseApplied()` moving `destinationURL`→`sourceURL`, then remove `manifest.allCreatedFolders` deepest-first only when empty; return the manifest with `state = .reverted` and op `status = .reverted`.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/FileMutator.swift MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift && git commit -m "Add FileMutator undo and partial-apply rollback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 13 — Stale-file guard at apply time (data-loss safety)

**Files:** `MacAllYouNeed/FileOrganizer/FileMutator.swift` (extend), test append to `MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift`

- [ ] Write a failing test: if the source's size/mtime changed since proposal, that op is skipped + flagged, not acted on (spec §9 "Concurrent external changes"). Extend `apply` to accept an optional `expectedFingerprints: [String: FileFingerprint]` (id → size+mtime); when a fingerprint mismatches, set op `.failed` and continue without moving.

```swift
func testSkipsFileChangedSinceProposal() throws {
    let root = try tempDir()
    let src = root.appendingPathComponent("a.pdf")
    try Data("orig".utf8).write(to: src)
    let stale = FileFingerprint(size: 999, modified: Date(timeIntervalSince1970: 0))
    let op = ProposedOperation(id: "1", sourceURL: src, originalName: "a.pdf",
                               proposedName: "New.pdf", targetFolder: nil,
                               reason: "", isRenameApproved: true, isFolderApproved: false)
    let manifest = try FileMutator().apply(operations: [op], rootURL: root, manifestID: "M",
                                           expectedFingerprints: ["1": stale])
    XCTAssertTrue(FileManager.default.fileExists(atPath: src.path)) // untouched
    XCTAssertEqual(manifest.operations.first?.status, .failed)
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Implement `FileFingerprint(size:modified:)` + the guard (default param `nil` keeps existing tests green).
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileMutatorTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/FileMutator.swift MacAllYouNeedTests/FileOrganizer/FileMutatorTests.swift && git commit -m "Add stale-file guard to FileMutator apply

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 14 — `ContentExtractor` UTType routing (testable) + Vision/PDFKit seams

**Files:** `MacAllYouNeed/FileOrganizer/ContentExtractor.swift`, test `MacAllYouNeedTests/FileOrganizer/ContentExtractorTests.swift`

- [ ] Write failing tests against fixture files for type routing, snippet byte cap, and metadata (spec §3.1, §10). Use a real text fixture written to a temp dir; the image/PDF text engines are behind injectable closures so tests don't need Vision/PDFKit output:

```swift
import XCTest
import UniformTypeIdentifiers
import Core
@testable import MacAllYouNeed

final class ContentExtractorTests: XCTestCase {
    func testClassifiesByUTType() {
        XCTAssertEqual(ContentExtractor.classify(ext: "png"), .image)
        XCTAssertEqual(ContentExtractor.classify(ext: "pdf"), .pdf)
        XCTAssertEqual(ContentExtractor.classify(ext: "swift"), .source)
        XCTAssertEqual(ContentExtractor.classify(ext: "txt"), .text)
        XCTAssertEqual(ContentExtractor.classify(ext: "xyz"), .unknown)
    }

    func testTextExtractionRespectsByteCap() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("notes.txt")
        try Data(String(repeating: "x", count: 50_000).utf8).write(to: f)
        let extractor = ContentExtractor(byteCap: 8_192, ocr: { _ in "" }, pdfText: { _ in ("", [:]) })
        let content = try extractor.extract(url: f)
        XCTAssertEqual(content.kind, .text)
        XCTAssertLessThanOrEqual(content.snippet.utf8.count, 8_192)
    }

    func testUnknownBinaryYieldsMetadataOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("blob.xyz")
        try Data([0x00, 0xFF, 0x00]).write(to: f)
        let extractor = ContentExtractor(byteCap: 8_192, ocr: { _ in "" }, pdfText: { _ in ("", [:]) })
        let content = try extractor.extract(url: f)
        XCTAssertEqual(content.kind, .unknown)
        XCTAssertTrue(content.snippet.isEmpty)
        XCTAssertNotNil(content.metadata["size"])
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/ContentExtractorTests`
- [ ] Implement `ContentExtractor`: `static func classify(ext:)` via `UTType(filenameExtension:)` conformance checks; `init(byteCap:ocr:pdfText:)` with `ocr: (URL) -> String` (production: `VNRecognizeTextRequest`) and `pdfText: (URL) -> (String, [String:String])` (production: `PDFDocument`, first N pages + `documentAttributes`). `extract(url:)` routes by kind, reads at most `byteCap` UTF-8 for text/source, calls the injected OCR/PDF seams for image/pdf, and always fills `metadata` (size, created/modified) for every kind. Default initializer wires the real Vision/PDFKit closures.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/ContentExtractorTests`
- [ ] **Manual verification (noted):** run a real Downloads scan and confirm OCR text from a screenshot PNG and first-page text from a real PDF appear in the diff pane reasons. Vision/PDFKit output is not unit-tested.
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/ContentExtractor.swift MacAllYouNeedTests/FileOrganizer/ContentExtractorTests.swift && git commit -m "Add ContentExtractor with UTType routing and Vision/PDFKit seams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 15 — Folder bookmark persistence + staleness handling

**Files:** `MacAllYouNeed/FileOrganizer/FolderBookmark.swift`, test `MacAllYouNeedTests/FileOrganizer/FolderBookmarkTests.swift`

- [ ] Write a failing test for bookmark round-trip + stale detection (spec §5.3, §9). Non-sandboxed `URL.bookmarkData()`/`URL(resolvingBookmarkData:)`:

```swift
import XCTest
@testable import MacAllYouNeed

final class FolderBookmarkTests: XCTestCase {
    func testBookmarkResolvesToSameFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try FolderBookmark.make(for: dir)
        let resolved = try FolderBookmark.resolve(data)
        XCTAssertEqual(resolved.url.standardizedFileURL, dir.standardizedFileURL)
        XCTAssertFalse(resolved.isStale)
    }

    func testResolveThrowsOnGarbageData() {
        XCTAssertThrowsError(try FolderBookmark.resolve(Data([0x00, 0x01])))
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderBookmarkTests`
- [ ] Implement `FolderBookmark.make(for:)` → `URL.bookmarkData(options: [])` and `resolve(_:)` → `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)` returning `(url, isStale)`. Document that callers re-prompt via `NSOpenPanel` when resolve throws or `isStale` is true.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FolderBookmarkTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/FolderBookmark.swift MacAllYouNeedTests/FileOrganizer/FolderBookmarkTests.swift && git commit -m "Add folder bookmark persistence with staleness handling

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 16 — `WatchDaemon` debounce + in-progress-file skip (never moves)

**Files:** `MacAllYouNeed/FileOrganizer/WatchDaemon.swift`, test `MacAllYouNeedTests/FileOrganizer/WatchDaemonTests.swift`

- [ ] Write failing tests for the debounce/queue logic + `.part`/`.crdownload` skip, asserting the daemon only **emits a proposal request**, never mutates (spec §3.8, §9). Drive the pure queue with an injected clock so the FSEvents source itself is a thin seam:

```swift
import XCTest
@testable import MacAllYouNeed

final class WatchDaemonTests: XCTestCase {
    func testSkipsInProgressDownloads() {
        XCTAssertTrue(WatchQueue.shouldSkip(filename: "movie.mp4.part"))
        XCTAssertTrue(WatchQueue.shouldSkip(filename: "movie.crdownload"))
        XCTAssertFalse(WatchQueue.shouldSkip(filename: "movie.mp4"))
    }

    func testDebounceCoalescesBurst() {
        var queue = WatchQueue(debounce: 5)
        queue.enqueue("a.pdf", at: 0)
        queue.enqueue("b.pdf", at: 2)
        XCTAssertEqual(queue.readyBatch(now: 4), [])          // still quiet-window
        XCTAssertEqual(queue.readyBatch(now: 8).sorted(), ["a.pdf", "b.pdf"])
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/WatchDaemonTests`
- [ ] Implement a pure `WatchQueue` (`debounce` seconds, `enqueue(_:at:)`, `shouldSkip(filename:)`, `readyBatch(now:)` returning files only after `debounce` of quiet) and a thin `WatchDaemon` that owns the `DispatchSource`/`FSEvents` watch on a resolved bookmarked folder, funnels filenames through `WatchQueue`, and calls an `onBatchReady: ([URL]) -> Void` callback. The daemon **never** mutates files — it hands the batch to the coordinator, which opens the diff pane.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/WatchDaemonTests`
- [ ] **Manual verification (noted):** enable watch on a temp folder, drop a file, confirm a proposal surfaces (dashboard badge) and nothing moves until Apply. FSEvents wiring is not unit-tested.
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/WatchDaemon.swift MacAllYouNeedTests/FileOrganizer/WatchDaemonTests.swift && git commit -m "Add WatchDaemon debounce queue and in-progress skip

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 17 — Real `OrganizerLLMService` over S2 (Groq default + local) — injectable

**Files:** `MacAllYouNeed/FileOrganizer/S2OrganizerLLMService.swift`, test `MacAllYouNeedTests/FileOrganizer/S2OrganizerLLMServiceTests.swift`

- [ ] Write a failing test that the S2-backed service builds `file-organizer/rename` / `file-organizer/folder-plan` prompts from an `ExtractedContent` containing **only snippet + metadata** and never the file URL bytes (spec §3.2, §6, §11). Use a fake S2 completion seam (the same shape as `cleanupPipelineFactoryOverride`):

```swift
import XCTest
import Core
@testable import MacAllYouNeed

final class S2OrganizerLLMServiceTests: XCTestCase {
    func testRenamePromptContainsSnippetNotBytes() async throws {
        var capturedSystemPrompt = ""
        var capturedUserPrompt = ""
        // complete: (systemPrompt: String, userPrompt: String) async throws -> String
        let service = S2OrganizerLLMService(complete: { system, user in
            capturedSystemPrompt = system; capturedUserPrompt = user; return "Clean Name"
        })
        let content = ExtractedContent(originalURL: URL(fileURLWithPath: "/secret/path/a.pdf"),
            utTypeIdentifier: "com.adobe.pdf", kind: .pdf, snippet: "INVOICE #42", metadata: ["author": "ACME"])
        let name = try await service.proposeName(.init(content: content, recentExamples: []))
        XCTAssertEqual(name, "Clean Name")
        XCTAssertTrue(capturedUserPrompt.contains("INVOICE #42"))
        XCTAssertFalse(capturedUserPrompt.contains("/secret/path"))  // no raw path/bytes
        XCTAssertFalse(capturedSystemPrompt.contains("/secret/path"))
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/S2OrganizerLLMServiceTests`
- [ ] Implement `S2OrganizerLLMService` conforming to `OrganizerLLMService`, injected with `complete: (systemPrompt: String, userPrompt: String) async throws -> String` from the S2 layer (which carries the user's `VoiceCleanupProviderKind` Groq/local selection). Build prompts from `content.snippet` + sanitized metadata + `recentExamples` few-shot; never include the file path or any bytes. Production constructs `complete` from the shared S2 service; tests inject a stub closure matching that same `(systemPrompt: String, userPrompt: String) async throws -> String` signature.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/S2OrganizerLLMServiceTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/S2OrganizerLLMService.swift MacAllYouNeedTests/FileOrganizer/S2OrganizerLLMServiceTests.swift && git commit -m "Add S2-backed OrganizerLLMService sending only snippets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 18 — Coordinator: scan → propose, with LLM-failure leave-untouched

**Files:** `MacAllYouNeed/FileOrganizer/FileOrganizerCoordinator.swift`, test `MacAllYouNeedTests/FileOrganizer/FileOrganizerCoordinatorTests.swift`

- [ ] Write a failing test wiring extractor + engine + stores, asserting an LLM failure for one file leaves it with its original name while others still get proposals (spec §9 "LLM failure", §11). Inject a fake extractor, a `FakeLLM` stub that throws on a specified call index, and the in-memory stores from Tasks 8/9.

```swift
// Stub LLM that throws on a specific call index.
final class FakeLLM: OrganizerLLMService, @unchecked Sendable {
    var namesByIndex: [String]
    var throwOnIndex: Int?
    private var callCount = 0
    init(names: [String], throwOn: Int? = nil) { namesByIndex = names; throwOnIndex = throwOn }
    func proposeName(_ request: RenameRequest) async throws -> String {
        defer { callCount += 1 }
        if callCount == throwOnIndex { throw OrganizerError.llmFailure("stub") }
        return namesByIndex[callCount % namesByIndex.count]
    }
    func proposeFolders(_ request: FolderPlanRequest) async throws -> [String: String] { [:] }
}

func testLLMFailureLeavesFileUntouched() async throws {
    // FakeLLM: returns "Good" on call 0, throws on call 1.
    let llm = FakeLLM(names: ["Good", "ignored"], throwOn: 1)
    let coordinator = makeCoordinator(llm: llm)
    let proposal = try await coordinator.scan(urls: [pdfA, pdfB])
    XCTAssertEqual(proposal.operations[0].proposedName, "Good.pdf")
    XCTAssertEqual(proposal.operations[1].proposedName, "b.pdf") // original preserved on throw
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileOrganizerCoordinatorTests`
- [ ] Implement `FileOrganizerCoordinator` (owned by `AppController`): `scan(urls:)` extracts each file, calls the engine per file, and on a per-file LLM throw produces a `ProposedOperation` whose `proposedName == originalName` (untouched, `reason: "couldn't name"`). `apply(proposal:)` persists the manifest via `OrganizerManifestStore`, runs `FileMutator`, records inline edits as corrections via `OrganizerPreferenceStore`, and exposes `undo(manifestID:)`.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/FileOrganizerCoordinatorTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/FileOrganizerCoordinator.swift MacAllYouNeedTests/FileOrganizer/FileOrganizerCoordinatorTests.swift && git commit -m "Add FileOrganizerCoordinator with LLM-failure leave-untouched

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 19 — Mandatory preview/approve diff pane (UI, design-system)

**Files:** `MacAllYouNeed/FileOrganizer/UI/OrganizerDiffPane.swift`, test `MacAllYouNeedTests/FileOrganizer/OrganizerDiffPaneModelTests.swift`

- [ ] Write a failing test on the pane's view model (the safety gate is logic, the view is thin): Apply is disabled with zero approved ops; toggling select-all approves all; inline edit updates the op **and** records a correction (spec §3.5, §8.3, §11 mitigation 1).

```swift
@MainActor
final class OrganizerDiffPaneModelTests: XCTestCase {
    func testApplyDisabledWhenNothingApproved() {
        let model = OrganizerDiffPaneModel(proposal: proposalAllUnapproved)
        XCTAssertFalse(model.canApply)
    }
    func testApproveBothEnablesApply() {
        let model = OrganizerDiffPaneModel(proposal: proposalAllUnapproved)
        model.approveAll()
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.approvedCount, model.proposal.operations.count)
    }
    func testInlineEditRecordsCorrection() {
        let model = OrganizerDiffPaneModel(proposal: proposalOneOp)
        model.edit(operationID: "1", to: "Better Name.pdf")
        XCTAssertEqual(model.proposal.operations[0].proposedName, "Better Name.pdf")
        XCTAssertEqual(model.pendingCorrections.count, 1)
    }
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/OrganizerDiffPaneModelTests`
- [ ] Implement `OrganizerDiffPaneModel` (`canApply` = approvedCount > 0; `approveAll`/`approveNone`/`approveRenamesOnly`/`approveFoldersOnly`; `edit(operationID:to:)` updates the op and appends a `Correction` to `pendingCorrections`). Implement `OrganizerDiffPane` SwiftUI sheet using `MAYNTheme`/`MAYNControlMetrics`/`MAYNMotion`, per-row FolderPreview icon, old→new with change highlight, proposed folder ("stays here" when nil), per-row checkbox + `MAYNTextField` inline edit, header `FunctionSegmentedTabStrip` (renames/folders/both) + live count, a non-default `MAYNButton(.primary)` **Apply** and `MAYNButton(.secondary)` **Cancel** that discards with no filesystem change.
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/OrganizerDiffPaneModelTests`
- [ ] **Manual verification (noted):** confirm no code path applies without `canApply`; Reduce Motion leaves no spatial animation.
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/UI/OrganizerDiffPane.swift MacAllYouNeedTests/FileOrganizer/OrganizerDiffPaneModelTests.swift && git commit -m "Add mandatory preview/approve diff pane

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 20 — Tool page (FunctionPageShell) + History/undo + privacy disclosure

**Files:** `MacAllYouNeed/FileOrganizer/UI/FileOrganizerPage.swift`, `MacAllYouNeed/FileOrganizer/UI/OrganizerHistoryView.swift`, test `MacAllYouNeedTests/FileOrganizer/OrganizerHistoryModelTests.swift`

- [ ] Write a failing test on the History view model: lists manifests newest-first, "Undo last batch" targets the most recent `.applied`/`.partial` manifest, and a reverted manifest is marked not deleted (spec §3.6, §8.1, §8.4).

```swift
func testUndoLastTargetsMostRecentApplied() {
    let model = OrganizerHistoryModel(manifests: [appliedOld, revertedMid, partialNew])
    XCTAssertEqual(model.undoLastTargetID, partialNew.id)
}
```

- [ ] Run (expect FAIL): `xcodebuild test ... -only-testing:MacAllYouNeedTests/OrganizerHistoryModelTests`
- [ ] Implement `OrganizerHistoryModel` (`undoLastTargetID` = newest non-reverted) and `OrganizerHistoryView` (manifest rows: folder/count/date/state + per-row Undo). Implement `FileOrganizerPage` via `FunctionPageShell` + `FunctionSegmentedTabStrip` (Organize / Watch / History): Organize tab has **Scan Downloads** + **Choose Folder…** (`NSOpenPanel` directory mode → bookmark), the `NamingPattern` summary chip, a progress row, and the §8.6 privacy disclosure ("Only short extracted text snippets and file metadata are sent…") with the active provider + a "what gets sent" sample preview. Wire Apply→transient undo affordance (Voice `pendingUndo` mental model).
- [ ] Run (expect PASS): `xcodebuild test ... -only-testing:MacAllYouNeedTests/OrganizerHistoryModelTests`
- [ ] Commit: `git add MacAllYouNeed/FileOrganizer/UI/FileOrganizerPage.swift MacAllYouNeed/FileOrganizer/UI/OrganizerHistoryView.swift MacAllYouNeedTests/FileOrganizer/OrganizerHistoryModelTests.swift && git commit -m "Add File Organizer tool page, history, and privacy disclosure

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 21 — Feature wiring: `FeatureID`, descriptor, store registration, destination

**Files:** `Shared/Sources/FeatureCore/FeatureID.swift`, `MacAllYouNeed/App/Descriptors/FileOrganizerDescriptor.swift`, `MacAllYouNeed/App/Coordinators/AppStoreContainer.swift`, `MacAllYouNeed/App/MainAppDestination.swift`, `MacAllYouNeed/App/FunctionDestinationRegistry.swift`, test `Shared/Tests/CoreTests/FeatureID/FeatureIDTests.swift`

- [ ] Write a failing test that `.aiFileOrganizer` exists and round-trips its raw value:

```swift
import XCTest
@testable import FeatureCore

final class FeatureIDTests: XCTestCase {
    func testAIFileOrganizerCase() {
        XCTAssertEqual(FeatureID(rawValue: "aiFileOrganizer"), .aiFileOrganizer)
        XCTAssertTrue(FeatureID.allCases.contains(.aiFileOrganizer))
    }
}
```

- [ ] Run (expect FAIL): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureIDTests`
- [ ] Add `case aiFileOrganizer` to `FeatureID`. Run the Shared test (expect PASS).
- [ ] Implement `FileOrganizerDescriptor.descriptor()` mirroring `DownloaderDescriptor` (id `.aiFileOrganizer`, displayName "AI File Organizer", icon `wand.and.stars`, summary, `assetPacks: []`, an activator). Register the two new databases in `AppStoreContainer.makeProductionStores` (real file: `MacAllYouNeed/App/Coordinators/AppStoreContainer.swift`, method `static func makeProductionStores(...)`) as `databases/organizer.sqlite` with `OrganizerManifestStore.migrations + OrganizerPreferenceStore.migrations`, and expose the stores. Instantiate `FileOrganizerCoordinator` in `AppController.init` (real file: `MacAllYouNeed/App/AppController.swift`) using the stores from `AppStoreContainer`. Add the `.aiFileOrganizer` `MainAppDestination` case (title/subtitle/icon) and register `FileOrganizerPage` in `FunctionDestinationRegistry`.
- [ ] Run app build/tests (expect PASS): `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/FileOrganizerCoordinatorTests`
- [ ] Commit: `git add Shared/Sources/FeatureCore/FeatureID.swift Shared/Tests/CoreTests/FeatureID/FeatureIDTests.swift MacAllYouNeed/App/Descriptors/FileOrganizerDescriptor.swift MacAllYouNeed/App/Coordinators/AppStoreContainer.swift MacAllYouNeed/App/MainAppDestination.swift MacAllYouNeed/App/FunctionDestinationRegistry.swift && git commit -m "Wire AI File Organizer feature descriptor and stores

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 22 — Full-suite green + Voice regression gate

**Files:** none new (verification task)

- [ ] Run the full Shared suite (expect PASS, incl. existing `VoicePromptBuilder*Tests`): `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test`
- [ ] Run the full app suite (expect PASS, S2 refactor must not regress Voice): `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`
- [ ] Run lint (expect PASS): `swiftlint --strict` (no ad-hoc colors/animations/segmented pickers in the new UI).
- [ ] Commit (only if any fixups were needed): `git commit -am "Fix AI File Organizer test/lint fallout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

## Self-Review

Spec coverage check against `docs/specs/feature-expansion-2026/05-ai-file-organizer.md`:

- **Content extraction (§3.1):** Task 14 — UTType routing, Vision OCR seam, PDFKit seam, text/source byte cap, metadata-only for unknown, byte/page bound asserted.
- **AI rename: sanitization (§3.2):** Task 2 — illegal chars, whitespace, leading-dot trap, length cap, extension preservation, empty fallback.
- **Collision / de-dup (§3.2, §9):** Task 3 (resolver) + Task 6 (applied across the whole batch + target dir at proposal time) + Task 11 (re-checked atomically at apply, fail-closed).
- **Auto-foldering (§3.3):** Task 6 — depth/count caps, folder-name sanitization, "leave in place" when over-deep, optional per batch.
- **Custom naming patterns (§3.4):** Task 4 — date prefix/suffix, custom text, sequence, case styles, identity.
- **Mandatory preview/approve diff pane (§3.5, §8.3, §11.1):** Task 19 — `canApply` gate, approve renames/folders/both, inline edit, no apply path bypasses it.
- **Undo via operation manifest (§3.6, §5.1):** Task 7 (model), Task 8 (op-by-op store), Task 12 (reverse-replay + empty-folder cleanup), Task 20 (History + undo-last).
- **Partial-apply rollback (§9, §11.3):** Task 11 (`.partial` on failure) + Task 12 (partial undo) — explicit data-loss-safety tasks.
- **No-overwrite invariant + stale-file guard (§9, §11.2/11.4):** Task 11 + Task 13.
- **Entry points (§3.7):** Task 20 — Scan Downloads + `NSOpenPanel`; Task 15 — security-scoped bookmark persist/resolve + staleness re-prompt.
- **Watch mode (§3.8):** Task 16 — debounce, in-progress skip, proposal-only (never silent), routes to the same diff pane.
- **Learn-from-edits (§3.9, §5.2):** Task 9 (store), Task 10 (feeds next prompt), Task 19 (inline edits captured).
- **S2 reuse / only-snippets-to-cloud (§4, §6, §11 privacy):** Task 5 (seam), Task 17 (S2 service asserts snippet-in / path-out), Task 18 (LLM-failure leave-untouched).
- **Storage pattern (§5):** Tasks 8/9 mirror `DownloadStore` encrypted-envelope + `Migration` + `RecordID`.
- **Feature wiring (§4, §6):** Task 21 — `FeatureID`, descriptor, store registration, destination, page registry.
- **Design system (§8, CLAUDE.md):** Tasks 19/20 — `FunctionPageShell`, `FunctionSegmentedTabStrip`, `MAYNTheme`/`MAYNMotion`, `MAYNButton`/`MAYNTextField`, Reduce Motion noted.
- **Voice regression (§10):** Task 22 gates the S2 refactor against existing Voice tests.

Pure-testable units (sanitizer, collision, naming pattern, proposal/manifest models, engine with fake LLM, both stores, diff-pane + history view models) run under `swift test` / `xcodebuild test`; file-IO apply/undo/rollback use temp-dir integration tests; Vision/PDF extraction, the real S2 LLM, and FSEvents are behind injected seams with explicit manual-verification notes. Data-loss safety has dedicated tested tasks for the approve gate (19), the manifest (7/8), partial rollback (11/12), no-overwrite (11), and stale-file skip (13).
