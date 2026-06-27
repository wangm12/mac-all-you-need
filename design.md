---
version: 2.0
product: Mayn / MacAllYouNeed
direction: Monochrome Native Command Layer — Apple Liquid Glass
platform: macOS desktop app, SwiftUI + AppKit native
primary_color_system: black-white-grayscale
status: final design guide
intended_readers:
  - product designers
  - SwiftUI engineers
  - AppKit engineers
  - AI coding agents
  - design QA reviewers
references:
  - https://developer.apple.com/documentation/technologyoverviews/liquid-glass
  - https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
  - https://developer.apple.com/design/human-interface-guidelines/materials
  - https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
---

# Mayn DESIGN.md

Mayn is a black-and-white native macOS command layer for clipboard memory, voice input, downloads, Finder workflows, file organization, and window control.

Mayn should feel like a quiet system utility: invisible until needed, instant when invoked, precise in every interaction, and restrained even when many features are enabled.

Core direction:

> Invisible until needed. Precise when invoked. Black, white, native, fast — with Liquid Glass depth only where it improves control hierarchy.

---

## 0. Final design position

Mayn is not a SaaS dashboard, a colorful productivity suite, or a marketing-first AI app.

It should feel closer to:

- Finder sidebar structure
- System Settings density
- Spotlight / Raycast command speed
- native macOS floating HUDs
- a premium menu-bar utility

The main app window is for configuration, review, and history. The runtime overlays are the product.

### Design sentence

```text
A black-and-white native macOS command center with stable content surfaces, Liquid Glass controls and selection, and fast keyboard-first overlays.
```

### What must be visible in every screen

- Native macOS structure
- Black / white / grayscale system
- Crisp text
- Clear selected state
- Compact spacing
- Visible shortcut hints
- No decorative color
- No muddy full-window blur
- Selected rows use Liquid Glass, not solid inversion fills

---

## 1. Core principles

### 1.1 Native first

Use system components first. Do not rebuild macOS chrome manually unless a runtime overlay requires it.

Use:

- `NavigationSplitView` for main navigation
- native `.toolbar` for top actions
- system search fields where possible
- native `Button`, `Toggle`, `TextField`, `List`, `Table`, `Form` behavior
- AppKit `NSPanel` only for runtime HUDs that need to float above other apps

Avoid:

- custom web-style titlebars
- custom sidebar backgrounds that fight system chrome
- full-window glass overlays
- non-native scrollbars
- custom focus handling that breaks keyboard expectations

### 1.2 Monochrome first

Mayn's brand system is black, white, and grayscale.

Feature identity must come from:

- icon
- label
- layout position
- keyboard shortcut
- state copy
- motion behavior

Feature identity must not come from:

- bright feature colors
- gradient cards
- colorful borders
- emoji
- decorative illustrations

Do not map features to colors:

```text
Clipboard != blue
Voice != purple
Downloads != green
Windows != orange
AI != rainbow sparkle
```

### 1.3 Liquid Glass is chrome, not content

Liquid Glass belongs to the functional layer: navigation, controls, floating command surfaces, HUD shells, and transient overlays.

Content uses stable standard surfaces.

Use Liquid Glass for:

- global toolbar search pill
- attention badge
- command palette shell
- segmented control track
- popovers
- floating HUD shells
- Window Hub shell
- Clipboard Dock shell
- radial layout menu shell

Do not use Liquid Glass for:

- every dashboard card
- dense list rows
- long text panels
- settings rows
- selected command rows
- selected sidebar rows
- clipboard list selection
- whole app background

Rule:

```text
Glass is the control and selection material.
Stable panels are the content layer.
```

### 1.4 Liquid Glass selection

Keyboard-focused and pointer-selected interactive rows use **Liquid Glass** — not solid black/white inversion fills.

Follow [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass):

- Apply `glassEffect(.regular, in: shape)` to the selected row/chip via `MAYNSelectionGlassBackground` / `maynSelectionBackground`.
- Keep labels **`.primary`** on glass selection (`MAYNSelectionLabelStyle`) — do not invert text to white-on-black.
- Use `GlassEffectContainer` only when multiple glass controls morph together (toolbar search → command palette, attention badge → popover).
- Do not stack a parent glass shell and a child glass selection on the same pixel without a sharp opaque content layer between them.

Use Liquid Glass selection for:

- selected sidebar item
- selected command palette row
- selected clipboard history row
- selected Window Hub row
- selected Clipboard Dock card
- segmented control selected tab
- feature-picker tile during onboarding
- filter chips and compact list rows

Reserve solid inversion fills only for:

- copy / action toasts (`CopyHUD`)
- rare destructive confirmation emphasis when glass would be illegible

Never put opaque inversion fills on routine navigation rows.

### 1.5 Keyboard-first

Every primary action must be reachable by keyboard.

Required commands:

- `⌘K` opens command palette
- `Esc` closes overlays
- `↑` / `↓` navigate command lists
- `Return` executes selection
- `⌘1` to `⌘9` execute visible quick actions where appropriate
- `Space` previews or toggles depending context
- `Tab` only moves focus when arrow navigation is not available

### 1.6 Dense but calm

Mayn handles lists, files, history, downloads, windows, settings, permissions, and runtime state. Density is required.

Good density:

- sidebar item: 38-40 px
- command row: 46-48 px
- history row: 52-60 px
- settings row: 48-56 px
- toolbar control: 34-38 px
- card padding: 18-22 px
- page section gap: 20-28 px

Bad density:

- huge feature cards with empty bodies
- oversized icons
- repeated decorative panels
- marketing hero sections
- sparse forms that hide important system state

---

## 2. Liquid Glass architecture

### 2.1 Platform guidance

On macOS 26+, use system Liquid Glass through native SwiftUI / AppKit components first. Standard components such as bars, sheets, popovers, controls, and navigation pick up the latest system material automatically when built with current SDKs.

Custom Liquid Glass should be limited to high-value functional surfaces. It should not be used as a general background texture.

### 2.2 Material layer model

Use five visual layers.

| Layer | Name | Role | Material | Examples |
|---|---|---|---|---|
| L0 | Window base | stable app foundation | system window background / opaque token | main app window |
| L1 | Content | readable content and data | standard material or opaque panel | dashboard cards, clipboard list, settings groups |
| L2 | System chrome | native navigation | system-managed sidebar / toolbar glass | `NavigationSplitView`, `.toolbar` |
| L3 | Floating controls | compact interactive chrome | Liquid Glass | search pill, badge, segmented track |
| L4 | Runtime overlays | command / HUD surfaces | Liquid Glass shell + sharp content layer | command palette, Voice HUD, Clipboard Dock, Window Hub |

### 2.3 Scope rules

```text
Do not wrap NavigationSplitView in GlassEffectContainer.
Do not wrap page content in GlassEffectContainer.
Do not place glassEffect on every card.
Do not stack glassEffect on a panel and also on the search field inside it.
Use glassEffect for selected rows via MAYNSelectionGlassBackground — one glass layer per selected control.
```

Use `GlassEffectContainer` only when multiple glass controls need to visually belong together or morph:

- toolbar search pill → command palette search header
- attention badge → attention popover
- Window Hub search field + quick action chip
- Voice HUD is a **single** shaped glass capsule (392×58); do not group a separate caption chip with the hub pill

### 2.4 Custom glass shape rule

The default `glassEffect` shape is capsule-like. For large surfaces, always specify shape.

```swift
.glassEffect(.regular, in: .rect(cornerRadius: 28))
```

Use capsule only for:

- search pill
- status pill
- key action badge
- Voice hub pill
- compact HUD controls

Use rounded rectangle for:

- command palette
- Clipboard Dock
- Window Hub
- popover panels
- segmented track

### 2.5 macOS fallback strategy

| Surface | macOS 26+ | macOS 14-25 fallback |
|---|---|---|
| main shell | `NavigationSplitView` + system chrome | same structure, system window + vibrancy |
| toolbar search | single `glassEffect(.regular, in: Capsule())` | `NSVisualEffectView` / `thinMaterial` |
| command palette shell | `GlassEffectContainer` + shaped glass | `regularMaterial` + hairline + shadow |
| dense content cards | opaque content tokens | opaque content tokens |
| clipboard list | opaque list panel | opaque list panel |
| selected rows | `glassEffect(.regular, in: rowShape)` via `maynSelectionBackground` | `MAYNTheme.selected` fill |
| Voice HUD | shaped glass in borderless panel | `NSVisualEffectView` in non-activating panel |
| copy toast | solid inversion pill | solid inversion pill |

### 2.6 Reduce Transparency behavior

When Reduce Transparency is enabled:

- replace glass surfaces with opaque elevated panels
- keep borders and shadows subtle
- replace glass selection with `MAYNTheme.selected` opaque fill
- remove background sampling effects
- keep toolbar search and command palette visually distinct with elevation and border

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
```

### 2.7 Reduce Motion behavior

When Reduce Motion is enabled:

- keep opacity changes
- remove scale and translate movement
- replace morph animations with crossfade
- remove shimmer
- make waveform static or use one pulsing dot
- disable radial expansion

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

---

## 3. Color system

### 3.1 Hard rule

The default UI is black, white, and grayscale only.

Color is allowed only when it comes from:

- app icons or file thumbnails
- media thumbnails
- macOS permission UI
- user content
- unavoidable external status assets

Even then, it should be small, contained, and visually secondary.

### 3.2 Light mode tokens

```css
:root {
  color-scheme: light;

  --mayn-black: #090909;
  --mayn-white: #ffffff;

  /* L0 window */
  --bg-app: #f5f5f2;
  --bg-window: #fbfbf8;

  /* L1 content */
  --bg-content: #fbfbf8;
  --bg-panel: #ffffff;
  --bg-panel-elevated: #f4f4f1;
  --bg-list: #ffffff;
  --bg-inset: #eeeeeb;

  /* L3 / L4 glass reference fallback */
  --bg-glass: rgba(255, 255, 255, 0.72);
  --bg-glass-strong: rgba(255, 255, 255, 0.84);
  --bg-glass-border: rgba(255, 255, 255, 0.78);

  /* text */
  --text-primary: rgba(9, 9, 9, 0.94);
  --text-secondary: rgba(9, 9, 9, 0.66);
  --text-tertiary: rgba(9, 9, 9, 0.44);
  --text-disabled: rgba(9, 9, 9, 0.30);
  --text-inverse: #ffffff;

  /* borders */
  --border-hairline: rgba(0, 0, 0, 0.08);
  --border-soft: rgba(0, 0, 0, 0.13);
  --border-strong: rgba(0, 0, 0, 0.22);

  /* interaction */
  --hover: rgba(0, 0, 0, 0.045);
  --pressed: rgba(0, 0, 0, 0.075);
  --selected-bg: #090909;
  --selected-fg: #ffffff;

  /* controls */
  --control-primary-bg: #090909;
  --control-primary-fg: #ffffff;
  --control-secondary-bg: #ffffff;
  --control-secondary-fg: #090909;
  --control-secondary-border: rgba(0, 0, 0, 0.12);

  /* overlays */
  --scrim-command: rgba(0, 0, 0, 0.22);
  --hud-bg: #090909;
  --hud-fg: #ffffff;
}
```

### 3.3 Dark mode tokens

```css
[data-theme="dark"] {
  color-scheme: dark;

  --mayn-black: #000000;
  --mayn-white: #ffffff;

  /* L0 window */
  --bg-app: #070708;
  --bg-window: #0b0b0c;

  /* L1 content */
  --bg-content: #101011;
  --bg-panel: #171718;
  --bg-panel-elevated: #1d1d1f;
  --bg-list: #151516;
  --bg-inset: #242426;

  /* L3 / L4 glass reference fallback */
  --bg-glass: rgba(28, 28, 30, 0.72);
  --bg-glass-strong: rgba(34, 34, 36, 0.82);
  --bg-glass-border: rgba(255, 255, 255, 0.15);

  /* text */
  --text-primary: rgba(255, 255, 255, 0.92);
  --text-secondary: rgba(255, 255, 255, 0.66);
  --text-tertiary: rgba(255, 255, 255, 0.44);
  --text-disabled: rgba(255, 255, 255, 0.32);
  --text-inverse: #090909;

  /* borders */
  --border-hairline: rgba(255, 255, 255, 0.08);
  --border-soft: rgba(255, 255, 255, 0.13);
  --border-strong: rgba(255, 255, 255, 0.22);

  /* interaction */
  --hover: rgba(255, 255, 255, 0.065);
  --pressed: rgba(255, 255, 255, 0.105);
  --selected-bg: #f4f4f4;
  --selected-fg: #090909;

  /* controls */
  --control-primary-bg: #ffffff;
  --control-primary-fg: #090909;
  --control-secondary-bg: #171718;
  --control-secondary-fg: #ffffff;
  --control-secondary-border: rgba(255, 255, 255, 0.13);

  /* overlays */
  --scrim-command: rgba(0, 0, 0, 0.44);
  --hud-bg: #f4f4f4;
  --hud-fg: #050505;
}
```

### 3.4 SwiftUI token mapping

Centralize tokens in `MAYNTokens.swift`.

```swift
enum MAYNTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let contentPanel = Color("MAYNContentPanel")
    static let contentPanelElevated = Color("MAYNContentPanelElevated")
    static let contentListPanel = Color("MAYNContentListPanel")

    static let textPrimary = Color.primary.opacity(0.92)
    static let textSecondary = Color.primary.opacity(0.66)
    static let textTertiary = Color.primary.opacity(0.44)
    static let textDisabled = Color.primary.opacity(0.32)

    static let hairline = Color.primary.opacity(0.08)
    static let softBorder = Color.primary.opacity(0.13)
    static let strongBorder = Color.primary.opacity(0.22)

    static let hover = Color.primary.opacity(0.06)
    static let pressed = Color.primary.opacity(0.10)

    static let activeFill = Color.primary
    static let activeText = Color(nsColor: .windowBackgroundColor)
}
```

Do not hard-code `.blue`, `.green`, `.purple`, `.orange`, or `.red` in normal Mayn UI.

### 3.5 Status tags

Status pills use small semantic color families (success, warning, danger, progress, neutral) via `MAYNStatusTagPalette`. Pair color with icon + text; never rely on color alone.

| Status | Visual | Icon | Copy |
|---|---|---|---|
| Ready / Enabled | green-tinted pill | checkmark optional | `Ready`, `Enabled` |
| Running / Active | blue-tinted pill or dot + label | dot | `Running`, `Listening` |
| Paused | amber outline pill | pause | `Paused` |
| Needs setup | amber outline pill | exclamationmark.circle | `Needs Setup` |
| Failed | red-tinted pill + warning icon | exclamationmark.triangle | `Failed`, `Review` |
| Processing | blue progress line + label | none or dot | `Processing` |

Download progress bars use `MAYNTheme.success`, `.danger`, `.warning`, and `.progress` — not monochrome primary fills.

---

## 4. Typography

### 4.1 Font

Use macOS system typography.

```swift
.font(.system(size: size, weight: weight, design: .default))
```

CSS reference:

```css
font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", system-ui, sans-serif;
```

Use monospaced only for:

- keyboard shortcuts
- file paths
- technical IDs
- durations
- terminal-like snippets

### 4.2 Type scale

| Token | Size | Weight | Line height | Use |
|---|---:|---:|---:|---|
| Display | 32 | 650 | 38 | onboarding hero only |
| Page title | 28 | 650 | 34 | page headers |
| Large section | 18 | 650 | 24 | dashboard tool card title |
| Section title | 15 | 600 | 21 | section headings |
| Row title | 14 | 550 | 20 | command/list rows |
| Body | 13 | 400 | 19 | normal text |
| Body strong | 13 | 550 | 19 | labels / metadata title |
| Caption | 12 | 400 | 16 | secondary copy |
| Micro | 11 | 550 | 14 | section labels, badges |
| Keycap | 11 | 600 | 14 | shortcuts |

### 4.3 Text contrast by mode

| Text role | Light | Dark |
|---|---|---|
| Primary | 94% black | 92% white |
| Secondary | 66% black | 66% white |
| Tertiary | 44% black | 44% white |
| Disabled | 30% black | 32% white |
| Selected | white on black | black on white |

Do not put critical labels in tertiary or disabled color.

### 4.4 Copy tone

Use short, direct, functional copy.

Good:

- `Ready`
- `Listening`
- `Transcribing...`
- `Inserted`
- `Needs Accessibility`
- `Watching Downloads`
- `Review 4 downloads`
- `Open Clipboard Dock`
- `Apply 12 changes`

Bad:

- `Unlock productivity`
- `Experience magic`
- `Supercharge your Mac`
- `Your AI-powered future workflow assistant`

---

## 5. Layout system

### 5.1 Main window shell

Use `NavigationSplitView` for the app shell.

```text
┌────────────────────────────────────────────────────────────────┐
│  ● ● ●                         [ Search Mayn  ⌘K ] [Status]   │
├───────────────────────┬────────────────────────────────────────┤
│ Sidebar               │ Detail content                         │
│ Core                  │ Page header                            │
│ Automation            │ Page controls                          │
│ Windows               │ Content panels / lists                 │
│                       │                                        │
│ Settings              │                                        │
└───────────────────────┴────────────────────────────────────────┘
```

Default:

- window width: 1120 px
- window height: 760 px
- minimum width: 920 px
- minimum height: 640 px
- sidebar width: 260 px
- collapsed sidebar: 56 px
- page content max width: 1120 px
- page side padding: 32 px
- main content top padding: 32 px from toolbar

### 5.2 Sidebar

Sidebar should feel Finder-like, not like a web app rail.

Specs:

- width: 260 px
- collapsed width: 56 px
- item height: 40 px
- item radius: 12 px
- item horizontal padding: 12 px
- icon: 16 px SF Symbol, monochrome
- label: 13.5 px / medium when selected
- section label: 11 px / 600 / uppercase / 0.45 letter spacing

Navigation groups:

```text
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

Active item:

- light mode: black gradient pill + white text
- dark mode: white gradient pill + black text
- no glass over text
- no blur on text

Disabled item:

- lower opacity
- optional `Setup` micro-pill if an action is required
- never merely gray out without explanation

### 5.3 Toolbar

Use native `.toolbar` on the detail column.

Contents:

- principal: global search pill
- trailing: attention badge / runtime status
- optional: page-specific action only if frequent

Global search pill:

- height: 36-38 px
- width: 240-320 px depending window size
- radius: capsule
- icon: magnifying glass, 14-15 px
- placeholder: `Search Mayn`
- right keycap: `⌘K`
- Liquid Glass, single layer

Behavior:

- click or `⌘K` opens command palette
- search pill morphs into command palette header on macOS 26+
- if morph is not available, fade search pill to opacity 0 during palette session
- never show toolbar search and command palette search as competing active controls

### 5.4 Attention badge

Top-right badge is a compact control, not a warning banner.

Copy:

```text
Review 4 downloads
```

Not:

```text
4 downloads need attention
```

Specs:

- height: 32-34 px
- radius: capsule
- padding: 10-12 px horizontal
- dot: 6 px monochrome
- font: 12 px / 600
- max width: 210 px
- one glass layer only
- no duplicate border / ghost ring

When command palette opens:

- badge fades out or becomes part of dimmed background
- attention items appear inside command palette under `Attention`

### 5.5 Page header

Every page uses the same header structure.

```text
Page Title                                      Primary action / shortcut
Short functional description.
```

Specs:

- title: 28 px / 650
- subtitle: 13 px / secondary
- header bottom gap: 20-24 px
- right control: labelled action, not shortcut-only if unclear

Example:

```text
Clipboard                                      Open Dock  ⇧⌘V
History, snippets, and paste behavior for local clipboard memory.
```

### 5.6 Spacing

Use a 4 px grid.

```text
4, 8, 12, 16, 20, 24, 32, 40, 48, 64
```

Rules:

- page side padding: 32 px
- section gap: 24 px
- card gap: 12-16 px
- list row vertical padding: 10-14 px
- compact filter bar: 34-38 px
- settings row: 48-56 px

---

## 6. Shape, borders, and elevation

### 6.1 Radius tokens

| Component | Radius |
|---|---:|
| keycap | 7 px |
| sidebar item | 12 px |
| small button | 10 px |
| search field | 12 px or capsule |
| card | 18-20 px |
| list panel | 20 px |
| command palette | 28 px |
| HUD | 20-24 px |
| pill | capsule |

### 6.2 Border usage

Use hairline borders for structure, not decoration.

- content panel: hairline
- list panel: hairline
- card: hairline
- selected card: Liquid Glass via `maynSelectionBackground` on dock cards; hairline focus ring optional
- floating control: glass highlight + subtle border
- command palette: gradient/hairline border + shadow

Do not use colored borders for feature states.

### 6.3 Elevation

| Elevation | Use | Shadow guidance |
|---|---|---|
| 0 | page background | none |
| 1 | content panels | hairline only |
| 2 | normal cards | minimal |
| 3 | sticky filter bar / active panel | subtle |
| 4 | popover / dropdown | clear floating shadow |
| 5 | command palette / HUD / Window Hub | strong but clean shadow |

Dark mode floating shadow:

```css
box-shadow:
  inset 0 1px 0 rgba(255,255,255,0.10),
  0 28px 80px rgba(0,0,0,0.68);
```

Light mode floating shadow:

```css
box-shadow:
  inset 0 1px 0 rgba(255,255,255,0.85),
  0 24px 70px rgba(0,0,0,0.24);
```

---

## 7. Component system

### 7.1 Buttons

#### Primary button

Use for committed actions.

Light:

- black fill
- white text

Dark:

- white fill
- black text

Specs:

- height: 36-40 px
- radius: 10-12 px
- font: 13 px / 600
- no color accents

Examples:

- `Grant Permission`
- `Start Dictation`
- `Apply 12 changes`
- `Open Window Hub`

#### Secondary button

Use for non-primary actions.

- content panel background or transparent
- hairline border
- primary text
- height: 34-38 px
- radius: 10-12 px

#### Ghost button

Use for low-risk secondary actions.

- transparent
- secondary text
- hover fill only
- no border by default

### 7.2 Toggles

Toggles must be monochrome.

On:

- light mode: black track + white knob
- dark mode: white track + black knob

Off:

- muted track
- hairline border
- secondary knob

Specs:

- width: 44 px
- height: 26 px
- knob: 20 px
- animation: 140 ms, no bounce

Do not use system green as the Mayn brand state.

### 7.3 Keycaps

Specs:

- height: 22-24 px
- padding: 7-8 px horizontal
- radius: 7 px
- font: 11 px / 600
- background: subtle panel fill
- border: hairline

Selected row keycap must invert with selected row.

### 7.4 Segmented control

Used for page tabs like History / Snippets / Settings.

Specs:

- height: 36-38 px
- radius: capsule
- track: single Liquid Glass surface or elevated standard surface
- selected tab: glass pill only if text stays crisp
- icon: 13-14 px
- label: 12-13 px / 600
- width: fit-content or max 620 px, not necessarily full page width

### 7.5 Search and filter bars

Search is a first-class control.

Compact search:

- height: 34-38 px
- radius: 12 px or capsule
- left icon: 14 px
- right metadata: count / shortcut / filter state

Large data surfaces should have:

```text
[ Search clipboard...                         983 items ] [Type: All] [Sort: Recent]
```

Do not hide search behind a menu on history-heavy pages.

### 7.6 Cards

Cards are content surfaces, not glass surfaces.

Specs:

- background: content panel
- border: hairline
- radius: 18-20 px
- padding: 18-22 px
- hover: border stronger + background slightly lifted
- no decorative gradient
- no colorful icon background

Feature card layout:

```text
┌─────────────────────────────────────────────┐
│ [icon] Clipboard                    Enabled │
│ Capture, search, pin, paste snippets.       │
│                                             │
│ 30 items saved                Open Dock ⇧⌘V │
└─────────────────────────────────────────────┘
```

Disabled card layout:

```text
┌─────────────────────────────────────────────┐
│ [icon] Downloads                Needs Setup │
│ Download media and manage saved files.      │
│                                             │
│ Permission required                  Setup  │
└─────────────────────────────────────────────┘
```

Do not put an unlabeled toggle alone in the card corner.

### 7.7 Lists and rows

Lists are dense, sharp, and stable.

Specs:

- row height: 44-64 px depending content
- divider: hairline
- hover: subtle fill
- selection: Liquid Glass via `maynSelectionBackground` (`glassEffect(.regular, in: rowShape)` on macOS 26+)
- metadata: right aligned where possible
- actions: reveal on hover/focus unless critical

Clipboard / command / hub row selection:

```text
Selected row: glassEffect background, primary text (MAYNSelectionLabelStyle)
Reduce Transparency: MAYNTheme.selected opaque fill
```

Do not use glass row backgrounds for long lists.

### 7.8 Scrollbars

Prefer system overlay scrollbars.

If a custom scrollbar is unavoidable:

- visual width: 6-8 px
- no visible track
- idle opacity: 0
- scrolling/hover opacity: 35-45%
- radius: capsule

Never use thick permanent scrollbars in command palette or lists.

### 7.9 Status pills

Specs:

- height: 22-24 px
- radius: capsule
- padding: 8-10 px horizontal
- font: 11-12 px / 550
- icon: 9-11 px optional

Status language:

```text
Ready
Enabled
Needs Setup
Review
Paused
Failed
Running
Processing
```

Use icon + text for warning states.

### 7.10 Toasts

Specs:

- height: 34-38 px
- radius: capsule
- position: bottom center for runtime actions, top-right for in-window actions
- light mode: black pill + white text
- dark mode: white pill + black text
- duration: 1200-1800 ms

Copy:

- `Copied`
- `Inserted`
- `3 files organized`
- `Window moved left`
- `Permission granted`

No confetti. No green success animation.

---

## 8. Command palette

The command palette is Mayn's most important UI surface.

### 8.1 Role

It is a command surface, not a modal settings dialog.

It should answer:

```text
What can I do right now?
What needs attention?
Where can I go?
```

### 8.2 Structure

Use one unified shell.

```text
┌────────────────────────────────────────────────────┐
│  Search Mayn                                  esc  │
├────────────────────────────────────────────────────┤
│ CURRENT CONTEXT                                    │
│  Start dictation                          ⌥ Space  │
│  Open Clipboard Dock                       ⇧⌘V     │
│                                                    │
│ ATTENTION                                          │
│  Complete Voice setup                              │
│  Review 4 downloads                                │
│                                                    │
│ NAVIGATION                                         │
│  Dashboard                                         │
│  Clipboard                                 ⇧⌘V     │
│  Windows Hub                              ⌥⇧W      │
└────────────────────────────────────────────────────┘
```

### 8.3 Shell specs

| Token | Value |
|---|---|
| Width | 680 px |
| Max width | `min(680px, windowWidth - 160px)` |
| Max height | 560 px |
| Corner radius | 28 px continuous |
| Vertical anchor | top 104-128 px, not vertical center |
| Outer padding | 8 px |
| Search header | 58 px |
| Result row | 48 px |
| Row radius | 13 px |
| Icon column | 34 px |
| Shadow | elevation 5 |

### 8.4 Glass and backdrop

Shell:

- Liquid Glass shell only
- search header and rows are sharp content inside shell
- no glass on individual rows

Backdrop:

- dim inside app window only
- light mode: black 20-24%
- dark mode: black 40-46%
- blur: none or max 2 px
- do not make main app window transparent
- do not reveal desktop / browser through the main window

### 8.5 Toolbar morph

Preferred:

```text
toolbar search pill → command palette search header
```

Implementation direction:

```swift
GlassEffectContainer(spacing: 40) {
    if isCommandPaletteOpen {
        CommandPaletteShell()
            .glassEffectID("command-search", in: namespace)
    } else {
        ToolbarSearchPill()
            .glassEffectID("command-search", in: namespace)
    }
}
```

Fallback:

- toolbar search fades to opacity 0 in 100 ms
- command palette fades/scales in
- no duplicate search field stays visible

### 8.6 Search header

Specs:

- height: 58 px
- horizontal padding: 18 px
- placeholder: `Search Mayn`
- right keycap: `esc`
- bottom divider: hairline
- text: 14 px / 500

Avoid long placeholder copy like `Search actions, history, files, windows...` inside the opened palette. It looks web-like and gets truncated.

### 8.7 Section order

Empty query:

1. Current Context
2. Attention
3. Recent
4. Navigation
5. Settings

Filtered query:

- flat result list
- no section headers unless there are many grouped results

### 8.8 Selected row

Mandatory Liquid Glass selection per §1.4.

```swift
.maynSelectionBackground(isSelected: isSelected, isHovering: isHovering, shape: .rounded(radius))
```

Labels stay `.primary` / `MAYNSelectionLabelStyle` — never invert to white-on-black for routine rows.

Selected row should be inset, not full-bleed.

Specs:

- horizontal inset: 10 px
- radius: 13 px
- row height: 48 px
- selection animation: 90-100 ms

### 8.9 Keyboard behavior

- `⌘K`: open
- `Esc`: close
- `↑` / `↓`: move selection
- `Return`: activate
- `⌘1` to `⌘9`: quick activate visible top actions
- typing: immediate filter
- `Backspace` on empty query: no destructive action

### 8.10 Attention inside palette

Move active attention into the palette when it opens.

Examples:

- `Review 4 downloads`
- `Complete Voice setup`
- `Grant Accessibility permission`
- `Review failed downloads`

Top-right badge should fade out during palette session.

---

## 9. Runtime HUDs

### 9.1 Voice HUD

Voice should feel like system dictation, not an audio app.

Default: Liquid Glass.

Legacy option: Graphite.

> **Implementation (canonical):** [`design/voice_pill/mayn-voice-hud-liquid-glass-v3-bundle/VOICE_HUD_LIQUID_GLASS_V3_SPEC.md`](voice_pill/mayn-voice-hud-liquid-glass-v3-bundle/VOICE_HUD_LIQUID_GLASS_V3_SPEC.md). Interactive reference: [`mayn-voice-hud-liquid-glass-v3.html`](voice_pill/mayn-voice-hud-liquid-glass-v3-bundle/mayn-voice-hud-liquid-glass-v3.html).  
> A stacked caption chip above a separate hub pill is **deprecated**; use one fixed-size capsule for all runtime states.

Structure — **single Liquid Glass capsule** (fixed geometry every state):

```text
┌──────────────────────────────────────────────────────────────┐
│  [left 64]     Center label (optically centered)    [right 64] │
│  waveform/dot       Listening / Transcribing…        icon btn  │
└──────────────────────────────────────────────────────────────┘
         392 px × 58 px capsule — one glass layer only
```

Specs:

- width: **392 px**, height: **58 px**, radius: capsule
- left slot: **64 px** (waveform, dot, status icon) — always reserved
- center: flexible label, **optically centered** (reserve both side slots even when empty)
- right slot: **64 px** — icon-only action buttons **40×40** circular glass when present
- waveform box: **44×28 px**, monochrome
- text: primary at 92% on glass
- panel: borderless, non-activating, clear background
- no text buttons (`Stop`, `Undo 5s`); use SF Symbols only
- no purple mic branding, no nested glass, no ghost ring
- no red recording UI unless required by OS convention

Transcribing progress: full-bleed background wipe clipped by the capsule (z=0 behind content). Do not use an inner loading line inside content padding.

States (left | center label | right):

| State | Left | Center | Right |
|---|---|---|---|
| Idle | hidden | hidden | hidden |
| Starting | pulsing dot | `Starting` | empty |
| Listening | waveform | `Listening` | stop icon (`stop.fill`) |
| Transcribing | dim waveform | `Transcribing` | empty |
| Inserted | checkmark | `Inserted` | empty |
| Cancelled | x mark | `Cancelled` | undo icon + 5s countdown ring |
| Failed | warning | `Couldn't transcribe` | retry icon |

Inserted: show **600–900 ms** then fade out (do not dismiss instantly after paste).

### 9.2 Clipboard Dock

Bottom command shelf.

Specs:

- bottom anchored
- width: 720-900 px or adaptive
- height: 260-360 px
- radius: 22 px top corners / 24 px floating if detached
- shell: Liquid Glass if over desktop, standard panel if inside app
- selected row: Liquid Glass (`maynSelectionBackground`)
- first 9 rows show `⌘1` to `⌘9`

### 9.3 Window Hub

The most polished runtime surface.

Structure:

```text
┌──────────────────────────────────────────────────────────┐
│ Search apps, windows, tabs...                 AI Organize │
├──────────────────────────────────────────────────────────┤
│ Chrome                           2 windows · 40 tabs      │
│   YouTube                        youtube.com              │
│   Gmail                          mail.google.com          │
│ Cursor                           2 windows · 2 tabs       │
└──────────────────────────────────────────────────────────┘
```

Specs:

- width: 720-860 px
- max height: 620 px
- radius: 28 px
- shell: Liquid Glass
- row selection: Liquid Glass (`maynSelectionBackground`)
- grouped list preferred over masonry unless scanability stays high

### 9.4 Radial layout menu

Precise, not game-like.

- center anchored to cursor or active window
- monochrome layout regions
- selected region fill: black/white at 12-18% opacity
- label appears on hover
- no elastic / playful motion

### 9.5 Window Grab

Runtime feedback:

- grabbed window outline: 1.5 px monochrome
- snap target: translucent black/white rectangle
- release flash: 80-120 ms
- no rubber-band dragging

---

## 10. Feature surface guidelines

### 10.1 Dashboard

Dashboard is a system status board, not a feature catalog.

Preferred layout:

```text
Dashboard
Local tools, shortcuts, and current activity.

Status
Ready · 3 tools active · 400 saved files · Review 4 downloads

Recommended
[Review downloads] [Complete Voice setup] [Open Clipboard Dock]

Tools
[Clipboard] [Voice]
[Downloads] [Windows Hub]
[Enhanced Finder] [AI File Organizer]

Recent Activity
...
```

Rules:

- remove onboarding instructions after setup is ready
- no blue numbered circles
- no huge standalone numbers without context
- tool cards must show state, shortcut, last activity, and primary action
- disabled cards must explain why they are disabled

### 10.2 Clipboard

Clipboard is a fast memory browser.

Preferred layout:

```text
Clipboard                                      Open Dock ⇧⌘V
History, snippets, and paste behavior for local clipboard memory.

[ History ] [ Snippets ] [ Settings ]

All items                                      983 items
[ Search clipboard... ] [ Type: All ] [ Sort: Recent ]

Pinned
Today
  Text   Design direction for Mayn...       Cursor    5m    ⌘1
  Link   github.com/...                     Chrome    44m   ⌘2
  File   invoice.pdf                        Finder    1h    ⌘3
```

Rules:

- list is opaque and sharp, not blurry glass
- app icons may be colored but small and secondary
- source app metadata should not dominate
- selected row uses Liquid Glass selection (§1.4)
- hover actions: Copy, Pin, Delete, Reveal

### 10.3 Voice

Voice is system dictation.

Main page:

```text
Voice                                            ⌥ Space
Dictate into any app with local speech recognition.

Status
Ready · Sense Voice Small · Chinese + English

Recent Transcripts
  Inserted     帮我看一下...          6.5s    Jun 22
  Cancelled    Cancelled              1.3s    Jun 20
  Failed       Could not clean up      14.7s   Jun 19
```

Rules:

- no purple / colorful audio branding
- shortcut visible in header
- setup blockers visible but not scary
- permission rows use clear copy

### 10.4 Downloads

Downloads is a queue and file pipeline.

Preferred layout:

```text
Downloads                                  Open Downloads Folder
Manage active and completed downloads.

[All 401] [Active 0] [Paused 396] [Failed 4]      [Search]

Attention
4 downloads failed. Review failed items or retry.

Collections
  UI Audit Demo Bulk           Paused       0 / 200       Resume
  UI Audit Demo Bulk           Failed       0 / 200       Retry
```

Rules:

- filters are monochrome
- failed state uses warning icon + label, not red banner
- progress uses thin line, not chunky colorful bar
- row actions are clear: Resume, Retry, Reveal, Remove

### 10.5 AI File Organizer

Review-and-approve workspace.

Preferred layout:

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

Rules:

- use diff table, not generic cards per file
- destructive operations require confirmation
- show before/after clearly

### 10.6 Enhanced Finder

Native Finder history inspector.

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

Rules:

- folder path rows
- compact metadata
- no marketing panels

### 10.7 Window Layouts

Precise and geometric.

```text
Window Layouts                                Active
Arrange, snap, and restore windows.

Shortcuts
[Left Half  ⌃←] [Right Half  ⌃→] [Top Half  ⌃↑] [Center  ⌃C]

Radial Preview
monochrome grid with selected region filled
```

Rules:

- grid previews use line and fill, not color zones
- shortcuts visible on every preset

### 10.8 Window Grab

Lightweight setup page and precise runtime outline.

```text
Window Grab                                  Active
Move windows by holding a modifier and dragging anywhere.

Trigger: ⌥ + drag
Ignored apps: 4
Snap preview: enabled

[Test Grab] [Change Trigger]
```

### 10.9 Windows Hub

Main page:

```text
Windows Hub                                  ⌥⇧W
Search apps, windows, and tabs from a floating panel.

[Open Window Hub]

Permissions
Accessibility       Granted
Browser tabs        Enabled
Background apps     Off
```

Floating runtime panel follows §9.3.

### 10.10 Settings

Settings should be the calmest part of the app.

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
  Clipboard History                       ⌘⇧V
  Voice Dictation                         ⌥ Space
  Window Hub                              ⌥⇧W
```

Rules:

- grouped rows, not feature cards
- no promotional copy
- toggles and shortcuts aligned

### 10.11 Onboarding

Premium and clear.

Flow:

1. Welcome
2. Choose features
3. Grant permissions
4. Set shortcuts
5. Ready

Feature selection:

```text
Choose what Mayn should run.

[✓ Clipboard History] [✓ Voice Dictation]
[✓ Downloads]         [✓ Windows Hub]
[  AI File Organizer] [  Enhanced Finder]
```

Selected tile:

- light: black fill / white text
- dark: white fill / black text

Unselected tile:

- content surface
- hairline border
- primary text

---

## 11. Motion system

### 11.1 Motion principle

> Fast in. Calm out. Never decorative.

Motion should confirm state and reduce uncertainty. It should not become the focus.

### 11.2 Motion tokens

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

  --scale-pressed: 0.985;
  --scale-panel-start: 0.975;
  --scale-hud-start: 0.94;
}
```

Hard rule:

```text
Common UI transitions should not exceed 280 ms.
```

### 11.3 Duration standards

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

### 11.4 Page transition

Use only opacity and small vertical motion.

- exit: opacity 1 → 0, y 0 → -4 px, 100 ms
- enter: opacity 0 → 1, y 8 px → 0, 180 ms

Do not slide pages horizontally.

### 11.5 Command palette animation

Open:

- scrim opacity 0 → 1, 120 ms
- toolbar search begins morph/fade at 20-40 ms
- palette opacity 0 → 1
- palette scale 0.975 → 1
- palette y -8 px → 0
- duration: 180 ms

Rows:

- opacity 0 → 1
- y 3 px → 0
- stagger: 8-12 ms, total ≤ 80 ms

Close:

- palette opacity 1 → 0
- scale 1 → 0.985
- duration: 120 ms
- scrim fades in 100 ms

No bounce.

### 11.6 Sidebar animation

- hover fill: 100 ms
- active pill movement: 140-160 ms
- icon/text crossfade: 90-120 ms
- no glowing indicator
- no blur over text

### 11.7 Card hover and press

Hover:

- translateY -1 px
- border hairline → soft
- background + slight brightness
- 120 ms

Press:

- scale 1 → 0.985
- 80 ms

### 11.8 Toggle animation

- knob slide: 140 ms
- track glass slide: 120 ms
- no bounce
- label update after 40 ms if present

### 11.9 Clipboard Dock animation

Enter:

- opacity 0 → 1
- translateY 16 px → 0
- scale 0.96 → 1
- duration: 180 ms

Exit:

- opacity 1 → 0
- translateY 0 → 10 px
- duration: 130 ms

Copy feedback:

- selected row flashes inverted for 100 ms
- toast appears as flash begins

### 11.10 Voice HUD animation

Idle → listening:

- HUD opacity 0 → 1
- scale 0.94 → 1
- y 8 px → 0
- duration: 150 ms

Listening:

- waveform bars cycle: 700-900 ms
- bar stagger: 60 ms
- dot opacity 0.35 → 1 → 0.35, 900 ms

Listening → transcribing:

- waveform opacity drops to 30%
- **center label** changes to `Transcribing`
- full-bleed background progress wipe inside capsule
- duration: 160 ms

Transcribing → inserted:

- **center label** changes to `Inserted`
- checkmark in left slot
- fade out after **600–900 ms**

Failure:

- no shake
- center label `Couldn't transcribe` stays visible
- retry icon in right slot

### 11.11 Downloads animation

New row:

- opacity 0 → 1
- x 12 px → 0
- duration: 180 ms

Progress:

- thin progress line
- shimmer cycle 1000 ms
- opacity 0.45

Completed:

- row background briefly inverts at 8% opacity
- status updates to `Completed` / `Moved`
- duration: 220 ms

Failed:

- border strengthens
- warning icon appears
- no shake
- duration: 160 ms

### 11.12 Window Hub animation

Open:

- opacity 0 → 1
- scale 0.96 → 1
- y -6 px → 0
- duration: 160 ms

Navigate:

- selected row changes in 90-100 ms
- metadata fades in 80 ms

Select:

- selected row flashes inverse 80 ms
- panel closes 120 ms

### 11.13 Radial layout animation

Open:

- center dot appears first
- options expand from center
- opacity 0 → 1
- scale 0.8 → 1
- duration: 150 ms

Hover:

- target region fills black/white at 12-18% opacity
- label appears in 100 ms

Select:

- selected region holds for 80 ms
- overlay fades 120 ms
- actual window movement starts immediately

### 11.14 Reduced motion

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
- replace waveform with static bars or one pulsing dot
- disable radial expansion
- replace glass morphs with crossfades

---

## 12. Iconography

Use SF Symbols or a single matching monochrome stroke set.

Specs:

- sidebar: 16 px
- cards: 18-20 px
- empty states: 28-36 px
- weight: regular / medium
- stroke-like appearance
- rounded caps and joins
- monochrome rendering

Recommended SF Symbols:

| Feature | Symbol direction |
|---|---|
| Dashboard | `square.grid.2x2` |
| Clipboard | `clipboard` |
| Voice | `waveform` or `mic` |
| Downloads | `arrow.down.circle` or tray symbol |
| AI File Organizer | folder + gear / command mark |
| Enhanced Finder | `folder` / `clock` variant |
| Window Layouts | split rectangle / grid |
| Window Grab | hand / cursor + rectangle |
| Windows Hub | `rectangle.3.group` |
| Settings | `gearshape` |

Avoid:

- emoji
- 3D icons
- colorful fills
- mixed icon libraries
- decorative AI sparkle as a primary symbol

---

## 13. Accessibility

### 13.1 Contrast

- primary text must meet WCAG AA
- secondary text should remain readable on panel backgrounds
- tertiary text cannot carry required state
- selected rows must be readable in light and dark mode
- status must not rely on color only

### 13.2 Focus

Every interactive element needs visible focus.

```css
:focus-visible {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}
```

SwiftUI:

- use `@FocusState`
- keep focus visible in command palette, Clipboard Dock, Window Hub, and settings
- do not remove system focus ring unless replacing with equal or better focus affordance

### 13.3 Screen reader labels

Every icon-only control needs an accessible label.

Examples:

- `Open command palette`
- `Review downloads`
- `Start dictation`
- `Open clipboard dock`
- `Grant Accessibility permission`

### 13.4 Reduced transparency

Test all custom glass surfaces with Reduce Transparency enabled.

Required replacement:

- command palette becomes opaque elevated panel
- toolbar search becomes opaque pill
- attention badge becomes opaque pill
- Voice HUD becomes solid or standard material panel

### 13.5 Keyboard QA

Every page must support:

- tab focus for controls
- arrow navigation for lists where applicable
- escape to close overlays
- return to activate primary focused item
- command palette access to all high-frequency actions

---

## 14. Implementation guardrails

### 14.1 Required helpers

Create shared implementation helpers:

```text
MAYNTokens.swift
MAYNTheme
MAYNMaterial
MAYNGlassSurface
MAYNLiquidGlassPanel
MAYNSelectionInversionBackground
MAYNSelectionInversionLabelStyle
MAYNKeycap
MAYNStatusPill
MAYNCommandPaletteShell
MAYNMotion
```

### 14.2 Selection implementation

```swift
struct MAYNSelectionInversionBackground: ViewModifier {
    let isSelected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.primary)
                }
            }
            .foregroundStyle(isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.66))
    }
}
```

Use a gradient version if needed for native polish, but keep text contrast crisp.

### 14.3 Glass helper

```swift
struct MAYNGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let enabled: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), enabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
```

Never apply this helper to selected rows.

### 14.4 Window opacity rule

The main app window must stay opaque.

Do not let Safari, wallpaper, or other apps show through the entire Mayn window.

```swift
window.isOpaque = true
window.backgroundColor = .windowBackgroundColor
```

Runtime HUD `NSPanel`s may be transparent because they intentionally float over the desktop.

---

## 15. Do / Don't

### Do

- use `NavigationSplitView` and `.toolbar`
- keep page content on stable surfaces
- use Liquid Glass for control chrome, runtime shells, and keyboard selection
- keep command palette compact and context-aware
- show shortcuts for frequent actions
- use dense, sharp lists
- use native scroll behavior
- test light and dark mode equally
- test Reduce Motion and Reduce Transparency
- make runtime overlays feel more polished than settings pages

### Don't

- do not make the whole window transparent
- do not use glass on every card
- do not use glass-over-text selection
- do not leave duplicate search fields open
- do not use thick custom scrollbars
- do not use blue / green / purple / orange feature colors
- do not use system green toggles as brand language
- do not create marketing dashboard hero sections
- do not use emoji icons
- do not use slow bounce animations
- do not require color to understand state
- do not show attention badges above command palette focus

---

## 16. Design QA checklist

Before shipping any screen, verify:

- Does it work in pure black and white?
- Does it feel native on macOS?
- Does content remain sharp and stable?
- Is glass limited to controls / navigation / HUD shells?
- Are selected rows Liquid Glass (`maynSelectionBackground`) with primary labels?
- Is the command palette useful before typing?
- Is the current context first in command palette?
- Are attention items inside command palette when it opens?
- Is the toolbar search hidden or morphed during palette open?
- Are scrollbars native or subtle overlay scrollbars?
- Are shortcuts visible for frequent actions?
- Are disabled states explained?
- Is dark mode readable without muddy blur?
- Is light mode premium and not washed out?
- Does Reduce Transparency still look good?
- Does Reduce Motion remove transform-heavy animation?
- Can every major action be completed with keyboard?

---

## 17. AI / agent prompt

Use this prompt when generating Mayn UI:

```text
Build Mayn as a monochrome native macOS productivity app. Use black, white, and grayscale as the brand system. Use NavigationSplitView and native .toolbar for app chrome. Use Liquid Glass for floating controls, runtime shells, and selected rows: toolbar search, attention badge, command palette shell and rows, segmented track, sidebar selection, list row selection, popovers, Voice HUD (single 392×58 Liquid Glass capsule per V3 spec — not stacked caption+hub), Clipboard Dock, and Window Hub. Keep dashboard cards, settings groups, and dense list content on stable standard surfaces — selection is a single glass layer per row via `MAYNSelectionGlassBackground`, not inversion fills. Status pills and download progress use semantic color families. Do not use colored feature cards, gradients, emoji, or thick custom scrollbars. Follow [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass). The app should feel like a native macOS utility: compact, sharp, keyboard-first, and fast.
```

Animation prompt:

```text
Implement Mayn motion as fast in, calm out. Use opacity, scale, and small translate values only. Use cubic-bezier(0.16, 1, 0.3, 1) for entrances and cubic-bezier(0.7, 0, 0.84, 0) for exits. Keep common transitions under 220ms and never exceed 280ms except real progress. Command palette opens in 180ms from toolbar search morph or opacity + scale 0.975. Voice HUD opens with scale 0.94 and a monochrome waveform. Clipboard Dock slides up 16px. Window Hub scales from 0.96. Radial menu expands from center in 150ms. Toasts are black/white inversion pills. Respect Reduce Motion and Reduce Transparency.
```
