# Mayn UI Improvement Plan

This plan turns the current MacAllYouNeed / Mayn UI from a functional SwiftUI prototype into a polished black-and-white native macOS command layer.

The current app already has the right feature set: clipboard history, voice, downloads, AI file organizer, enhanced Finder, window layouts, window grab, windows hub, permissions, settings, onboarding, and runtime surfaces. The main issue is visual direction: the UI currently looks like a default SwiftUI settings app with many independent feature pages. The target is a unified monochrome system utility with premium runtime overlays.

---

## 1. Product-level UI Diagnosis

### Current visual problems

1. Too much default SwiftUI appearance.
   - Default segmented controls, default green toggles, default list rows, default rounded cards.
   - This makes the app feel unfinished even when the functionality is strong.

2. Color is used inconsistently.
   - Dashboard feature cards use blue, purple, green, orange borders or icons.
   - Voice uses green/orange/red status pills.
   - Downloads uses colored filters and warning backgrounds.
   - Window radial preview uses blue highlight.
   - Target should be black-white-grayscale first.

3. Feature hierarchy is unclear.
   - Dashboard shows many feature cards of equal weight.
   - Large numbers such as `30` or `400` appear without enough context.
   - Users need to know: what is active, what needs permission, what shortcut to use, what happened recently.

4. Runtime surfaces are more important than the main app, but not yet treated as premium.
   - Clipboard Dock, Voice HUD, Window Hub, Radial Layout, Copy HUD, and Permission panels should be the most polished surfaces.
   - The current UI focuses too much on settings pages.

5. Page structure varies too much.
   - Clipboard, Voice, Downloads, Windows, and Settings use similar elements but not a shared visual system.
   - The app needs shared header, search, tab, card, list, settings row, HUD, toast, and keycap components.

6. Motion has no unified standard.
   - Overlays, tabs, cards, and toasts should share timing, easing, and reduced-motion behavior.

---

## 2. Target Experience

Mayn should feel like this:

```text
A black-and-white native macOS command layer.
It sits quietly in the background.
When called, it responds instantly.
Every screen is compact, legible, keyboard-first, and visually consistent.
```

Visual references to internalize:

- Vercel-like monochrome precision
- Raycast-like command palette and runtime utility feeling
- Linear-like dark surface discipline and dense lists
- Apple System Settings-like native trust and grouped rows
- Finder-like sidebar and file list familiarity

Do not copy any single reference literally. Use the shared pattern: monochrome, precise hierarchy, compact interaction, premium motion.

---

## 3. Global Redesign Priorities

### P0: Establish one monochrome design system

Create shared design primitives before polishing individual pages.

Deliverables:

- `MaynColor.swift`
- `MaynSpacing.swift`
- `MaynRadius.swift`
- `MaynTypography.swift`
- `MaynMotion.swift`
- `MaynButtonStyle.swift`
- `MaynCard.swift`
- `MaynKeycap.swift`
- `MaynStatusPill.swift`
- `MaynSearchField.swift`
- `MaynSegmentedTabs.swift`
- `MaynSettingsRow.swift`
- `MaynHUDContainer.swift`
- `MaynToast.swift`

Acceptance criteria:

- No normal UI component uses `.blue`, `.green`, `.purple`, `.orange`, or `.red` directly.
- All feature icons are monochrome except external app/file icons.
- Active states use black-white inversion.
- Toggles are monochrome or intentionally native only where customization is risky.

### P0: Redesign app shell

Current shell is usable but generic. It needs a more intentional macOS utility layout.

Target shell:

```text
┌────────────────────────────────────────────────────────────┐
│ traffic lights   Mayn         Search Mayn...        Status │
├────────────────┬───────────────────────────────────────────┤
│ Sidebar        │ Page header                               │
│ grouped nav    │ Shared tabs/filter/search                 │
│                │ Feature-specific content                  │
└────────────────┴───────────────────────────────────────────┘
```

Specific changes:

- Sidebar width: 220 px.
- Toolbar height: 56 px.
- Add global command search field in the toolbar: `Search actions, history, files, windows...` with `⌘K` keycap.
- Add a compact runtime indicator on the right: `Ready`, `Listening`, `Organizing`, or `Needs permission`.
- Group sidebar items into Core, Automation, Windows, System.
- Replace colorful nav icons with 16 px monochrome stroke icons.
- Selected sidebar item: black fill / white text in light mode; white fill / black text in dark mode.

### P0: Redesign runtime overlays first

The main app can be minimal, but runtime surfaces must feel premium.

Runtime surface order:

1. Command Palette
2. Window Hub floating panel
3. Voice HUD
4. Clipboard Dock
5. Radial Layout overlay
6. Toast / Copy HUD
7. Permission helper panel

Reason: these surfaces define how users experience Mayn during real work.

---

## 4. Shared Components to Build

### 4.1 `MaynPageHeader`

Current issue:

- Page headers exist but are not visually consistent.
- Shortcut chips float differently across pages.

Target:

```text
Clipboard                                      ⌘ ⇧ V
Search copied text, links, images, and files.
```

Specs:

- Title: 28 px, semibold.
- Subtitle: 13 px, secondary.
- Right side: shortcut chip or primary action.
- Bottom spacing: 20-24 px.
- Optional divider when followed by tabs.

Use on:

- Dashboard
- Clipboard
- Voice
- Downloads
- AI File Organizer
- Enhanced Finder
- Window Layouts
- Window Grab
- Windows Hub
- Settings

### 4.2 `MaynSegmentedTabs`

Current issue:

- Default segmented controls look system-generic and bulky.
- Selected tabs use gray system fill but lack premium intent.

Target visual:

```text
[ History ] [ Snippets ] [ Settings ]
```

Specs:

- Height: 36 px.
- Outer radius: 12 px or pill.
- Outer border: hairline.
- Selected segment: black fill / white text.
- Unselected text: secondary.
- Icons optional, 13 px monochrome.
- Animation: selected background slides 160 ms.

Use on:

- Clipboard: History / Snippets / Settings
- Voice: History / Recognition / Dictionary / Personalization / Settings
- Downloads: Downloads / Settings
- Window Layouts: Shortcuts / Radial / Snap / Ignored Apps / Rules / Diagnostics

### 4.3 `MaynSearchField`

Current issue:

- Search fields are present but feel like normal form fields.
- Search should be a primary interaction pattern.

Target visual:

```text
[ magnifier  Search clipboard...                         983 items ]
```

Specs:

- Height: 38 px.
- Background: subtle panel.
- Border: hairline.
- Radius: 12 px.
- Focus: 2 px monochrome ring.
- Right metadata: item count, filter count, or keycap.

Use on:

- Clipboard History
- Clipboard Dock
- Downloads
- Enhanced Finder
- Windows Hub
- Command Palette

### 4.4 `MaynStatusPill`

Current issue:

- Status uses color-coded chips: success green, cancelled orange, failed red.
- This breaks the black-white direction.

Target status system:

| Status | Visual |
|---|---|
| Ready | filled black / white text |
| Active | filled black + pulsing dot |
| Granted | filled black / white text |
| Needs permission | outline + lock icon |
| Paused | muted gray pill |
| Failed | outline + warning icon + stronger border |
| Cancelled | muted gray pill |
| Success | plain text or filled pill only when fresh |

Specs:

- Height: 22-24 px.
- Radius: pill.
- Font: 11-12 px medium.
- Optional icon: 10 px.
- No green/orange/red except system-provided app icons or unavoidable warnings.

### 4.5 `MaynKeycap`

Current issue:

- Shortcut chips exist but vary in scale and prominence.

Target:

```text
⌘ ⇧ V
⌥ Space
⌥ ⇧ W
⌃ ←
```

Specs:

- Height: 20-22 px.
- Radius: 6 px.
- Border: soft hairline.
- Background: subtle panel.
- Text: 11 px, semibold.
- Use in page headers, cards, list rows, command palette, and onboarding.

### 4.6 `MaynCard`

Current issue:

- Feature cards on Dashboard use colored borders and icons.
- Cards compete for attention instead of creating hierarchy.

Target:

```text
┌────────────────────────────────────┐
│ Clipboard                 ⌘ ⇧ V    │
│ 983 items saved                    │
│ Last copied 5m ago                 │
│                              Ready │
└────────────────────────────────────┘
```

Specs:

- Radius: 16 px.
- Border: hairline.
- Padding: 18-22 px.
- Hover: translateY(-1), stronger border.
- Active card: subtle inverted header strip or black/white selected state.
- No colored border per feature.

### 4.7 `MaynSettingsRow`

Current issue:

- Settings pages are readable but look default and fragmented.

Target:

```text
Launch at login                         [toggle]
Start Mayn automatically when you sign in.
```

Specs:

- Row height: 52-60 px.
- Left: title + optional description.
- Right: toggle, pill, keycap, or button.
- Group background: panel.
- Group radius: 16 px.
- Dividers: hairline, inset 16 px.

Use for:

- General settings
- Permissions
- Voice settings
- Clipboard settings
- Downloads settings
- Window settings

### 4.8 `MaynHUDContainer`

Current issue:

- Runtime surfaces do not share a common premium container.

Target:

- rounded 20-24 px
- black / near-black surface
- white text
- strong but clean shadow
- optional subtle border
- compact density
- fast open/close animation

Use for:

- Voice HUD
- Window Hub
- Clipboard Dock
- Radial Layout
- Copy HUD
- Auto-download prompt

---

## 5. Feature-by-feature Redesign Plan

## 5.1 Dashboard

### Current screenshot diagnosis

Observed current state:

- Page title and subtitle are clear.
- Setup stat cards and feature cards are functional.
- Feature cards use colored outlines/icons and large numbers.
- Step guidance exists but looks like generic information cards.
- Toggle states use system green.
- The dashboard feels like a feature catalog rather than a system control center.

### Target role

Dashboard should answer four questions in five seconds:

1. Is Mayn ready?
2. What is running?
3. What needs attention?
4. What shortcut should I use next?

### Target visual

```text
Dashboard
Your Mac workflow is ready.

[Ready] 7 tools active    983 clipboard items    4 downloads need attention

Quick Actions
[Open Clipboard] [Start Dictation] [Open Window Hub] [Organize Downloads]

Active Tools
┌ Clipboard ──────────────── ⌘ ⇧ V ┐  ┌ Voice ─────────────── ⌥ Space ┐
│ 983 items saved                   │  │ Ready · local recognition     │
│ Last copied 5m ago                │  │ Last transcript 2h ago        │
│ [Open]                    [on]    │  │ [Start]                 [on]  │
└───────────────────────────────────┘  └──────────────────────────────┘
```

### Specific changes

1. Replace three top stat cards with a single `System Status Strip`.
   - Height: 64-76 px.
   - Left: filled `Ready` pill.
   - Middle: compact metrics.
   - Right: only show attention item if there is a problem.

2. Replace onboarding step cards with an `Attention / Next Setup` section.
   - If all setup is complete, hide the instructional steps.
   - Show only issues: missing permissions, disabled shortcuts, failed downloads.

3. Replace feature-card colors.
   - Remove blue/purple/green/orange borders.
   - Use monochrome icons.
   - Enabled: black status pill or active dot.
   - Disabled: muted border and secondary text.

4. Improve feature card content.
   - Clipboard: `983 items saved`, `Last copied 5m ago`, `Open`, `⌘ ⇧ V`.
   - Voice: `Ready`, `Sense Voice Small`, `Start`, `⌥ Space`.
   - Downloads: `4 failed`, `396 paused`, `Retry Failed`, `Open Folder`.
   - AI File Organizer: `No pending plan`, `Scan Folder`.
   - Windows Hub: `Browser tabs enabled`, `Open Hub`, `⌥ ⇧ W`.

5. Make toggles less visually dominant.
   - Move toggles to bottom-right of card.
   - Use monochrome toggle style.
   - Do not use bright green.

### Animation

- Card hover: 120 ms, translateY(-1 px).
- Feature toggle: 140 ms knob animation.
- Status strip count updates: 160 ms opacity crossfade, no rolling numbers.
- Attention card appearance: 180 ms opacity + y 8 -> 0.

### Priority

P0. This is the first screen users judge.

---

## 5.2 Sidebar and Navigation

### Current screenshot diagnosis

Observed current state:

- Sidebar is functional and native-feeling.
- Active state uses light gray fill only.
- Items are a flat list without grouping.
- Icons are mixed and too light.
- Settings is pinned at bottom, which is good.

### Target visual

```text
Mayn

Core
  Dashboard
  Clipboard
  Voice
  Downloads

Automation
  AI File Organizer
  Enhanced Finder

Windows
  Window Layouts
  Window Grab
  Windows Hub

System
  Settings
```

### Specific changes

1. Add groups with small uppercase labels.
   - Label size: 11 px.
   - Letter spacing: 0.2 px.
   - Color: tertiary.

2. Selected item should be high contrast.
   - Light: black background, white text.
   - Dark: white background, black text.

3. Normalize icons.
   - 16 px.
   - 1.5 px stroke.
   - No colorful symbols.

4. Add status dot only when needed.
   - Example: Downloads has 4 failures, show tiny monochrome warning dot on the right.
   - Voice listening, show tiny pulsing dot.

5. Keep Settings pinned to bottom.
   - Divider above settings.
   - Settings selected state follows same style.

### Animation

- Hover: 100 ms.
- Active selection background slides or crossfades in 160 ms.
- Status dot pulse: 900 ms, only for active runtime states.

### Priority

P0. This creates the app's visual foundation.

---

## 5.3 Clipboard Page

### Current screenshot diagnosis

Observed current state:

- Clipboard page has tabs for History / Snippets / Settings.
- History list is useful and dense.
- Search bar is prominent.
- App icons on right are helpful.
- Rows are too plain and look like a default table.
- Text previews lack structure by type.
- Active item and keyboard actions are not obvious.

### Target role

Clipboard should feel like a searchable memory system.

### Target visual

```text
Clipboard                                      ⌘ ⇧ V
Search copied text, links, images, and files.

[ History ] [ Snippets ] [ Settings ]

[ Search clipboard...                                      983 items ]

Pinned
  Text   Meeting notes from...                  Cursor      ⌘1

Today
  Text   Design direction for Mayn...           Cursor      5m
  Link   youtube.com/watch?v=...                Chrome      44m
  Code   <!doctype html>                        Chrome      1h
```

### Specific changes

1. Make type explicit.
   - Left type label: Text, Link, Code, Image, File.
   - Use monochrome small capsule, not color.

2. Structure each row.
   - Column 1: type chip, 52-64 px wide.
   - Column 2: preview text, two-line max.
   - Column 3: source app icon + app name, optional.
   - Column 4: timestamp.
   - Column 5: hover actions / keycap.

3. Add keyboard affordance.
   - First 9 visible rows show `⌘1`, `⌘2`, etc. on hover/focus or always in command mode.
   - `Enter` copies selected.
   - `Space` previews.

4. Improve search.
   - Right side of search field shows total count.
   - Focus state is monochrome ring.
   - Search results highlight matched text with subtle underline or background, not color.

5. Add Pinned section.
   - Pinned items should be visually separate at top.
   - Use section header with item count.

6. Snippets tab.
   - Show abbreviation, expansion, usage count, and last used.
   - Example: `;email` -> `mingjie@example.com`.
   - Use table/list, not generic form cards.

7. Settings tab.
   - Convert to `MaynSettingsRow` groups.
   - Retention, ignored apps, smart text, paste behavior.

### Animation

- Row hover actions fade in 100 ms.
- Copy: selected row flashes inverted 100 ms.
- Pin/unpin: row moves to Pinned with 180 ms crossfade and y transition.
- Search filtering: rows crossfade 120 ms; no dramatic stagger.

### Priority

P0. Clipboard is a core feature and appears in main app + dock.

---

## 5.4 Clipboard Dock

### Current screenshot diagnosis

Observed current state:

- Bottom dock appears, but the screenshot shows only the top tab strip and a Copy button.
- It feels like a cut-off sheet rather than a deliberate command shelf.
- It needs stronger contrast against whatever app is behind it.

### Target role

Clipboard Dock should be the fast runtime clipboard selector.

### Target visual

```text
┌────────────────────────────────────────────────────────────────────┐
│ Clipboard History   Snippets   Pinned          Search...      Esc  │
├────────────────────────────────────────────────────────────────────┤
│ Text    Design direction for Mayn...               Cursor     ⌘1   │
│ Link    github.com/voltagent/awesome-design-md     Chrome     ⌘2   │
│ File    invoice.pdf                                Finder     ⌘3   │
└────────────────────────────────────────────────────────────────────┘
```

### Specific changes

1. Use dark floating shelf by default.
   - Background: #090909 or material near-black.
   - Text: white / secondary gray.
   - Reason: it overlays arbitrary apps; dark shelf reads as runtime layer.

2. Position and size.
   - Bottom anchored.
   - Width: 720-860 px or 70% of screen, max 920 px.
   - Height: 280-360 px.
   - Radius: 20-24 px top corners or full rounded if detached.

3. Tabs.
   - Keep History / Snippets / Pinned.
   - Use monochrome selected pill.
   - Add search field to the right.

4. Row interactions.
   - Selected row: white fill / black text inside dark shelf.
   - Row actions: Copy, Pin, Delete, Transform.
   - Default action visible on selected row only.

5. Copy button.
   - Remove isolated bottom-right Copy button unless a row is selected.
   - Put `Copy` as selected row action and also support Enter.

6. Empty state.
   - `No clipboard items yet. Copy anything and it will appear here.`

### Animation

- Enter: opacity 0->1, y 16->0, scale 0.96->1, 180 ms.
- Exit: opacity 1->0, y 0->10, 130 ms.
- Selected row change: immediate background move, text crossfade 80 ms.
- Copy feedback: row flashes inverse 100 ms, toast appears.

### Priority

P0. Runtime surface; needs polish before screenshots/marketing.

---

## 5.5 Voice Page

### Current screenshot diagnosis

Observed current state:

- Voice has useful tabs: History, Recognition, Dictionary, Personalization, Settings.
- Recent transcripts are readable.
- Status pills use green/orange/red, which conflicts with black-white direction.
- Rows feel default, not premium.
- Runtime mini HUD is not visually unified with the main design.

### Target role

Voice should feel like local system dictation with a high-trust transcript log.

### Target visual

```text
Voice                                             ⌥ Space
Dictate into any app with local speech recognition.

[ History ] [ Recognition ] [ Dictionary ] [ Personalization ] [ Settings ]

Status
Ready · Sense Voice Small · Chinese + English

Recent Transcripts
  Success     帮我看一下具体的这个...       6.5s     Jun 22 9:57 PM
  Cancelled   Cancelled                    1.3s     Jun 20 3:57 PM
  Failed      Could not clean up            14.7s    Jun 19 11:03 PM
```

### Specific changes

1. Status chip redesign.
   - Success: monochrome filled pill only for recent success; otherwise plain text.
   - Cancelled: muted gray pill.
   - Failed: outline pill + warning icon.
   - Remove green/orange/red background chips.

2. Transcript row structure.
   - Left: status pill.
   - Middle: transcript preview.
   - Right: language, model, duration, timestamp.
   - Hover actions: Copy, Replay if available, Delete.

3. Recognition tab.
   - Show model/provider as settings rows.
   - Selected engine uses black-white active pill.
   - Avoid colored model badges.

4. Dictionary tab.
   - Use two-column table: phrase / replacement or pronunciation.
   - Add search and `Add phrase` primary button.

5. Personalization tab.
   - Use grouped rows and small explanatory text.
   - No large marketing cards.

6. Settings tab.
   - Shortcut, language, cleanup, punctuation, app-specific behavior as settings rows.

### Runtime Voice HUD target

```text
┌──────────────────────────────┐
│ ● Listening                  │
│ ▂ ▄ ▆ █ ▆ ▄ ▂                │
│ Release to insert            │
└──────────────────────────────┘
```

States:

- Idle: no HUD.
- Listening: black HUD, white dot/waveform.
- Transcribing: waveform fades, pulsing line, text `Transcribing...`.
- Inserted: text `Inserted`, fade out after 600-900 ms.
- Failed: text `Could not transcribe`, secondary action `Try again`.

### Animation

- HUD open: scale 0.94->1, y 8->0, opacity 0->1, 150 ms.
- Dot pulse: 900 ms.
- Waveform: 700-900 ms cycle, 60 ms stagger.
- Transcribing transition: 160 ms.
- Done fade: 120 ms after short hold.

### Priority

P0. Voice is highly visible and must feel premium/trustworthy.

---

## 5.6 Downloads Page

### Current screenshot diagnosis

Observed current state:

- Downloads page has good functional structure: filters, search, open folder, failed banner, stats, collections.
- It uses many colors: green completed, blue active, orange paused, red failed, pink failed banner.
- The failed banner is visually loud and web-app-like.
- Collection cards are useful but could be more compact and consistent.

### Target role

Downloads should feel like a queue monitor and file pipeline.

### Target visual

```text
Downloads                                      Open Downloads Folder
Manage active and completed downloads.

[All 401] [Completed 1] [Active 0] [Paused 396] [Failed 4]    [Search downloads]

Attention
4 downloads failed. Review failed items or retry.       [Show Failed] [Retry Failed]

Collections
  UI Audit Demo Bulk          Paused     0 / 200     0%      [Resume]
  UI Audit Demo Bulk          Failed     0 / 200     0%      [Retry]
```

### Specific changes

1. Replace colored filter dots.
   - Use monochrome pills.
   - Active filter: black fill / white text.
   - Failed filter: outline + warning icon, not red dot.

2. Replace pink failed banner.
   - Use monochrome Attention panel.
   - Stronger border and warning icon.
   - White/black surface only.

3. Replace stat cards with compact status row.
   - `Total 401`, `Completed 1`, `Active 0`, `Paused 396`, `Failed 4`.
   - Use one row, not five independent cards.

4. Collection row redesign.
   - Use list row with folder/collection icon.
   - Main title, subtitle path, progress, status, actions.
   - Progress bar: grayscale only.
   - Action buttons appear on hover unless action is urgent.

5. Items/Collections toggle.
   - Use compact segmented control.
   - Active segment: black/white.

6. Downloads Settings.
   - Convert to grouped settings rows.
   - Browser/cookie integrations as permission-like rows.
   - Destination folder row with `Reveal` / `Change`.

### Animation

- New download row: x 12->0, opacity 0->1, 180 ms.
- Progress update: linear width but no bouncing.
- Retry action: row status changes with 160 ms crossfade.
- Failed attention panel appears with y 8->0, opacity 0->1, 180 ms.

### Priority

P1. Important but after core shell + runtime surfaces.

---

## 5.7 AI File Organizer

### Current screenshot diagnosis

Observed current state:

- Feature exists for folder scan and proposed rename/move plan.
- The visual should make review/approval very clear.
- Current page likely resembles settings/form layout more than a file diff tool.

### Target role

AI File Organizer should be a safe review-and-approve workspace, not an automatic magic feature.

### Target visual

```text
AI File Organizer                                      Scan Folder
Review file moves and renames before applying.

Source: ~/Downloads                   Rules: 6 active       Model: Local

Plan Summary
12 files · 4 folders · 8 renames · 0 destructive changes

Before                                      After
IMG_4221.png                                Screenshots/2026-06-24.png
invoice final final.pdf                     Documents/Invoices/invoice-final.pdf
setup.dmg                                   Installers/setup.dmg

[Apply 12 changes] [Export plan] [Cancel]
```

### Specific changes

1. Use a diff table.
   - Left: current file name/path.
   - Right: proposed file name/path.
   - Middle: operation type: Move, Rename, Skip.
   - No colorful row highlights.

2. Add safety summary.
   - Destructive changes count should be explicit.
   - If destructive change exists, use outline warning panel.

3. Use sticky bottom action bar.
   - `Apply 12 changes` primary.
   - `Export plan` secondary.
   - `Cancel` ghost.

4. Model/provider selection.
   - Put in right-side inspector or compact settings row.
   - Do not overemphasize AI.

5. Watch-folder setup.
   - Use settings rows: folder path, rule set, auto-review, notifications.

### Animation

- Scan start: button becomes processing with pulsing line.
- Plan rows insert with 12 ms max stagger, total under 120 ms.
- Apply: rows collapse into completed summary, 220 ms.
- Do not use magic sparkles.

### Priority

P1. Important for trust and safety.

---

## 5.8 Enhanced Finder

### Current screenshot diagnosis

Observed current state:

- Feature covers folder history / switcher / excluded folders / cleanup.
- The page should visually map to Finder, not to generic settings.

### Target role

Enhanced Finder should feel like a Finder memory panel.

### Target visual

```text
Enhanced Finder
Switch back to recent folders and clean history.

[Search folders...]                         128 folders

Today
  ~/Downloads/UI Audit Demo Bulk             7 visits      Open
  ~/Desktop/Screenshots                      3 visits      Open
  ~/Documents/Invoices                       1 visit       Open

Excluded Folders
  ~/Library
  ~/.Trash
```

### Specific changes

1. Use folder path list.
   - Folder icon, path, visits, last visited, action.
   - Use monospace only for path fragments if needed.

2. Group by recency.
   - Today, Yesterday, This Week, Older.

3. Add search and quick filters.
   - `All`, `Pinned`, `Excluded`.

4. Cleanup action.
   - Put `Clear old history` in a small danger-like outline section, but monochrome.
   - Require confirmation for destructive clear.

5. Folder preview settings.
   - Move into Settings-style grouped rows.

### Animation

- Switcher open: use HUD animation 160 ms.
- Folder row open: row inverse flash 80 ms.
- Cleanup confirmation: compact sheet, 180 ms.

### Priority

P2. Polish after core/runtime/clipboard/voice/windows.

---

## 5.9 Window Layouts

### Current screenshot diagnosis

Observed current state:

- Page has Shortcuts / Radial / Snap / Ignored Apps / Rules / Diagnostics.
- Radial preview is compelling but uses blue highlight and a large embedded screenshot-like demo.
- Current page explains the feature but could look more precise and premium.

### Target role

Window Layouts should be a geometric control system.

### Target visual

```text
Window Layouts                                          Active
Arrange, snap, and restore windows.

[Shortcuts] [Radial] [Snap] [Ignored Apps] [Rules] [Diagnostics]

Shortcuts
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Left Half    │ │ Right Half   │ │ Center       │
│ ⌃ ←          │ │ ⌃ →          │ │ ⌃ C          │
└──────────────┘ └──────────────┘ └──────────────┘

Radial Preview
[monochrome window grid; selected region filled at 14% opacity]
```

### Specific changes

1. Remove blue radial target.
   - Use black/white translucent fill.
   - Light mode: black at 12-16% opacity.
   - Dark mode: white at 12-18% opacity.
   - Border: strong monochrome.

2. Make shortcuts visual.
   - Cards show mini layout diagram + keycap.
   - Selected/active shortcut uses subtle stronger border.

3. Split settings from preview.
   - Top: explanation and trigger.
   - Middle: live preview.
   - Bottom: settings rows.

4. Ignored Apps.
   - Use app list rows with small app icon, app name, reason, remove action.

5. Rules.
   - Use table: app, condition, layout, trigger, enabled.

6. Diagnostics.
   - Use monospace log only in a contained technical panel.

### Runtime radial target

Visual:

- center dot + ring
- 6-8 target directions
- selected region uses translucent monochrome rectangle
- label pill near cursor: `Left Half`, `Bottom Right`, `Maximize`

### Animation

- Open radial: center dot appears, options expand 150 ms.
- Hover target: fill appears 100 ms.
- Select: selected region holds 80 ms, overlay fades 120 ms.
- No game-like wheel bounce.

### Priority

P1. The radial feature has strong visual potential.

---

## 5.10 Window Grab

### Current screenshot diagnosis

Observed current state:

- Window Grab covers modifier-drag window movement and gesture settings.
- It needs a clear runtime mental model.

### Target role

Window Grab should communicate: hold modifier, drag anywhere, snap precisely.

### Target visual

```text
Window Grab                                             Active
Move windows by holding a modifier and dragging visible content.

Trigger
⌥ + drag anywhere on a window

Behavior
Snap preview              Enabled
Ignored apps              4 apps
Sensitivity               Medium

[Test Grab] [Change Trigger]
```

### Specific changes

1. Add a visual interaction diagram.
   - Simple monochrome window outline.
   - Cursor icon.
   - Modifier keycap.
   - Snap zone preview.

2. Move gesture settings into grouped rows.

3. Runtime status.
   - Show `Active` or `Needs Accessibility` pill in header.

4. Test area.
   - Add a small draggable demo box within the page.
   - This should use the same runtime outline behavior.

### Runtime visual

- Window outline: 2 px monochrome stroke.
- Snap target: filled black/white at 10-14% opacity.
- Label pill: `Left Half`, `Center`, `Maximize`.

### Animation

- Grab start: outline appears 100 ms.
- Snap target: appears 80 ms.
- Release: target flashes 80 ms, fade 120 ms.

### Priority

P2. Runtime polish matters, but page can be simple.

---

## 5.11 Windows Hub Page and Floating Panel

### Current screenshot diagnosis

Observed current state:

- Dark Windows page looks closer to target than other screens.
- Window Hub panel is powerful and data-rich.
- Search field has a colored/orange focus ring.
- Layout is masonry-like, which can be visually busy.
- External app icons are helpful but the panel needs clearer selected state and hierarchy.

### Target role

Windows Hub should be Mayn's flagship command panel for apps, windows, and browser tabs.

### Main page target visual

```text
Windows Hub                                            ⌥ ⇧ W
Search apps, windows, and tabs from a floating panel.

[Open Window Hub]

Permissions
Accessibility                         Granted
Browser tab discovery                 Enabled
Background apps                       Off

Panel
Show background apps                  [toggle]
AI organize                           Ask before applying
```

### Floating panel target visual

```text
┌────────────────────────────────────────────────────────────────┐
│ Search apps, windows, tabs...                    AI Organize   │
├────────────────────────────────────────────────────────────────┤
│ Chrome                                      2 windows · 40 tabs │
│   改善 Mac App UI                          chatgpt.com         │
│   Inbox                                    mail.google.com     │
│ Cursor                                      2 windows · 2 tabs  │
│   mac-all-you-need                          github.com         │
│ iTerm2                                      2 windows          │
└────────────────────────────────────────────────────────────────┘
```

### Specific changes

1. Replace orange focus ring.
   - Use monochrome focus ring.
   - In dark mode: white/gray ring.
   - In light mode: black ring.

2. Decide between grouped list and masonry.
   - For scanability, default to grouped list.
   - Masonry can be optional `Compact grid` mode.

3. App group headers.
   - App icon, app name, count summary.
   - Counts in muted text.
   - Header height: 32-36 px.

4. Window/tab rows.
   - Title left.
   - Domain/app subtitle right or below.
   - Active row: white fill / black text in dark panel.
   - Use keyboard shortcuts for top results if applicable.

5. AI Organize.
   - Keep as secondary button, not primary unless user selected multiple items.
   - Confirmation panel required before applying batch changes.
   - Label: `Organize` may be better than `AI Organize` if AI branding is too loud.

6. Browser tabs.
   - Show domain as metadata.
   - Avoid tiny blue bullets; use simple dot or no dot.

7. Page settings.
   - Convert to `MaynSettingsRow` groups.
   - Keep Windows page dark-compatible and monochrome.

### Animation

- Panel open: opacity 0->1, scale 0.96->1, y -6->0, 160 ms.
- Search results: crossfade 120 ms.
- Active row change: immediate; text color crossfade 80 ms.
- Selection: row flashes inverse 80 ms, close 120 ms.

### Priority

P0. This is already close to target and can become a signature surface quickly.

---

## 5.12 Settings

### Current screenshot diagnosis

Observed current state:

- Settings General, Permissions, Advanced exist and are clear.
- The visual feels default but acceptable.
- It needs consistency with the rest of the app and less color.

### Target role

Settings should be calm, trusted, grouped, and native.

### Target visual

```text
Settings

General
  Launch at login                         [toggle]
  Show menu bar icon                      [toggle]
  Sound feedback                          [toggle]

Permissions
  Accessibility                           Granted
  Microphone                              Granted
  Screen Recording                        Needs permission      [Open]
  Full Disk Access                        Optional              [Open]

Advanced
  Reset onboarding                        [Reset]
  Export diagnostics                      [Export]
```

### Specific changes

1. Replace all settings sections with `MaynSettingsGroup`.
   - Group radius: 16 px.
   - Row height: 52-60 px.
   - Inset dividers.

2. Permission status.
   - Granted: filled monochrome pill.
   - Needs permission: outline pill + button.
   - Optional: muted pill.

3. Advanced actions.
   - Keep dangerous actions in a separate group.
   - Use outline button, not red.
   - Confirmation required for resets.

4. Add shortcut settings group.
   - List all global shortcuts in one place.

### Animation

- Toggle: 140 ms.
- Permission row status update: 180 ms crossfade.
- Confirmation sheet: scale 0.975->1, opacity, 180 ms.

### Priority

P1. Needed for consistency but not highest impact.

---

## 5.13 Permissions

### Current screenshot diagnosis

Observed current state:

- Permissions are captured in settings and onboarding.
- Permission setup needs to be clearer because macOS permission flows are stressful.

### Target role

Permissions should feel transparent and non-scary.

### Target visual

```text
Permissions
Mayn needs these permissions only for the features you enable.

Accessibility             Required for shortcuts, paste, and window control.   Granted
Microphone                Required for Voice.                                  Granted
Screen Recording          Required for window previews.                         Needs permission
Full Disk Access          Optional for file organization.                       Optional
Notifications             Optional for download alerts.                         Off
```

### Specific changes

1. Explain why each permission is needed.
2. Tie permission to feature.
3. Show `Required`, `Optional`, or `Only if using X`.
4. Use buttons: `Open System Settings`, `Check Again`.
5. Use monochrome status pills.
6. For grant helper floating panel, use HUD style.

### Animation

- Permission granted: row border strengthens briefly, status crossfades to `Granted`, 180 ms.
- Helper panel: open 180 ms, close 130 ms.

### Priority

P0. Permissions gate core features.

---

## 5.14 Onboarding

### Current screenshot diagnosis

Observed current state:

- Onboarding flow exists and covers feature picking, permissions, setup, and done state.
- Visual is too close to default wizard UI.
- Feature selection needs stronger black-white design.

### Target role

Onboarding should make Mayn feel like a premium Mac power tool.

### Flow

1. Welcome
2. Choose features
3. Grant permissions
4. Set shortcuts
5. Ready

### Welcome target

```text
Mayn
A command layer for your Mac.

Clipboard memory, voice input, downloads, Finder workflows, and window control.

[Get Started]
```

Visual:

- Big monochrome app mark or simple command glyph.
- No colorful illustration.
- Centered card, 560-640 px wide.

### Feature selection target

```text
Choose what Mayn should run.
You can change this later.

[✓ Clipboard History]    [✓ Voice Dictation]
[✓ Downloads]            [✓ Windows Hub]
[  AI File Organizer]    [  Enhanced Finder]
[  Window Layouts]       [  Window Grab]
```

Selected tile:

- black fill / white text
- white checkmark
- shortcut shown as inverse keycap

Unselected tile:

- panel background
- hairline border
- primary text

### Permission target

Group permissions by enabled feature.

```text
Required for selected features
Accessibility       Clipboard, Windows, Window Grab       Grant
Microphone          Voice Dictation                       Grant
Screen Recording    Windows previews                      Grant
```

### Done target

```text
Mayn is ready.

Clipboard History       ⌘ ⇧ V
Voice Dictation         ⌥ Space
Window Hub              ⌥ ⇧ W

[Open Mayn] [Try Clipboard]
```

### Animation

- Step transition: old step opacity 1->0 y 0->-6 in 100 ms; new step opacity 0->1 y 10->0 in 180 ms.
- Feature selection: background inverts in 140 ms; check scales 0.8->1.
- Permission granted: pill crossfades in 180 ms.
- Done state: no confetti; simple fade-in checklist.

### Priority

P0. First impression.

---

## 5.15 Runtime Toasts and Popups

### Current screenshot diagnosis

Observed current state:

- Copy HUD and auto-download prompts exist.
- Runtime surfaces are documented but not visually unified.

### Target role

Toasts confirm actions without stealing focus.

### Target visual

```text
Copied
Inserted
Window moved left
3 files organized
Download added
```

Visual specs:

- Black pill / white text in light mode.
- White pill / black text in dark mode.
- Height: 34-38 px.
- Radius: pill.
- Position: bottom center for clipboard/voice/window actions; top-right for download prompts.
- Optional icon only if it helps.

### Specific changes

1. Create one toast component.
2. Remove colored success/error styling.
3. Use concise action-result copy.
4. Stack toasts with max 3 visible.
5. Add reduced-motion behavior.

### Animation

- Enter: opacity 0->1, y 8->0, scale 0.96->1, 180 ms.
- Stay: 1200-1800 ms.
- Exit: opacity 1->0, y 0->6, 130 ms.

### Priority

P0. Small component, high perceived polish.

---

## 6. Implementation Roadmap

### Phase 1: Foundation and shell, 2-4 days

Build shared primitives:

- `MaynColor`
- `MaynTypography`
- `MaynSpacing`
- `MaynRadius`
- `MaynMotion`
- `MaynButtonStyle`
- `MaynStatusPill`
- `MaynKeycap`
- `MaynSearchField`
- `MaynPageHeader`
- `MaynSegmentedTabs`
- `MaynSettingsRow`

Refactor:

- Main window shell
- Sidebar grouping and active states
- Toolbar command search placeholder
- Global black-white tint rules

Definition of done:

- Dashboard, Clipboard, Voice, Downloads, Windows pages all use same header.
- Sidebar is grouped and monochrome.
- No colorful feature borders remain.

### Phase 2: Runtime surfaces, 3-5 days

Polish:

- Command Palette
- Clipboard Dock
- Voice HUD
- Window Hub floating panel
- Copy HUD / Toast
- Permission helper panel
- Radial layout overlay

Definition of done:

- Every runtime surface uses `MaynHUDContainer` or equivalent.
- All open/close animations match motion tokens.
- Keyboard navigation is visible.
- Reduced motion supported.

### Phase 3: Core pages, 4-6 days

Redesign:

- Dashboard
- Clipboard History / Snippets / Settings
- Voice History / Recognition / Dictionary / Settings
- Downloads Main / Settings
- Windows Hub page

Definition of done:

- Every page is monochrome.
- Lists use shared row patterns.
- Status pills are standardized.
- Search fields are consistent.

### Phase 4: Automation and window tools, 4-6 days

Redesign:

- AI File Organizer
- Enhanced Finder
- Window Layouts
- Window Grab
- Window rules / ignored apps / diagnostics

Definition of done:

- AI File Organizer has before/after review table.
- Enhanced Finder looks like folder history, not settings.
- Window Layouts radial preview is monochrome.
- Window Grab has clear runtime demo.

### Phase 5: Onboarding and permissions, 3-5 days

Redesign:

- Welcome
- Feature selection
- Permissions
- Shortcut setup
- Done screen
- Settings Permissions

Definition of done:

- Feature selection uses black-white selected state.
- Permissions explain why each permission is needed.
- Done screen gives shortcuts and first action.
- No colorful feature tiles.

### Phase 6: QA and polish, 2-4 days

Checklist:

- Light mode screenshot pass.
- Dark mode screenshot pass.
- Reduced motion pass.
- Keyboard-only pass.
- High-contrast pass.
- Empty states pass.
- Long text / Chinese text pass.
- Many windows/tabs pass.
- 1000 clipboard items pass.
- Failed downloads pass.

---

## 7. Screen-specific Acceptance Criteria

### Dashboard acceptance criteria

- Top status strip replaces disconnected stat cards.
- Setup guidance only appears if setup is incomplete.
- Feature cards are monochrome.
- Every active feature card shows shortcut or primary action.
- No green toggles or colored feature borders.

### Clipboard acceptance criteria

- History rows have type, preview, source, time, and action/keycap.
- Search field shows item count.
- Selected row is clear with black-white inversion.
- Copy feedback is row flash + toast.
- Snippets are table-like, not generic cards.

### Clipboard Dock acceptance criteria

- Dock is a polished floating shelf.
- It has search, tabs, selected row, and keyboard hints.
- Copy action is tied to selected row.
- It animates in under 200 ms.

### Voice acceptance criteria

- Status pills are monochrome.
- Transcript rows are structured and scannable.
- Voice HUD uses black/white waveform.
- Listening, transcribing, inserted, failed states are distinct.

### Downloads acceptance criteria

- Filters are monochrome pills.
- Failed state is an attention panel, not a pink/red banner.
- Download collection rows are compact.
- Progress bars are grayscale.

### AI File Organizer acceptance criteria

- File plan is shown as before/after table.
- Apply action is sticky and explicit.
- Destructive actions are summarized clearly.
- AI is not visually over-branded.

### Enhanced Finder acceptance criteria

- Recent folders are grouped by time.
- Folder paths are scannable.
- Excluded folders are separate.
- Open/switch action is clear.

### Window Layouts acceptance criteria

- Radial preview is monochrome.
- Shortcut cards show mini layout diagrams.
- Ignored apps and rules use structured rows.
- Runtime radial animation is fast and precise.

### Window Grab acceptance criteria

- Trigger is visually obvious.
- Runtime outline and snap target are monochrome.
- Page includes a small demo/test area.

### Windows Hub acceptance criteria

- Search focus ring is monochrome.
- Results are grouped and keyboard navigable.
- Active row is clearly inverted.
- AI organize is secondary and confirmation-based.

### Settings acceptance criteria

- Settings use grouped rows.
- Permissions use standardized status pills.
- Shortcuts are centralized.
- Destructive reset actions require confirmation.

### Onboarding acceptance criteria

- Feature tiles are black-white selected/unselected.
- Permission steps explain why each permission is required.
- Final screen shows the user's enabled shortcuts.
- No confetti, no colorful feature artwork.

---

## 8. Engineering Notes for SwiftUI

### 8.1 Avoid direct system color usage

Replace direct usage:

```swift
.foregroundStyle(.blue)
.tint(.green)
.background(.red.opacity(0.1))
```

With semantic tokens:

```swift
.foregroundStyle(MaynColor.primaryText)
.tint(MaynColor.activeFill)
.background(MaynColor.panelSubtle)
```

### 8.2 Create shared view modifiers

Recommended modifiers:

```swift
.maynPanel()
.maynCard(active: Bool)
.maynHoverLift()
.maynFocusRing(isFocused: Bool)
.maynRuntimeHUD()
.maynPageTransition()
```

### 8.3 Use semantic components instead of one-off views

Replace page-specific chips/buttons with shared components:

- `StatusPill(status:)`
- `Keycap(keys:)`
- `MaynButton(kind:)`
- `SettingsRow(title:description:control:)`
- `SearchField(text:placeholder:trailing:)`
- `SegmentedTabs(selection:tabs:)`

### 8.4 Animation constants

Create one place for animation tokens:

```swift
enum MaynMotion {
    static let instant: Double = 0.08
    static let fast: Double = 0.12
    static let standard: Double = 0.18
    static let panel: Double = 0.22

    static let standardAnimation = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: standard)
    static let overlayIn = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.18)
    static let overlayOut = Animation.timingCurve(0.7, 0, 0.84, 0, duration: 0.13)
}
```

### 8.5 Reduced motion

Use environment:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

If `reduceMotion` is true:

- remove scale and translate animations
- keep opacity transition only
- disable waveform height animation
- disable shimmer

---

## 9. Design QA Checklist

Run this checklist for every PR that changes UI:

- Is the UI black-white-grayscale first?
- Are colors semantic rather than hard-coded?
- Is the active state readable without color?
- Are shortcuts visible for frequent actions?
- Does the page use `MaynPageHeader`?
- Are tabs using `MaynSegmentedTabs`?
- Are settings using `MaynSettingsRow`?
- Are status pills standardized?
- Are app/file icons the only colorful elements?
- Does the screen work in dark mode?
- Does the animation finish under 220 ms for common transitions?
- Does reduced motion work?
- Can the surface be operated by keyboard?
- Is Chinese / long text handled cleanly?
- Does the page feel like a native Mac utility instead of a web app?

---

## 10. Immediate Next Tasks

### Task 1: Replace feature-card color system

Files likely involved:

- `MacAllYouNeed/App/Dashboard/FeatureToolCard.swift`
- `MacAllYouNeed/App/MainWindow/Destinations/DashboardDestinationView.swift`

Work:

- Remove per-feature colored border/background.
- Add `MaynCard` style.
- Add monochrome icons.
- Move toggle to consistent card footer.
- Show status pill and shortcut.

### Task 2: Build monochrome status pill

Files likely involved:

- shared UI components folder
- Voice transcript rows
- Downloads filters
- Permissions rows
- Dashboard cards

Work:

- Implement status enum.
- Map states to monochrome visual variants.
- Replace green/orange/red chips.

### Task 3: Redesign Window Hub focus and selection

Files likely involved:

- `MacAllYouNeed/WindowHub/WindowHubOverlayView.swift`
- `MacAllYouNeed/WindowHub/WindowHubPage.swift`

Work:

- Replace orange focus ring.
- Add monochrome active row.
- Improve grouped app headers.
- Add panel open/close animation.

### Task 4: Redesign Clipboard History rows

Files likely involved:

- `MacAllYouNeed/App/MainWindow/Destinations/ClipboardDestinationView.swift`
- `MacAllYouNeed/ClipboardDock/Views/*`

Work:

- Add type chip.
- Add source/time/actions columns.
- Add keyboard row keycaps.
- Add row flash on copy.

### Task 5: Redesign Voice HUD

Files likely involved:

- `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift`

Work:

- Create black/white HUD container.
- Add pulsing dot and waveform.
- Add transcribing state with pulsing line.
- Add inserted/failed states.

### Task 6: Redesign Onboarding feature picker

Files likely involved:

- `MacAllYouNeed/Onboarding/FeaturePickerView.swift`
- `MacAllYouNeed/Onboarding/OnboardingWizardView.swift`

Work:

- Selected tile = black fill / white text.
- Unselected tile = panel + hairline border.
- Remove colorful feature icons.
- Show shortcut preview per selected feature.

---

## 11. Final Target Summary

The redesigned Mayn should look like:

```text
A monochrome macOS power tool.
Native shell.
Grouped sidebar.
Compact command search.
Dense lists.
Black-white selected states.
Premium floating HUDs.
Fast, calm motion.
No colorful SaaS dashboard styling.
```

The UI should make the user feel:

```text
This app is reliable enough to control my Mac.
It is quiet until I need it.
When I call it, it is instant.
```
