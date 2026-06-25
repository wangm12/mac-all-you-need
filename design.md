---
version: 1.0
product: Mayn / MacAllYouNeed
direction: Monochrome Native Command Layer
platform: macOS desktop app
primary_color_system: black-white-grayscale
intended_readers:
  - product designers
  - SwiftUI engineers
  - AI coding agents
  - design QA reviewers
---

# Mayn DESIGN.md

Mayn is a black-and-white native macOS command layer for clipboard memory, voice input, downloads, Finder workflows, file organization, and window control.

The app should feel like a quiet system utility, not like a colorful SaaS dashboard. It should look native to macOS, feel instant when invoked, and stay visually restrained even though the product has many features.

Core direction:

> Invisible until needed. Precise when invoked. Black, white, native, fast.

---

## 1. Design Principles

### 1.1 Monochrome first

Mayn's primary brand system is black, white, and grayscale.

Use black-white inversion for primary emphasis:

- selected sidebar item
- active command row
- primary button
- enabled feature card
- focused HUD state
- selected radial target
- copied / inserted toast

Do not assign bright colors to features. Clipboard should not be blue, Voice should not be purple, Downloads should not be green, Windows should not be orange. The feature identity should come from icon, label, hierarchy, and motion behavior.

### 1.2 Native macOS utility, not web dashboard

The app should feel closer to Finder, System Settings, Spotlight, Raycast, Linear, and a premium menu bar utility than a SaaS admin panel.

Use:

- native window chrome
- system typography
- sidebar + toolbar structure
- compact rows
- subtle hairline borders
- keyboard shortcuts as first-class UI
- floating HUDs for runtime actions

Avoid:

- marketing-style hero sections
- colorful stat cards
- gradient feature tiles
- large empty web-app spacing
- emoji icons
- confetti or celebratory effects
- slow decorative animation

### 1.3 Keyboard-first

Mayn exists to keep users in flow. Every important action should have a shortcut or be reachable from the command palette.

Primary interaction surfaces:

1. Global command palette
2. Runtime HUDs
3. Sidebar pages
4. Settings rows

The main app window is for configuration and review. The runtime experience is the product.

### 1.4 Dense but calm

Mayn handles history lists, files, downloads, windows, tabs, and settings. Density is required, but it must be controlled.

Use dense rows for data. Use generous white space only around page headers, onboarding, and permission explanation.

Good density:

- 44-56 px history rows
- 36-40 px sidebar items
- 34-38 px buttons
- 18-24 px card padding
- 12-16 px section gaps

Bad density:

- huge marketing cards
- multi-color dashboards
- oversized icons
- sparse settings forms with little information

---

## 2. Visual Identity

### 2.1 Personality

Mayn should feel:

- precise
- quiet
- trustworthy
- fast
- system-level
- technical but approachable
- premium without decoration

Mayn should not feel:

- playful
- flashy
- colorful
- AI-magical
- web-template-like
- overloaded

### 2.2 Visual keywords

Use these words when evaluating the UI:

- monochrome
- native
- command layer
- overlay
- utility
- compact
- sharp
- quiet
- focused
- keyboard-first

### 2.3 One-line visual target

> A black-and-white native macOS command center that appears only when needed and disappears without friction.

---

## 3. Color System

### 3.1 Hard rule

The primary palette is black, white, and grayscale only.

Accent colors are not a core part of the visual identity. They may appear only when forced by macOS permissions, external app icons, file thumbnails, media thumbnails, or system status that would be unsafe to hide. Even then, keep them secondary and small.

### 3.2 Light mode tokens

```css
:root {
  --mayn-black: #090909;
  --mayn-white: #ffffff;

  --bg-app: #f5f5f2;
  --bg-window: #fbfbf8;
  --bg-sidebar: #f0f0ed;
  --bg-toolbar: rgba(251, 251, 248, 0.86);
  --bg-panel: #ffffff;
  --bg-panel-subtle: #f3f3f1;
  --bg-inset: #ececea;
  --bg-hover: rgba(0, 0, 0, 0.045);
  --bg-active: #090909;

  --text-primary: #0d0d0d;
  --text-secondary: #4d4d49;
  --text-tertiary: #81817b;
  --text-disabled: #b9b9b3;
  --text-inverse: #ffffff;

  --border-hairline: rgba(0, 0, 0, 0.08);
  --border-soft: rgba(0, 0, 0, 0.13);
  --border-strong: rgba(0, 0, 0, 0.24);

  --control-primary-bg: #090909;
  --control-primary-fg: #ffffff;
  --control-secondary-bg: #ffffff;
  --control-secondary-fg: #0d0d0d;
  --control-secondary-border: rgba(0, 0, 0, 0.12);

  --status-ok-bg: #111111;
  --status-ok-fg: #ffffff;
  --status-warn-bg: #f3f3f1;
  --status-warn-fg: #171717;
  --status-error-bg: #ffffff;
  --status-error-fg: #111111;
  --status-error-border: rgba(0, 0, 0, 0.3);

  --hud-bg: #090909;
  --hud-fg: #ffffff;
  --overlay-bg: rgba(0, 0, 0, 0.42);
}
```

### 3.3 Dark mode tokens

```css
[data-theme="dark"] {
  --mayn-black: #000000;
  --mayn-white: #ffffff;

  --bg-app: #070707;
  --bg-window: #0c0c0c;
  --bg-sidebar: #101010;
  --bg-toolbar: rgba(12, 12, 12, 0.86);
  --bg-panel: #141414;
  --bg-panel-subtle: #1b1b1b;
  --bg-inset: #242424;
  --bg-hover: rgba(255, 255, 255, 0.07);
  --bg-active: #ffffff;

  --text-primary: #f3f3f3;
  --text-secondary: #b9b9b9;
  --text-tertiary: #7d7d7d;
  --text-disabled: #505050;
  --text-inverse: #090909;

  --border-hairline: rgba(255, 255, 255, 0.08);
  --border-soft: rgba(255, 255, 255, 0.13);
  --border-strong: rgba(255, 255, 255, 0.24);

  --control-primary-bg: #ffffff;
  --control-primary-fg: #090909;
  --control-secondary-bg: #171717;
  --control-secondary-fg: #ffffff;
  --control-secondary-border: rgba(255, 255, 255, 0.13);

  --status-ok-bg: #ffffff;
  --status-ok-fg: #090909;
  --status-warn-bg: #1d1d1d;
  --status-warn-fg: #f3f3f3;
  --status-error-bg: #121212;
  --status-error-fg: #ffffff;
  --status-error-border: rgba(255, 255, 255, 0.28);

  --hud-bg: #f4f4f4;
  --hud-fg: #050505;
  --overlay-bg: rgba(0, 0, 0, 0.62);
}
```

### 3.4 SwiftUI color tokens

Create centralized color tokens. Do not hard-code `.blue`, `.green`, `.purple`, `.orange`, or `.red` for normal UI.

```swift
enum MaynColor {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let panelSubtle = Color.primary.opacity(0.035)
    static let hairline = Color.primary.opacity(0.08)
    static let softBorder = Color.primary.opacity(0.13)
    static let strongBorder = Color.primary.opacity(0.24)
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
    static let activeFill = Color.primary
    static let activeText = Color(nsColor: .windowBackgroundColor)
    static let hoverFill = Color.primary.opacity(0.045)
}
```

For toggles and selected controls, use monochrome tint:

```swift
.tint(Color.primary)
```

When the control becomes unreadable in dark mode, define a custom toggle style instead of using system green.

### 3.5 Status without color

Use monochrome status language:

| State | Visual |
|---|---|
| Ready | filled black pill in light mode / filled white pill in dark mode |
| Active | filled pill + small pulsing dot |
| Idle | outline pill + muted text |
| Needs permission | outline pill + lock icon |
| Failed | outlined pill + warning triangle + stronger border |
| Processing | subtle progress line / pulsing dot |
| Paused | gray pill + pause icon |
| Completed | filled monochrome pill only when action just completed; otherwise plain text |

Avoid green success pills, red error banners, blue info badges, purple voice badges, and orange warning pills unless the OS component provides them and they cannot be customized.

---

## 4. Typography

### 4.1 Font family

Use macOS system type.

```css
font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif;
```

SwiftUI:

```swift
.font(.system(size: size, weight: weight, design: .default))
```

Use monospaced only for shortcuts, file paths, technical IDs, durations, and code-like snippets.

### 4.2 Type scale

| Token | Size | Weight | Line height | Use |
|---|---:|---:|---:|---|
| Display | 32 | 600 | 38 | onboarding hero only |
| Page title | 28 | 650 | 34 | major page header |
| Section title | 15 | 600 | 21 | section headings |
| Card title | 14 | 600 | 20 | card headers |
| Body | 13 | 400 | 19 | primary content |
| Body strong | 13 | 550 | 19 | row titles |
| Caption | 12 | 400 | 16 | secondary copy |
| Micro | 11 | 500 | 14 | labels, metadata |
| Keycap | 11 | 550 | 14 | shortcuts |

### 4.3 Typography rules

Use short, functional text.

Good:

- Clipboard History
- Search copied text, links, images, and files.
- Watching `~/Downloads`
- Accessibility required to switch windows.
- 3 files organized today.

Bad:

- Supercharge your productivity with AI-powered automations.
- Unlock your ultimate workflow potential.
- Your personal intelligent assistant for the future of Mac productivity.

Page titles should be direct nouns:

- Dashboard
- Clipboard
- Voice
- Downloads
- File Organizer
- Finder
- Window Layouts
- Window Grab
- Windows Hub
- Settings

---

## 5. Layout System

### 5.1 Window shell

Default main window:

- width: 1120 px
- height: 760 px
- minimum width: 920 px
- minimum height: 640 px
- corner radius: native macOS window radius
- sidebar width: 220 px
- toolbar height: 56 px
- content max width: 920 px

Layout:

```text
┌────────────────────────────────────────────────────────────┐
│ traffic lights   Mayn         Search / Command      Status │
├────────────────┬───────────────────────────────────────────┤
│ Sidebar        │ Page title / subtitle / primary action    │
│                │ Segmented controls / filters              │
│ Dashboard      │ Main panels / dense lists / preview       │
│ Clipboard      │                                           │
│ Voice          │                                           │
│ Downloads      │                                           │
│ Windows        │                                           │
│ Settings       │                                           │
└────────────────┴───────────────────────────────────────────┘
```

### 5.2 Sidebar

Sidebar width: 220 px.

Sidebar item:

- height: 36 px
- horizontal padding: 12 px
- radius: 9 px
- icon: 16 px stroke-based
- label: 13 px, medium when selected
- active state: black fill / white text in light mode; white fill / black text in dark mode
- hover state: subtle gray fill

Navigation groups:

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

Do not use colorful icons in the sidebar.

### 5.3 Toolbar

Toolbar contents:

- traffic lights
- optional app title / current workspace
- global command search
- active runtime indicator
- compact settings / theme menu

Command search visual:

```text
[ Search actions, history, files, windows...        ⌘K ]
```

Specs:

- height: 34-38 px
- width: 320-420 px
- radius: 11 px
- background: panelSubtle
- border: hairline
- icon: magnifying glass, 14 px
- keycap: right aligned

### 5.4 Page header

Each page should use the same header structure.

```text
Page Title                                      Primary action / shortcut
Short functional description.
```

Specs:

- top padding: 32 px from toolbar
- title: 28 px / 650
- subtitle: 13 px / secondary
- right control: shortcut chip or primary action
- bottom divider only when content scrolls

### 5.5 Spacing scale

Use a 4 px base grid.

```text
4, 8, 12, 16, 20, 24, 32, 40, 48, 64
```

Rules:

- page side padding: 32 px
- section gap: 24 px
- card gap: 12-16 px
- list row vertical padding: 10-14 px
- settings row height: 48-56 px
- compact filter bar height: 34-38 px

---

## 6. Shape, Borders, and Elevation

### 6.1 Radius tokens

```css
--radius-xs: 5px;
--radius-sm: 8px;
--radius-md: 12px;
--radius-lg: 16px;
--radius-xl: 20px;
--radius-panel: 22px;
--radius-pill: 9999px;
```

Usage:

| Component | Radius |
|---|---:|
| keycap | 6 px |
| sidebar item | 9 px |
| button | 10-12 px |
| search field | 11-12 px |
| card | 16 px |
| large panel | 18-22 px |
| command palette | 22 px |
| HUD | 20-24 px |
| pill | 9999 px |

### 6.2 Border usage

Use borders for structure, not decoration.

- page section: hairline
- card: hairline
- selected card: strong border or inverted fill
- table row divider: hairline
- command palette: soft border
- floating HUD: subtle border only in dark mode if needed

Do not use colored borders for feature cards.

### 6.3 Elevation tokens

```css
--elevation-0: none;

--elevation-1:
  0 0 0 1px rgba(0, 0, 0, 0.08);

--elevation-2:
  0 0 0 1px rgba(0, 0, 0, 0.08),
  0 1px 2px rgba(0, 0, 0, 0.04);

--elevation-3:
  0 0 0 1px rgba(0, 0, 0, 0.08),
  0 8px 24px rgba(0, 0, 0, 0.07);

--elevation-4:
  0 0 0 1px rgba(0, 0, 0, 0.12),
  0 16px 48px rgba(0, 0, 0, 0.16);

--elevation-5:
  0 0 0 1px rgba(0, 0, 0, 0.16),
  0 24px 80px rgba(0, 0, 0, 0.28);
```

Usage:

| Elevation | Use |
|---|---|
| 0 | page background, list background |
| 1 | settings groups, flat panels |
| 2 | normal cards |
| 3 | active card, sticky toolbar |
| 4 | dropdown, popover, contextual menu |
| 5 | command palette, window hub, voice HUD |

---

## 7. Components

### 7.1 Buttons

#### Primary button

Use for the one main action on a surface.

Visual:

- light mode: black background, white text
- dark mode: white background, black text
- height: 36-40 px
- padding: 12-16 px horizontal
- radius: 10-12 px
- no color accents

Examples:

- Grant Permission
- Open Window Hub
- Organize Files
- Start Dictation
- Run Scan

#### Secondary button

Visual:

- transparent or panel background
- text primary
- hairline border
- height: 34-38 px
- radius: 10-12 px

Examples:

- Customize
- Show Failed
- Retry Failed
- Open in Finder
- Change Shortcut

#### Ghost button

Visual:

- transparent background
- secondary text
- hover gray fill
- no border by default

Examples:

- Reset
- Dismiss
- Learn more
- Clear history

### 7.2 Segmented control

Current segmented controls feel too large and generic. Replace with compact monochrome tabs.

Specs:

- height: 34-38 px
- background: panelSubtle
- outer border: hairline
- selected segment: active fill, inverse text
- radius: pill or 12 px
- icon optional, 13-14 px
- text: 12-13 px medium

Avoid system-blue selected states.

### 7.3 Search fields

Search fields are core in Clipboard, Downloads, Windows Hub, Finder history, and command palette.

Specs:

- compact search: 34-38 px height
- command search: 52-56 px height
- radius: 11-14 px
- left icon: 14-16 px
- right metadata: item count or shortcut keycap
- focus ring: monochrome, 2 px

For large data surfaces, search should sit directly above the list and remain sticky if scrolling.

### 7.4 Keycaps

Shortcuts should be shown everywhere they matter.

Visual:

```text
⌘ ⇧ V
⌥ Space
⌃ ←
```

Specs:

- height: 20-22 px
- padding: 6-8 px horizontal
- radius: 6 px
- background: panelSubtle
- border: soft border
- text: 11 px / 550
- monospaced digits only if needed

### 7.5 Cards

Cards should be monochrome control panels, not colorful feature tiles.

Card specs:

- background: panel
- border: hairline
- radius: 16 px
- padding: 18-22 px
- hover: border slightly stronger + translateY(-1 px)
- selected / enabled: either black-white inversion or subtle active rail, never colored border

Feature card layout:

```text
┌────────────────────────────────────┐
│ [icon] Clipboard          ⌘ ⇧ V    │
│ Save, search, and reuse copies.    │
│                                    │
│ 983 items saved                    │
│ Last copied 5m ago         [toggle]│
└────────────────────────────────────┘
```

### 7.6 Lists

Use list rows for history, transcripts, downloads, windows, tabs, rules, and settings.

Row specs:

- height: 44-64 px depending content
- border-bottom: hairline
- hover: subtle gray fill
- selected: inverted fill
- primary text: 13 px
- metadata: 11-12 px secondary
- actions: hidden until hover/focus unless critical

### 7.7 Status pills

Specs:

- height: 22-24 px
- padding: 8-10 px horizontal
- radius: pill
- font: 11-12 px / 500
- icons: 8-10 px if used

Monochrome mapping:

- Granted: filled active pill
- Enabled: filled active pill
- Ready: filled active pill
- Needs Setup: outline pill
- Paused: muted pill
- Failed: outline pill + warning icon
- Running: animated dot + text

### 7.8 Empty states

Empty states should be minimal.

Example:

```text
No clipboard items yet.
Copy anything on your Mac and it will appear here.
```

Visual:

- simple line icon, 28-36 px
- no illustrations
- no colorful artwork
- one primary action max

### 7.9 Toasts

Specs:

- position: bottom center or top-right, depending surface
- height: 34-38 px
- radius: pill
- background: black in light mode / white in dark mode
- text: inverse
- icon optional, monochrome
- stay: 1200-1800 ms

Copy:

- Copied
- Inserted
- 3 files organized
- Window moved left
- Permission granted

### 7.10 HUDs

HUDs are the most Mayn-specific visual language.

Use for:

- Voice dictation
- Clipboard Dock
- Window Hub
- Radial Layout menu
- Window Grab snap preview
- Copy confirmation
- Auto-download prompt

HUD specs:

- background: black in light mode / near-black in dark mode, or inverted if above dark app
- text: white
- radius: 20-24 px
- strong but clean shadow
- compact layout
- no web-modal styling
- no colorful gradients

---

## 8. Feature Surface Guidelines

### 8.1 Dashboard

Dashboard should become a system status board, not a feature catalog.

Visual target:

```text
Mayn
Your Mac workflow is ready.
7 tools active · 983 clipboard items · 4 downloads need attention

┌ Status strip ─────────────────────────────────────────────┐
│ Permissions OK    Shortcuts active    Watchers running    │
└───────────────────────────────────────────────────────────┘

Quick Actions
[Open Clipboard] [Start Dictation] [Open Window Hub] [Organize Downloads]

Active Tools
[Clipboard] [Voice] [Downloads]
[Finder]    [Windows] [Layouts]
```

Dashboard cards should show:

- current state
- shortcut
- last activity
- primary action

Avoid showing large standalone numbers without context.

### 8.2 Clipboard

Clipboard should feel like a fast searchable memory list.

Visual target:

```text
Clipboard                                      ⌘ ⇧ V
Search copied text, links, images, and files.

[ Search clipboard...                         983 items ]

Pinned
Today
  Text     Design direction for Mayn...       Cursor    5m
  Link     github.com/...                     Chrome    44m
  File     invoice.pdf                        Finder    1h
```

Use dense rows and monochrome source chips. External app icons may keep their original colors but should be small and not dominate.

### 8.3 Clipboard Dock

The Clipboard Dock should feel like a bottom command shelf.

Visual target:

```text
┌ Clipboard History ─ Snippets ─ Pinned ───────── Search ┐
│ Text    Design direction for Mayn...       ⌘1   Copy   │
│ Link    github.com/voltagent/...           ⌘2   Copy   │
│ File    invoice.pdf                        ⌘3   Reveal │
└─────────────────────────────────────────────────────────┘
```

Specs:

- bottom anchored panel
- height: 260-360 px depending content
- dark by default if floating over screen content
- rounded top corners: 18-22 px
- selected row uses inverted fill
- Copy button is primary only on selected row

### 8.4 Voice

Voice should feel like system dictation, not an audio dashboard.

Main page visual target:

```text
Voice                                            ⌥ Space
Dictate into any app with local speech recognition.

Status
Ready · Sense Voice Small · Chinese + English

Recent Transcripts
  Success    帮我看一下...          6.5s    Jun 22
  Cancelled  Cancelled              1.3s    Jun 20
  Failed     Could not clean up      14.7s   Jun 19
```

Runtime HUD visual target:

```text
┌─────────────────────────────┐
│ ● Listening                 │
│ ▂ ▄ ▆ █ ▆ ▄ ▂               │
│ Release to insert           │
└─────────────────────────────┘
```

Use monochrome waveform and a pulsing dot. Avoid purple microphone branding.

### 8.5 Downloads

Downloads should feel like a queue and file pipeline.

Visual target:

```text
Downloads                                  Open Downloads Folder
Manage active and completed downloads.

[All 401] [Active 0] [Paused 396] [Failed 4]      [Search]

Attention
4 downloads failed. Review failed items or retry.

Collections
  UI Audit Demo Bulk           Paused       0 / 200       [Resume]
  UI Audit Demo Bulk           Failed       0 / 200       [Retry]
```

Use monochrome filters. Failed state may use stronger border and warning icon, but avoid pink/red filled banners.

### 8.6 AI File Organizer

The AI File Organizer should be a review-and-approve workspace.

Visual target:

```text
AI File Organizer                         Scan Folder
Review file moves and renames before applying.

Source: ~/Downloads
Rules: screenshots, PDFs, installers, archives

Before                              After
IMG_4221.png                        Screenshots/2026-06-24.png
invoice final.pdf                   Documents/Invoices/invoice-final.pdf
setup.dmg                           Installers/setup.dmg

[Apply 12 changes] [Export plan] [Cancel]
```

Use a two-column diff-style table. Do not use generic cards for every file.

### 8.7 Enhanced Finder

Enhanced Finder should look like a native Finder history inspector.

Visual target:

```text
Enhanced Finder
Switch back to recent folders and clean history.

[ Search folders... ]

Today
  ~/Downloads/UI Audit Demo Bulk       7 visits
  ~/Desktop/Screenshots                3 visits
  ~/Documents/Invoices                 1 visit

Excluded
  ~/Library
  ~/.Trash
```

Use folder path rows with small folder icons and compact metadata.

### 8.8 Window Layouts

Window Layouts should feel precise and geometric.

Visual target:

```text
Window Layouts                                Active
Arrange, snap, and restore windows.

Shortcuts
┌ Left Half ┐ ┌ Right Half ┐ ┌ Top Half ┐ ┌ Center ┐
│  ⌃ ←      │ │  ⌃ →       │ │  ⌃ ↑     │ │  ⌃ C   │
└───────────┘ └────────────┘ └──────────┘ └────────┘

Radial Preview
[monochrome grid with selected region filled]
```

The radial overlay may use a very subtle translucent blue only if it comes from a legacy system highlight; target design should be black-white fill with 12-18% opacity.

### 8.9 Window Grab

Window Grab should be visualized as a lightweight interaction setup page plus runtime outline.

Main page visual target:

```text
Window Grab                                  Active
Move windows by holding a modifier and dragging anywhere.

Trigger: ⌥ + drag
Ignored apps: 4
Snap preview: enabled

[Test Grab] [Change Trigger]
```

Runtime target:

- thin monochrome outline around grabbed window
- snap target appears as translucent black/white rectangle
- release flashes target for 80-120 ms

### 8.10 Windows Hub

Windows Hub should become the most polished runtime feature.

Main page visual target:

```text
Windows Hub                                  ⌥ ⇧ W
Search apps, windows, and tabs from a floating panel.

[Open Window Hub]

Permissions
Accessibility       Granted
Browser tabs        Enabled
Background apps     Off
```

Floating panel visual target:

```text
┌──────────────────────────────────────────────────────────┐
│ Search apps, windows, tabs...                 AI Organize │
├──────────────────────────────────────────────────────────┤
│ Chrome                          2 windows · 40 tabs       │
│   YouTube                       youtube.com               │
│   Gmail                         mail.google.com           │
│ Cursor                          2 windows · 2 tabs        │
│   mac-all-you-need              github.com                │
└──────────────────────────────────────────────────────────┘
```

Use masonry only if scanability remains high. Otherwise use grouped list with app sections.

### 8.11 Settings

Settings should be the calmest part of the app.

Visual target:

```text
Settings

General
  Launch at login                         [toggle]
  Show menu bar icon                      [toggle]
  Play sound feedback                     [toggle]

Permissions
  Accessibility                           Granted
  Microphone                              Granted
  Screen Recording                        Needs permission

Shortcuts
  Clipboard History                       ⌘ ⇧ V
  Voice Dictation                         ⌥ Space
  Window Hub                              ⌥ ⇧ W
```

Use grouped settings rows, not feature cards.

### 8.12 Onboarding

Onboarding should be clear and premium.

Flow:

1. Welcome
2. Choose features
3. Grant permissions
4. Set shortcuts
5. Ready

Feature selection visual:

```text
Choose what Mayn should run.

[✓ Clipboard History] [✓ Voice Dictation]
[✓ Downloads]         [✓ Windows Hub]
[  AI File Organizer] [  Enhanced Finder]
```

Selected tile: black fill / white text. Unselected tile: white/transparent fill / hairline border / black text.

No colorful feature tiles.

---

## 9. Motion System

### 9.1 Motion principle

> Fast in. Calm out. Never decorative.

Motion should communicate state changes and reduce uncertainty. It should not become the focus.

### 9.2 Motion tokens

```css
:root {
  --motion-instant: 80ms;
  --motion-fast: 120ms;
  --motion-standard: 180ms;
  --motion-panel: 220ms;
  --motion-complex: 280ms;

  --ease-standard: cubic-bezier(0.2, 0.8, 0.2, 1);
  --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  --ease-in: cubic-bezier(0.7, 0, 0.84, 0);
  --ease-emphasized: cubic-bezier(0.2, 0.9, 0.1, 1);

  --scale-pressed: 0.985;
  --scale-panel-start: 0.975;
  --scale-hud-start: 0.94;
}
```

### 9.3 Duration standards

| Interaction | Duration |
|---|---:|
| hover | 80-120 ms |
| button press | 80-100 ms |
| toggle | 120-160 ms |
| sidebar active change | 140-180 ms |
| page transition | 160-220 ms |
| command palette open | 160-200 ms |
| command palette close | 120-160 ms |
| HUD open | 140-180 ms |
| toast enter | 180-220 ms |
| toast exit | 120-160 ms |
| radial menu open | 140-180 ms |
| row insert | 160-200 ms |
| progress shimmer cycle | 900-1200 ms |

Hard rule: common UI transitions should not exceed 280 ms.

### 9.4 Page transition

Use opacity and small vertical movement only.

- exiting page: opacity 1 -> 0, y 0 -> -4 px, 100 ms
- entering page: opacity 0 -> 1, y 8 px -> 0, 180 ms

Do not slide full pages horizontally.

### 9.5 Command palette animation

Open:

- overlay opacity 0 -> 1
- palette opacity 0 -> 1
- palette scale 0.975 -> 1
- palette y -8 px -> 0
- duration 180 ms

Close:

- opacity 1 -> 0
- scale 1 -> 0.985
- duration 120 ms

Result changes:

- rows crossfade within 120 ms
- active row movement should be immediate
- stagger max: 12 ms per row, total not over 80 ms

### 9.6 Sidebar animation

- hover fill: 100 ms
- active background: 160 ms
- icon/text color: 120 ms crossfade
- no bounce
- no glowing indicator

### 9.7 Card hover and press

Hover:

- translateY: -1 px
- border: hairline -> soft
- duration: 120 ms

Press:

- scale: 1 -> 0.985
- duration: 80 ms

### 9.8 Toggle animation

- knob slides: 140 ms
- track inverts: 120 ms
- label updates after 40 ms
- no bounce

### 9.9 Clipboard Dock animation

Enter:

- opacity 0 -> 1
- translateY 16 px -> 0
- scale 0.96 -> 1
- duration 180 ms

Exit:

- opacity 1 -> 0
- translateY 0 -> 10 px
- duration 130 ms

Copy feedback:

- selected row flashes inverted for 100 ms
- toast enters immediately after row flash starts

### 9.10 Voice HUD animation

Idle -> Listening:

- HUD opacity 0 -> 1
- scale 0.94 -> 1
- y 8 px -> 0
- duration 150 ms

Listening:

- dot opacity 0.35 -> 1 -> 0.35
- dot scale 0.86 -> 1 -> 0.86
- dot cycle: 900 ms
- waveform bars cycle: 700-900 ms
- bar stagger: 60 ms

Listening -> Transcribing:

- waveform opacity drops to 30%
- label changes to `Transcribing...`
- pulsing line appears
- duration 160 ms

Transcribing -> Done:

- label changes to `Inserted`
- HUD compresses slightly
- fade out after 600-900 ms

### 9.11 Downloads animation

New file:

- row opacity 0 -> 1
- x 12 px -> 0
- duration 180 ms

Progress:

- thin progress line
- shimmer cycle 1000 ms
- opacity 0.45

Completed:

- row background inverts at 8% opacity
- status updates to `Moved` / `Completed`
- duration 220 ms

Failed:

- no shake
- border strengthens
- warning icon appears
- duration 160 ms

### 9.12 Window Hub animation

Open:

- opacity 0 -> 1
- scale 0.96 -> 1
- y -6 px -> 0
- duration 160 ms

Navigate rows:

- active row changes immediately
- metadata fades 80 ms

Select:

- selected row flashes inverse for 80 ms
- panel closes in 120 ms

### 9.13 Radial layout animation

Open:

- center dot appears first
- options expand from center
- opacity 0 -> 1
- scale 0.8 -> 1
- duration 150 ms

Hover:

- target region fills black/white at 12-18% opacity
- label appears in 100 ms

Select:

- selected region holds for 80 ms
- overlay fades 120 ms
- actual window movement starts immediately

### 9.14 Window Grab animation

Start:

- outline opacity 0 -> 1
- duration 100 ms

Snap target:

- target rectangle opacity 0 -> 1
- duration 80 ms

Release:

- target fill flashes 80 ms
- outline fades 120 ms

No elastic dragging.

### 9.15 Reduced motion

Respect reduced motion.

```css
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 1ms !important;
    transition-duration: 1ms !important;
    scroll-behavior: auto !important;
  }
}
```

Reduced motion behavior:

- keep opacity changes
- remove transform movement
- remove shimmer
- replace waveform with static bars or pulsing dot only
- disable radial expansion

---

## 10. Iconography

Icon style:

- stroke-based
- 1.5 px stroke
- rounded caps
- rounded joins
- monochrome
- 16 px sidebar
- 18-20 px cards
- 24-32 px empty states

Recommended icons:

| Feature | Icon |
|---|---|
| Dashboard | 2x2 grid |
| Clipboard | clipboard outline |
| Voice | waveform or microphone outline |
| Downloads | arrow down into tray |
| AI File Organizer | folder with small command mark |
| Enhanced Finder | folder clock |
| Window Layouts | split grid |
| Window Grab | cursor + window outline |
| Windows Hub | overlapping rectangles |
| Settings | gear |

Avoid emoji, 3D icons, and colorful symbol fills.

---

## 11. Accessibility

### 11.1 Contrast

- primary text must meet WCAG AA
- secondary text should remain legible on panel backgrounds
- tertiary text must not carry critical status
- selected rows must be readable in both modes

### 11.2 Focus

Every interactive element needs visible focus.

```css
:focus-visible {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
```

SwiftUI equivalent:

- use focus rings for text fields
- use `@FocusState` for keyboard navigation
- keep focus visible inside command palette, clipboard dock, and window hub

### 11.3 Keyboard rules

- `Esc` closes overlays
- `Enter` confirms selected action
- arrow keys navigate lists
- `Space` previews or toggles depending context
- `Cmd+K` opens command palette
- command palette should expose all primary actions

---

## 12. Copywriting

Voice:

- direct
- short
- utility-like
- no hype
- no vague AI promise

Good examples:

- Ready
- Listening
- Transcribing...
- Inserted
- Needs Accessibility
- Watching Downloads
- 4 downloads failed
- Open Window Hub
- Retry Failed
- Run Scan
- Apply 12 changes

Bad examples:

- Unlock productivity
- Experience magic
- Powered by next-generation AI
- Supercharge your Mac
- Seamlessly revolutionize your workflow

---

## 13. Do / Don't

### Do

- use black and white as the primary visual identity
- use monochrome active states
- make shortcuts visible
- make runtime overlays polished
- keep settings native and quiet
- use dense lists for history and windows
- use subtle borders and restrained shadows
- make animation fast and interruptible
- make command palette central

### Don't

- do not use colorful feature-card borders
- do not use system green toggles as brand color
- do not use blue focus rings unless unavoidable
- do not use gradients
- do not use emoji icons
- do not overuse shadows
- do not create marketing-style dashboard hero sections
- do not make every feature page visually different
- do not use slow bounce animations
- do not require color to understand state

---

## 14. AI / Agent Prompt

When generating Mayn UI, use this prompt:

```text
Build Mayn as a monochrome native macOS productivity app. The UI should feel like a system-level command layer for clipboard memory, voice dictation, downloads, Finder workflows, file organization, and window management. Use only black, white, and grayscale for core UI. Do not use colorful cards, gradients, emoji icons, or SaaS dashboard styling. Use SF Pro/system typography, compact native spacing, hairline borders, black-white inverted selected states, keyboard shortcut keycaps, dense lists, command palette patterns, and polished floating HUDs. Motion should be fast, quiet, interruptible, and mostly opacity/transform based: hover 80-120ms, panels 160-220ms, overlays under 200ms, no bounce, no decorative animation.
```

Animation prompt:

```text
Implement Mayn motion as fast in, calm out. Use opacity, scale, and small translate values only. Use cubic-bezier(0.16, 1, 0.3, 1) for panel entrances, cubic-bezier(0.7, 0, 0.84, 0) for exits, and keep common transitions under 220ms. Command palette opens with opacity + scale 0.975 to 1. Voice HUD opens with scale 0.94 to 1 and uses a monochrome waveform. Clipboard Dock slides up 16px. Window Hub scales from 0.96. Radial menu expands from center in 150ms. Toasts are black/white pills. Respect prefers-reduced-motion.
```

---

## 15. Design QA Checklist

Before shipping any screen, check:

- Does it work in black and white?
- Is the active state clear without color?
- Is the primary action obvious?
- Is the shortcut visible if the action is frequent?
- Are icons monochrome and consistent?
- Is the page using the shared header pattern?
- Are settings rows native and compact?
- Are runtime overlays more polished than settings pages?
- Does the animation finish quickly?
- Can the surface be operated by keyboard?
- Does it feel like a macOS utility, not a website?

