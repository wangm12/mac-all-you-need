# Clipboard Smart Text — Design Spec

Status: Draft
Owner: mingjie-father
Last updated: 2026-05-30
Feature flag: `FeatureID.clipboardSmartText` (new, gated via existing FeatureRuntime)

---

## 1. Summary

Clipboard Smart Text is a *smart layer* over MAYN's existing clipboard manager.
It does not replace capture, storage, search, or the dock — it observes the same
records and enriches them with cheap, fully on-device intelligence:

- inline calculation of copied math expressions,
- tracking-parameter cleaning for copied URLs,
- type classification (email / URL / phone / JWT / color / code-language) that
  drives type-aware card actions,
- background Vision OCR on copied images, indexed into the existing FTS5 store so
  screenshots become searchable,
- sensitive-data filtering at capture (Luhn + sensitive frontmost window title)
  so cards/IDs are never recorded,
- regex and slash-operator search filters (`/app:`, `/type:`, `/date:`),
- on-device semantic search via Apple `NLEmbedding`, layered over the current
  FTS5 + `FuzzyMatcher` ranking.

The feature is additive and reversible. With the flag off, capture, storage, the
dock, and search behave exactly as they do today. The reference project
`reference-projects/Deck-main` informs the surface area (its `ClipboardItem`
model already carries `itemType`, `ocrTextForImage`, and a `SmartTextService.*`
result surface), but MAYN's architecture — daemon capture, encrypted GRDB store,
XPC-free local reads — is the source of truth.

A naming note: the reference's `Deck/Services/SmartTextService.swift` is *not*
present in the checkout (only `TextTransformer.swift` and `SecurityService.swift`
ship). `ClipboardItem.swift` references `SmartTextService.DetectionResult`,
`.CodeLanguage`, and `.CalculationResult` as the intended shape. We design
`SmartTextService` fresh for MAYN rather than porting.

---

## 2. Goals / Non-goals

### Goals

- Detect and surface results without changing the user's clipboard unless they
  explicitly act (copy result, paste cleaned URL, etc.).
- Keep every enrichment on-device with **no new permissions** and **no model
  download**. `NLEmbedding` ships with macOS; Vision OCR ships with macOS.
- Preserve current capture latency. Heavy work (OCR, embeddings) is deferred and
  runs off the capture hot path.
- Layer cleanly on the existing pipeline: daemon append → `ClipboardStore` →
  `LocalClipboardReader` / dock `SearchFilterSubModel` → cards.
- Ship as a single gated `FeatureDescriptor`; off by default for existing users,
  opt-in via onboarding/dashboard.

### Non-goals

- **AI chat over clips.** No LLM conversation surface over history.
- **JS / script plugin engine.** The reference's `ScriptPluginService` is
  explicitly out of scope.
- **LAN / Multipeer sync.** The reference's `LANFileArchiver` and
  `receivedFromLAN` paths are out of scope (Plan 2 remains skipped).
- Cloud anything: no remote OCR, no remote embeddings, no remote classification.
- Rewriting transforms — Smart Text composes with the existing `TextTransform`
  menu, it does not subsume it.

---

## 3. Full feature scope

All capabilities below share one classification pass (`SmartTextService.analyze`)
computed once per record and cached. They are individually toggleable in
settings; each toggle gates only its own behavior.

### 3.1 Inline calculation

- On text records whose trimmed body matches an arithmetic grammar
  (`+ - * / % ^`, parentheses, decimals, leading/trailing whitespace, optional
  thousands separators), compute the result with a bounded expression evaluator
  (`NSExpression` with a safelist of operators; reject identifiers/selectors).
- Surface as a non-destructive **calculation result row** on the text card:
  `2+3*4 = 14`. Actions: *Copy result* (writes `14` to the clipboard via the
  existing paste/copy path), *Replace clip text* (saves a new record, never
  mutates the original — mirrors `applyTransform(saveAsNew: true)`).
- Guardrails: max input length 256 chars; division-by-zero and overflow yield no
  row (silent); must contain at least one operator and one digit on each side to
  avoid treating a bare number or a phone number as math.
- Result is cached on the record's `detectedType` payload, not recomputed per
  render.

### 3.2 Link cleaner

- On URL records, strip known tracking params: `utm_*` (prefix match),
  `fbclid`, `gclid`, `gclsrc`, `dclid`, `msclkid`, `mc_eid`, `mc_cid`,
  `igshid`, `si` (YouTube/Spotify share token), `ref`, `ref_src`, `_hsenc`,
  `_hsmi`, `vero_id`, `oly_enc_id`, `oly_anon_id`, `yclid`, `twclid`,
  `wickedid`, `_openstat`. List lives in one `static let trackingParameters`
  table so it is reviewable and testable.
- Preserve fragment and path; only the query is filtered. Empty query after
  filtering drops the `?`.
- Two modes (settings):
  - **Manual** (default): card shows a *Clean link* action and a small "N
    trackers" badge; clicking copies/pastes the cleaned URL as a new clip.
  - **Auto-apply**: at capture, if cleaning changes the URL, the *stored* record
    is the cleaned URL and the original is discarded. A one-line provenance note
    is kept in the `detectedType` payload (`cleanedFrom: <original>`), so the
    card can offer *Restore original*.
- Auto-apply is conservative: only triggers when the input parses as a single
  absolute `http(s)` URL with a host. Multi-line text containing a URL is left
  alone in auto mode (still offered in manual mode).

### 3.3 Smart text detection

- One classifier produces a `DetectedType` for every text record:
  `email`, `url`, `phone`, `jwt`, `color`, `code(language:)`, or `plain`.
- Detection order (first match wins, mirrors the reference's
  `detectItemType` precedence where color/url beat code):
  1. `color` — hex `#RGB/#RGBA/#RRGGBB/#RRGGBBAA`, `rgb()/rgba()`, `hsl()`.
  2. `url` — single absolute http(s) URL with host.
  3. `email` — single RFC-5322-lite address, whole-string.
  4. `jwt` — three base64url segments separated by `.`, header decodes to JSON
     with `alg`/`typ`.
  5. `phone` — `NSDataDetector` `.phoneNumber` covering the whole trimmed string.
  6. `code(language:)` — lightweight heuristic + `NLLanguageRecognizer` is *not*
     used here; use a keyword/sigil heuristic (braces density, `def`/`func`/
     `import`/`SELECT`/`<tag>`/`#include`) producing a coarse language label.
     Markdown is classified as `plain` (matches reference: markdown is not code).
  7. else `plain`.
- The detected type drives **type-aware card actions** (see §8) and is stored so
  the dock and search can filter on it without re-analyzing.
- Multi-value text (e.g. a paragraph that merely *contains* an email) is
  `plain`; detection is whole-string to avoid noisy badges. (A future "entities
  in selection" mode is out of scope.)

### 3.4 Background OCR on copied images

- For image records, run Vision `VNRecognizeTextRequest`
  (`.accurate`, `usesLanguageCorrection = true`, automatic language detection)
  on the decrypted blob, **off the capture hot path** on a utility queue.
- Store extracted text in the new `ocr_text` column (encrypted at rest via the
  same envelope path is not required — see §5 decision) and **upsert it into the
  existing FTS5 `search_index`** (`SearchStore.upsert(kind:id:text:)`) so images
  match text queries. The card shows a small "Text found" affordance and a
  *Copy recognized text* action when `ocr_text` is non-empty.
- Bounds: skip blobs above a pixel cap (e.g. 8192 px max dimension is
  downsampled first), 5 s per-request timeout, single-flight per record, and a
  bounded concurrent OCR pool (2). Failures leave `ocr_text` NULL and are not
  retried within the session.
- OCR runs for both pasteboard images and fileURL-image records, reusing the
  same blob/thumbnail decode path the dock already uses
  (`ImageBlobLoader` / `BlobStore`).

### 3.5 Sensitive-data filtering at capture

- Before a text record is appended, run a **sensitivity check**:
  - **Luhn** validation on digit runs of length 13–19 (after stripping spaces
    and dashes) → likely a payment-card / ID number.
  - **Sensitive frontmost window title** check: the daemon already records the
    source app; extend the snapshot with the frontmost window title (available
    via the daemon's existing AX/`NSWorkspace` context) and match against a
    case-insensitive keyword set (`password`, `1password`, `keychain`,
    `bitwarden`, `lastpass`, `secret`, `private key`, `seed phrase`, `cvv`,
    `social security`). Title matching is best-effort; absence of a title never
    blocks capture.
- On a positive check → **skip capture entirely** (no record, no blob, no FTS
  row). This is the privacy-preserving default. A short structured log line
  (no content) records the skip reason for diagnostics.
- Respects existing pasteboard signals already understood elsewhere in the
  stack: records carrying the concealed marker (`org.nspasteboard.ConcealedType`)
  are skipped regardless of the toggle.
- Settings: master toggle (default ON when feature is enabled), plus a
  "skipped N sensitive items today" read-only counter. No allow-list in v1.

### 3.6 Regex + slash search filters

- Extend the dock search box parser with two layered capabilities:
  - **Slash operators**: tokens of the form `/app:Safari`, `/type:code`,
    `/date:today` (also `/date:7d`, `/date:2026-05`), and negation with a
    leading `-` (`-/app:Slack`). Operators are stripped from the free-text query
    and converted to predicates over existing metadata
    (`source_app`, new `detected_type`, `modified`). Free text after operators
    still feeds FTS/fuzzy/semantic ranking.
  - **Regex search**: when the query is wrapped in `/.../ ` (slashes) or a
    settings "Regex mode" toggle is on, treat the free-text portion as an
    `NSRegularExpression` matched against `preview` (and `ocr_text` when present).
    Invalid regex degrades gracefully to literal contains (no crash, subtle
    "invalid pattern" hint).
- Operators compose (AND across operators, OR within a repeated operator:
  `/type:url /type:email` matches either type).
- Parsing lives in a new `SmartSearchQuery` value type so it is unit-testable in
  isolation from the dock.

### 3.7 On-device semantic search

- At capture (deferred, like OCR), compute a sentence embedding for the record's
  searchable text using `NLEmbedding.sentenceEmbedding(for:)` for the detected
  language (fallback English). Store the vector as a `Float32` blob in the new
  `embedding` column.
- At query time, when the query has ≥ 1 free-text token and semantic mode is on,
  embed the query once and **cosine-rank** candidates whose embeddings exist.
  Semantic score is *blended* with the existing ranking rather than replacing it:
  1. FTS5 / slash-operator predicates select the candidate set (as today).
  2. `FuzzyMatcher` and substring give the lexical score (as today).
  3. Semantic cosine gives a separate score in `[0,1]`.
  4. Final order = weighted sum (lexical-dominant by default; semantic breaks
     ties and rescues "no lexical overlap but related" items). Weight is a fixed
     constant in v1, not user-tunable.
- Embeddings are never required: records without an embedding (older items,
  embedding failures, languages without an `NLEmbedding`) fall back to pure
  lexical ranking. No model download, no network.
- Bounds: only the bounded candidate window already loaded by the dock
  (`limit` 200) is cosine-scored; we do not scan the whole DB.

---

## 4. Architecture & components

New types (Swift), with intended home:

| Type | Location | Responsibility |
|---|---|---|
| `SmartTextService` | `Shared/Sources/Core/SmartText/SmartTextService.swift` | Pure, `Sendable`, no AppKit. `analyze(text:) -> Detection`, `calculate(_:) -> CalculationResult?`, `cleanLink(_:) -> LinkCleanResult?`, `detectCodeLanguage(in:)`. All regex tables live here. |
| `SmartText.Detection` / `.DetectedType` / `.CalculationResult` / `.LinkCleanResult` / `.CodeLanguage` | same file | Value results, `Codable` for the `detected_type` JSON payload. |
| `SensitiveContentFilter` | `Shared/Sources/Core/SmartText/SensitiveContentFilter.swift` | `shouldSkip(text:windowTitle:pasteboardTypes:) -> SkipReason?`. Luhn + keyword sets. Pure/testable. |
| `ImageOCRService` | `MacAllYouNeed/ClipboardDock/Services/ImageOCRService.swift` | Vision wrapper (AppKit/Vision), bounded pool, single-flight, downsample. Main-app side (daemon stays lean). |
| `ClipEmbeddingService` | `Shared/Sources/Core/SmartText/ClipEmbeddingService.swift` | `NLEmbedding` wrap: `vector(for:language:) -> [Float]?`, `cosine(_:_:)`, blob (de)serialization. (`NaturalLanguage` is OS-level, fine in Core.) |
| `SmartSearchQuery` | `MacAllYouNeed/ClipboardDock/Search/SmartSearchQuery.swift` | Parse free text + slash operators + regex into predicates; pure value type. |
| `ClipboardEnrichmentCoordinator` | `MacAllYouNeed/App/Coordinators/ClipboardEnrichmentCoordinator.swift` | Main-actor coordinator: observes `clipboardStoreDidChange` / poll, finds records missing OCR/embedding/detected_type, enriches them off the hot path, writes back, posts change. Idempotent and resumable. |
| `SmartTextFeatureActivator` + `ClipboardSmartTextDescriptor` | `MacAllYouNeed/App/Descriptors/ClipboardSmartTextDescriptor.swift` | Feature gating (see §7). |
| `ClipboardSmartTextSettingsView` | `MacAllYouNeed/Settings/...` | Toggles (see §8). |

Pipeline extension (two insertion points, by cost):

- **Hot path (synchronous, cheap) — at capture, in the daemon.**
  `SensitiveContentFilter` and (optional) link auto-clean run *before*
  `clip.append(...)` in `ClipboardDaemon/DaemonContainer.swift`. Cheap text
  classification (`detected_type`) is also computed here because it is regex-only
  and sub-millisecond; it is written as a column on insert.
- **Cold path (deferred, expensive) — in the main app.**
  `ClipboardEnrichmentCoordinator` performs OCR and embedding computation,
  because Vision and `NLEmbedding` should not run inside the headless capture
  daemon's tight loop and the main app already owns blob decode + FTS upsert.
  The coordinator backfills existing history lazily when the feature is first
  enabled.

Rationale for the split: the daemon must stay responsive 24/7; classification is
trivially cheap and must influence the skip/clean decision, so it stays inline.
OCR/embeddings are latency-tolerant and need richer frameworks, so they run in
the main app against the shared store.

---

## 5. Data model / storage

### New columns on `clipboard_records`

Added by one new GRDB migration appended to `ClipboardStore.migrations`
(`Shared/Sources/Core/Storage/ClipboardStore.swift:67`), following the exact
`ALTER TABLE ... ADD COLUMN` pattern already used by migrations `002`–`007`:

```
Migration(identifier: "008-smart-text") { conn in
    ALTER TABLE clipboard_records ADD COLUMN detected_type TEXT;   -- JSON: Detection payload
    ALTER TABLE clipboard_records ADD COLUMN ocr_text TEXT;        -- recognized text, NULL until OCR runs
    ALTER TABLE clipboard_records ADD COLUMN embedding BLOB;       -- Float32[] little-endian, NULL until embedded
    CREATE INDEX IF NOT EXISTS idx_records_detected_type ON clipboard_records(detected_type);
}
```

- `detected_type` stores the full `Detection` as JSON (type + payload:
  calculation result, link-clean provenance, code language). Indexed for
  `/type:` filtering. Written on insert by the daemon (cheap classification).
- `ocr_text` and `embedding` are nullable and populated lazily by
  `ClipboardEnrichmentCoordinator`. Their presence is the resumability signal:
  the coordinator selects rows where the relevant column is NULL.
- These columns sit *alongside* the encrypted `envelope` blob. Decision: store
  `detected_type`/`ocr_text`/`embedding` as plaintext columns (consistent with
  the existing plaintext `preview` and `source_app` columns, which already leak a
  120-char preview). OCR text is no more sensitive than the preview it
  accompanies; keeping it plaintext is required for FTS5 indexing anyway (FTS
  already holds plaintext content). This matches the existing threat model where
  `preview` and `search_index` are unencrypted; the envelope protects the full
  body. **Open question 12.1 revisits this.**

### FTS

No schema change to `SearchStore` (`Shared/Sources/Core/Storage/SearchStore.swift:17`).
OCR text is added by calling the existing `upsert(kind:id:text:)` with the record
id and `ocr_text`. On record delete, the existing FTS removal path covers it.

### New write APIs on `ClipboardStore`

Mirror the existing `setCustomLabel(id:label:)` shape (`ClipboardStore.swift:240`):

- `setDetectedType(id:json:)`
- `setOCRText(id:text:)`
- `setEmbedding(id:blob:)`
- read helpers + extend the `SELECT` column lists in `listRows`
  (`ClipboardStore.swift:171`), `metas`, `recentByFrequency`,
  `recentByLastAccessed` to project the new columns into `ClipboardItemMeta`
  (new optional fields), so cards and search see them without a second read.

`ClipboardItemMeta` gains optional `detectedType`, `ocrText`, `embedding`
(decoded lazily). The `append` path (`ClipboardStore.swift:117`) gains an
optional `detectedTypeJSON` parameter set by the daemon at insert.

---

## 6. Integration seams (file:line)

Capture / hot path:
- `ClipboardDaemon/DaemonContainer.swift:96-120` — the five `clip.append(...)`
  call sites (text/rtf/html/image/files). Insert `SensitiveContentFilter` before
  the text/rtf/html appends; insert link auto-clean before the text append when
  the body is a single URL; pass `detectedTypeJSON` into `append`.
- `Shared/Sources/Core/Storage/ClipboardStore.swift:117` — `append(...)` gains
  the `detectedTypeJSON` parameter and writes the `detected_type` column.
- `Shared/Sources/Core/Storage/ClipboardStore.swift:67` — append migration `008`.
- `Shared/Sources/Core/Storage/ClipboardStore.swift:171,191,249,272` — extend
  `SELECT` column lists + `metaRow` (`:342`) to project new columns.

Cold path / enrichment:
- `MacAllYouNeed/App/LocalClipboardReader.swift:41` — `clipboardStoreDidChange`
  observer is the natural trigger; the enrichment coordinator subscribes to the
  same notification (and the 1 s poll at `:121`) to find un-enriched rows.
- `Shared/Sources/Core/Storage/SearchStore.swift` — `upsert`/`remove` for OCR
  text indexing (no schema change).
- `MacAllYouNeed/ClipboardDock/Services/ImageBlobLoader.swift` /
  `BlobStore` — reuse the existing decrypt+decode path to feed Vision.

Search:
- `MacAllYouNeed/ClipboardDock/Model/SubModels/SearchFilterSubModel.swift:303`
  — `filteredAndRanked(items:query:)` is the single ranking chokepoint. Parse
  the query into `SmartSearchQuery` here, apply slash/regex predicates to the
  candidate list, then blend semantic cosine into the fuzzy ordering.
- `MacAllYouNeed/ClipboardDock/Model/SubModels/SearchFilterSubModel.swift:155`
  — `loadHistoryLocally` currently pre-filters by `preview.contains`. Extend so
  `/type:`/`/app:`/`ocr_text` matches are not lost by the substring pre-filter
  (loosen pre-filter when operators/regex/semantic are present).
- `MacAllYouNeed/ClipboardDock/Search/FuzzyMatcher.swift:4` — `rank(...)` stays
  as-is; semantic blending wraps it rather than editing it.
- `MacAllYouNeed/App/LocalClipboardReader.swift:144` — the menu-bar popover's
  simpler `preview.contains` filter gains the same `SmartSearchQuery` parse so
  operators work there too.

Cards / actions:
- `MacAllYouNeed/ClipboardDock/Views/Cards/TextCard.swift`,
  `LinkCard.swift:3` — add the calculation result row and type badges/actions.
- `MacAllYouNeed/ClipboardDock/Views/Cards/CardContextMenu.swift` — add
  type-aware menu entries.
- `MacAllYouNeed/ClipboardDock/Views/MultiSelect/TransformMenu.swift:4` — Smart
  Text actions compose with, and reuse, `applyTransform(_, saveAsNew: true)`
  (`ClipboardDockModel`) so "Copy result" / "Clean link" / "Copy recognized
  text" persist as new clips, never mutating the original.
- `MacAllYouNeed/ClipboardDock/Model/DockItem.swift:5` — `DockItemKind` already
  models `link`, `color`, `code(language:)`; map `detected_type` onto it and add
  the calculation/OCR affordance flags to `DockItem`.

Feature gating:
- `Shared/Sources/FeatureCore/FeatureID.swift:3` — add
  `case clipboardSmartText`.
- `MacAllYouNeed/App/Descriptors/ClipboardDescriptor.swift` — new sibling
  descriptor file; registered wherever the other descriptors are registered.

---

## 7. Permissions

**None.** This is a hard requirement and is satisfiable:

- Vision OCR runs on in-process image data already owned by the app; it requires
  no TCC permission.
- `NLEmbedding` is an offline framework API; no permission, no download.
- The sensitive frontmost-window-title check reuses context the daemon already
  has (source-app capture); it adds no new entitlement. If a window title is
  unavailable, the check simply skips the title branch.

The descriptor declares `requiredPermissions: []`. It still inherits the
clipboard feature's accessibility need indirectly (paste actions go through the
existing dock paste coordinator), but Smart Text adds nothing new.

---

## 8. UI / UX

All UI uses `MAYNTheme` / `MAYNControlMetrics` / `MAYNMotion`,
`FunctionSegmentedTabStrip` for any multi-choice control, and the existing card
chrome. No ad-hoc colors, durations, or raw segmented pickers (per
`MacAllYouNeed/CLAUDE.md` hard rules).

### Card affordances per detected type

- **Calculation** (text card): a result row below the preview —
  `= 14` rendered with the standard secondary label color; trailing
  `Copy result` (`MAYNButton .secondary`, compact). Optional `Replace` in the
  context menu.
- **Link** (`LinkCard.swift`): existing host/favicon row gains a small "N
  trackers" badge (`StatusPill`) when cleanable; primary action `Clean link`. In
  auto-apply mode the badge reads "cleaned" with a `Restore original` context
  action.
- **Email / phone / JWT**: a small leading SF Symbol + type label, plus a
  context action: email → `Compose` (mailto), phone → `Call`/`Copy digits`,
  JWT → `Decode` (shows header/payload JSON in the existing Quick Look overlay,
  read-only; no signature verification claim).
- **Color**: reuse the existing `ColorCard` swatch presentation.
- **Code**: reuse the existing `CodeCard`; the detected language label populates
  its header.
- **Image with OCR**: a `Text found` `StatusPill` and a `Copy recognized text`
  context action when `ocr_text` is non-empty. No badge while OCR is pending or
  empty.

### Search operator UX

- The dock search field accepts inline operators; recognized operators render as
  removable chips (visual parity with `DockListTabs` per the accepted-exception
  note, not a new primitive). Free text continues to type normally.
- A small affordance in the search field's trailing area toggles **Regex mode**;
  invalid patterns show a subtle inline hint and fall back to literal search.
- A short operator legend is available from the existing dock more-menu
  (`DockMoreMenu`), not as always-on chrome.

### Settings toggles

New `ClipboardSmartTextSettingsView` reachable from the Clipboard tool page's
settings (consistent with how clipboard settings are wired today), using
`MAYNSettingsPage` + `MAYNSection` + `MAYNSettingsRow` + `MAYNDivider`:

- Inline calculation — on/off.
- Link cleaner — `FunctionSegmentedTabStrip`: Off / Manual / Auto-apply.
- Smart detection — on/off (master for badges/actions).
- Image OCR — on/off + read-only "indexed N images".
- Sensitive-data filtering — on/off (default on) + read-only "skipped N today".
- Search: Semantic ranking on/off; Regex-by-default on/off.

All toggles persist in `AppGroupSettings.defaults` (same store the dock already
reads, e.g. `search.fuzzy` at `SearchFilterSubModel.swift:300`) so both the
daemon and the main app observe them.

---

## 9. Edge cases & error handling

- **Calculation false positives**: phone numbers, version strings (`1.2.3`),
  dates (`2026-05-30`), ranges (`10-20`) must not render a result. Require a
  binary operator with operands on both sides and reject inputs that
  `NSDataDetector` flags as phone/date.
- **Link cleaner over-stripping**: never strip params on non-tracking keys; only
  the explicit table + `utm_` prefix. Preserve param order for kept params.
  Auto-apply only on single absolute URLs.
- **OCR on non-text images** (photos, UI screenshots with no text): empty result
  → `ocr_text` stays NULL, no badge, no FTS row. Huge images downsampled first;
  decode failure logged, not retried.
- **Embedding gaps**: unsupported language or `NLEmbedding` returns nil →
  `embedding` stays NULL; ranking silently falls back to lexical. Query embedding
  failure → semantic step skipped entirely for that query.
- **Sensitive filter false negatives/positives**: Luhn matches some non-card
  19-digit numbers; acceptable (privacy-favoring). False negatives (cards not
  caught) are best-effort; we never claim completeness in copy.
- **Backfill cost**: enabling the feature with a large history triggers lazy
  enrichment. Process in small batches with yields; never block the UI; resumable
  across launches (NULL-column selection). Honor the existing retention window
  (`ClipboardHistoryWindow`) so we don't enrich items about to be pruned.
- **Daemon/main-app race**: enrichment writes go through `ClipboardStore` and
  post `clipboardStoreDidChange`; the daemon never writes these enrichment
  columns, avoiding write contention (single GRDB queue serializes anyway).
- **Migration on downgrade**: extra columns are additive and ignored by older
  builds; FTS rows for OCR are harmless to an older reader.
- **Regex DoS**: cap pattern length and matched-text length; run regex on the
  already-bounded candidate window only.
- **Feature off**: classification/OCR/embedding are skipped; existing columns (if
  previously populated) are simply unused — capture/search behave as today.

---

## 10. Testing strategy

Core (no AppKit, run under `Shared` swift test):

- `SmartTextServiceTests` — table-driven: calculation (valid/invalid/overflow/
  div-by-zero/phone-not-math/date-not-math), detection precedence
  (color>url>email>jwt>phone>code>plain), JWT header decode, code-language
  heuristic incl. markdown→plain, link cleaner (each tracking key, prefix match,
  order preservation, empty-query collapse, non-tracking preserved, multi-URL
  left alone).
- `SensitiveContentFilterTests` — Luhn positives (known test card numbers) and
  negatives (random 16-digit, phone), window-title keyword matching
  (case-insensitive), concealed-type short-circuit.
- `SmartSearchQueryTests` — parse `/app:`, `/type:`, `/date:` (today/Nd/YYYY-MM),
  negation, repeated-operator OR, free-text remainder extraction, regex
  delimiters, invalid-regex fallback.
- `ClipEmbeddingServiceTests` — blob round-trip (Float32 LE), cosine identity =
  1, orthogonal ≈ 0, nil-embedding fallback. (Skip/guard if `NLEmbedding`
  unavailable on CI.)
- `ClipboardStore` migration test — `008` adds columns; existing rows readable;
  new write/read APIs round-trip; column projection in `listRows`/`metas`.

App-side:

- `ImageOCRServiceTests` — fixture PNGs with known text (rendered offscreen) →
  expected recognized substrings; empty-text image → nil; oversized image
  downsample path; timeout/single-flight behavior with a stubbed request.
- Ranking blend test — given fixed lexical + semantic scores, assert ordering
  matches the documented weighted policy and that NULL-embedding items still
  rank by lexical score.

Fixtures: a small set of text samples (`fixtures/smarttext/*.txt`),
generated-image PNGs with embedded text, and synthetic embedding vectors so
ranking tests are deterministic without invoking `NLEmbedding`.

---

## 11. Risks & mitigations

- **Capture latency regression (daemon hot path).** Mitigation: only cheap
  regex/Luhn/title checks run inline; OCR/embeddings are deferred to the main
  app. Add a micro-benchmark guard in the daemon append path.
- **OCR/embedding CPU on backfill.** Mitigation: bounded pool, small batches,
  utility QoS, retention-window scoping, resumable NULL-selection.
- **Plaintext OCR/embedding columns widen the unencrypted surface.** Mitigation:
  matches the existing `preview`/FTS threat model; documented; revisited in
  §12.1. Sensitive filter reduces what reaches storage at all.
- **Semantic ranking surprises users** (related-but-not-matching results
  surfacing). Mitigation: lexical-dominant blend, semantic only breaks ties /
  rescues empty-lexical; toggle to disable.
- **Slash-operator collisions with literal `/` text.** Mitigation: operators
  must match the strict `^-?/(app|type|date):` grammar; anything else is literal
  free text; regex requires explicit delimiters or mode toggle.
- **`NLEmbedding` / Vision availability variance across macOS minor versions.**
  Mitigation: all calls guarded; nil-tolerant fallbacks; no hard dependency on a
  specific language model.
- **Scope creep toward AI-chat / plugins.** Mitigation: explicit non-goals (§2).

---

## 12. Open questions

1. **Encrypt `ocr_text` / `embedding`?** FTS needs plaintext to index OCR text,
   but `embedding` could be sealed and decrypted only at query time. Is the added
   ranking latency acceptable for the privacy gain? (Default proposal: leave
   plaintext, matching `preview`/FTS; flag for security review.)
2. **Window-title source for the sensitive check.** Confirm the daemon can read
   the frontmost window title without a new entitlement on the target macOS; if
   not, fall back to app-bundle-only matching (e.g. known password managers).
3. **Backfill opt-in.** On first enable with a large history, do we backfill all
   eligible items, only items within the retention window, or only new items
   going forward with a manual "Index existing" button? (Proposal: retention
   window + manual full-index button.)
4. **Semantic blend weight** — fixed constant in v1. Do we want a hidden
   `AppGroupSettings` override for tuning before committing a number?
5. **Calculation "Replace clip text"** — should it ever auto-replace (like link
   auto-apply), or always stay manual? (Proposal: always manual; numbers are
   higher-stakes to silently change than tracking params.)
6. **JWT "Decode" surface** — reuse the Quick Look overlay vs. a dedicated
   inspector. (Proposal: Quick Look overlay, read-only, no validity claims.)
