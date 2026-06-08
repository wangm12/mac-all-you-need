# Dock Hub parity matrix (MAYN vs DockDoor reference)

Behavioral spec only — no GPL source in MAYN.

## Status legend

- `done` — implemented and wired
- `partial` — scaffold or subset
- `excluded` — intentionally not shipped in MAYN
- `todo` — not yet implemented

## Included (parity targets)

| ID | Subsystem | Behavior | MAYN owner | Status |
|----|-----------|----------|------------|--------|
| P01 | Previews | Hover dock icon → window grid | `DockPreviewHoverContainer` + `DockPreviewDimensionEngine` | done |
| P02 | Previews | Cache-first show, async merge | `DockPreviewCoordinator` | done |
| P03 | Previews | fittingSize, expectedContentSize, animated frame | `DockPreviewPanel` + `DockPreviewPanelLayoutEngine` | done |
| P04 | Previews | Traffic lights, raise on click | `DockPreviewTrafficLightButtons` | done |
| P05 | Previews | Live preview + panel open/close lifecycle | `DockPreviewLiveCaptureManager` | done |
| P06 | Previews | Scroll edge fade, flow grid chunks | `DockPreviewScrollFade` + dimension engine | done |
| P07 | Previews | Frame-aware dismissal + icon transition preserve | `DockPreviewDismissalView` | done |
| P08 | Previews | DockDoor card chrome (blur, embedded controls, dynamic frame) | `DockPreviewWindowCard` + `DockPreviewHoverChrome` | done |
| P09 | Previews | Control position / title visibility settings | `DockPreviewAppearanceTypes` + `DockPreviewAppearanceContext` | done |
| W01 | Widgets | Folder embedded in hover panel | `Widgets/Folder/DockFolderWidget*` | done |
| W02 | Widgets | Media embedded (Now Playing + transport + lyrics) | `Widgets/Media/` + `DockMediaRemoteService` | done |
| W03 | Widgets | Calendar embedded (EventKit) | `Widgets/Calendar/DockCalendarWidgetView` | done |
| S01 | Switcher | Global hotkey session + shared panel | `DockKeybindController` | done |
| S02 | Switcher | Search + cycle selection | `DockPreviewSearchBar` + `DockPreviewSearchWindow` | done |
| S03 | Switcher | Edge-scroll while hovering panel | `DockPreviewHoverContainer` | done |
| C01 | Cmd+Tab | Enhance while Cmd held | `DockCmdTabController` + shared panel | done |
| L01 | Dock lock | Multi-monitor zones | `DockLockingController` | done |
| I01 | Indicator | Active app underline | `DockActiveIndicatorController` | done |
| A01 | Appearance | Dynamic sizing, animations, padding keys | `DockPreviewSettings` | done |
| I02 | Interactions | Full-size hover overlay | `DockPreviewFullSizeOverlay` | done |
| I03 | Interactions | Windowless app card | `DockPreviewWindowlessCard` | done |
| I04 | Interactions | Drag ghost between apps | `DockDragPreviewCoordinator` | done |
| G01 | Gestures | Dock scroll on icon | `DockGestureController` | done |
| G02 | Gestures | Title-bar scroll resize | `DockTitleBarScrollController` | done |
| G03 | Gestures | Trackpad swipe in preview | `DockPreviewTrackpadGestureModifier` | done |
| G04 | Gestures | Middle-click / Aero-shake on preview | `DockPreviewInteractionGestures` | done |
| F01 | Filters | App / window title filters | `DockSettingsTabCustomizations` + `DockPreviewWindowFilter` | done |
| F02 | Filters | Custom app directories | `DockSettingsTabCustomizations` + `DockAppDiscovery` | done |
| F03 | Filters | Widget app filters | `DockPreviewEmbedRouting` + settings UI | done |
| X09 | Pinning | Pinnable media/calendar | `DockPinnedWindowController` | done |
| FH01 | Finder bridge | Dock folder → Browse + History | `DockFolderWidgetActions` | done |

## Excluded (not shipped)

| ID | Subsystem | Behavior | Reason |
|----|-----------|----------|--------|
| X01 | Shell | Menu bar icon, onboarding, settings search shell | MAYN uses main-window Dock page |
| X06 | Support | Permissions/updater/donation surfaces | Overview tab covers TCC only |
| X07 | Automation | AppleScript command surface | Product choice — no external automation API |
| X10 | Visual | GPL FluidGradient / NSGlassEffectView verbatim | License |
| X11 | Product | DockDoor Pro replacement dock | Separate product |

## Manual QA (side-by-side with DockDoor)

1. Enable Dock on Dashboard; grant Accessibility + Screen Recording.
2. Hover Safari (2–3 windows) — frosted panel, embedded title pill on thumbnails, icon-to-icon without full dismiss flash.
3. Hover Music — embedded Now Playing row with transport buttons; lyrics in AppleScript mode.
4. Hover Calendar — today's events or permission hint; calendar filter in settings.
5. Hover dock folder — navigate, sort, open items, grant access if needed.
6. Option+Tab — centered panel; optional detached search.
7. Hold Cmd+Tab — preview tracks frontmost app; no fade on dismiss.
8. Reduce Motion — spatial animations respect system setting.
9. 8+ windows — compact list or horizontal scroll with edge fade.
10. Pin media/calendar — panel dismisses; pinned window stays.

## Intentional exclusions (summary)

- Menu-bar-only shell, standalone settings search catalog
- AppleScript / CLI command surface for dock hub
- DockDoor donation/updater UX parity
- Cmd+Tab first-run overlay hints (deferred)
