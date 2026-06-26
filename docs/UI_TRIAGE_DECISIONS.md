# UI Triage Decisions (Phase 0)

Decisions for the Mayn UI Improvement Plan. Do not edit the plan file; this document is the checked-in record.

## Orphan / legacy files

| File | Decision |
|------|----------|
| `StorageSettingsView.swift` | **Keep and wire** — add to Settings System group as Storage destination when Advanced expands. |
| `OrganizerHistoryView.swift` | **Keep** — restyle monochrome; wire from File Organizer History tab in a follow-up. |
| `SnippetsPopoverView.swift` | **Keep** — main-window Snippets library (`SnippetsListView`); not a Command Center tab. |
| `PermissionStepViews.swift` (`WelcomeStep`) | **Keep** — legacy helper; no router change. |
| `MicrophoneStepView` / `AccessibilityStepView` | **Keep** — not in active 7-step voice router; restyle only if touched. |

## Color exception policy (DESIGN.md §3.1)

| Surface | Policy |
|---------|--------|
| External app icons | **Keep** full color (small, secondary). |
| File / media thumbnails | **Keep** full color. |
| Voice provider brand logos | **Keep** asset logos; SF Symbol fallbacks stay monochrome. |
| ClipCard per-app accent | **Keep** — 12-color palette + known bundle IDs + `AppIconColor` fallback for card/header tint. |
| NewListSheet hex pinboard swatches | **Collapse** to grayscale swatches. |
| `AppIconColor` dynamic extraction | **Keep** for clipboard card accent when bundle ID is unknown. |
| MiniVoiceHUD graphite RGB | **Keep** documented HUD exception for legibility over arbitrary desktops. |
| Radial / active window border blue | **Remove** — monochrome 12–18% fill. |
| Dashboard / onboarding feature RGB accents | **Remove** — monochrome icons only. |

## Scope exclusions

| Surface | Policy |
|---------|--------|
| `UIAuditGalleryView` | Dev-only; out of redesign scope. |
| Quick Look extension (`FolderPreview/`) | Restyle hairlines/typography only; AppKit constraints apply. |
