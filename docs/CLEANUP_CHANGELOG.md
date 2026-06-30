# Cleanup & optimization changelog (2026-06-28)

Behavior-preserving maintenance pass. See the approved plan for full audit notes.

## Phase 1 — Safe cleanup

- Removed dead helpers from `MainWindowRoot.swift` (`MainHeaderToolbar`, `MainPage`, `MainStatusRow`).
- Removed unused `SearchFilterSubModel.loadPinned`.
- Deleted unreferenced `scripts/export-ui-html-symbols.swift`.
- Replaced empty `catch {}` blocks in downloader UI with documented fallbacks + logging.

## Phase 2 — Repo cleanup

- Stopped tracking `reference-projects/` and `docs/mayn-ui-capture.zip` (files remain on disk; paths are gitignored).

## Phase 3 — Build & packaging

- Added explicit Release strip settings in `project.yml` (`DEAD_CODE_STRIPPING`, `STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE`).
- Deduplicated `yt-dlp`/`ffmpeg` between main app and `DownloadDaemon` via App Group `binaries/` + `BinaryManager.installSharedBinariesIfNeeded`.
- Removed DownloadDaemon post-build binary copy script; added a cleanup script that strips stale copies from daemon `Resources/`.
- **Measured:** Release `.app` 547 MB → 363 MB (~184 MB saved); `DownloadDaemon.app` 198 MB → 15 MB.

## Phase 4 — Dependencies

- Removed unused **Splash** dependency from `Shared/Package.swift` `UI` target.
- Removed dead `mlxExperimental` local ASR catalog slot.

## Phase 5 — Duplicate code

- Added `DownloadCookieConfiguration` (Platform) and routed coordinator/view-model cookie paths through it.
- Centralized `YtdlpProcessHelpers.findNode()` in Core.
- Added shared `String.nilIfEmpty` in Core; removed per-file private copies.
- Added `MAYNByteCountFormatting` for cache-cleanup sheets.
- `DownloaderFeatureActivator` no longer allocates a second `DownloadCoordinator` in the main app (daemon/test mode unchanged).

## Phase 6 — Best practices

- Added `os.Logger` diagnostics at silent process-launch fallback sites in downloader UI.

## Phase 7 — Documentation

- Updated README, CLAUDE.md, AGENTS.md, and MacAllYouNeed/CLAUDE.md for current Command Center tabs and target layout.
- Documented bundle size budget and shared-binary strategy in README.

## Not changed (approval-gated)

- Semantic embedding write-only pipeline (toggle vs ranking reader).
- `RemindersWidget` embed / `mayn://reminders` deep links.
- Entitlements, signing profiles, and notarization scripts.
