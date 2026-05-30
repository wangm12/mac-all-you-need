# Clipboard Smart Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an additive, fully on-device "smart layer" over MAYN's existing clipboard manager that enriches records with inline calculation, link cleaning, type detection (email/URL/phone/JWT/color/code), background Vision OCR, sensitive-data filtering at capture, regex/slash search filters, and Apple `NLEmbedding` semantic search — all gated behind a new `FeatureID.clipboardSmartText`, off by default, reversible.

**Architecture:** Pure, `Sendable` logic (calculation, Luhn, link cleaner, detection, slash-query parsing, embedding cosine) lives in `Shared/Sources/Core/SmartText/` with exhaustive unit tests. Cheap classification + sensitive filtering run inline on the daemon hot path before `clip.append`; expensive OCR + embeddings run deferred in the main app via `ClipboardEnrichmentCoordinator`, writing back through new `ClipboardStore` columns (added by GRDB migration `008-smart-text`) and the existing FTS5 index. Search blends the new predicates and semantic cosine on top of the existing `FuzzyMatcher` chokepoint without rewriting it.

**Tech Stack:** Swift 5.9+, SwiftUI/AppKit, GRDB, Vision, NaturalLanguage (NLEmbedding), XCTest

---

## File Structure

### Create — Shared/Core (pure logic, unit-tested under `Shared` swift test)

| File | Responsibility |
|---|---|
| `Shared/Sources/Core/SmartText/SmartTextService.swift` | Pure `Sendable` enum. `analyze(text:) -> Detection`, `calculate(_:) -> CalculationResult?`, `cleanLink(_:) -> LinkCleanResult?`, `detectCodeLanguage(in:) -> CodeLanguage?`. All regex/keyword tables live here. |
| `Shared/Sources/Core/SmartText/SmartTextModels.swift` | `Detection`, `DetectedType`, `CalculationResult`, `LinkCleanResult`, `CodeLanguage` — `Codable`/`Equatable`/`Sendable` value types for the `detected_type` JSON payload. |
| `Shared/Sources/Core/SmartText/SensitiveContentFilter.swift` | `shouldSkip(text:windowTitle:pasteboardTypes:) -> SkipReason?`. Luhn on 13–19 digit runs + case-insensitive title keyword set + `org.nspasteboard.ConcealedType` short-circuit. |
| `Shared/Sources/Core/SmartText/ClipEmbeddingService.swift` | `NLEmbedding` wrapper: `vector(for:language:) -> [Float]?`, static `cosine(_:_:) -> Double`, `encode([Float]) -> Data` / `decode(Data) -> [Float]?` (Float32 little-endian blob). |
| `Shared/Sources/Core/SmartText/SmartTextRankBlend.swift` | Pure `blend(lexicalOrder:semanticScores:weight:) -> [String]` ranking policy (lexical-dominant; semantic breaks ties / rescues empty-lexical; NULL-embedding falls back to lexical). |

### Create — App side (Vision/UI; thin seams + manual verification noted)

| File | Responsibility |
|---|---|
| `MacAllYouNeed/ClipboardDock/Services/ImageOCRService.swift` | Vision `VNRecognizeTextRequest` wrapper: downsample > 8192px, 5 s timeout, single-flight per record, bounded pool (2). Testable seam: `recognize(cgImage:) async -> String?`. |
| `MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift` | Parse free text + `/app:`/`/type:`/`/date:` (+ `-` negation) + `/regex/` or regex-mode into predicates; pure value type, unit-tested under app scheme. |
| `MacAllYouNeed/App/Coordinators/ClipboardEnrichmentCoordinator.swift` | `@MainActor` coordinator: subscribes to `clipboardStoreDidChange` + 1 s poll, selects rows with NULL `ocr_text`/`embedding`, enriches off the hot path in bounded batches, writes back via `ClipboardStore`, upserts OCR into FTS. Idempotent/resumable; retention-scoped. |
| `MacAllYouNeed/App/Descriptors/ClipboardSmartTextDescriptor.swift` | `ClipboardSmartTextDescriptor` + `SmartTextFeatureActivator`; `requiredPermissions: []`. Registered alongside other descriptors. |
| `MacAllYouNeed/Settings/ClipboardSmartTextSettingsView.swift` | Toggles via `MAYNSettingsPage`/`MAYNSection`/`MAYNSettingsRow`/`MAYNDivider`; link-cleaner mode via `FunctionSegmentedTabStrip`. Persists in `AppGroupSettings.defaults`. |

### Modify

| File (line anchors) | Change |
|---|---|
| `Shared/Sources/Core/Storage/ClipboardStore.swift` (migrations `:67`; `append` `:117`; `SELECT` lists `:171,:191,:249,:272`; `metaRow` `:342`) | Append migration `008-smart-text`; add `detectedTypeJSON` param to `append`; project `detected_type`/`ocr_text`/`embedding` columns; add `setDetectedType`/`setOCRText`/`setEmbedding` + NULL-selection read helpers. |
| `Shared/Sources/Core/Models/ClipboardRecord.swift` (`ClipboardItemMeta` `:11`) | Add optional `detectedTypeJSON: String?`, `ocrText: String?`, `embedding: Data?`. |
| `Shared/Sources/FeatureCore/FeatureID.swift` (`:3`) | Add `case clipboardSmartText`. |
| `ClipboardDaemon/DaemonContainer.swift` (`persist` `:80`, append sites `:95-121`) | Run `SensitiveContentFilter` before text/rtf/html appends; auto-clean single-URL text when mode == auto; compute cheap `Detection` JSON and pass `detectedTypeJSON` into `append`. |
| `MacAllYouNeed/ClipboardDock/Model/SubModels/SearchFilterSubModel.swift` (`loadHistoryLocally` `:155`, `filteredAndRanked` `:303`, `xpcMeta` `:264`) | Parse query into `SmartSearchQuery`; loosen substring pre-filter when operators/regex/semantic present; apply slash/regex predicates; blend semantic cosine into the fuzzy ordering. |
| `MacAllYouNeed/App/LocalClipboardReader.swift` (popover filter `:144`) | Reuse `SmartSearchQuery` parse so operators work in the menu-bar popover. |
| `MacAllYouNeed/ClipboardDock/Model/DockItem.swift` (`:5`) | Map `detected_type` JSON onto `DockItemKind`; add `calculation`/`hasOCRText`/`trackerCount` affordance fields to `DockItem`. |
| `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift`, `LinkCard.swift` | Calculation result row + "Copy result"; "N trackers" badge + "Clean link". |
| `MacAllYouNeed/ClipboardDock/Views/Cards/CardContextMenu.swift` | Type-aware entries (Compose / Call / Decode / Copy recognized text / Restore original). |

### Create — Tests

`Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift`, `SensitiveContentFilterTests.swift`, `ClipEmbeddingServiceTests.swift`, `SmartTextRankBlendTests.swift`; `Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift`. App: `MacAllYouNeedTests/ClipboardDock/SmartSearchQueryTests.swift`, `ImageOCRServiceTests.swift`.

---

### Task 1: Smart Text value models (`Detection` / payloads)

**Files:** Create `Shared/Sources/Core/SmartText/SmartTextModels.swift` · Test `Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift`

- [ ] Write failing test for JSON round-trip of `Detection`:

```swift
@testable import Core
import XCTest

final class SmartTextServiceTests: XCTestCase {
    func testDetectionJSONRoundTrip() throws {
        let d = Detection(type: .code(language: .swift), calculation: nil, linkClean: nil)
        let json = try d.encodedJSON()
        let back = try Detection.decode(json: json)
        XCTAssertEqual(back, d)
    }
}
```

- [ ] Run to fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter SmartTextServiceTests` → fails: cannot find `Detection` in scope.
- [ ] Implement minimal models:

```swift
import Foundation

public enum CodeLanguage: String, Codable, Equatable, Sendable {
    case swift, javascript, python, sql, html, c, shell, unknown
}

public enum DetectedType: Codable, Equatable, Sendable {
    case plain, email, url, phone, jwt, color
    case code(language: CodeLanguage)
}

public struct CalculationResult: Codable, Equatable, Sendable {
    public let expression: String
    public let value: String
    public init(expression: String, value: String) {
        self.expression = expression; self.value = value
    }
}

public struct LinkCleanResult: Codable, Equatable, Sendable {
    public let cleaned: String
    public let removedCount: Int
    public let original: String
    public init(cleaned: String, removedCount: Int, original: String) {
        self.cleaned = cleaned; self.removedCount = removedCount; self.original = original
    }
}

public struct Detection: Codable, Equatable, Sendable {
    public let type: DetectedType
    public let calculation: CalculationResult?
    public let linkClean: LinkCleanResult?
    public init(type: DetectedType, calculation: CalculationResult? = nil, linkClean: LinkCleanResult? = nil) {
        self.type = type; self.calculation = calculation; self.linkClean = linkClean
    }
    public func encodedJSON() throws -> String {
        String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
    }
    public static func decode(json: String) throws -> Detection {
        try JSONDecoder().decode(Detection.self, from: Data(json.utf8))
    }
}
```

- [ ] Run to pass: same command → 1 test passes.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextModels.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(smarttext): add Detection value models

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Inline calculation evaluator

**Files:** Create `Shared/Sources/Core/SmartText/SmartTextService.swift` · Test `Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift`

- [ ] Add failing tests (valid, precedence, div-by-zero silent, phone-not-math, date-not-math, bare-number rejected, length cap):

```swift
func testCalculateBasic() {
    XCTAssertEqual(SmartTextService.calculate("2+3*4")?.value, "14")
}
func testCalculateParensAndDecimals() {
    XCTAssertEqual(SmartTextService.calculate("(1.5+2.5)*2")?.value, "8")
}
func testCalculateDivByZeroIsSilent() {
    XCTAssertNil(SmartTextService.calculate("5/0"))
}
func testCalculateRejectsBareNumber() {
    XCTAssertNil(SmartTextService.calculate("42"))
}
func testCalculateRejectsPhone() {
    XCTAssertNil(SmartTextService.calculate("+1-415-555-2671"))
}
func testCalculateRejectsDate() {
    XCTAssertNil(SmartTextService.calculate("2026-05-30"))
}
func testCalculateRejectsOverLength() {
    XCTAssertNil(SmartTextService.calculate(String(repeating: "1+", count: 200) + "1"))
}
```

- [ ] Run to fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter testCalculate` → fails: cannot find `SmartTextService`.
- [ ] Implement minimal `calculate`:

```swift
import Foundation

public enum SmartTextService {
    public static func calculate(_ raw: String) -> CalculationResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count <= 256, !s.isEmpty else { return nil }
        // Reject NSDataDetector phone/date matches outright.
        if let det = try? NSDataDetector(types:
            NSTextCheckingResult.CheckingType.phoneNumber.rawValue |
            NSTextCheckingResult.CheckingType.date.rawValue),
           det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil {
            return nil
        }
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%^() ,")
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let expr = s.replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "^", with: "**")
        // Require a binary operator with a digit on each side.
        guard expr.range(of: #"\d\s*[-+*/%]|\*\*"#, options: .regularExpression) != nil,
              expr.range(of: #"[-+*/%]\s*[\d(]"#, options: .regularExpression) != nil else { return nil }
        let ns = NSExpression(format: expr.replacingOccurrences(of: "**", with: "**"))
        guard let n = ns.expressionValue(with: nil, context: nil) as? NSNumber else { return nil }
        let d = n.doubleValue
        guard d.isFinite else { return nil }
        let value = (d == d.rounded()) ? String(Int(d)) : String(d)
        return CalculationResult(expression: s, value: value)
    }
}
```

(Note: `NSExpression(format:)` supports `**` via `raise:toPower:`; verify with `2^3 = 8` test added below.)

- [ ] Add `func testCalculatePower() { XCTAssertEqual(SmartTextService.calculate("2^3")?.value, "8") }`.
- [ ] Run to pass: same command → calculation tests pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextService.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(smarttext): bounded inline calculation evaluator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Link cleaner with tracking-parameter table

**Files:** Modify `Shared/Sources/Core/SmartText/SmartTextService.swift` · Test `SmartTextServiceTests.swift`

- [ ] Add failing tests (each key class, prefix, order preservation, empty-query collapse, non-tracking preserved, fragment/path kept, multi-line URL left alone, non-URL returns nil):

```swift
func testCleanLinkStripsUTMPrefix() {
    let r = SmartTextService.cleanLink("https://x.com/p?utm_source=a&utm_medium=b&id=7")
    XCTAssertEqual(r?.cleaned, "https://x.com/p?id=7")
    XCTAssertEqual(r?.removedCount, 2)
}
func testCleanLinkStripsKnownKeys() {
    XCTAssertEqual(SmartTextService.cleanLink("https://x.com/?fbclid=z&q=1")?.cleaned, "https://x.com/?q=1")
}
func testCleanLinkEmptyQueryCollapses() {
    XCTAssertEqual(SmartTextService.cleanLink("https://x.com/p?utm_source=a")?.cleaned, "https://x.com/p")
}
func testCleanLinkPreservesFragmentAndOrder() {
    XCTAssertEqual(SmartTextService.cleanLink("https://x.com/p?b=2&a=1#frag")?.cleaned, nil) // no trackers -> nil
}
func testCleanLinkNoTrackersReturnsNil() {
    XCTAssertNil(SmartTextService.cleanLink("https://x.com/p?a=1"))
}
func testCleanLinkMultilineReturnsNil() {
    XCTAssertNil(SmartTextService.cleanLink("see https://x.com/?utm_source=a here"))
}
```

- [ ] Run to fail: `... swift test --filter testCleanLink` → fails: no `cleanLink`.
- [ ] Implement:

```swift
extension SmartTextService {
    public static let trackingParameters: Set<String> = [
        "fbclid","gclid","gclsrc","dclid","msclkid","mc_eid","mc_cid",
        "igshid","si","ref","ref_src","_hsenc","_hsmi","vero_id",
        "oly_enc_id","oly_anon_id","yclid","twclid","wickedid","_openstat"
    ]
    public static func isTracking(_ key: String) -> Bool {
        let k = key.lowercased()
        return k.hasPrefix("utm_") || trackingParameters.contains(k)
    }
    public static func cleanLink(_ raw: String) -> LinkCleanResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains("\n"), !s.contains(" "),
              var comps = URLComponents(string: s),
              let scheme = comps.scheme, scheme == "http" || scheme == "https",
              comps.host != nil, let items = comps.queryItems, !items.isEmpty
        else { return nil }
        let kept = items.filter { !isTracking($0.name) }
        let removed = items.count - kept.count
        guard removed > 0 else { return nil }
        comps.queryItems = kept.isEmpty ? nil : kept
        guard let cleaned = comps.string else { return nil }
        return LinkCleanResult(cleaned: cleaned, removedCount: removed, original: s)
    }
}
```

- [ ] Run to pass: `... swift test --filter testCleanLink`.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextService.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(smarttext): tracking-parameter link cleaner

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Code-language heuristic (markdown → plain)

**Files:** Modify `SmartTextService.swift` · Test `SmartTextServiceTests.swift`

- [ ] Add failing tests:

```swift
func testDetectSwift() { XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "func foo() {\n  let x = 1\n}"), .swift) }
func testDetectSQL() { XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "SELECT id FROM users WHERE x = 1"), .sql) }
func testDetectHTML() { XCTAssertEqual(SmartTextService.detectCodeLanguage(in: "<div class=\"a\"><span>hi</span></div>"), .html) }
func testMarkdownIsNotCode() { XCTAssertNil(SmartTextService.detectCodeLanguage(in: "# Title\n\n- bullet\n- bullet")) }
func testProseIsNotCode() { XCTAssertNil(SmartTextService.detectCodeLanguage(in: "Just a normal sentence about cats.")) }
```

- [ ] Run to fail: `... swift test --filter "testDetect|testMarkdown|testProse"` → fails: no `detectCodeLanguage`.
- [ ] Implement keyword/sigil heuristic (brace density, `def`/`func`/`import`/`SELECT`/`<tag>`/`#include`; markdown `#`/`-`/`*` bullets are NOT code):

```swift
extension SmartTextService {
    public static func detectCodeLanguage(in raw: String) -> CodeLanguage? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Markdown guard: heading or list lines dominate -> not code.
        let lines = s.split(separator: "\n")
        let mdLines = lines.filter { $0.hasPrefix("#") || $0.hasPrefix("- ") || $0.hasPrefix("* ") }
        if !lines.isEmpty, mdLines.count * 2 >= lines.count, !s.contains("{") { return nil }
        if s.range(of: #"(?i)\bselect\b[\s\S]+\bfrom\b"#, options: .regularExpression) != nil { return .sql }
        if s.range(of: #"<[a-zA-Z][^>]*>[\s\S]*</[a-zA-Z]"#, options: .regularExpression) != nil { return .html }
        if s.contains("func ") || s.contains("let ") || s.contains("var ") || s.contains("guard ") { return .swift }
        if s.contains("=>") || s.contains("const ") || s.contains("function ") { return .javascript }
        if s.contains("def ") || s.contains("import ") && s.contains(":") { return .python }
        if s.contains("#include") { return .c }
        if s.hasPrefix("#!/") || s.contains("echo ") { return .shell }
        let braceDensity = (s.contains("{") && s.contains("}")) || s.contains(";\n")
        return braceDensity ? .unknown : nil
    }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextService.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(smarttext): code-language heuristic excluding markdown

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `analyze` precedence (color > url > email > jwt > phone > code > plain)

**Files:** Modify `SmartTextService.swift` · Test `SmartTextServiceTests.swift`

- [ ] Add failing tests:

```swift
func testAnalyzeColorBeatsCode() { XCTAssertEqual(SmartTextService.analyze(text: "#ff8800").type, .color) }
func testAnalyzeURL() { XCTAssertEqual(SmartTextService.analyze(text: "https://x.com").type, .url) }
func testAnalyzeEmail() { XCTAssertEqual(SmartTextService.analyze(text: "a.b@example.com").type, .email) }
func testAnalyzeJWT() {
    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.sig"
    XCTAssertEqual(SmartTextService.analyze(text: jwt).type, .jwt)
}
func testAnalyzePhone() { XCTAssertEqual(SmartTextService.analyze(text: "+1 (415) 555-2671").type, .phone) }
func testAnalyzeCode() { if case .code = SmartTextService.analyze(text: "func a() {}").type {} else { XCTFail() } }
func testAnalyzeParagraphIsPlain() { XCTAssertEqual(SmartTextService.analyze(text: "email me at a@b.com please").type, .plain) }
func testAnalyzeAttachesCalculation() { XCTAssertNotNil(SmartTextService.analyze(text: "2+2").calculation) }
```

- [ ] Run to fail: `... swift test --filter testAnalyze` → fails: no `analyze`.
- [ ] Implement (whole-string matches; JWT header decodes to JSON with `alg`/`typ`; calc/linkClean attached when present):

```swift
extension SmartTextService {
    public static func analyze(text raw: String) -> Detection {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let calc = calculate(s)
        let link = cleanLink(s)
        let type = classify(s)
        return Detection(type: type, calculation: calc, linkClean: link)
    }
    static func classify(_ s: String) -> DetectedType {
        if isColor(s) { return .color }
        if isSingleURL(s) { return .url }
        if isEmail(s) { return .email }
        if isJWT(s) { return .jwt }
        if isWholePhone(s) { return .phone }
        if let lang = detectCodeLanguage(in: s) { return .code(language: lang) }
        return .plain
    }
    static func isColor(_ s: String) -> Bool {
        s.range(of: #"^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#, options: .regularExpression) != nil
        || s.range(of: #"^(rgb|rgba|hsl)\([^)]*\)$"#, options: .regularExpression) != nil
    }
    static func isSingleURL(_ s: String) -> Bool {
        guard !s.contains(" "), !s.contains("\n"), let u = URLComponents(string: s) else { return false }
        return (u.scheme == "http" || u.scheme == "https") && (u.host?.isEmpty == false)
    }
    static func isEmail(_ s: String) -> Bool {
        s.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
    static func isJWT(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        guard let header = base64urlDecode(String(parts[0])),
              let obj = try? JSONSerialization.jsonObject(with: header) as? [String: Any]
        else { return false }
        return obj["alg"] != nil || obj["typ"] != nil
    }
    static func base64urlDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
    static func isWholePhone(_ s: String) -> Bool {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else { return false }
        let r = NSRange(s.startIndex..., in: s)
        guard let m = det.firstMatch(in: s, range: r) else { return false }
        return m.range == r
    }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextService.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(smarttext): analyze() type precedence classifier

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `SensitiveContentFilter` (Luhn + window-title + concealed)

**Files:** Create `Shared/Sources/Core/SmartText/SensitiveContentFilter.swift` · Test `Shared/Tests/CoreTests/SmartText/SensitiveContentFilterTests.swift`

- [ ] Failing tests:

```swift
@testable import Core
import XCTest

final class SensitiveContentFilterTests: XCTestCase {
    func testLuhnValidCard() {
        XCTAssertEqual(SensitiveContentFilter.shouldSkip(text: "4242 4242 4242 4242", windowTitle: nil, pasteboardTypes: []), .paymentCard)
    }
    func testRandom16DigitNotCard() {
        XCTAssertNil(SensitiveContentFilter.shouldSkip(text: "1234 5678 1234 5670".replacingOccurrences(of: "0", with: "3"), windowTitle: nil, pasteboardTypes: []))
    }
    func testPhoneNotCard() {
        XCTAssertNil(SensitiveContentFilter.shouldSkip(text: "+1 415 555 2671", windowTitle: nil, pasteboardTypes: []))
    }
    func testWindowTitleKeywordCaseInsensitive() {
        XCTAssertEqual(SensitiveContentFilter.shouldSkip(text: "hunter2", windowTitle: "1Password — Login", pasteboardTypes: []), .sensitiveWindow)
    }
    func testConcealedTypeShortCircuits() {
        XCTAssertEqual(SensitiveContentFilter.shouldSkip(text: "ok", windowTitle: nil, pasteboardTypes: ["org.nspasteboard.ConcealedType"]), .concealed)
    }
    func testCleanTextNotSkipped() {
        XCTAssertNil(SensitiveContentFilter.shouldSkip(text: "just some notes", windowTitle: "Notes", pasteboardTypes: []))
    }
}
```

- [ ] Run to fail: `... swift test --filter SensitiveContentFilterTests`.
- [ ] Implement:

```swift
import Foundation

public enum SkipReason: String, Equatable, Sendable { case paymentCard, sensitiveWindow, concealed }

public enum SensitiveContentFilter {
    static let titleKeywords = ["password","1password","keychain","bitwarden","lastpass",
                                "secret","private key","seed phrase","cvv","social security"]
    public static func shouldSkip(text: String, windowTitle: String?, pasteboardTypes: [String]) -> SkipReason? {
        if pasteboardTypes.contains("org.nspasteboard.ConcealedType") { return .concealed }
        if let t = windowTitle?.lowercased(), titleKeywords.contains(where: t.contains) { return .sensitiveWindow }
        if containsLuhnRun(text) { return .paymentCard }
        return nil
    }
    static func containsLuhnRun(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: "[ -]", with: "", options: .regularExpression)
        for match in stripped.ranges(of: #"\d{13,19}"#) {
            if luhnValid(String(stripped[match])) { return true }
        }
        return false
    }
    static func luhnValid(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count >= 13 else { return false }
        var sum = 0
        for (i, d) in nums.reversed().enumerated() {
            var v = d
            if i % 2 == 1 { v *= 2; if v > 9 { v -= 9 } }
            sum += v
        }
        return sum % 10 == 0
    }
}

private extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = NSRange(startIndex..., in: self)
        return re.matches(in: self, range: ns).compactMap { Range($0.range, in: self) }
    }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SensitiveContentFilter.swift Shared/Tests/CoreTests/SmartText/SensitiveContentFilterTests.swift
git commit -m "feat(smarttext): sensitive-data capture filter (Luhn + title)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: `ClipEmbeddingService` blob + cosine

**Files:** Create `Shared/Sources/Core/SmartText/ClipEmbeddingService.swift` · Test `Shared/Tests/CoreTests/SmartText/ClipEmbeddingServiceTests.swift`

- [ ] Failing tests (blob round-trip, cosine identity = 1, orthogonal ≈ 0; `NLEmbedding` call guarded/skipped when unavailable):

```swift
@testable import Core
import XCTest

final class ClipEmbeddingServiceTests: XCTestCase {
    func testBlobRoundTrip() {
        let v: [Float] = [0.1, -0.2, 0.33, 1.0]
        let data = ClipEmbeddingService.encode(v)
        XCTAssertEqual(ClipEmbeddingService.decode(data), v)
    }
    func testCosineIdentity() {
        XCTAssertEqual(ClipEmbeddingService.cosine([1, 0, 0], [1, 0, 0]), 1.0, accuracy: 1e-6)
    }
    func testCosineOrthogonal() {
        XCTAssertEqual(ClipEmbeddingService.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }
    func testCosineMismatchedLengthsZero() {
        XCTAssertEqual(ClipEmbeddingService.cosine([1, 0], [1]), 0.0, accuracy: 1e-6)
    }
}
```

- [ ] Run to fail: `... swift test --filter ClipEmbeddingServiceTests`.
- [ ] Implement (pure blob + cosine now; `vector(for:language:)` wraps `NLEmbedding`, returns nil when unavailable):

```swift
import Foundation
import NaturalLanguage

public enum ClipEmbeddingService {
    public static func encode(_ v: [Float]) -> Data {
        var le = v.map { $0.bitPattern.littleEndian }
        return Data(bytes: &le, count: le.count * MemoryLayout<UInt32>.size)
    }
    public static func decode(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<UInt32>.size == 0 else { return nil }
        return data.withUnsafeBytes { buf -> [Float] in
            buf.bindMemory(to: UInt32.self).map { Float(bitPattern: UInt32(littleEndian: $0)) }
        }
    }
    public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += Double(a[i]*b[i]); na += Double(a[i]*a[i]); nb += Double(b[i]*b[i]) }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
    public static func vector(for text: String, language: NLLanguage = .english) -> [Float]? {
        guard let emb = NLEmbedding.sentenceEmbedding(for: language),
              let v = emb.vector(for: text) else { return nil }
        return v.map(Float.init)
    }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/ClipEmbeddingService.swift Shared/Tests/CoreTests/SmartText/ClipEmbeddingServiceTests.swift
git commit -m "feat(smarttext): NLEmbedding wrapper + cosine + Float32 blob

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Semantic + lexical rank blend policy

**Files:** Create `Shared/Sources/Core/SmartText/SmartTextRankBlend.swift` · Test `Shared/Tests/CoreTests/SmartText/SmartTextRankBlendTests.swift`

- [ ] Failing tests (lexical-dominant; semantic breaks ties; NULL-embedding items keep lexical order):

```swift
@testable import Core
import XCTest

final class SmartTextRankBlendTests: XCTestCase {
    func testLexicalDominates() {
        // a strong lexical, b weak lexical but high semantic -> a still first.
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["a": 1.0, "b": 0.2],
            semanticScores: ["a": 0.1, "b": 0.99],
            weight: 0.3)
        XCTAssertEqual(order, ["a", "b"])
    }
    func testSemanticBreaksTie() {
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["a": 0.5, "b": 0.5],
            semanticScores: ["a": 0.1, "b": 0.9],
            weight: 0.3)
        XCTAssertEqual(order, ["b", "a"])
    }
    func testNilEmbeddingFallsBackToLexical() {
        let order = SmartTextRankBlend.blend(
            lexicalScores: ["a": 0.9, "b": 0.4],
            semanticScores: [:],
            weight: 0.3)
        XCTAssertEqual(order, ["a", "b"])
    }
}
```

- [ ] Run to fail: `... swift test --filter SmartTextRankBlendTests`.
- [ ] Implement:

```swift
import Foundation

public enum SmartTextRankBlend {
    /// Final score = lexical + weight * semantic (semantic defaults to 0 when absent).
    public static func blend(lexicalScores: [String: Double],
                             semanticScores: [String: Double],
                             weight: Double) -> [String] {
        lexicalScores.keys.sorted { l, r in
            let sl = lexicalScores[l]! + weight * (semanticScores[l] ?? 0)
            let sr = lexicalScores[r]! + weight * (semanticScores[r] ?? 0)
            if sl == sr { return l < r }
            return sl > sr
        }
    }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/SmartTextRankBlend.swift Shared/Tests/CoreTests/SmartText/SmartTextRankBlendTests.swift
git commit -m "feat(smarttext): lexical-dominant semantic rank blend

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: GRDB migration `008-smart-text` + columns

**Files:** Modify `Shared/Sources/Core/Storage/ClipboardStore.swift` (migrations `:67-115`) · Test `Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift`

- [ ] Failing test (columns + index exist; pre-existing rows readable):

```swift
@testable import Core
import GRDB
import XCTest

final class SmartTextMigrationTests: XCTestCase {
    func testMigration008AddsColumnsAndIndex() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SmartTextMig-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
        try db.queue.read { conn in
            let cols = try Row.fetchAll(conn, sql: "PRAGMA table_info(clipboard_records)").compactMap { $0["name"] as String? }
            XCTAssertTrue(cols.contains("detected_type"))
            XCTAssertTrue(cols.contains("ocr_text"))
            XCTAssertTrue(cols.contains("embedding"))
            let idx = try Row.fetchAll(conn, sql: "PRAGMA index_list(clipboard_records)").compactMap { $0["name"] as String? }
            XCTAssertTrue(idx.contains("idx_records_detected_type"))
        }
    }
}
```

- [ ] Run to fail: `... swift test --filter SmartTextMigrationTests`.
- [ ] Append migration to the `migrations` array (after `007`):

```swift
        ,Migration(identifier: "008-smart-text") { conn in
            try conn.execute(sql: """
                ALTER TABLE clipboard_records ADD COLUMN detected_type TEXT;
                ALTER TABLE clipboard_records ADD COLUMN ocr_text TEXT;
                ALTER TABLE clipboard_records ADD COLUMN embedding BLOB;
                CREATE INDEX IF NOT EXISTS idx_records_detected_type ON clipboard_records(detected_type);
            """)
        }
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/Storage/ClipboardStore.swift Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift
git commit -m "feat(storage): migration 008 adds smart-text columns

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: `ClipboardItemMeta` new fields + column projection

**Files:** Modify `Shared/Sources/Core/Models/ClipboardRecord.swift` (`:11`), `Shared/Sources/Core/Storage/ClipboardStore.swift` (SELECT lists `:177,:185,:196,:255,:264,:286,:288`, `metaRow` `:342`) · Test `Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift`

- [ ] Add failing test (projection round-trip via new write APIs):

```swift
func testMetaProjectsSmartTextColumns() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SmartTextMeta-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
    let store = try ClipboardStore(database: db, deviceKey: .init(size: .bits256), deviceID: .generate())
    let m = try store.append(.text("2+2"))
    try store.setDetectedType(id: m.id, json: #"{"type":{"plain":{}}}"#)
    try store.setOCRText(id: m.id, text: "hello")
    try store.setEmbedding(id: m.id, blob: ClipEmbeddingService.encode([0.1, 0.2]))
    let read = try store.list(limit: 1).first!
    XCTAssertEqual(read.ocrText, "hello")
    XCTAssertNotNil(read.detectedTypeJSON)
    XCTAssertEqual(ClipEmbeddingService.decode(read.embedding!), [0.1, 0.2])
}
```

- [ ] Run to fail: `... swift test --filter testMetaProjectsSmartTextColumns` → fails: no members/APIs.
- [ ] Add three optional fields to `ClipboardItemMeta` (+ init params defaulting nil): `detectedTypeJSON: String?`, `ocrText: String?`, `embedding: Data?`. Add `detected_type, ocr_text, embedding` to every `SELECT` column list. Extend `metaRow` to read them. Add the three write APIs mirroring `setCustomLabel`:

```swift
public func setDetectedType(id: RecordID, json: String?) throws {
    try db.queue.write { try $0.execute(sql: "UPDATE clipboard_records SET detected_type = ? WHERE id = ?", arguments: [json, id.rawValue]) }
}
public func setOCRText(id: RecordID, text: String?) throws {
    try db.queue.write { try $0.execute(sql: "UPDATE clipboard_records SET ocr_text = ? WHERE id = ?", arguments: [text, id.rawValue]) }
}
public func setEmbedding(id: RecordID, blob: Data?) throws {
    try db.queue.write { try $0.execute(sql: "UPDATE clipboard_records SET embedding = ? WHERE id = ?", arguments: [blob, id.rawValue]) }
}
```

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/Models/ClipboardRecord.swift Shared/Sources/Core/Storage/ClipboardStore.swift Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift
git commit -m "feat(storage): project + write smart-text columns

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: `append(detectedTypeJSON:)` + NULL-selection read helpers

**Files:** Modify `Shared/Sources/Core/Storage/ClipboardStore.swift` (`append` `:117`) · Test `Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift`

- [ ] Failing tests (`append` persists JSON; helpers select NULL rows):

```swift
func testAppendStoresDetectedTypeAndNullSelection() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SmartAppend-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try Database(url: dir.appendingPathComponent("c.sqlite"), migrations: ClipboardStore.migrations)
    let store = try ClipboardStore(database: db, deviceKey: .init(size: .bits256), deviceID: .generate())
    let m = try store.append(.text("x"), sourceAppBundleID: nil, detectedTypeJSON: #"{"type":{"plain":{}}}"#)
    XCTAssertNotNil(try store.list(limit: 1).first?.detectedTypeJSON)
    XCTAssertEqual(try store.idsMissingEmbedding(limit: 10), [m.id])
    try store.setEmbedding(id: m.id, blob: Data([0,0,0,0]))
    XCTAssertTrue(try store.idsMissingEmbedding(limit: 10).isEmpty)
}
```

- [ ] Run to fail: `... swift test --filter testAppendStoresDetectedTypeAndNullSelection`.
- [ ] Add `detectedTypeJSON: String? = nil` to `append`, write into a new column slot of the INSERT, and add helpers:

```swift
public func idsMissingEmbedding(limit: Int, modifiedOnOrAfter: Date? = nil) throws -> [RecordID] {
    try db.queue.read { conn in
        try Row.fetchAll(conn, sql: """
            SELECT id FROM clipboard_records WHERE embedding IS NULL ORDER BY modified DESC LIMIT ?
        """, arguments: [limit]).compactMap { RecordID(rawValue: $0["id"]) }
    }
}
public func idsMissingOCR(limit: Int) throws -> [RecordID] {
    try db.queue.read { conn in
        try Row.fetchAll(conn, sql: """
            SELECT id FROM clipboard_records WHERE kind = ? AND ocr_text IS NULL ORDER BY modified DESC LIMIT ?
        """, arguments: [RecordKind.clipboardItem.rawValue, limit]).compactMap { RecordID(rawValue: $0["id"]) }
    }
}
```

(Update the INSERT statement to include `detected_type` and its bound value.)

- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/Core/Storage/ClipboardStore.swift Shared/Tests/CoreTests/Storage/SmartTextMigrationTests.swift
git commit -m "feat(storage): append detected_type + NULL-selection helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: `FeatureID.clipboardSmartText`

**Files:** Modify `Shared/Sources/FeatureCore/FeatureID.swift` (`:3`) · Test `Shared/Tests/FeatureCoreTests/` (new `FeatureIDTests.swift` if none — otherwise extend existing)

- [ ] Failing test:

```swift
@testable import FeatureCore
import XCTest

final class FeatureIDSmartTextTests: XCTestCase {
    func testClipboardSmartTextCaseExists() {
        XCTAssertEqual(FeatureID(rawValue: "clipboardSmartText"), .clipboardSmartText)
        XCTAssertTrue(FeatureID.allCases.contains(.clipboardSmartText))
    }
}
```

- [ ] Run to fail: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test --filter FeatureIDSmartTextTests`.
- [ ] Add `case clipboardSmartText` to the enum.
- [ ] Run to pass.
- [ ] Commit:

```
git add Shared/Sources/FeatureCore/FeatureID.swift Shared/Tests/FeatureCoreTests/FeatureIDSmartTextTests.swift
git commit -m "feat(feature-core): add clipboardSmartText feature id

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: `SmartSearchQuery` parser (slash operators + negation)

**Files:** Create `MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift` · Test `MacAllYouNeedTests/ClipboardDock/SmartSearchQueryTests.swift`

- [ ] Failing tests (parse `/app:`, `/type:`, `/date:` today/Nd/YYYY-MM, negation, repeated-operator OR, free-text remainder):

```swift
@testable import MacAllYouNeed
import XCTest

final class SmartSearchQueryTests: XCTestCase {
    func testParsesAppOperatorAndFreeText() {
        let q = SmartSearchQuery(raw: "/app:Safari hello world")
        XCTAssertEqual(q.appFilters, ["safari"])
        XCTAssertEqual(q.freeText, "hello world")
    }
    func testNegation() {
        let q = SmartSearchQuery(raw: "-/app:Slack foo")
        XCTAssertEqual(q.negatedApps, ["slack"])
        XCTAssertEqual(q.freeText, "foo")
    }
    func testRepeatedTypeIsOr() {
        let q = SmartSearchQuery(raw: "/type:url /type:email")
        XCTAssertEqual(Set(q.typeFilters), ["url", "email"])
    }
    func testDateToday() {
        let q = SmartSearchQuery(raw: "/date:today")
        XCTAssertNotNil(q.dateOnOrAfter)
    }
    func testDate7d() {
        let q = SmartSearchQuery(raw: "/date:7d")
        XCTAssertNotNil(q.dateOnOrAfter)
    }
    func testLiteralSlashIsFreeText() {
        let q = SmartSearchQuery(raw: "a/b path")
        XCTAssertEqual(q.freeText, "a/b path")
        XCTAssertTrue(q.appFilters.isEmpty)
    }
}
```

- [ ] Run to fail: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' -only-testing:MacAllYouNeedTests/SmartSearchQueryTests` → compile/assert failure.
- [ ] Implement pure value type. Strict grammar `^-?/(app|type|date):` per token; everything else is free text. Parse `/date:` to a `Date?` (today = start of day; `Nd` = N days ago; `YYYY-MM` = month start; `YYYY-MM-DD` exact). Regex fields (`isRegex`, `regexPattern`) added in Task 14.
- [ ] Run to pass.
- [ ] Commit:

```
git add MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift MacAllYouNeedTests/ClipboardDock/SmartSearchQueryTests.swift
git commit -m "feat(search): SmartSearchQuery slash-operator parser

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 14: `SmartSearchQuery` regex delimiters + invalid fallback

**Files:** Modify `MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift` · Test `SmartSearchQueryTests.swift`

- [ ] Failing tests:

```swift
func testRegexDelimiters() {
    let q = SmartSearchQuery(raw: "/foo.*bar/")
    XCTAssertTrue(q.isRegex)
    XCTAssertEqual(q.regexPattern, "foo.*bar")
    XCTAssertNotNil(q.compiledRegex)
}
func testInvalidRegexFallsBackLiteral() {
    let q = SmartSearchQuery(raw: "/[unterminated/")
    XCTAssertTrue(q.isRegex)
    XCTAssertNil(q.compiledRegex)        // invalid -> graceful nil
    XCTAssertEqual(q.freeText, "[unterminated") // literal fallback text
}
func testMatchesPreviewOrOCR() {
    let q = SmartSearchQuery(raw: "/cat/")
    XCTAssertTrue(q.matchesText("a cat sat", ocrText: nil))
    XCTAssertTrue(q.matchesText("dog", ocrText: "a cat"))
    XCTAssertFalse(q.matchesText("dog", ocrText: nil))
}
```

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/SmartSearchQueryTests`.
- [ ] Add: detect `^/.../$` wrapping → `isRegex = true`, `regexPattern`, compile with length cap; expose `compiledRegex: NSRegularExpression?` (nil on failure), `matchesText(_:ocrText:)` matching pattern (or literal contains when compile failed) against preview + optional OCR text.
- [ ] Run to pass.
- [ ] Commit:

```
git add MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift MacAllYouNeedTests/ClipboardDock/SmartSearchQueryTests.swift
git commit -m "feat(search): regex delimiters with literal fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 15: `ImageOCRService` Vision wrapper (testable seam)

**Files:** Create `MacAllYouNeed/ClipboardDock/Services/ImageOCRService.swift` · Test `MacAllYouNeedTests/ClipboardDock/ImageOCRServiceTests.swift`

- [ ] Failing tests using an offscreen-rendered PNG with known text + an empty image (manual verification noted for live capture):

```swift
@testable import MacAllYouNeed
import AppKit
import XCTest

final class ImageOCRServiceTests: XCTestCase {
    func testRecognizesRenderedText() async throws {
        let cg = TestImageFactory.cgImage(text: "INVOICE 42", size: .init(width: 400, height: 120))
        let result = await ImageOCRService.shared.recognize(cgImage: cg)
        XCTAssertTrue((result ?? "").uppercased().contains("INVOICE"))
    }
    func testEmptyImageReturnsNilOrEmpty() async throws {
        let cg = TestImageFactory.solid(.white, size: .init(width: 64, height: 64))
        let result = await ImageOCRService.shared.recognize(cgImage: cg)
        XCTAssertTrue((result ?? "").isEmpty)
    }
    func testDownsampleCapApplied() {
        XCTAssertEqual(ImageOCRService.downsampledMaxDimension(forLongestSide: 16384), 8192)
        XCTAssertEqual(ImageOCRService.downsampledMaxDimension(forLongestSide: 4000), 4000)
    }
}
```

(Add `TestImageFactory` helper in the test target rendering text via `NSAttributedString` into an `NSImage` → `CGImage`.)

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/ImageOCRServiceTests`.
- [ ] Implement actor with `recognize(cgImage:) async -> String?` (VNRecognizeTextRequest, `.accurate`, `usesLanguageCorrection`, automatic languages), 5 s timeout, single-flight cache keyed by image, bounded pool (2), pure `downsampledMaxDimension(forLongestSide:)`. **Manual verification:** copy a screenshot with text into the app with the feature on; confirm the card shows "Text found" and the OCR text becomes searchable.
- [ ] Run to pass.
- [ ] Commit:

```
git add MacAllYouNeed/ClipboardDock/Services/ImageOCRService.swift MacAllYouNeedTests/ClipboardDock/ImageOCRServiceTests.swift
git commit -m "feat(ocr): Vision OCR service with downsample + bounds

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 16: Daemon hot path — sensitive filter + auto-clean + detected_type

**Files:** Modify `ClipboardDaemon/DaemonContainer.swift` (`persist` `:80`, append sites `:95-121`) · Test (seam) `Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift` (logic already covered) + manual

- [ ] The branching logic is already unit-tested (Tasks 2–6). Add one seam test asserting the daemon's capture decision helper composes filter + detection. Create a pure helper in Core so it is testable without the daemon:

  Create `Shared/Sources/Core/SmartText/CaptureDecision.swift` with:

```swift
import Foundation

public enum CaptureDecision: Equatable, Sendable {
    case skip(SkipReason)
    case keep(detectedTypeJSON: String, autoCleanedText: String?)
}

public enum SmartCapturePolicy {
    public static func decideText(_ text: String, windowTitle: String?, pasteboardTypes: [String],
                                  sensitiveEnabled: Bool, autoCleanLinks: Bool) -> CaptureDecision {
        if sensitiveEnabled, let reason = SensitiveContentFilter.shouldSkip(
            text: text, windowTitle: windowTitle, pasteboardTypes: pasteboardTypes) {
            return .skip(reason)
        }
        let detection = SmartTextService.analyze(text: text)
        let json = (try? detection.encodedJSON()) ?? #"{"type":{"plain":{}}}"#
        let cleaned = (autoCleanLinks && detection.type == .url) ? detection.linkClean?.cleaned : nil
        return .keep(detectedTypeJSON: json, autoCleanedText: cleaned)
    }
}
```

  Failing test:

```swift
func testCapturePolicySkipsSensitive() {
    let d = SmartCapturePolicy.decideText("4242 4242 4242 4242", windowTitle: nil, pasteboardTypes: [],
                                          sensitiveEnabled: true, autoCleanLinks: false)
    XCTAssertEqual(d, .skip(.paymentCard))
}
func testCapturePolicyAutoCleans() {
    let d = SmartCapturePolicy.decideText("https://x.com/?utm_source=a", windowTitle: nil, pasteboardTypes: [],
                                          sensitiveEnabled: false, autoCleanLinks: true)
    if case let .keep(_, cleaned) = d { XCTAssertEqual(cleaned, "https://x.com/") } else { XCTFail() }
}
```

- [ ] Run to fail: `... swift test --filter testCapturePolicy`.
- [ ] Implement `CaptureDecision.swift`. Then wire `DaemonContainer.persist` text/rtf/html branches: read `sensitiveEnabled`/`linkMode` from `AppGroupSettings.defaults`, read frontmost window title from the daemon's existing source context, call `SmartCapturePolicy.decideText`, `return` on `.skip` (increment skip counter), pass `detectedTypeJSON` into `clip.append`, and substitute `autoCleanedText` when present.
- [ ] Run to pass (Core test) + build daemon: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`. **Manual verification:** copy a Luhn card number while feature on → no record; copy a UTM URL in auto mode → stored URL is cleaned.
- [ ] Commit:

```
git add Shared/Sources/Core/SmartText/CaptureDecision.swift ClipboardDaemon/DaemonContainer.swift Shared/Tests/CoreTests/SmartText/SmartTextServiceTests.swift
git commit -m "feat(capture): sensitive filter + auto-clean + detected_type inline

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 17: `ClipboardEnrichmentCoordinator` (deferred OCR + embeddings)

**Files:** Create `MacAllYouNeed/App/Coordinators/ClipboardEnrichmentCoordinator.swift` · Test `MacAllYouNeedTests/App/ClipboardEnrichmentCoordinatorTests.swift`

- [ ] Failing test against an in-memory store: seed a text record with NULL embedding, run one enrichment batch with an injected embedding provider, assert the embedding column is now populated and OCR is upserted to FTS for image rows:

```swift
@testable import MacAllYouNeed
@testable import Core
import XCTest

final class ClipboardEnrichmentCoordinatorTests: XCTestCase {
    func testBackfillsMissingEmbedding() async throws {
        let (store, search) = try makeStores()
        let m = try store.append(.text("hello world"))
        let coord = ClipboardEnrichmentCoordinator(
            clip: store, search: search,
            embed: { _ in [0.1, 0.2, 0.3] },     // injected stub
            ocr: { _ in nil })
        await coord.runOneBatch(limit: 10)
        XCTAssertNotNil(try store.list(limit: 1).first?.embedding)
        _ = m
    }
}
```

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/ClipboardEnrichmentCoordinatorTests`.
- [ ] Implement `@MainActor` coordinator with injectable `embed`/`ocr` closures (default to `ClipEmbeddingService.vector` / `ImageOCRService.shared.recognize`). `runOneBatch(limit:)`: select `idsMissingEmbedding`/`idsMissingOCR` (retention-scoped), compute off-actor, write via `setEmbedding`/`setOCRText`, `search.upsert` OCR text, post `clipboardStoreDidChange`. `start()` subscribes to `clipboardStoreDidChange` + a coalesced timer; gated on `FeatureID.clipboardSmartText` enabled. Idempotent (NULL-selection), resumable across launches, batched with `Task.yield()`.
- [ ] Run to pass.
- [ ] Commit:

```
git add MacAllYouNeed/App/Coordinators/ClipboardEnrichmentCoordinator.swift MacAllYouNeedTests/App/ClipboardEnrichmentCoordinatorTests.swift
git commit -m "feat(enrichment): deferred OCR + embedding backfill coordinator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 18: Wire `SmartSearchQuery` into dock ranking (predicates + semantic blend)

**Files:** Modify `MacAllYouNeed/ClipboardDock/Model/SubModels/SearchFilterSubModel.swift` (`loadHistoryLocally` `:155`, `filteredAndRanked` `:303`, `xpcMeta` `:264`) · Test `MacAllYouNeedTests/ClipboardDock/SearchFilterRankingTests.swift`

- [ ] Failing test for predicate filtering + blend using a small `DockItem` fixture set with stub embeddings (deterministic, no `NLEmbedding`):

```swift
@testable import MacAllYouNeed
import XCTest

final class SearchFilterRankingTests: XCTestCase {
    func testTypeOperatorFilters() {
        let items = [stubItem(id: "1", type: "url"), stubItem(id: "2", type: "email")]
        let out = SearchFilterSubModel.applySmartPredicates(items, query: SmartSearchQuery(raw: "/type:url"))
        XCTAssertEqual(out.map(\.id), ["1"])
    }
    func testRegexFiltersOnPreviewAndOCR() {
        let items = [stubItem(id: "1", preview: "cat"), stubItem(id: "2", preview: "dog", ocr: "cat photo")]
        let out = SearchFilterSubModel.applySmartPredicates(items, query: SmartSearchQuery(raw: "/cat/"))
        XCTAssertEqual(Set(out.map(\.id)), ["1", "2"])
    }
}
```

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/SearchFilterRankingTests`.
- [ ] Add a `nonisolated static func applySmartPredicates(_:query:)` that filters by app/type/date/negation/regex (using `DockItem`'s new `detectedTypeJSON`/`ocrText` carried via `ClipboardXPCMeta` — extend `xpcMeta` to copy them). In `loadHistoryLocally`, loosen the substring pre-filter when the parsed query has operators/regex/semantic so matches aren't lost. In `filteredAndRanked`, after the existing fuzzy/contains pass, when semantic mode is on (`AppGroupSettings` `search.semantic`) and free text is present, compute query embedding once, cosine-score the candidate window, and reorder via `SmartTextRankBlend.blend`. Items without an embedding keep their lexical position.
- [ ] Run to pass + full app build.
- [ ] Commit:

```
git add MacAllYouNeed/ClipboardDock/Model/SubModels/SearchFilterSubModel.swift MacAllYouNeedTests/ClipboardDock/SearchFilterRankingTests.swift
git commit -m "feat(search): slash/regex predicates + semantic blend in dock

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 19: Popover search parity + `DockItem` affordance mapping

**Files:** Modify `MacAllYouNeed/App/LocalClipboardReader.swift` (`:144`), `MacAllYouNeed/ClipboardDock/Model/DockItem.swift` (`:5`) · Test `MacAllYouNeedTests/ClipboardDock/DockItemSmartTextTests.swift`

- [ ] Failing test (DockItem maps detected_type JSON → kind + affordance flags):

```swift
@testable import MacAllYouNeed
import XCTest

final class DockItemSmartTextTests: XCTestCase {
    func testCalculationAffordance() {
        let item = makeDockItem(preview: "2+2", detectedTypeJSON: #"{"type":{"plain":{}},"calculation":{"expression":"2+2","value":"4"}}"#)
        XCTAssertEqual(item.calculation?.value, "4")
    }
    func testTrackerBadgeFromLinkClean() {
        let json = #"{"type":{"url":{}},"linkClean":{"cleaned":"https://x.com/","removedCount":2,"original":"https://x.com/?utm_source=a&fbclid=z"}}"#
        let item = makeDockItem(preview: "https://x.com/?utm_source=a&fbclid=z", detectedTypeJSON: json)
        XCTAssertEqual(item.trackerCount, 2)
    }
    func testOCRFlag() {
        let item = makeDockItem(preview: "(image 10×10)", ocrText: "hello")
        XCTAssertTrue(item.hasOCRText)
    }
}
```

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/DockItemSmartTextTests`.
- [ ] Decode `detectedTypeJSON` in `DockItem.init` into `calculation: CalculationResult?`, `trackerCount: Int`, `hasOCRText: Bool`, and map `DetectedType` onto `DockItemKind` (preferring the stored detection over `PreviewDetection` when present). Apply the same `SmartSearchQuery` parse + `applySmartPredicates` to `LocalClipboardReader`'s popover filter.
- [ ] Run to pass + app build.
- [ ] Commit:

```
git add MacAllYouNeed/App/LocalClipboardReader.swift MacAllYouNeed/ClipboardDock/Model/DockItem.swift MacAllYouNeedTests/ClipboardDock/DockItemSmartTextTests.swift
git commit -m "feat(dock): map detected_type to affordances + popover parity

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 20: Card affordances (calculation row, tracker badge, type actions)

**Files:** Modify `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift`, `LinkCard.swift`, `CardContextMenu.swift` · Test: manual (SwiftUI views) + reuse Task 19 unit coverage

- [ ] No new logic test (logic is in `DockItem`/`SmartTextService`, already covered). Add a `#Preview` for the calculation row and tracker badge to enable visual checks.
- [ ] Implement using design-system primitives only: calculation result row in `TextCard` (`= 14` in `MAYNTheme` secondary label + compact `MAYNButton .secondary` "Copy result"), `StatusPill` "N trackers" + primary `Clean link` in `LinkCard`, `StatusPill` "Text found" for OCR. Context-menu entries in `CardContextMenu`: email → Compose (mailto), phone → Call / Copy digits, JWT → Decode (Quick Look overlay, read-only), image → Copy recognized text, auto-cleaned link → Restore original. All actions route through `applyTransform(_, saveAsNew: true)` so the original is never mutated. No ad-hoc colors / durations / raw segmented pickers.
- [ ] Build: `xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'`. **Manual verification:** copy `2+3*4`, a UTM URL, an email, a JWT, and an OCR-bearing image; confirm each card shows the documented affordance and that acting persists a new clip.
- [ ] Commit:

```
git add MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift MacAllYouNeed/ClipboardDock/Views/Cards/LinkCard.swift MacAllYouNeed/ClipboardDock/Views/Cards/CardContextMenu.swift
git commit -m "feat(cards): smart-text affordances via MAYN design system

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 21: Feature descriptor + settings view + wiring

**Files:** Create `MacAllYouNeed/App/Descriptors/ClipboardSmartTextDescriptor.swift`, `MacAllYouNeed/Settings/ClipboardSmartTextSettingsView.swift` · Modify the descriptor-registration site · Test `MacAllYouNeedTests/App/ClipboardSmartTextDescriptorTests.swift`

- [ ] Failing test (descriptor identity + no permissions):

```swift
@testable import MacAllYouNeed
@testable import FeatureCore
import XCTest

final class ClipboardSmartTextDescriptorTests: XCTestCase {
    func testDescriptorBasics() {
        let d = ClipboardSmartTextDescriptor()
        XCTAssertEqual(d.id, .clipboardSmartText)
        XCTAssertTrue(d.requiredPermissions.isEmpty)
    }
}
```

- [ ] Run to fail: `... -only-testing:MacAllYouNeedTests/App/ClipboardSmartTextDescriptorTests`.
- [ ] Implement the descriptor mirroring `ClipboardDescriptor` (off by default, `requiredPermissions: []`, activator starts/stops `ClipboardEnrichmentCoordinator`). Register it where the others are registered. Build `ClipboardSmartTextSettingsView` with `MAYNSettingsPage`/`MAYNSection`/`MAYNSettingsRow`/`MAYNDivider`: inline calc on/off; link cleaner `FunctionSegmentedTabStrip` Off/Manual/Auto-apply; smart detection on/off; OCR on/off + "indexed N images"; sensitive filter on/off (default on) + "skipped N today"; semantic ranking on/off; regex-by-default on/off. All persisted in `AppGroupSettings.defaults`.
- [ ] Run to pass + app build. **Manual verification:** toggle each setting; confirm daemon (sensitive/auto-clean) and main app (OCR/semantic) honor the keys.
- [ ] Commit:

```
git add MacAllYouNeed/App/Descriptors/ClipboardSmartTextDescriptor.swift MacAllYouNeed/Settings/ClipboardSmartTextSettingsView.swift MacAllYouNeedTests/App/ClipboardSmartTextDescriptorTests.swift
git commit -m "feat(feature): clipboard smart-text descriptor + settings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 22: Full suite + lint gate

**Files:** none (verification)

- [ ] Run Shared tests: `cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test` → all green.
- [ ] Run app tests: `xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64'` → all green.
- [ ] Run `./scripts/ci-build.sh` (swiftlint `--strict` + swiftformat + tests + app build) → passes; confirm no `Color(red:…)`, `.pickerStyle(.segmented)`, or raw animation duration was introduced.
- [ ] Commit (only if formatting changes): `git commit -am "chore(smarttext): lint/format pass\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

## Self-Review

Every spec capability maps to a task:

- **§3.1 Inline calculation** → Task 2 (evaluator, guardrails, phone/date/bare-number rejection) + Task 19 (affordance flag) + Task 20 (result row, Copy result / Replace).
- **§3.2 Link cleaner** → Task 3 (tracking table, prefix, order, empty-query collapse, multi-line guard) + Task 16 (auto-apply at capture) + Task 20 (manual Clean link / Restore original badge).
- **§3.3 Smart text detection** → Task 4 (code-language, markdown→plain) + Task 5 (color>url>email>jwt>phone>code>plain precedence, JWT header decode) + Task 19 (kind mapping) + Task 20 (type-aware actions).
- **§3.4 Background OCR (Vision)** → Task 15 (Vision wrapper, downsample, timeout, single-flight, pool) + Task 17 (deferred backfill + FTS upsert) + Task 19/20 (Text found / Copy recognized text).
- **§3.5 Sensitive-data filtering (Luhn + window title)** → Task 6 (Luhn, title keywords, concealed) + Task 16 (skip-at-capture wiring + counter) + Task 21 (toggle + skipped-N).
- **§3.6 Regex + slash search filters** → Task 13 (slash operators, negation, OR, date) + Task 14 (regex delimiters, invalid fallback, preview+OCR match) + Task 18 (predicate application) + Task 19 (popover parity) + Task 21 (regex-by-default toggle).
- **§3.7 On-device semantic search (NLEmbedding)** → Task 7 (embedding wrapper, cosine, blob) + Task 8 (blend policy) + Task 17 (embedding backfill) + Task 18 (query-time blend over bounded window) + Task 21 (semantic toggle).
- **§5 Storage (migration + columns)** → Task 9 (migration 008, `detected_type`/`ocr_text`/`embedding`, index) + Task 10 (meta projection + write APIs) + Task 11 (`append(detectedTypeJSON:)` + NULL-selection helpers).
- **§7 No new permissions** → Task 21 (`requiredPermissions: []`).
- **§2 Gated / reversible** → Task 12 (`FeatureID.clipboardSmartText`) + Task 21 (descriptor off by default; enrichment gated).
- **§8 Design-system UI** → Tasks 20–21 use only `MAYNTheme`/`MAYNControlMetrics`/`MAYNMotion`, `FunctionSegmentedTabStrip`, `StatusPill`, `MAYNButton`, `MAYN*` settings primitives; Task 22 enforces via `swiftlint --strict`.

Pure logic (calculation, Luhn, link cleaner, detection, slash/regex parsing, cosine, blend, capture policy) is unit-tested in Shared/Core; Vision/OCR and SwiftUI cards carry thin testable seams plus the noted manual verification. No spec capability is unmapped.
