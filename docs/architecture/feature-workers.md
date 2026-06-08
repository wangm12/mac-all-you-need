# Feature workers architecture

Each dashboard feature (`FeatureID`) can own a **background worker** (Swift `actor` or serial
`DispatchQueue`) for CPU/IO. UI coordinators stay on **`@MainActor`**.

## Rules

### Must stay on the main actor / main run loop

- AppKit: `NSPanel`, `NSHostingView`, dock carousel, voice HUD, paste into `NSPasteboard`
- `CGEventTap` and `AXObserver` run-loop sources (see `AXObserverEngine`)
- SwiftUI observable model mutations (`ClipboardDockModel`, `DockPreviewCoordinator`)

### Safe on feature workers

- GRDB reads/writes through existing `DatabaseQueue` APIs (`ClipboardStore`, `SearchStore`)
- FTS5 queries (`SearchStore.search`)
- Clipboard history dedup, fuzzy ranking, smart-operator predicates on value types
- Dock window enumeration, `purify`, thumbnail capture scheduling, JPEG disk I/O
- Voice ASR (existing actors), download job orchestration (existing `DownloadQueue` actor)

### Shared databases (do not open duplicate queues)

| File | Owner |
|------|--------|
| `databases/clipboard.sqlite` | Single `ClipboardStore` per process |
| `databases/search.sqlite` | Single `SearchStore` per process |

Workers receive store references at construction; they never create second connections.

### Process boundaries

- **ClipboardDaemon** remains a separate process with `PerFeatureWorkerHost` for pasteboard capture.
- Main app `AppFeatureWorkerHost` mirrors start/stop per enabled feature.

## Registry

`AppFeatureWorkerHost` (`MacAllYouNeed/App/Workers/`) is wired from `FeatureRuntime` on
enable/disable. `ClipboardWorker` is shared by `.clipboard` and `.clipboardSmartText`.

## Observability

`PerformanceSignpost` (`Shared/Sources/Core/PerformanceSignpost.swift`) wraps clipboard
history loads and dock capture refresh in Instruments (os_signpost). Use the
**Points of Interest** instrument to compare main-thread time while dock hover and
clipboard search run concurrently (target: p95 main-thread stalls under 16ms).

## Integration hooks

| Surface | Hook |
|---------|------|
| Browse Folder | `FolderPreviewListing.install` → `FolderPreviewFeatureWorker.enumerate` |
| AI File Organizer | `FileOrganizerCoordinator` extraction via `OrganizerFeatureWorker.perform` |
| Window Layouts settings | **Copy diagnostics** → `WindowControlFeatureWorker.formatDiagnosticsReport` |
| Clipboard dock / main window | `ClipboardWorker` (skip duplicate in-memory ranking; `AppIconResolver.prefetch`) |
| Dock thumbnails | `DockPreviewWorker.hydrateEntries` only — no sync disk read in LRU cache |

## Worker map (main app)

| `FeatureID` | Worker | Notes |
|-------------|--------|--------|
| `.clipboard`, `.clipboardSmartText` | `ClipboardWorker` | FTS, dedup, fuzzy/smart ranking |
| `.dockPreviews` | `DockPreviewWorker` | Disk hydrate, window enumeration |
| `.downloader` | `DownloadFeatureWorker` | Facade; jobs stay in `DownloadQueue` |
| `.voice`, `.voiceReminders` | `VoiceFeatureWorker` | Retention sweeps; ASR stays in coordinator |
| `.folderPreview` | `FolderPreviewFeatureWorker` | Listing hook for browse/analyze |
| `.folderHistory` | `FolderHistoryFeatureWorker` | GRDB upsert + eviction |
| `.windowLayouts`, `.windowGrab` | `WindowControlFeatureWorker` | Diagnostics only |
| `.aiFileOrganizer` | `OrganizerFeatureWorker` | Serializes scan/LLM I/O |

## Adding a new worker

1. Implement `FeatureWorker` (`start`/`stop` idempotent).
2. Register in `AppFeatureWorkerHost.startWorker(for:)` / `stopWorker(for:)`.
3. Post `Sendable` results to the feature’s `@MainActor` coordinator only.
