# 2026 Feature Expansion — Roadmap & Mega-Spec

Date: 2026-05-30
Status: Design approved (brainstorming complete), specs in review.

This is the **root spec** for a six-feature expansion of Mac All You Need
(MAYN). Each feature is independent, ships as its own gated
`FeatureDescriptor` (dashboard card + onboarding + enable/disable through the
existing `FeatureRuntime`), and has its own child spec and implementation plan.

The six features were each derived from a reference project (or product) plus
research against our existing codebase. The reference material lives under
`reference-projects/` and the prior research notes under `docs/research/`.

## The six features

| # | Feature | Child spec | Reference | Effort | New permission |
|---|---------|-----------|-----------|--------|----------------|
| A | Clipboard Smart Text | [`01-clipboard-smart-text.md`](./01-clipboard-smart-text.md) | Deck | M | none |
| B | Finder Folder History | [`02-finder-folder-history.md`](./02-finder-folder-history.md) | (own design) | M | Automation (opt-in) |
| C | Voice → Reminders | [`03-voice-reminders.md`](./03-voice-reminders.md) | reminders-menubar | M | Reminders (EventKit) |
| D | Loop Radial Window UI | [`04-loop-radial-window-ui.md`](./04-loop-radial-window-ui.md) | Loop | M | none |
| E | AI File Organizer | [`05-ai-file-organizer.md`](./05-ai-file-organizer.md) | Riffo.ai / LlamaFS | M–L | none (Groq) |
| F | Dock-Hover Window Previews | [`06-dock-hover-previews.md`](./06-dock-hover-previews.md) | DockDoor | M–L | Screen Recording |

## Locked product decisions

These apply across all six specs (set during brainstorming on 2026-05-30):

1. **Ambition: full-featured each.** Specs describe the complete feature, not a
   trimmed MVP. Where a sub-capability is genuinely large, it is called out as a
   distinct phase *within* that feature's spec, but nothing is dropped.
2. **Build everything at once.** The six are designed to be **independent and
   parallelizable**. There is no required build order; shared infrastructure
   (below) is the only coupling and is built once, first.
3. **AI posture (File Organizer + Voice Reminders): Groq cloud default + local
   opt-in.** This mirrors the existing Voice pipeline. Cloud calls send only
   extracted text/metadata, never raw files or audio beyond what the user
   dictated.
4. **Clipboard semantic search: included, on-device.** Apple `NLEmbedding`
   (local, no cloud, no model download) layered over existing FTS5 +
   `FuzzyMatcher`.
5. **Voice → Reminders trigger: hotkey + spoken trigger.** A dedicated global
   hotkey is the reliable path; spoken-prefix detection ("take a reminder…",
   "remind me to…") is a best-effort second path checked after LLM cleanup.
6. **Finder history UI: hotkey quick-switcher + menu-bar dropdown + FinderSync
   toolbar button.** The main-window page is **configuration/guidance only**
   (settings, exclusions, permission, how-to) — not a browse surface. Pin/remove
   actions live inline in the switcher and dropdown.
7. **Main app is not sandboxed** (only the FolderPreview QuickLook extension is).
   This is confirmed and is what makes the Dock-preview private-API path viable.
   The project distributes via DMG/notarization/Sparkle, so there is no Mac App
   Store constraint.

## Shared infrastructure (build once, first)

Two pieces of shared infrastructure are extracted up front because more than one
feature depends on them. Everything else is feature-local.

### S1. `AXObserverCoordinator` — robust Accessibility observation utility

Both **Dock previews** (observe `com.apple.dock`) and **Finder history**
(observe Finder's focused window) need the same pattern: attach an `AXObserver`
to a target process, subscribe to notifications, and **re-subscribe via a
health-check timer** when the target rebuilds its AX tree (the Dock and Finder
both do this silently). Today this lives ad hoc in
`MacAllYouNeed/WindowControl/WindowControlCoordinator.swift`.

Scope: a small reusable type that owns `AXObserverCreate` + run-loop source +
notification registration + a periodic liveness re-subscribe, with a clean
Swift callback surface. It does **not** own any feature logic. The existing
`WindowControl` AX usage may optionally be refactored onto it, but that is not
required for the new features and should not expand scope.

Owner spec: documented here; consumed by B and F.

### S2. LLM intent layer — generalize the voice cleanup pipeline

**Voice Reminders** and the **File Organizer** both want "run text through an
LLM with a task-specific prompt, Groq-default with a local fallback, injectable
for tests." The Voice subsystem already has exactly this shape
(`VoiceCoordinator` injects a cleanup pipeline factory + summarizer;
`VoicePromptBuilder` builds prompts).

Scope: factor the provider-selection + prompt-variant + injection seam so a
non-voice caller (the File Organizer) can request a completion with a named
prompt template and the same Groq/local selection the user already configured
for voice. This is a **refactor of existing voice infra into a reusable
service**, not a new model stack. Voice behavior must be unchanged (covered by
existing `VoicePromptBuilder*Tests`).

Owner spec: documented here; consumed by C and E.

## Permissions matrix

| Permission | Already held | Needed by | Onboarding |
|------------|--------------|-----------|------------|
| Accessibility | ✅ (WindowControl, snippets, CGEventTap) | B, D, F | reuse existing card |
| Screen Recording | ❌ | F (thumbnails/live previews) | new card; degrade to text list when denied |
| Reminders (EventKit) | ❌ | C | new card; `NSRemindersFullAccessUsageDescription` |
| Automation / Apple Events | ❌ | B (special-folder path fallback, **opt-in**) | new card; lazy/opt-in only |

No two permission prompts collide; each feature requests its own at onboarding
time, gated behind its feature toggle. Features that need a permission must
degrade gracefully when it is denied (never hard-fail the app).

## Design-system compliance (applies to every feature)

All new UI follows [`design.md`](../../design.md) and the hard rules in
`CLAUDE.md`:

- Use `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`, `MAYNMotionBridge`. No
  ad-hoc colors, dimensions, durations, or springs.
- Product-owned segmented choices use `FunctionSegmentedTabStrip`, never raw
  `.pickerStyle(.segmented)`.
- Tool pages display shortcuts with `ShortcutChip` / `MAYNHotkeyDisplay`; editing
  hotkeys belongs in Settings via `HotkeyRecorder`.
- New tool pages use `FunctionPageShell`; new floating panels follow the
  existing borderless `NSPanel` + SwiftUI pattern
  (`WindowSnapOverlayPanel`, `MiniVoiceHUD`).
- Honor Reduce Motion.

## New targets introduced

Two features add new Xcode targets (via `project.yml` + `xcodegen generate`):

- **F (Dock previews):** none required if built in-app (main app is
  non-sandboxed), but a Screen Recording entitlement/usage string is added.
- **C (Voice Reminders):** an optional **WidgetKit `.appex`** target for the
  desktop/Notification-Center widget (sandboxed, App Group data sharing).
- **B (Finder history):** a **FinderSync `.appex`** target for the in-Finder
  toolbar button (sandboxed, reads the shared `FolderHistoryStore` via App
  Group).

All new extensions communicate with the main app only through the existing App
Group container (`group.com.macallyouneed.shared`).

## Out of scope (explicitly deferred)

Carried over from research as not worth building now:

- Clipboard: AI-chat-over-clips, JavaScript script-plugin engine, LAN sync
  (Plan 2 is skipped indefinitely).
- Loop: matching Loop's *full* action vocabulary (thirds/fourths/cycles/custom
  percentages). We adopt Loop's **UI**, mapped onto our existing
  `WindowAction` set; extending the action set is a separate future effort.
- File Organizer: shipping a bundled visual-LLM; we use native Vision/PDFKit for
  extraction and an LLM only for naming/categorization text.

## Spec → plan → build

Each child spec is self-contained and approved independently. After spec
approval, each feature gets its own implementation plan (via the writing-plans
skill) under `docs/plans/feature-expansion-2026/`. Because the features are
parallelizable, plans can be executed concurrently once S1 and S2 land.
