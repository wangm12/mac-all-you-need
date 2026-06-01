# Dock Hub parity matrix (MAYN vs DockDoor reference)

Behavioral spec only — no GPL source in MAYN. Out of scope: WindowAction pickers, user filters tab, AppleScript, FluidGradient verbatim.

## Status legend

- `done` — implemented and wired
- `partial` — scaffold or subset
- `todo` — not yet implemented

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
| W01 | Widgets | Folder embedded in hover panel | `Widgets/Folder/DockFolderWidgetView` | done |
| W02 | Widgets | Media embedded (Now Playing + transport) | `Widgets/Media/` + `DockMediaRemoteService` | partial |
| W03 | Widgets | Calendar embedded (EventKit) | `Widgets/Calendar/DockCalendarWidgetView` | partial |
| S01 | Switcher | Global hotkey session + shared panel | `DockKeybindController` | done |
| S02 | Switcher | Search + cycle selection | `DockPreviewSearchBar` + `DockPreviewSearchWindow` | done |
| S03 | Switcher | Edge-scroll while hovering panel | `DockPreviewHoverContainer` | done |
| C01 | Cmd+Tab | Enhance while Cmd held | `DockCmdTabController` + shared panel | done |
| L01 | Dock lock | Multi-monitor zones | `DockLockingController` | done |
| I01 | Indicator | Active app underline | `DockActiveIndicatorController` | done |
| G01 | Gestures | Dock scroll in dock band | `DockGesturesRuntime` | done |
| G02 | Gestures | Trackpad swipe in preview | `DockPreviewTrackpadGestureModifier` | done |
| A01 | Appearance | Dynamic sizing, animations, padding keys | `DockPreviewSettings` | done |
| I02 | Interactions | Full-size hover overlay | `DockPreviewFullSizeOverlay` | done |
| I03 | Interactions | Windowless app card | `DockPreviewWindowlessCard` | done |
| I04 | Interactions | Drag ghost (subset) | `DockPreviewDragCoordinator` | partial |

## Manual QA (side-by-side with DockDoor)

1. Enable Dock Previews on Dashboard; grant Accessibility + Screen Recording.
2. Hover Safari (2–3 windows) — frosted panel, embedded title pill on thumbnails, icon-to-icon without full dismiss flash.
3. Hover Music — embedded Now Playing row with transport buttons.
4. Hover Calendar — today’s events or permission hint.
5. Hover dock folder — file list in same panel.
6. Option+Tab — centered panel; optional detached search (`detachedSwitcherSearch` in preview settings).
7. Hold Cmd+Tab — preview tracks frontmost app; no fade on dismiss.
8. Reduce Motion — spatial animations respect system setting.
9. 8+ windows — compact list or horizontal scroll with edge fade.
10. Dock scroll gesture — enable in Dock hub gestures; scroll over dock band posts switch notification.

## Intentional exclusions

- WindowAction enum / middle-click / swipe action pickers / aero-shake picker
- Filters settings (app name, window title, custom app dirs)
- AppleScript command surface
- GPL FluidGradient / liquid-glass NSGlassEffectView verbatim port
- Pinnable media/calendar full windows (deferred)
- Cmd+Tab first-run overlay hints (deferred)
