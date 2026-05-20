# Mac All You Need UI Audit Prototype And Improvement Plan

## Summary

Build a debug-only UI Audit Gallery that can render representative primary, transient, modal, and stateful Mac All You Need screens with sanitized demo data. Use it to drive Computer Use screenshot capture, produce a manifest/index, and turn findings into a prioritized UI backlog.

The prototype must not touch live clipboard history, transcripts, downloads, browser cookies, API keys, real permissions, model installs/deletes, resets, or user files.

The first deliverable is a reliable, privacy-safe capture harness. Visual redesign and settings refactors are backlog output from the audit, not part of the first harness milestone.

## Non-Goals For The First Milestone

- Do not redesign product screens while building the harness.
- Do not deduplicate settings implementations as part of the capture prototype.
- Do not make the gallery a user-facing feature.
- Do not require live app permissions, live App Group data, real keychain secrets, browser cookies, or installed model assets.
- Do not attempt full inventory coverage before proving the capture workflow with a small scenario set.

## Key Changes

- Add a debug-only launch mode: `MAYN_UI_AUDIT=1`.
  - Branches before normal `AppController` side effects start.
  - Opens a UI Audit Gallery window through an audit-specific boot path, such as `AuditAppController`, instead of normal user data surfaces.
  - Seeds a temporary demo profile through `MAYN_APP_GROUP_CONTAINER_OVERRIDE`.
  - Adds a separate UserDefaults suite override so demo settings do not fall back to `.standard`.
  - Stubs or disables live-only services: daemon registration, login item mutation, global hotkeys, event taps, DispatchServer, XPC connections, keychain reads, permission prompts/probes, pasteboard writes, file panels, model installs/deletes, downloader execution, and browser cookie import.
- Add an `AuditSurfaceCatalog` with stable scenario IDs.
  - First milestone covers 15-25 high-value scenarios, then expands toward full inventory.
  - Include main window tabs, Command Center tabs, representative paste panel states, dock tabs, key overlays, onboarding/permission states, Downloads states, Folder Preview states, voice HUD states, and representative sheets/dialogs in view-only mode.
  - Each scenario records: screen ID, surface, route/action path, state, native rendering mode, sensitivity risk, expected redactions, screenshot filename, capture status, and `notCapturedReason` when skipped.
- Add a `DemoDataProfile`.
  - Clipboard items: text, code, URL, image, file, color, multi-item copy.
  - Pinboards/snippets: several lists, selected states, empty states, edit states.
  - Voice: sanitized transcripts, dictionary entries, personalization profiles, model states, all HUD states.
  - Downloads: empty, queued, running, paused, failed, completed, invalid URL, no video URL.
  - Folder Preview: empty folder, normal folder, large folder, archive, loading/analyze states.
  - Feature runtime: enabled, disabled, not-installed, downloading, install-failed dashboard variants.
- Add debug state drivers for transient UI.
  - `CopyHUD`, `AutoDownloadHUD`, and all `MiniVoiceHUD.State` variants.
  - Dock transform menu, Quick Look overlay, cheatsheet, card context menu, rename sheet, snippet create/edit overlay, new list sheet.
  - Onboarding step forcing for main onboarding and all 9 voice onboarding steps.
  - Permission provider mocks for granted, denied, not determined, restricted, and instruction-panel states.

## Native Surface Strategy

Some surfaces are not pure SwiftUI pages and should be classified explicitly before capture:

- `native-isolated`: render the real AppKit/window surface in audit mode with mocked dependencies.
- `simulated-equivalent`: render an equivalent SwiftUI/AppKit view when the true system surface cannot be safely opened.
- `manual-only`: record a manifest entry and `notCapturedReason` when automation would be unreliable or unsafe.

Menu-bar popovers, global HUD windows, Quick Look extension states, file panels, context menus, and destructive sheets should each declare one of these modes. The plan should not assume every surface can be embedded inside one SwiftUI gallery window.

## Phase Plan

### Phase 0: Boot Guard And Privacy Harness

- Detect `MAYN_UI_AUDIT=1` before constructing normal app services.
- Route into audit-only composition and block normal background behavior.
- Create a temporary app-group container and isolated defaults suite.
- Add keychain, permission, pasteboard, downloader, browser-cookie, and file-system test doubles where needed.
- Verify the audit app can launch without reading or writing live state.

### Phase 1: Gallery MVP

- Add `AuditSurfaceCatalog`, scenario metadata, and manifest generation.
- Render 15-25 high-value scenarios:
  - Dashboard and main function tabs.
  - Command Center tabs.
  - Clipboard Dock tabs and one selected/multi-select state.
  - Downloads empty, running, failed, and completed states.
  - Snippets list and edit/create state.
  - MiniVoiceHUD states.
  - One permission/onboarding path.
  - One destructive dialog in view-only mode.
- Generate `index.md` and screenshots for the MVP set.

### Phase 2: Coverage Expansion

- Add remaining onboarding steps, all voice onboarding steps, more permission states, Folder Preview states, lifecycle sheets, overlay menus, and destructive dialogs.
- Add explicit exclusions with `notCapturedReason` for surfaces that are not worth automating.

### Phase 3: Variant Passes

- Capture targeted second-pass variants only where layout is likely to break:
  - Dark mode.
  - Reduced motion.
  - Narrow window sizes.
  - Dense data states.

### Phase 4: UI Backlog

- Review screenshots and convert findings into prioritized UI issues.
- Keep implementation of redesign/refactor work separate from the capture harness.

## Expected UI Backlog Themes

These are likely follow-up improvements after the audit produces screenshots. They should not block the first harness milestone.

### P0: Privacy-Safe Capture Harness

- Isolate defaults and data fully before screenshots.
- Block live-history routes unless `MAYN_UI_AUDIT=1` is active with seeded data.
- Every uncaptured sensitive surface gets an explicit manifest reason.

### P1: Settings Deduplication

- Make tool-page Settings tabs the primary home for feature-specific settings.
- Keep global Settings focused on General, Permissions, Storage, Advanced.
- Extract shared reusable settings content for Clipboard, Voice, Downloads, Folder Preview, Snippets, and Window Control so duplicated rows cannot drift.
- Resolve `clipboardMaxItems` vs `retention.maxItems`: Storage owns retention deletion limits; Clipboard only owns capture/paste behavior unless a distinct history cap is actually used.

### P1: Capture Completeness And Product Polish

- Make Command Center footer actions less crowded and show visible feedback for Pause 60s.
- Give Folder Preview a richer main page: current status, Browse Folder action, and preview-mode examples instead of a settings-only feel.
- Improve empty/loading/error states for Downloads, Snippets, Clipboard, Voice History, and Folder Preview with one clear primary action.
- Standardize transient overlay chrome across CopyHUD, AutoDownloadHUD, dock overlays, and voice terminal states.

### P2: Calm Pro Utility Refinements

- Tighten page density where pages feel sparse, especially Folder Preview and some status-only sections.
- Use consistent status language across Dashboard, Command Center, settings cards, and HUDs.
- Reduce modal friction in onboarding by keeping advanced cleanup/provider choices optional and skippable.
- Make shared Window Layouts / Window Grab settings visibly shared instead of repeated as two separate-feeling pages.

### P3: Feel-Better Details

- Add clearer selected-count and target-list feedback in the paste panel.
- Improve snippet creation from clipboard with a preview before save.
- Add better inline validation to Add URL and custom download filename patterns.
- Polish microcopy for permission repair, failed downloads, no speech, and invalid URL states.

## Capture Workflow

- Capture to `artifacts/ui-audit/YYYY-MM-DD-HHMM/`.
- Generate `manifest.json` and `index.md`.
- For every inventory item, record either a screenshot entry or `notCapturedReason`.
- Record reproducibility metadata for every capture:
  - `gitSha`
  - build configuration
  - app version/build number when available
  - scenario ID
  - data profile ID
  - color scheme
  - window size
  - reduced motion setting
  - native rendering mode
  - sensitivity risk
  - expected redactions
  - screenshot filename
  - capture status
  - stability/wait hint
- Use Computer Use to navigate the Audit Gallery, open each scenario, wait for stable state, screenshot, and update the manifest.
- Do second-pass captures in dark mode, reduced motion, and narrow window sizes only for surfaces likely to break layout.

## Test Plan

- Unit-test audit boot routing: `MAYN_UI_AUDIT=1` uses the audit composition and does not construct live services.
- Unit-test the audit catalog: every required inventory item has a scenario or explicit exclusion.
- Unit-test demo defaults isolation: container override and defaults suite do not read/write live app settings.
- Unit-test sensitive-service guards: audit mode cannot invoke live pasteboard writes, keychain reads, downloader execution, browser-cookie import, model deletes, or reset confirmations.
- Unit-test settings dedup mappings: each setting key has exactly one owner and any duplicate surface reuses shared content.
- Existing UI presentation tests stay passing for `FunctionTabs`, `SettingsDestination`, `MiniVoiceHUD`, downloads rows, and window-control settings.
- Manual Phase 1 acceptance: screenshot index includes the MVP scenario set, manifest entries have reproducibility metadata, and skipped sensitive surfaces have explicit reasons.
- Manual full-coverage acceptance: screenshot index includes each main tab, Command Center tab, dock tab, onboarding step, voice HUD state, major sheet/dialog, and notification family.

## Assumptions

- Prototype code is `#if DEBUG` or launch-argument gated and does not ship as a normal user-facing feature.
- Destructive flows are view-only: reset, uninstall, model delete, sideload install, cache cleanup, and clear-history dialogs are opened but not confirmed.
- The first implementation goal is reliable capture coverage for a small scenario set; broader visual redesign happens after the screenshot audit identifies the highest-impact gaps.
- Full inventory coverage is useful only after the privacy harness and manifest workflow are proven.
