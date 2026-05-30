# Feature E — AI File Organizer

Date: 2026-05-30
Status: Design (child of [`00-roadmap.md`](./00-roadmap.md))
Reference: Riffo.ai (product), LlamaFS (OSS, MIT, Groq-first), AI File Sorter
(AGPL, reference-only for preview/approve UX)
Effort: M–L · New permission: none (Groq reused; folder access via
security-scoped bookmarks)

---

## 1. Summary

AI File Organizer is a gated MAYN feature that renames and re-files messy folders
(Downloads first, any folder second) using the **content of the files**, not just
their existing names. For each file it extracts a small amount of text/metadata
on-device (Vision OCR for images, PDFKit for PDFs, plain text for documents,
`UTType` for type detection), sends **only those extracted snippets + metadata**
to the shared S2 LLM intent layer, and gets back a descriptive filename plus a
proposed subfolder. Nothing moves until the user approves an explicit old → new
**diff pane**. Applied operations are recorded in an **operation manifest** so the
whole batch can be undone, reusing MAYN's existing undo mental model from Voice.

The AI posture matches Voice exactly: **Groq cloud by default, local model
opt-in backup**, selected through the user's existing cleanup-provider choice. The
cloud never receives raw file bytes — only extracted text snippets and metadata.

A full-featured **watch mode** can observe a folder (e.g. Downloads) and surface a
proposal when new files land; it still routes through the same mandatory
preview/approve pane and never moves a file silently.

This feature ships as its own `FeatureDescriptor` (dashboard card + onboarding +
enable/disable through `FeatureRuntime`), with a `FunctionPageShell` tool page and
a new `.aiFileOrganizer` `MainAppDestination` / `FeatureID`.

---

## 2. Goals / Non-goals

### Goals

- Rename files from **content**, producing clear, descriptive, consistent names.
- Propose and apply a **logical subfolder structure** for a reviewed batch.
- On-device content extraction (OCR, PDF text, document text, type detection)
  with **only extracted snippets/metadata leaving the device**.
- A **mandatory preview/approve diff pane** before any rename or move — the core
  safety guardrail. No "apply" path skips it.
- Full **undo** of a batch via a persisted operation manifest.
- Entry points: **Scan Downloads** and **arbitrary folder** via `NSOpenPanel` +
  security-scoped bookmark.
- **Watch mode** that proposes organization for new files (still preview/approve).
- **Learn-from-edits**: corrections the user makes to proposed names feed back
  into later proposals (prompt context + lightweight preference store).
- Reuse the existing Groq/local provider selection and injection seam (S2); no
  new model stack, no new permission for AI.

### Non-goals

- **No bundled visual-LLM.** We do not ship or call an image-understanding model.
  Image "understanding" is OCR text via Vision only. (Explicit non-goal.)
- **No silent auto-apply.** Watch mode and batch scans always require approval;
  there is no "trust it, just rename everything" mode. (Explicit non-goal.)
- No cloud upload of raw file bytes, ever.
- No content-based dedup/cleanup of duplicate files (out of scope; this is rename
  + foldering only).
- No sync of manifests across devices (MAYN Plan 2 sync is skipped indefinitely).
- No Finder Sync extension surface in v1 (the tool page + watch mode are the
  surfaces; a FinderSync action menu is an open question, §12).

---

## 3. Full feature scope

### 3.1 Content extraction (native, on-device)

A single `ContentExtractor` resolves each file to a small `ExtractedContent`
struct. It never reads more than a bounded budget per file (configurable cap,
default ~8 KB of text and the first N pages/region).

- **Type detection**: `UTType(filenameExtension:)` / `URL.resourceValues` to
  classify each file (image, PDF, plain/rich text, source code, archive, media,
  unknown). Drives which extractor runs.
- **Images / screenshots**: Vision (`VNRecognizeTextRequest`) OCR. Captures the
  recognized text plus image dimensions and capture date from EXIF/`NSImage`
  metadata. This is the "screenshot → readable name" path Riffo highlights.
- **PDFs**: PDFKit (`PDFDocument`) text from the first N pages, plus
  `documentAttributes` (title/author/creation date) when present.
- **Text / rich text / source**: read the head of the file as UTF-8 (with a fast
  fallback for non-UTF-8), bounded by the byte cap. For source files, capture the
  language + top-of-file identifiers.
- **Everything else**: metadata only — filename, extension, size, created/modified
  dates, and (if available) Spotlight `kMDItem*` attributes. No content is sent.

`ExtractedContent` carries: `originalURL`, detected `UTType`, a `kind` enum,
`snippet: String` (already truncated), and a `metadata` dictionary (dates, size,
dims, page count, author, etc.). This struct — never the file — is what the engine
hands to the LLM.

Extraction is the on-device sibling of `FolderPreview/FolderEntryLoader.swift`'s
type/thumbnail handling; it reuses `UTType`/`FolderEntryKind` classification ideas
but produces text, not preview nodes.

### 3.2 AI rename

For each `ExtractedContent`, the engine requests a completion through S2 with a
named prompt template (`file-organizer/rename`). The LLM returns a proposed base
name (no extension). The engine then:

- **Sanitizes**: strips/replaces illegal characters (`/`, `:`, control chars, and
  the leading-dot hidden-file trap), collapses whitespace, trims, and enforces a
  max length (default 120 chars, configurable) while preserving the original
  extension.
- **Applies the user's naming pattern** (§3.4) — date prefix/suffix, custom text,
  sequence number — around the AI base name.
- **De-dups against the target directory and against the rest of the batch**: if a
  name collides, append ` (2)`, ` (3)`, … deterministically. Collisions are
  resolved at proposal time so the diff pane already shows final names.

The extension is **always preserved** unless the user opts into a type-correction
toggle (off by default; open question §12).

### 3.3 Auto-foldering

After per-file names are proposed, the engine optionally requests a **batch-level**
folder plan through S2 (`file-organizer/folder-plan`): given the list of proposed
names + kinds + a one-line content gist for each, the LLM proposes a small set of
subfolders (e.g. `Invoices/`, `Screenshots/`, `Contracts/2026/`) and assigns each
file to one. The engine:

- Caps folder depth (default 2) and folder count to avoid sprawl.
- Sanitizes folder names with the same rules as filenames.
- Leaves files at the root when the model is unsure (a file is never forced into a
  bad folder; "leave in place" is a valid assignment).
- Foldering is **optional per batch** — the user can approve renames only, folders
  only, or both, from the diff pane.

### 3.4 Custom naming patterns

A `NamingPattern` value (persisted per feature, not per batch) composes:

- **Date**: none / created / modified, with a format token (e.g. `yyyy-MM-dd`),
  placed as prefix or suffix.
- **Custom text**: a fixed prefix/suffix string.
- **Sequence**: optional zero-padded counter across the batch (`001`, `002`).
- **Case style**: as-is / Title Case / `kebab-case` / `snake_case`.

The AI base name is the variable middle; the pattern decorates it. The diff pane
shows the fully-composed result.

### 3.5 Preview / approve diff pane (centerpiece)

**Mandatory.** No rename or move executes without an approved proposal. The pane
shows, per file, a row with: source icon (reusing FolderPreview icon logic),
**old name → new name** (with a visible change highlight), the **proposed folder**
(or "stays here"), and a per-row checkbox plus inline edit affordance. Header
controls: select-all/none, "approve renames", "approve folders", "approve both",
and a live count of selected operations. Editing a proposed name inline both
updates the operation **and** is captured for learn-from-edits (§3.8).

### 3.6 Undo

Every applied batch writes an **operation manifest** (§5.1) before/while applying.
Undo replays the manifest in reverse: move files back, restore original names,
remove any now-empty folders the batch created. The mental model mirrors Voice's
`pendingUndo` affordance in `VoiceCoordinator.swift` (`undoLastCancel`): a recent
operation is undoable for a window of time from the UI, and the full history is
revertable from the tool page. Undo is itself recorded (a reverted manifest is
marked, not deleted).

### 3.7 Entry points

- **Scan Downloads**: one-tap action on the tool page. Resolves the user's
  Downloads directory (already reachable; see DownloaderDescriptor's file IO).
- **Choose folder**: `NSOpenPanel` (directory mode). The resolved URL is persisted
  as a **security-scoped bookmark** (§5.3) so re-scans and watch mode work across
  launches without re-prompting.

### 3.8 Watch mode (full-featured)

An opt-in per-folder watcher. When enabled for a folder:

- A `WatchDaemon` uses an `DispatchSource` / `FSEvents` watch on the bookmarked
  folder (resolving the security-scoped bookmark on start).
- New files are debounced (default 5 s of quiet, to let downloads finish writing)
  and queued.
- A batched proposal is generated and surfaced as a **non-intrusive prompt**
  (dashboard card badge + optional menu-bar item), opening the **same diff pane**.
- **Never silent.** Nothing is moved without the user opening and approving the
  proposal. If the app is quit, watch state resumes on next launch.

This matches LlamaFS's watch-mode + propose model, with MAYN's mandatory approval
laid on top.

### 3.9 Learn-from-edits

When the user edits a proposed name (or rejects a proposed folder) in the diff
pane, the engine records `(extractedGist, proposed, corrected)` triples in a
lightweight preference store (§5.2). On subsequent batches, the most recent N
relevant corrections are injected into the rename prompt as few-shot examples —
exactly the shape Voice already uses (`recentExamples: [(before, after)]` in
`VoiceCleanupRequest`). This is prompt context, not model fine-tuning.

---

## 4. Architecture & components

```
FileOrganizerCoordinator        (composition root for the feature; owned by AppController)
 ├── ContentExtractor           Vision / PDFKit / text / UTType → ExtractedContent
 ├── OrganizerEngine            orchestration: extract → rename → folder-plan →
 │                              sanitize/de-dup → OrganizationProposal
 │     └── (LLM via S2)         OrganizerLLMService (thin wrapper over the shared
 │                              S2 intent layer; named prompt templates)
 ├── FileMutator                executes approved ops (rename/move) + builds manifest
 ├── OperationManifestStore     persist manifests; drive undo
 ├── OrganizerPreferenceStore   learn-from-edits triples; bookmark store
 ├── WatchDaemon                FSEvents per bookmarked folder → debounced proposals
 └── UI                         tool page (FunctionPageShell) + diff pane + settings
```

- **`ContentExtractor`** — pure, on-device, no network. Bounded reads. Returns
  `ExtractedContent`. Testable with fixture files.
- **`OrganizerEngine`** — turns a folder's files into an `OrganizationProposal`
  (an ordered list of `ProposedOperation`: source URL, new name, target folder,
  reason). Owns sanitization, collision resolution, naming-pattern application.
  Has **no UI and no file mutation** — it only proposes.
- **LLM via S2** — `OrganizerLLMService` calls the shared LLM intent layer from
  `00-roadmap.md` §S2, which factors the Voice provider-selection +
  prompt-variant + injection seam out of `VoiceCoordinator` /
  `VoiceCleanupPipeline.swift`. It reuses the user's existing
  `VoiceCleanupProviderKind` choice (Groq default, Ollama/local opt-in; see
  `Voice/Cleanup/VoiceCleanupSettings.swift`) and the same Groq base URL +
  keychain key (`https://api.groq.com/openai/v1`). Two named templates:
  `file-organizer/rename` (per file) and `file-organizer/folder-plan` (per batch).
  The service is injectable (factory closure, mirroring
  `cleanupPipelineFactoryOverride`) so tests run with a stub and never hit cloud.
- **`FileMutator`** — the only component that touches the filesystem destructively.
  Applies approved ops one at a time, recording each completed op into the manifest
  **as it goes** so a crash mid-batch leaves a complete record of what was done.
- **`OperationManifestStore`** — see §5.1.
- **`OrganizerPreferenceStore`** — see §5.2 / §5.3.
- **`WatchDaemon`** — see §3.8. Runs in the **main app** (not the
  ClipboardDaemon), because the main app holds the security-scoped bookmark and is
  not sandboxed.
- **UI** — `FunctionPageShell` tool page with a `FunctionSegmentedTabStrip`
  (Organize / Watch / History), the diff pane, and a settings detail view wired via
  the `FeatureDescriptor` (same pattern as `DownloaderDescriptor`).

---

## 5. Data model / storage

Storage follows the existing encrypted GRDB pattern: a dedicated store class with a
`static let migrations: [Migration]` array (see
`Shared/Sources/Core/Storage/DownloadStore.swift` and `Migrations.swift`), an
AES-GCM `envelope BLOB` per row (`Cipher.seal` / `Cipher.open` with the device
key), and `RecordID`-style ids. New stores live in
`Shared/Sources/Core/Storage/`.

### 5.1 Operation manifest store (`OrganizerManifestStore`)

A manifest = one applied (or reverted) batch. Suggested schema (mirrors the
`downloads` table shape):

```
CREATE TABLE organizer_manifests (
  id TEXT PRIMARY KEY,          -- batch id
  state TEXT NOT NULL,          -- applied | reverted | partial
  created INTEGER NOT NULL,
  modified INTEGER NOT NULL,
  root_path TEXT,               -- the scanned folder (display only)
  envelope BLOB NOT NULL        -- encrypted [ManifestOperation]
);
CREATE INDEX idx_organizer_manifests_state ON organizer_manifests(state);
```

Each `ManifestOperation` (inside the encrypted envelope) stores: `sourceURL` (pre),
`destinationURL` (post), `originalName`, `newName`, `kind` (rename/move/both),
`appliedAt`, `createdFolders: [String]` (so undo can remove empties), and a
`status` (`applied`/`failed`/`reverted`). Storing both source and destination plus
created-folder list is what makes undo a deterministic reverse-replay.

### 5.2 Learn-from-edits preference store

Lightweight, append-only correction log (also encrypted):

```
CREATE TABLE organizer_corrections (
  id TEXT PRIMARY KEY,
  created INTEGER NOT NULL,
  envelope BLOB NOT NULL        -- { kind, gist, proposed, corrected }
);
```

The engine reads the most recent N (default 20) on each batch and injects them as
few-shot examples into the rename prompt (the `recentExamples` shape Voice already
uses). Bounded retention (e.g. last 200) keeps it small.

### 5.3 Security-scoped bookmarks

The main app is **not sandboxed** (confirmed: `MacAllYouNeed.entitlements` has only
app-group + audio-input + keychain; no `app-sandbox` key), so security-scoped
bookmarks are not strictly required for access. We still use
`URL.bookmarkData(options:)` (without the sandbox-only
`.withSecurityScope` requirement) to **persist a stable reference** to the chosen
folder across launches and to make watch mode resilient to moves/renames of the
parent. Bookmarks are stored (encrypted) keyed by folder, alongside the per-folder
watch-enabled flag and `NamingPattern`. On resolve, handle staleness (§9) by
re-prompting via `NSOpenPanel`. If the app is ever sandboxed later, the same code
path upgrades to `.withSecurityScope` + `startAccessingSecurityScopedResource()`.

---

## 6. Integration seams (real file refs)

- **S2 LLM intent layer** — `docs/specs/feature-expansion-2026/00-roadmap.md` §S2.
  Source it factors from: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
  (`cleanupPipelineFactory` / `cleanupPipelineFactoryOverride` injection seam,
  `processCapturedAudio`), `MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift`
  (`VoiceCleanupRequest` incl. `recentExamples`),
  `MacAllYouNeed/Voice/Cleanup/VoiceCleanupSettings.swift`
  (`VoiceCleanupProviderKind`: `.groq` default, `.ollama` local, Groq base URL +
  keychain key) and `MacAllYouNeed/Voice/Cleanup/Providers/`
  (`OpenAICompatibleVoiceProvider`, `OllamaServiceClient`).
- **Undo precedent** — `MacAllYouNeed/Voice/VoiceCoordinator.swift`
  `pendingUndo` / `undoLastCancel()` (the "recent op is undoable for a window"
  mental model and shared replay path).
- **File IO / folder access / Downloads resolution** — the Downloads subsystem:
  `MacAllYouNeed/App/Descriptors/DownloaderDescriptor.swift` +
  `Shared/Sources/Core/Storage/DownloadStore.swift` (record/queue + encrypted
  store pattern this feature copies).
- **Content/type/icon handling** — `FolderPreview/FolderEntryLoader.swift`
  (`PreviewRow`, `FolderEntryKind`, `UTType` classification, thumbnail capability)
  and `MacAllYouNeed/FolderPreview/` (`BrowseFolderCoordinator`,
  `FolderPreviewFeatureActivator`). The diff pane reuses this icon/kind logic.
- **Storage / migrations** — `Shared/Sources/Core/Storage/DownloadStore.swift`
  (table + `Cipher`/envelope pattern), `Shared/Sources/Core/Storage/Migrations.swift`
  (`Migration` struct), `Database.swift` (shared `Database`/`db.queue`).
- **Feature wiring** — `MacAllYouNeed/App/Descriptors/` (descriptor pattern;
  `DownloaderDescriptor` is the closest analog: id, displayName, icon, summary,
  assetPacks, activator), `Shared/Sources/FeatureCore/FeatureID.swift` (add
  `.aiFileOrganizer`), `MacAllYouNeed/App/MainAppDestination.swift` (add
  destination case + title/subtitle/icon), `MacAllYouNeed/App/FunctionPageShell.swift`
  (tool page chrome + `FunctionSegmentedTabStrip`),
  `MacAllYouNeed/App/FunctionDestinationRegistry.swift` (register the page).
- **Entitlements** — `MacAllYouNeed/MacAllYouNeed.entitlements` (no sandbox;
  app-group `group.com.macallyouneed.shared` for the shared DB).

---

## 7. Permissions

- **AI (Groq / local): none new.** Reuses the user's existing Voice cleanup
  provider selection and Groq keychain key. If no Groq key is set and no local
  model is configured, the feature surfaces the same "configure a provider" path
  Voice uses — it does not request a new permission.
- **Folder access: security-scoped bookmark flow.** First scan of an arbitrary
  folder goes through `NSOpenPanel`; the granted URL is bookmarked (§5.3) and
  re-resolved on later runs. "Scan Downloads" resolves the user's Downloads
  directory directly. No TCC prompt is required for ordinary user folders on a
  non-sandboxed app, though macOS may still gate Desktop/Documents/Downloads with
  a system prompt the first time — handled gracefully (§9).
- **Sandbox note.** The main app is **not sandboxed**; only the FolderPreview
  QuickLook extension is. This feature lives entirely in the main app, so it has
  ordinary user-level filesystem access. The bookmark layer is for persistence and
  forward-compatibility, not a sandbox requirement.

No two permission prompts collide with other 2026 features (per the roadmap
permissions matrix; this feature adds none).

---

## 8. UI / UX

All UI uses `MAYNTheme` / `MAYNControlMetrics` / `MAYNMotion` /
`MAYNMotionBridge`; segmented choices use `FunctionSegmentedTabStrip`; the page
uses `FunctionPageShell`. No ad-hoc colors, dimensions, durations, or springs.

### 8.1 Tool page

`FunctionPageShell` with a `FunctionSegmentedTabStrip`: **Organize / Watch /
History**.

- **Organize**: two primary actions — **Scan Downloads** and **Choose Folder…**
  Below, the current `NamingPattern` summary chip and a "configure pattern" link
  into settings. Running a scan shows a determinate progress row (extracting → asking
  AI → ready) then opens the diff pane.
- **Watch**: list of watched folders with per-folder enable toggle, debounce, and a
  "stop watching" action; an add-folder button.
- **History**: list of applied manifests (folder, count, date, state) with an
  **Undo** action per batch and a top "Undo last batch" affordance.

### 8.2 Batch picker

`NSOpenPanel` in directory mode for "Choose Folder…". After selection, an optional
include/exclude step (hidden files off by default, file-count cap, kind filter
reusing `FolderEntryKind`) before extraction begins, so huge folders are bounded up
front (§9).

### 8.3 Preview / approve diff pane (centerpiece)

A focused panel/sheet over the tool page. Per the centerpiece spec in §3.5: per-row
icon, **old → new** with change highlight, proposed folder (or "stays here"),
per-row checkbox + inline rename, and a header with select-all/none, approve
renames / folders / both, and a live selected-operation count. A clearly separated,
non-default **Apply** button commits; **Cancel** discards with no filesystem change.
Inline edits feed learn-from-edits.

### 8.4 Undo

After Apply, a transient undo affordance appears (Voice `pendingUndo` mental
model) — "Organized 23 files · Undo" for a short window — and the same batch stays
permanently revertable from **History**.

### 8.5 Watch-mode config

Per-folder: enable toggle, debounce seconds, and "scope" (this folder only vs.
include subfolders, default off). A watch proposal arrives as a dashboard card
badge / menu-bar item (never a modal grab) and opens the standard diff pane.

### 8.6 Cloud-vs-local toggle + privacy disclosure

Settings shows the active provider (inherited from the Voice cleanup selection;
Groq default / local opt-in) with a one-line override link, and a **plain-language
privacy disclosure**: "Only short extracted text snippets and file metadata are
sent to the AI provider. Your files are never uploaded." When local is selected,
the disclosure states nothing leaves the device. The exact snippet sent is
inspectable via a "what gets sent" preview for a sample file.

---

## 9. Edge cases & error handling

- **Data-loss prevention (dominant concern).** Never overwrite an existing file:
  collisions are resolved to a new unique name at proposal time and re-checked
  atomically at apply time; if a target exists unexpectedly at apply, that single
  op is skipped and flagged, not overwritten. Moves use `FileManager`
  rename/move that fails closed rather than clobbering.
- **Collisions** (two files → same proposed name, or name taken in target dir):
  deterministic ` (2)`, ` (3)` suffixing across the whole batch + target dir, shown
  in the diff before apply.
- **Partial-apply rollback.** The manifest is written op-by-op as files move, so a
  crash or mid-batch failure leaves a complete record. A failed op stops the batch,
  marks the manifest `partial`, and offers **Undo** to revert the ops that did
  succeed — never leaving the user guessing.
- **Stale / invalid bookmarks.** On resolve failure (folder moved/deleted, bookmark
  stale), re-prompt via `NSOpenPanel` and refresh the bookmark; watch mode for that
  folder pauses with a clear "folder unavailable" state instead of erroring in a
  loop.
- **LLM failure / timeout.** Reuse the Voice latency-budget posture
  (`VoiceCleanupLatencyPolicy`): on timeout or provider error, fall back to the
  local provider if configured; otherwise mark affected files "couldn't name" and
  **leave them untouched** with their original names — the batch still applies the
  files that did get names. AI failure never renames a file to garbage.
- **Empty / unreadable extraction.** Encrypted, zero-byte, permission-denied, or
  binary-only files yield metadata-only proposals (or "skip"); they are never
  forced into a content-based name.
- **Large batches.** Bounded extraction reads, an up-front file-count cap with a
  "scan first N" path, concurrency limits on extraction, and request batching /
  rate-limit handling for the LLM (especially Groq). Folder-plan is one batched
  call, not one per file.
- **Files in use / mid-download.** Watch-mode debounce (default 5 s quiet) plus a
  skip for files still being written (size changing, `.crdownload`/`.part`
  suffixes) prevents organizing half-written downloads.
- **Symlinks / packages / app bundles.** `.app`, `.bundle`, and directory-packages
  are treated as opaque single items (renamed, never descended into); symlinks are
  left in place by default.
- **Concurrent external changes.** If a file changed on disk between proposal and
  apply (mtime/size differs), that op is skipped and flagged so we never act on
  stale assumptions.

---

## 10. Testing strategy

- **`ContentExtractor`** — fixture files per kind (PNG screenshot, scanned PDF,
  text doc, source file, unknown binary); assert snippet bounds, metadata fields,
  and that no read exceeds the byte/page cap.
- **`OrganizerEngine`** — inject a **stub LLM service** (the S2 injection seam, same
  shape as `cleanupPipelineFactoryOverride`) returning canned names; assert
  sanitization (illegal chars, length, extension preservation), deterministic
  collision suffixing across a batch, naming-pattern composition, and folder-plan
  depth/count caps. No network.
- **`FileMutator` + `OperationManifestStore`** — apply against a temp directory,
  assert files moved/renamed, manifest written op-by-op, and **undo restores
  byte-for-byte original layout** including removal of created empty folders.
  Inject a mid-batch failure and assert `partial` + correct partial undo.
- **Learn-from-edits** — record corrections, assert recent N are injected into the
  next rename request (verify via the stub LLM seeing the few-shot examples).
- **Bookmark store** — round-trip persist/resolve; simulate stale bookmark →
  re-prompt path.
- **Watch daemon** — drop files into a temp watched dir, assert debounce, ignore of
  `.part`/in-progress files, and that a proposal is produced **but nothing moves**
  without approval.
- **Voice regression** — S2 refactor must keep Voice behavior unchanged; existing
  `VoicePromptBuilder*Tests` / `VoiceCleanupPipeline` tests must stay green.
- Shared-package tests run via
  `cd Shared && PKG_CONFIG_PATH=… swift test`; app-level tests via `xcodebuild test`.

---

## 11. Risks & mitigations

**Data loss is the dominant risk.** A bad rename or move that loses or clobbers a
user's file is unacceptable. Mitigations, layered:

1. **Mandatory diff pane** — nothing executes without explicit per-batch approval;
   there is no silent/auto path (enforced non-goal §2).
2. **No-overwrite invariant** — collisions resolved to unique names; existing-target
   check re-run atomically at apply; conflicting ops skipped, never clobbered.
3. **Op-by-op manifest + full undo** — every applied batch is reversible, including
   partial batches after a mid-run failure.
4. **Fail-closed file ops** — move/rename APIs that error rather than overwrite;
   stale-file detection (mtime/size) skips anything changed since proposal.
5. **AI never names blindly** — on LLM failure/timeout, files keep original names;
   low-confidence files are left in place rather than mis-foldered.

Other risks:

- **Privacy / wrong data to cloud** → only `ExtractedContent` snippets + metadata
  leave the device, never file bytes; an inspectable "what gets sent" preview; local
  opt-in for zero-cloud users; disclosure copy in settings (§8.6).
- **LLM cost / rate limits (Groq)** → batched folder-plan, bounded snippet size,
  file-count caps, concurrency throttling, latency-budget fallback to local.
- **Bad/unstable names hurting trust** → learn-from-edits, sanitization, and the
  user always editing inline before apply.
- **S2 refactor regressing Voice** → Voice covered by existing tests; S2 is a
  factor-out, not a rewrite (roadmap §S2).
- **Watch-mode noise** → debounce, in-progress-file skip, non-modal surfacing, and
  per-folder enable.

---

## 12. Open questions

1. **Type-correction toggle** — should we ever change a file's extension when the
   detected `UTType` disagrees with it (e.g. `.txt` that is really JSON)? Default
   off; risky for double-extensions and for breaking app associations.
2. **FinderSync action** — a right-click "Organize with MAYN" Finder menu item is
   attractive but adds a sandboxed extension surface (cf. FolderPreview). Deferred;
   v1 ships tool page + watch mode only.
3. **Folder-plan granularity** — one global plan per batch vs. incremental per-kind
   plans for very large heterogeneous folders. Start with one batched call.
4. **Undo retention** — how long to keep manifests (and whether to prune after the
   originals are externally deleted, which makes undo a no-op).
5. **Watch-mode menu-bar surface** — dashboard badge only, or a dedicated menu-bar
   item? Tied to the existing Command Center popover real estate.
6. **Per-folder vs. global naming pattern** — v1 uses a global `NamingPattern`;
   per-watched-folder overrides may be wanted later.
7. **Concurrency / cost ceiling defaults** — exact extraction concurrency and Groq
   request batching defaults to be tuned against real Downloads folders.
