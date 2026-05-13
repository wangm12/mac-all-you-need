# Main Function Tabs Design Spec

**Status:** Draft approved in chat on 2026-05-12
**Owner:** mingjie-father
**Project:** mac-all-you-need

---

## 1. Problem

The main app window currently mixes product surfaces, history, controls, and settings in the same long function pages. This makes each destination feel like a settings page with some operational content attached. It also makes the app read as a configuration utility instead of a multi-tool product.

The specific failure mode is visible on Clipboard and Voice:

- Clipboard mixes dock controls, shortcut settings, capture rules, paste behavior, and recent history in one scroll view.
- Voice mixes dictation controls, onboarding, activation, language, audio, cleanup, dictionary, app profiles, and MVP history in one scroll view.
- System is a first-level sidebar item even though it is not a product function.

## 2. Product Principle

The main sidebar should represent the app's main tools. Each tool owns its own local child tabs. Global system settings should be a floating configuration surface, not a first-level tool.

This keeps the app model simple:

```text
Main sidebar = product functions
Child tabs = sub-functions inside the selected product function
Floating settings = global app/system configuration
Menu bar = quick command center and deep links
```

## 3. Target Information Architecture

### 3.1 Main Sidebar

Keep:

- Dashboard
- Clipboard
- Voice
- Downloads
- Folder Preview
- Snippets

Remove as a normal sidebar destination:

- System

System moves to a bottom sidebar gear and menu bar settings button. It opens a floating Typeless-style settings window or sheet.

### 3.2 Function Child Tabs

Clipboard:

- History: recent captured items, previews, search entry point, open dock action
- Rules: excluded apps, regex/privacy capture rules, capture behavior
- Settings: shortcut, paste behavior, max items, capture sound

Voice:

- Dictate: start/stop, state, last transcript, setup status, primary shortcut summary
- History: recent transcripts and paste results
- Dictionary: voice dictionary CRUD
- Profiles: per-app cleanup and auto-submit profiles
- Settings: activation mode, shortcut, language, microphone/audio, cleanup provider

Downloads:

- Queue: active queue and add URL
- Completed: completed/failed items and reveal/preview actions
- Settings: concurrency, save location, output template, cookies/downloader status

Folder Preview:

- Browse: folder picker and current browse actions
- Recent: recent folders/archives
- Settings: include hidden files, max entries, display defaults, partial scan behavior

Snippets:

- Library: snippet list, create/edit, quick insert entry points
- Settings: snippet trigger behavior and shortcut hints

### 3.3 Global Settings

Global settings should contain only cross-product/system concerns:

- General
- Permissions
- Privacy
- Storage
- Hotkeys overview
- Advanced
- About

Do not duplicate function-specific settings here unless they are overview/deep-link rows.

## 4. Behavior

### 4.1 Navigation

- Selecting a main sidebar destination opens that product function.
- Each function remembers its last selected child tab using App Group defaults.
- Reopening the app restores the last main destination and each function's last child tab.
- Menu bar actions can deep link to `Voice > Dictionary`, `Clipboard > History`, `Downloads > Queue`, etc.

### 4.2 Settings Access

- Function pages expose local settings as child tabs.
- A gear in the main sidebar footer opens global settings as a floating settings window/sheet.
- Existing `Cmd+,` continues to open global settings.
- Existing calls that set `settings.selectedTab` remain compatible.

### 4.3 Visual Model

- Use a quiet black/white/gray shell.
- Child tabs use a compact segmented control below the page header.
- Tabs are not large cards and do not create nested-card layouts.
- Function pages should default to operational content, not settings.
- Global settings uses a floating modal/sheet like Typeless: sidebar left, detail right, dimmed app behind, close button top-right.

## 5. Non-Goals

- No database migration.
- No behavior changes to clipboard capture, voice dictation, downloader, folder preview, or snippet expansion.
- No new sync behavior.
- No redesign of the clipboard dock itself in this pass.
- No removal of the standalone SwiftUI `Settings` scene until all callers are migrated.

## 6. Acceptance Criteria

- Main sidebar no longer shows System as a product function.
- Each product function has child tabs and no longer mixes history with settings in one long page.
- Voice Dictionary is a first-class Voice child tab.
- Clipboard recent history is the default Clipboard child tab.
- Global settings opens as a floating surface from the sidebar footer gear, menu bar gear, and `Cmd+,`.
- Existing settings keys remain compatible.
- No clipped controls at the default `980x680` main window size.
- Build and targeted tests pass.

