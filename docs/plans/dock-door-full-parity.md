# DockDoor full parity — implementation checklist

Living checklist for Dock Hub vs DockDoor reference + Finder integration.  
Spec matrix: [`../dock-parity-matrix.md`](../dock-parity-matrix.md).

## Out of scope

- AppleScript / CLI automation surface
- Standalone menu-bar-only app shell
- GPL FluidGradient verbatim port
- DockDoor Pro clone

## Phases

| Phase | Focus | Status |
|-------|--------|--------|
| 0 | Reconcile `dock-parity-matrix.md` | done |
| 1 | Folder dock widget (model, bookmarks, panel UI) | done |
| 2 | Media (lyrics, universal mode, pin dismiss, big controls) | done |
| 3 | Calendar (filter, skeleton, pinned lifecycle) | done |
| 4 | Filters (custom app dirs, widget filters UI) | done |
| 5 | Gestures (middle-click, aero-shake, drag drop) | done |
| 6 | Finder bridge (browse, history upsert) | done |
| 7 | QA + tests + defaults | done |

## Manual QA

1. Dock folder: navigate subfolders, sort, open file, grant access on protected path.
2. Music/Spotify: transport, lyrics (AppleScript mode), pin dismisses hover panel.
3. Calendar: filtered calendars, permission CTA.
4. Option+Tab + Cmd+Tab unchanged.
5. Folder History: “Browse in Mac All You Need” from dock folder row menu.
