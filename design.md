# Mac All You Need — Design System

Normative UI specification. All new SwiftUI/AppKit code in this repo must follow this document. Older code that predates a rule is grandfathered until touched; once a file is edited, the touched surface conforms.

If something here conflicts with a screenshot, the document wins. If something here conflicts with the source of truth files listed in §3, the source files win — open a PR to update this document.

---

## 1. Purpose

One visual language across the menu-bar Command Center, dashboard, main tool pages, settings, onboarding wizards, the floating voice HUD, the clipboard dock, the folder browser, and the window-control surfaces. No new ad-hoc colors, fonts, spacings, animations, or controls when a system primitive already exists.

The system is calm, native, neutral. Color is for state (success/warning/danger/progress) and for accenting the app icon of a clipboard item — never for decoration.

---

## 2. Design principles

1. **Native first.** This is a macOS productivity tool. Use AppKit-derived `NSColor` system colors so dark/light/contrast/translucency behave correctly. Custom RGB only for branded app-icon accents in clipboard cards.
2. **Token in, never raw out.** Read from `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`. Never write a literal hex or numeric spacing in a leaf view if a token exists.
3. **One control per job.** There is exactly one button (`MAYNButton`), one text field (`MAYNTextField`), one dropdown (`MAYNDropdown`), one tab strip (`FunctionSegmentedTabStrip`), one row (`MAYNSettingsRow`), one card (`MAYNToolCard`), one status badge (`StatusPill`). Use them. Don't restyle them inline.
4. **Reduce Motion is a contract, not a polish.** Every spatial animation must funnel through `MAYNMotion.*` helpers that return `nil` (or zero offset) when Reduce Motion is on. This includes AppKit `NSAnimationContext` paths.
5. **Functional pages share one chrome.** Every tool page in the main window uses `FunctionPageShell` (title + subtitle + optional toolbar + tab strip + content). Every settings page uses `MAYNSettingsPage` + `MAYNSection` + `MAYNSettingsRow`.
6. **Function pages display shortcuts, they don't edit them.** Hotkey editing lives in the tool's Settings page. Use `ShortcutChip` / `MAYNHotkeyDisplay` to show, `HotkeyRecorder` (in Settings only) to edit.
7. **No invented tab styles.** If you need a segmented control, use `FunctionSegmentedTabStrip`. Raw SwiftUI `Picker(...).pickerStyle(.segmented)` is banned for product-owned tab switches.

---

## 3. Source of truth

Read these files before touching UI:

| Purpose | File |
|---|---|
| Tokens + most components | `MacAllYouNeed/Settings/MAYNSettingsUI.swift` |
| Function page chrome + tab strip | `MacAllYouNeed/App/FunctionPageShell.swift` |
| Dashboard feature card wrapper | `MacAllYouNeed/App/Dashboard/FeatureToolCard.swift` |
| Hotkey recorder (Settings only) | `MacAllYouNeed/Settings/HotkeyRecorder.swift` |
| Window backdrop helper | `MacAllYouNeed/Settings/SettingsWindowConfig.swift` |
| Clipboard card accent palette | `MacAllYouNeed/ClipboardDock/Views/Cards/AppIconColor.swift` |
| Window control pages | `MacAllYouNeed/WindowControl/WindowControlMainPage.swift` |

When a new generic primitive is needed, it lives in `MAYNSettingsUI.swift` (despite the name, this is the design-system file for the whole app). The name is historical; do not move it without coordinated edits.

---

## 4. Tokens

### 4.1 Color (`MAYNTheme`)

All colors derive from `NSColor` system colors or from `Color.primary`/`Color.secondary` opacity. Never `Color(red:green:blue:)` outside the documented exceptions in §10.

| Token | Light | Dark | Use |
|---|---|---|---|
| `window` | `#ECECEC` | `#323232` | The outermost background of any window/scene. |
| `panel` | `#FFFFFF` | `#1E1E1E` | Grouped section background (settings sections, capsule strips, dropdowns at rest). |
| `elevated` | `#FFFFFF` | `#1E1E1E` | Field/control fill (text fields, buttons at rest, dropdown rest). |
| `elevatedHover` | `.primary @ 4.5%` | `.primary @ 4.5%` | Control hover fill. |
| `elevatedPressed` | `.primary @ 7.5%` | `.primary @ 7.5%` | Control pressed fill. |
| `hover` | `.primary @ 5%` | `.primary @ 5%` | Row hover overlay. |
| `selected` | `.primary @ 8%` | `.primary @ 8%` | Row/item selected overlay. |
| `divider` | `.secondary @ 16%` | `.secondary @ 16%` | 1pt dividers between rows or sections. |
| `subtleBorder` | `.primary @ 10%` | `.primary @ 10%` | Default stroke around controls/cards/panels at rest. |
| `strongBorder` | `.primary @ 18%` | `.primary @ 18%` | Stroke around controls at hover, around capsule tab strips, around instruction strips. |
| `focusRing` | `.primary @ 70%` | `.primary @ 70%` | Stroke around the focused text field and around the selected clipboard card. |
| `tabSelectedFill` | `.primary @ 14%` | `.primary @ 14%` | Fill of the selected pill inside `FunctionSegmentedTabStrip` and `DockListTabs`. |
| `tabSelectedBorder` | `.primary @ 20%` | `.primary @ 20%` | Stroke of the selected tab pill. |
| `tabSelectedShadow` | `#000 @ 6%` | `#000 @ 6%` | 2pt drop-shadow under the selected tab pill. |
| `muted` | `.secondary` | `.secondary` | `Color.secondary` alias — for de-emphasized labels. |
| `controlTint` | `.secondary` | `.secondary` | Tint passed to `NavigationSplitView` so accent stays neutral gray. |
| `success` | `#28CD41` | `#32D74B` | Green — completed downloads, granted permissions, success toasts. |
| `warning` | `#FF9500` | `#FF9F0A` | Orange — denied permissions, recoverable problems. |
| `danger` | `#FF3B30` | `#FF453A` | Red — destructive buttons, error toasts. |
| `progress` | `#007AFF` | `#0A84FF` | Blue — active downloads, in-flight permission setup, highlighted permission card. |

Notation:
- `.primary` ≈ `NSColor.labelColor` — Light `rgba(0, 0, 0, .85)` / Dark `rgba(255, 255, 255, .85)`.
- `.secondary` ≈ `NSColor.secondaryLabelColor` — Light `rgba(0, 0, 0, .50)` / Dark `rgba(255, 255, 255, .55)`.
- `.primary @ N%` means `Color.primary` rendered at opacity `N%` over the surface beneath it; the effective hex depends on the underlying surface and the current appearance.
- All literal hex values are sRGB. macOS automatically swaps the variant based on the system appearance, so designer comps for both Light and Dark mode use the column that matches the comp.
- `success` / `warning` / `danger` / `progress` are Apple's `systemGreen` / `systemOrange` / `systemRed` / `systemBlue`; values shown are the standard macOS defaults but may shift by a few units across OS versions and Increase-Contrast modes.

Rules:
- Semantic only. There is no "brand color." If you want to draw attention, use `progress` or `focusRing`.
- Text colors come from `.primary` / `.secondary` / `.tertiary`, never from a token. The system handles contrast.
- `Color(nsColor: .controlBackgroundColor)` is allowed for the foreground of primary buttons and toasts (to flip text on a solid `Color.primary` fill). Do not introduce other `NSColor` system colors directly — go through `MAYNTheme`.

### 4.2 Motion (`MAYNMotion` + `MAYNMotionBridge`)

| Token | Duration | Use |
|---|---|---|
| `press` | 0.12s | Button press scale, card press scale. |
| `hover` | 0.16s | Hover-driven bg/border swaps on any control. |
| `control` | 0.18s | Focus ring, text-field focus state, generic control state. |
| `tab` | 0.23s | Tab strip selection swap, function-page content transition. |
| `panel` | 0.28s | NSPanel / floating window resize and fade. |
| `instruction` | 0.32s | Permission-card highlight pulse, instruction strip emphasis. |
| `toastIn` | 0.16s | Toast/HUD enter. |
| `toastOut` | 0.22s | Toast/HUD exit (ease-in via `MAYNMotionBridge.timingFunction(.toastOut)`). |

Rules:
- SwiftUI: call `MAYNMotion.<kind>Animation(reduceMotion:)` and feed the return into `.animation(_:value:)`. Never write `Animation.easeOut(duration: ...)` or `.spring(...)` directly.
- AppKit / Core Animation: use `MAYNMotionBridge.effectiveDuration(_:)` for `NSAnimationContext.duration` and `MAYNMotionBridge.timingFunction(_:)` for `CAMediaTimingFunction`. Both honor Reduce Motion automatically.
- Spatial offsets that should collapse under Reduce Motion: wrap with `MAYNMotionBridge.translation(_:reduceMotion:)`.
- The Reduce Motion read must come from either `@Environment(\.accessibilityReduceMotion)` (SwiftUI) or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (AppKit).

### 4.3 Metrics (`MAYNControlMetrics`)

| Token | Value | Use |
|---|---|---|
| `controlHeight` | 30 | All single-line interactive controls (buttons, text fields, dropdowns, hotkey chips, in-row tabs). |
| `controlRadius` | 7 | Controls and the icon background inside `MAYNToolCard`. |
| `cardRadius` | 8 | Cards (clipboard cards, permission cards, tool cards, instruction strips). |
| `panelRadius` | 8 | Section panels, dropdown menus, tab-strip capsules background. |
| `rowMinHeight` | 46 | Settings rows; do not go shorter, even with a tiny control. |
| `rowHorizontalPadding` | 14 | Left/right padding inside a row. |
| `rowVerticalPadding` | 9 | Top/bottom padding inside a row. |
| `rowControlSpacing` | 16 | Gap between row label and trailing control lane. |
| `trailingLaneMinWidth` | 220 | Minimum width of the trailing control lane in a row (so rows align vertically). |
| `pickerWidth` | 180 | Default `MAYNDropdown` width. |
| `widePickerWidth` | 220 | Wide `MAYNDropdown` width. |
| `textFieldWidth` | 260 | Default `MAYNTextField` width. |
| `wideTextFieldWidth` | 300 | Wide `MAYNTextField` width. |

If you find yourself reaching for a number not in this table, ask whether the layout really needs a new dimension, or whether you can compose existing tokens.

### 4.4 Typography

There is no `MAYNFont` enum — SwiftUI's semantic font system already handles dynamic type. Use:

| Where | Font |
|---|---|
| Page title (`MAYNSettingsPage`) | `.system(size: 24, weight: .semibold)` |
| Page title (`FunctionPageShell`) | `.system(size: 26, weight: .semibold)` |
| Page subtitle | `.callout` + `.foregroundStyle(.secondary)` |
| Section title (`MAYNSection`) | `.system(size: 13, weight: .semibold)` |
| Section subtitle | `.caption` + `.foregroundStyle(.secondary)` |
| Row title | `.callout` |
| Row subtitle | `.caption` + `.foregroundStyle(.secondary)` |
| Tool card title (`MAYNToolCard`) | `.system(size: 15, weight: .semibold)` |
| Tool card subtitle | `.caption` + `.foregroundStyle(.secondary)` |
| Status pill | `.caption` |
| Button label | `.callout` (`.semibold` for primary, `.medium` for others) |
| Numeric monospace (`MAYNNumericStepper`) | `.system(.caption, design: .monospaced)` |
| Hotkey glyph (full size) | `.system(size: 17, weight: .semibold)` modifier, `.system(size: 15, weight: .semibold, design: .rounded)` key |
| Hotkey glyph (compact, ≤24pt chip) | `.system(size: 15, weight: .semibold)` modifier, `.system(size: 13, weight: .semibold, design: .rounded)` key |

Do not write `.font(.system(size: 12))` or `.font(.system(size: 14))` in product code. If a label doesn't fit one of the rows above, it is almost certainly a `.caption`, `.callout`, or `.body`.

### 4.5 Feature-identity accents (sRGB literals)

These seven tints identify a function on the dashboard, the main sidebar icons, and feature-card iconography. They are the only literal RGB triples allowed in app chrome and are exempted per §10.4. They MUST NOT appear in settings rows, status indicators, toasts, badges, or any non-iconography surface.

| Feature | sRGB | Hex |
|---|---|---|
| Clipboard | `0.10, 0.42, 0.92` | `#1A6BEB` |
| Voice | `0.64, 0.22, 0.88` | `#A338E0` |
| Downloads | `0.02, 0.58, 0.42` | `#05946B` |
| Folder Preview | `0.86, 0.46, 0.12` | `#DB751F` |
| Snippets | `0.82, 0.18, 0.36` | `#D12E5C` |
| Window Layouts | `0.20, 0.48, 0.72` | `#337AB8` |
| Window Grab | `0.24, 0.46, 0.36` | `#3D755C` |

Source of truth: `MainWindowRoot.swift accent(for:)`. Both Light and Dark mode use the same value — these are designed to read on both appearances.

---

## 5. Layout primitives

### 5.1 Window shells

| Window | Shell | Bound size |
|---|---|---|
| Settings window | `MAYNSettingsShell { sidebar } detail: { … }` | min 760×520, ideal 900×640 |
| Main window | Hand-rolled `NavigationSplitView` in `MainWindowRoot` | Uses `MAYNTheme.window` background |
| Onboarding (main) | `OnboardingWizardView` panel | 760×520 |
| Onboarding (voice) | `VoiceOnboardingWizardView` panel | 860×640 |
| Voice HUD | Borderless non-activating `NSPanel`, position-aware | Adaptive |
| Clipboard dock | `BottomDockWindow`, bottom-screen | 12pt top corners only |
| Browse folder | Standard titled `NSWindow` | 900×600 |

### 5.2 Page chrome — main window tools

Use `FunctionPageShell` for every tool page:

```
FunctionPageShell(title:, subtitle:, tabs:, selection:) {
    // optional toolbar (right side of header)
} content: {
    FunctionPageScrollContent {
        // sections + rows
    }
}
```

It owns the 26pt title, callout subtitle, 32pt horizontal page padding, 28pt top padding, the `FunctionSegmentedTabStrip` underneath, the `MAYNTheme.divider`, and the directional content transition. Don't reimplement this layout.

### 5.3 Page chrome — Settings

Use `MAYNSettingsPage(title:subtitle:) { … }`. It supplies 24pt title, callout subtitle, 32pt horizontal padding, 28pt vertical padding, a 720pt max content width, and a scroll container with `MAYNTheme.window` background.

### 5.4 Section + row

```
MAYNSection(title: "Capture") {
    MAYNSettingsRow(title: "Auto-paste", subtitle: "Insert at the active cursor") {
        Toggle("", isOn: $autoPaste).labelsHidden()
    }
    MAYNDivider()
    MAYNSettingsRow(title: "Excluded apps") {
        MAYNButton("Manage…") { … }
    }
}
```

- A `MAYNSection` is always a card: `MAYNTheme.panel` fill, 8pt corner, `MAYNTheme.subtleBorder` stroke.
- Rows are children of the section. The trailing control lane has `MAYNControlMetrics.trailingLaneMinWidth` so rows align vertically across sections.
- Rows hover-highlight automatically via `MAYNTheme.hover`. Don't add additional hover treatments inside the row.
- Put a `MAYNDivider()` between consecutive rows. Do not wrap rows in extra `VStack(spacing:)`.

### 5.5 Content width

| Surface | Max content width |
|---|---|
| `MAYNSettingsPage` | 720 |
| `FunctionPageScrollContent` | 760 |
| Onboarding wizard panels | Full panel width minus internal padding |

Content wider than 760 inside the main/settings flow is a red flag — break it into columns or sections first.

---

## 6. Components catalog

All located in `MacAllYouNeed/Settings/MAYNSettingsUI.swift` unless noted.

### 6.1 Buttons — `MAYNButton`
- Roles: `.primary` (solid `Color.primary` fill, controlBackgroundColor text), `.secondary` (default), `.destructive` (red text + red border on hover/press).
- Height defaults to `MAYNControlMetrics.controlHeight`.
- Has built-in hover/press scale (0.985) gated by Reduce Motion.
- Convenience init: `MAYNButton("Title", role: .secondary) { … }`.
- Do not nest `Button(...) { … }` and a custom background — use this.

### 6.2 Text input — `MAYNTextField`, `MAYNSecureField`
- 260pt default width, 30pt height, 7pt corner, `MAYNTheme.elevated` fill, `MAYNTheme.focusRing` on focus.
- Always pass `placeholder:` (do not put placeholder text in the label).
- `MAYNSecureField` is identical for password/API-key entry — never put a raw `SecureField` in a settings row.

### 6.3 Selection — `MAYNDropdown`
- Use for any one-of-N pick that does not deserve a segmented strip (i.e. options > 4, or labels too long).
- Always hides the native menu chevron; render the `chevron.up.chevron.down` indicator via the built-in overlay.
- Default 180pt width; use `MAYNControlMetrics.widePickerWidth` (220) for longer labels.

### 6.4 Tab switching — `FunctionSegmentedTabStrip`
- The only acceptable segmented control. Use for 2–5 items with short labels and SF Symbol icons.
- `Size.header` (38pt outer, 30pt inner): use as the primary tab strip directly under a page title.
- `Size.control` (30pt outer, 24pt inner): use inline inside a row or a card for sub-selections.
- The `Tab` type must conform to `SegmentedTabDestination` (provides `symbolName`, `title`, `rawValue`, `allCases`).
- Selected pill uses an internal capsule overlay with `matchedGeometryEffect`. Do not wrap the strip in your own background or border.

### 6.5 Numeric input — `MAYNNumericStepper`
- Right-aligned monospaced caption inside a 30pt field.
- Auto-detects suffix from the row's existing text label (e.g. "30 days" → suffix "days").
- Commits on submit or focus loss via `MAYNNumericInputPresentation.committedValue` (clamps to range).

### 6.6 Hotkey display — `ShortcutChip`, `MAYNHotkeyDisplay`
- Read-only. Renders modifier glyphs (⌘⇧⌥⌃) at a slightly larger size than the key glyph.
- `ShortcutChip(text:)` for in-row badges.
- `MAYNHotkeyDisplay(text:)` adds the accessibility label "Shortcut <text>" — prefer this in product surfaces.
- For "no shortcut set" pass an empty string; the chip renders "Not set".

### 6.7 Status badge — `StatusPill`
- Five kinds: `.neutral`, `.success`, `.warning`, `.danger`, `.progress`.
- 6pt color dot + caption text inside a capsule with matching opacity.
- Use anywhere you need a one-word state ("Active", "Paused", "Granted", "Blocked", "12 queued").

### 6.8 Cards
- `MAYNToolCard` — the large interactive home-page card with icon tile, title, subtitle, content slot, optional `action`. Use on dashboards and tool entry points.
- `FeatureToolCard` (`MacAllYouNeed/App/Dashboard/FeatureToolCard.swift`) — the dashboard wrapper around `MAYNToolCard` that adds feature lifecycle state, install/enable actions, and asset status. Disabled / not-installed cards are dimmed and expose actions instead of navigating.
- `PermissionCard` — purpose-built for TCC permission rows (granted/needed/denied/optional). Use only on the Permissions settings page and in onboarding.
- Clipboard `ClipCard` and its variants — domain-specific to the dock; see §10.2 for accepted styling deviations.
- `SnippetCard` (`MacAllYouNeed/ClipboardDock/Views/Snippets/SnippetCard.swift`) — snippet-library card that intentionally mirrors clipboard card dimensions, background, focused border, and persistent unfocused border.

### 6.9 Instruction surfaces
- `InstructionStrip` — short instruction with optional drag-target tile and optional action button. Used in onboarding and in error banners that need a CTA.
- `DraggablePermissionAppTile` — the drag source inside `InstructionStrip` for "drag this app into System Settings" flows. Do not reimplement.

### 6.10 Toasts and HUD pills
- `MAYNToast(message:symbol:isDestructive:)` — the standard copy-confirmation pill (`MAYNNotificationPillPresentation` provides geometry constants).
- Solid `Color.primary` fill, `controlBackgroundColor` foreground. Destructive variant uses `MAYNTheme.danger` fill with white text.
- Sized via `MAYNNotificationPillPresentation.copyPanelSize(message:)` so the pill width tracks the message.

### 6.11 Divider — `MAYNDivider`
- 1pt `MAYNTheme.divider`, leading inset of 14pt (so it stops at the row label gutter).
- Use between consecutive `MAYNSettingsRow`s inside a section. Don't use SwiftUI's `Divider()` in product UI.

### 6.12 Text-focus dismissal
- Every shell that contains a text field should call `.maynDismissTextFocusOnOutsideClick()` (already wired into `MAYNSettingsShell`). This bridges `NSEvent` clicks and clears focus when the user clicks outside a text input.

---

## 7. Application surfaces

This is the map. When working on any surface, conform to this structure.

### 7.1 Menu-bar popover
- File: `MacAllYouNeed/App/AppMenuBarContent.swift`
- 500×600 `NSPopover` content.
- Layout: header (Command Center + Settings button) → `FunctionSegmentedTabStrip` (4 tabs: Clipboard / Voice / Downloads / Snippets) → tab content → footer.
- Footer is tab-specific: shortcut hint + label + Open button for the active tab + Quit. "Pause 60s" appears only on the Clipboard tab.
- Snippet rows show the snippet body preview as the primary readable text and keep the trigger visible as metadata.
- All four tabs must use `FunctionSegmentedTabStrip`.

### 7.2 Main window
- File: `MacAllYouNeed/App/MainWindowRoot.swift`
- `NavigationSplitView` with a vertical sidebar (Dashboard / Clipboard / Voice / Downloads / Folder Preview / Snippets / Window Layouts / Window Grab / Settings) and a detail pane.
- Disabled feature destinations remain visible in the sidebar, but are dimmed, show the slash indicator, ignore hover, and are non-clickable.
- Dashboard uses `FeatureToolCard` for Clipboard, Voice, Downloads, Folder Preview, Snippets, Window Layouts, and Window Grab. Cards show lifecycle status/actions; do not add non-actionable "Ready" pills.
- Each tool page in the detail pane uses `FunctionPageShell` + `FunctionPageScrollContent`.
- Current tool tabs:
  - Clipboard: History / Rules / Settings
  - Voice: Dictate / Models / History / Dictionary / Personalization / Settings
  - Downloads: Queue / Completed / Settings
  - Folder Preview: Settings
  - Snippets: Library / Settings
- Window Layouts and Window Grab are separate first-class destinations. They use `WindowControlFeaturePageShell`; see §10.5 for the no-nested-tabs exception.
- Sidebar badges (e.g. download count) use `StatusPill` or a small numeric badge — no inline NSColor.

### 7.3 Settings window
- Files: `MacAllYouNeed/Settings/SettingsRoot.swift`, `SettingsDestination.swift`
- `MAYNSettingsShell` with the current user-facing System group (`General` / `Permissions` / `Storage` / `Advanced`) and a detail pane.
- Each settings page uses `MAYNSettingsPage` + `MAYNSection` + `MAYNSettingsRow` + `MAYNDivider`.
- `SettingsDestination` still owns 11 detail views for route compatibility and reuse: Clipboard, Voice, Downloads, Folder Preview, Snippets, Hotkeys, Search, Permissions, Storage, General, Advanced.
- Feature/workflow settings are surfaced inside the corresponding main tool pages first; when a route opens a disabled feature's settings, wrap it with `FeatureSettingsContainer` so users see the disabled-feature banner.
- Hotkey editing belongs in Hotkeys or the tool's Settings tab — use `HotkeyRecorder`.

### 7.4 Onboarding wizards
- Main: `MacAllYouNeed/Onboarding/OnboardingWizardView.swift` — Welcome → Choose Features → per-feature setup loop → Done. Panel 760×520.
- Voice: `MacAllYouNeed/Voice/UI/Onboarding/VoiceOnboardingWizardView.swift` — 9 steps (Welcome, Microphone, Accessibility, Speech model, AI cleanup, Shortcut, Languages, Try it, Done). Panel 860×640.
- Use `SetupWizardShell` for step chrome. Permission steps use `PermissionCard` + `InstructionStrip`. Choice steps use `FunctionSegmentedTabStrip`.

### 7.5 Voice HUD
- File: `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift`
- Borderless non-activating `NSPanel`, presented with `MAYNMotion.toastIn/toastOut` timing.
- States: idle (hidden) → recording (waveform + timer + cancel/stop) → transcribing (spinner) → pasted (success flash) → error.
- Waveform amplitudes must respect Reduce Motion (collapse to a flat bar or static peak).

### 7.6 Clipboard dock
- File: `MacAllYouNeed/ClipboardDock/Views/DockRootView.swift`
- `BottomDockWindow` (custom AppKit) anchored to bottom-of-screen, 12pt top corners.
- Layout: `DockTopBar` (52pt) → `Divider` → `MultiSelectBar` slot (45pt) → carousel of `ClipCard`s or the Snippets library (220×240 card metrics) → overlays (TransformMenu, QuickLook, Cheatsheet, Snippet editor).
- Tabs in the top bar use `DockListTabs` — see §10.1 for why this is the only accepted exception to the "no custom tab strip" rule.
- The built-in Snippets tab accepts clipboard-card drags. A successful drop switches to Snippets and opens a prefilled in-panel `SnippetSheet` draft. The editor is an overlay inside the dock panel, not a native sheet that lifts the entire panel.
- Snippet cards copy the clipboard card shell: opaque control background, 8pt card radius, focus ring when focused, and a persistent subtle border when unfocused.

### 7.7 Browse folder window
- Files: `MacAllYouNeed/FolderPreview/BrowseFolderWindowController.swift`, `Shared/Sources/UI/FolderPreview/FolderPreviewView.swift`
- Standard `NSWindow`, 900×600, titled, resizable.
- Header: back button + folder icon + breadcrumb + item count/size + mode switch (Files / Grid / Analyze). New work should migrate this switch to `FunctionSegmentedTabStrip`; the current shared view still has the grandfathered raw segmented `Picker` documented in §11.
- Content swaps with `MAYNMotion.tab` transition.

### 7.8 Quick Look extension
- File: `MacAllYouNeed/FolderPreview/` (extension target)
- Returns an HTML table for folders, a libarchive entry list for archives.
- Constrained to `NSTextView + NSAttributedString(html:)` — WKWebView is blocked in the sandboxed extension on macOS 26. Do not try to use SwiftUI here.

### 7.9 Window control
- Files: `MacAllYouNeed/WindowControl/WindowControlMainPage.swift`, `WindowControlSettingsView.swift`, `WindowControlCoordinator.swift`
- Window Layouts and Window Grab are separate main-window destinations, not nested tabs inside one page.
- Shared settings sections: layout shortcuts, edge snap, window grab modifier, double-click layout, shared ignored apps, and diagnostics.
- Event-tap and overlay UI must use the MAYN tokens where possible; see §10.6 for the fixed black snap overlay exception.

---

## 8. Forced rules (must / must-not)

**Must:**
- Use `MAYNTheme.*` for every fill, stroke, and overlay outside the documented exceptions in §10.
- Use `MAYNControlMetrics.*` for every padding, height, radius, and width that maps to a token.
- Use `MAYNMotion.*` / `MAYNMotionBridge.*` for every animation duration and timing function.
- Use the components in §6 instead of restyling a SwiftUI primitive.
- Use `FunctionPageShell` for tool pages and `MAYNSettingsPage` for settings pages.
- Respect Reduce Motion on every spatial animation (including AppKit and Core Animation).
- Show hotkeys on tool pages with `ShortcutChip` / `MAYNHotkeyDisplay`; edit hotkeys only in Settings using `HotkeyRecorder`.
- Keep disabled features visible in navigation and dashboards, but make disabled sidebar rows inert. Route users through enable/install actions on dashboard cards or disabled-feature settings banners.

**Must not:**
- `Picker(...).pickerStyle(.segmented)` for product-owned tab switches. Use `FunctionSegmentedTabStrip`.
- Raw `TextField(...)` / `SecureField(...)` in product UI. Use `MAYNTextField` / `MAYNSecureField`.
- Raw `Color(red:, green:, blue:)`, `Color.blue`, `Color.orange` etc. for chrome. State colors come from `MAYNTheme.success/warning/danger/progress`.
- Raw `Animation.easeOut(duration: …)`, `.spring(…)`, or `NSAnimationContext` with literal durations. Always go through `MAYNMotion` / `MAYNMotionBridge`.
- Custom `Divider()` styling — use `MAYNDivider`.
- Inline hotkey recorders on top-level tool pages.
- Redundant "Ready" pills when the absence of a warning/progress state already communicates readiness.
- Native macOS form `Picker` (segmented or otherwise) on product surfaces. Exception: a `Picker` with `.menu` style nested inside a SwiftUI `Form` that is part of a system flow not owned by the app (e.g. SwiftUI's built-in `PhotosPicker`).

---

## 9. Reduce Motion contract

This is non-optional and the most common regression. A correctly motion-aware view does all of the following:

1. Reads `@Environment(\.accessibilityReduceMotion) private var reduceMotion` (SwiftUI) or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (AppKit).
2. Passes that flag through `MAYNMotion.<kind>Animation(reduceMotion:)` so the returned `Animation?` is `nil` under Reduce Motion (SwiftUI drops the animation).
3. Collapses spatial offsets, scales, and rotations via `MAYNMotionBridge.translation(_:reduceMotion:)` or an explicit ternary (`reduceMotion ? 0 : value`).
4. AppKit: uses `MAYNMotionBridge.effectiveDuration(_:)` so `NSAnimationContext.duration = 0` under Reduce Motion.
5. Does not animate continuous wave/particle effects (HUD waveform, loading shimmer) when Reduce Motion is on — show a static representative frame.

Reviewers: if you see a `.spring(...)`, a numeric duration, or an `.offset(x: 20)` without a reduce-motion guard, that is a blocking finding.

---

## 10. Accepted exceptions

These deviations exist for documented reasons. Do not generalize them.

### 10.1 `DockListTabs` (clipboard dock top bar)
- File: `MacAllYouNeed/ClipboardDock/Views/DockTopBar/DockListTabs.swift`
- Implements drag-to-reorder list tabs with `matchedGeometryEffect`. `FunctionSegmentedTabStrip` cannot host drag-reorder semantics.
- Visuals copy the FunctionSegmentedTabStrip language (capsule, panel bg, strong border, primary opacity selected fill) — when in doubt, mirror what the canonical strip does.

### 10.2 Clipboard card content
- Files: `MacAllYouNeed/ClipboardDock/Views/Cards/*`
- Card backgrounds use `Color(NSColor.controlBackgroundColor)` directly because the dock window is a translucent surface and the card needs to be fully opaque against an arbitrary desktop. `MAYNTheme.elevated` is the correct equivalent — prefer it on any new card.
- App-icon accents (`AppIconColor.swift` / `ClipCardAccentPresentation`) define 12 known per-app sRGB tuples plus a hash-based fallback. This is the only place in the app where literal RGB triples are allowed; they exist because they map to real third-party app brand colors.

### 10.3 Voice HUD processing background
- File: `MacAllYouNeed/Voice/UI/MiniVoiceHUD.swift:310`
- The processing state uses a near-black RGB to read against any window underneath. This is a deliberate visual choice for the floating HUD. If we ever expose a "system match" mode, replace it with `MAYNTheme.elevated` over a `.regularMaterial` background.

### 10.4 Main window function indicator colors
- File: `MacAllYouNeed/App/MainWindowRoot.swift`
- Seven RGB tuples used as iconography accents for the seven feature cards (Clipboard, Voice, Downloads, Folder Preview, Snippets, Window Layouts, Window Grab). These are product affordances, not chrome.
- Allowed because they identify the function. Do not extend to settings rows, cards, or status indicators.

### 10.5 Window control page shell
- File: `MacAllYouNeed/WindowControl/WindowControlMainPage.swift`
- `WindowControlFeaturePageShell` intentionally mirrors `FunctionPageShell` title/subtitle/status spacing but omits a tab strip. Window Layouts and Window Grab are separate sidebar destinations by product decision, so adding nested tabs would be a regression.
- Do not copy this shell elsewhere. If a future window-control page gains multiple tabs, migrate it to `FunctionPageShell`.

### 10.6 Window snap overlay
- File: `MacAllYouNeed/WindowControl/WindowSnapOverlayPanel.swift`
- Uses fixed black fill and light-gray stroke so the translucent snap target reads over arbitrary app content during a drag. This is an OS overlay affordance, not app chrome.

### 10.7 Context menu separators
- SwiftUI context menus must use the platform `Divider()` primitive. `MAYNDivider` renders as a rectangle view and is not appropriate inside a menu.

---

## 11. Known debt to clean up

These pre-date this document. Touch them when you're already in the file; do not file standalone cleanup PRs unless asked.

| File | Issue | Fix |
|---|---|---|
| `MacAllYouNeed/App/MainWindowRoot.swift:1074` | `ClipboardHistorySearchBar` uses a bare `TextField` inside a toolbar row. Acceptable today because there is no surrounding pill chrome (a `MAYNTextField` would add an unwanted border). If we later promote search to a chromed pill, swap to a future `MAYNSearchField` primitive. | Defer until a unified search-field primitive exists |
| `Shared/Sources/UI/FolderPreview/FolderPreviewView.swift` | Browse Folder still uses a raw segmented `Picker` for Files / Grid / Analyze. It is grandfathered by `.swiftlint.yml`. | Migrate to `FunctionSegmentedTabStrip` next time this shared view is touched |
| Many files (see §11.1) | Raw `.font(.system(size: N))` for N in {10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 22, 24, 26, 28} | Replace with semantic font (`.caption`, `.callout`, `.body`, `.title3`, `.title2`) where possible; if the size is genuinely unique to that surface (page title, large icon glyph), leave it but document at point of use |
| Many files | Raw `.padding(18)`, `.padding(20)`, `.padding(22)`, `.padding(24)` in sheets and onboarding cards | Funnel sheets through a `MAYNSheetContainer` (to be added) with a single content padding token |

**Resolved in this revision:** `MAYNTheme.tabSelectedFill`/`tabSelectedBorder`/`tabSelectedShadow` tokens promoted from raw `Color.primary.opacity(0.14)`/`0.20` and `Color.black.opacity(0.06)`. Both `FunctionPageShell` and `DockListTabs` now consume the tokens. `FileCard` footer and `CodeCard` language badge now use `MAYNTheme.elevated` instead of raw opacity fills.

### 11.1 Raw font size hotspots
These files account for most of the raw font-size literals. Prioritize when you touch them: `MainWindowRoot.swift`, `AppMenuBarContent.swift`, `DownloadsListView.swift`, `VoiceDictionaryPage.swift`, `PermissionsSettingsView.swift`, `VoiceSettingsView.swift`, `MiniVoiceHUD.swift`, `VoiceOnboardingWizardView.swift`, `OnboardingWizardView.swift`.

### 11.2 Search-field primitive (planned)

`DockSearchField` and `VoiceDictionarySearchField` independently implement the same composite pattern: magnifying-glass icon + plain `TextField` + optional clear button inside a `MAYNTheme.elevated` pill with `MAYNTheme.focusRing` on focus. Both are correctly tokenized — they are not violations — but they duplicate ~30 lines of identical chrome. The right cleanup is a `MAYNSearchField(query:placeholder:)` primitive in `MAYNSettingsUI.swift` that captures the pattern, then a one-line swap in both call sites and (optionally) `ClipboardHistorySearchBar`. Defer until a third search-field surface appears.

---

## 12. Recipes

### 12.1 Add a new settings page
1. Create `MacAllYouNeed/Settings/<Area>SettingsView.swift` returning a `MAYNSettingsPage(title:subtitle:) { … }`.
2. Inside, compose `MAYNSection`s, each holding `MAYNSettingsRow`s separated by `MAYNDivider`.
3. Add the destination to `SettingsDestination.swift` and wire it into `SettingsRoot.swift`'s sidebar group.
4. No new top-level styling files. If the page needs a control you don't see in §6, add the control to `MAYNSettingsUI.swift` first.

### 12.2 Add a new tool page in the main window
1. Add a `FunctionTabDestination` case (or new enum) and SF Symbols + titles.
2. Create the page view returning a `FunctionPageShell(title:subtitle:tabs:selection:)` with an optional toolbar and a `FunctionPageScrollContent { … }`.
3. Use `MAYNSection` / `MAYNSettingsRow` inside the scroll content. Yes, settings primitives are correct here — they are general purpose, not settings-only.

### 12.3 Add a new component
1. Justify why it can't be composed from §6.
2. Implement it in `MacAllYouNeed/Settings/MAYNSettingsUI.swift` (or a sibling file `MAYN<Area>UI.swift` if the component is large).
3. Read tokens from `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`. Take a `reduceMotion: Bool` if you animate anything spatial.
4. Add a usage line to §6.

### 12.4 Add a new global hotkey
1. Define the action in `HotkeyMapStore`.
2. Register in `AppController.applicationDidFinishLaunching` (not `onAppear` — `MenuBarExtra`'s `onAppear` only fires on first popover open).
3. Expose the recorder row in the Hotkeys settings page (using `HotkeyRecorder`) and a read-only `MAYNHotkeyDisplay` on the tool page that uses it.

---

## 13. Review checklist

Before merging any UI change, verify:

- [ ] Every color comes from `MAYNTheme` (or is a documented §10 exception).
- [ ] Every padding/height/radius/width either matches a `MAYNControlMetrics` token or is justified inline.
- [ ] Every font is a semantic SwiftUI font, a `MAYN<Component>` built-in style, or matches the §4.4 table.
- [ ] Every animation goes through `MAYNMotion` or `MAYNMotionBridge`. Reduce Motion is honored.
- [ ] Tab switches use `FunctionSegmentedTabStrip`. No `.pickerStyle(.segmented)` anywhere.
- [ ] Text input uses `MAYNTextField` / `MAYNSecureField`. No raw `TextField` / `SecureField` in product UI.
- [ ] Settings rows use `MAYNSettingsRow` with the standard trailing lane.
- [ ] Hotkey display uses `ShortcutChip` / `MAYNHotkeyDisplay`. Editing only lives on a Settings page.
- [ ] No regression: open the menu bar, open the main window, open Settings, open the dock, trigger a toast, trigger the voice HUD. Visual rhythm matches the rest of the app.
- [ ] If a new primitive was added, it lives in `MAYNSettingsUI.swift` and §6 has a one-paragraph entry for it.
- [ ] Reduce Motion test: System Settings → Accessibility → Display → Reduce Motion ON. Re-run the touched flows and confirm no spatial motion remains.

If any item fails, the change is not ready. This is the production confidence gate.
