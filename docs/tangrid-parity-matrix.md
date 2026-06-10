# Tangrid parity matrix (MAYN vs Tangrid v1.2.4)

Behavioral spec comparing [Tangrid](https://docs.tangrid.app/) against Mac All You Need window + dock surfaces.
DockDoor parity is tracked separately in [`dock-parity-matrix.md`](./dock-parity-matrix.md).

## Status legend

- `done` — implemented and wired
- `partial` — subset or scaffold
- `todo` — planned, not yet shipped
- `deferred` — intentionally out of scope (Phase C or product choice)
- `excluded` — will not ship

## Dock & switcher

| ID | Feature | Tangrid | MAYN owner | Phase | Status |
|----|---------|---------|------------|-------|--------|
| T01 | Dock hover preview | Yes | `DockPreviewCoordinator` | — | done |
| T02 | Multi-window-only preview | Yes | `ignoreSingleWindowApps` | — | done |
| T03 | Overlay Dock tooltip | Yes | `DockPreviewTooltipOverlay` | A | done |
| T04 | Dock icon click behavior | Yes | `hideAllOnDockClick` + `dockClickAction` | — | done |
| T05 | Window switcher (global hotkey) | Yes | `DockKeybindController` | — | done |
| T06 | Vertical searchable switcher | Yes | `DockSwitcherVerticalListView` | A | done |
| T07 | Preview at original position | Yes | `DockSwitcherOriginalPositionOverlay` | A | done |
| T08 | Sticky window switching | Yes | `stickyWindowSwitching` | A | done |
| T09 | Cmd+Tab enhancement | Yes | `DockCmdTabController` | — | done |
| T10 | Cmd+Tab first-run hints | Yes | `DockCmdTabFocusOverlayView` | A | done |
| T11 | Cursor auto-center on focus | Yes | `cursorAutoCenterOnFocus` | A | done |
| T12 | Active app Dock indicator | Yes | `DockActiveIndicatorController` | — | done |
| T13 | Folder/Media/Calendar widgets | No | Dock widgets | — | done (MAYN extra) |

## Window management

| ID | Feature | Tangrid | MAYN owner | Phase | Status |
|----|---------|---------|------------|-------|--------|
| W01 | Keyboard snap (halves, corners, etc.) | Yes | `WindowMover` + hotkeys | — | done |
| W02 | Modifier-drag anywhere | Yes | `WindowGrab` / event tap | — | done |
| W03 | Edge snap on drag | Yes | `WindowSnapOverlayPanel` | — | done |
| W04 | Snap Assist candidate zones | Yes | `SnapAssistZoneController` | B | done |
| W05 | Active window border | Yes | `ActiveWindowBorderController` | B | done |
| W06 | Move to next/prev Space | Yes | `WindowSpaceMover` | B | done |
| W07 | Move to Screen | Yes | `nextDisplay` / `previousDisplay` | — | done |
| W08 | Window rules (bundle + title) | Yes | `WindowRulesEngine` | B | done |
| W09 | Ignored apps | Yes | `ignoredBundleIDs` | — | done |
| W10 | Sequoia tiling conflict mitigation | Yes | `WindowControlPrivateAPI` | B | done |
| W11 | Modifier + scroll resize | Yes | `WindowScrollResizeController` | B | done |
| W12 | Animated window moves | Yes | `animateWindowMoves` | B | done |
| W13 | Hidden settings UI exposure | — | `WindowControlSettingsView` | B | done |
| W14 | Radial snap menu | No | `RadialMenuCoordinator` | — | done (MAYN extra) |

## Platform & large programs

| ID | Feature | Tangrid | MAYN owner | Phase | Status |
|----|---------|---------|------------|-------|--------|
| P01 | Shared CGS/SkyLight seam | Yes | `WindowServerPrivateAPI` | D | done |
| P02 | BSP Auto Flow tiling | Yes | `BSPAutoFlowSpike` | C | spike |
| P03 | Workspace launch/save | Yes | — | C | deferred |
| P04 | Stage Manager disable | Yes | — | C | deferred |

## Manual QA (Tangrid side-by-side)

1. Bottom-docked macOS Dock: hover Safari — preview panel covers Dock tooltip when overlay enabled.
2. Option+Tab switcher: enable preview-at-original-position — border tracks selected window frame.
3. Sticky switching: commit one window while holding modifier — panel stays open for next pick.
4. Vertical list switcher: search auto-focuses; arrow keys cycle rows.
5. Window Layouts: snap Assist zones appear during Option+drag near screen center.
6. Active window border: frontmost window shows inner/outer highlight.
7. Move to next Space hotkey moves focused window (requires separate Spaces enabled).
8. Window rule: exclude app by bundle ID from snap shortcuts.
9. Reduce Motion: all new overlays respect system setting.
