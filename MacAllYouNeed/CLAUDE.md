# MacAllYouNeed - UI Working Notes

This file applies when editing code under `MacAllYouNeed/`. The full normative
spec is [`../design.md`](../design.md) - read it before adding any new color,
font, spacing, animation, control, page chrome, or feature surface.

## Current App Surfaces

- Menu-bar tools popover: Clipboard / Voice / Downloads / Layouts / Snippets.
- Main window sidebar: Dashboard / Clipboard / Voice / Downloads / Folder
  Preview / Snippets / Window Layouts / Window Grab / Settings.
- Dashboard: `FeatureToolCard` lifecycle cards for all feature-backed tools.
- Bottom dock: Clipboard History / Snippets / user pinboards, with drag/drop,
  transforms, quick look, snippet creation, and in-panel snippet editing.
- Settings entry: current System group (General, Permissions, Storage,
  Advanced). Feature/workflow settings live primarily inside main tool pages.
- Onboarding: feature picker + per-feature setup; voice has a separate 9-step
  wizard.
- Voice AI cleanup: `VoiceCleanupProviderKind` includes Anthropic, OpenAI
  compatible, Groq, Gemini, Ollama, and oMLX presets (each with its own
  keychain slot). Groq **ASR** keys are separate from Groq **cleanup** keys.

## Hard Rules (Machine-Enforced via `.swiftlint.yml`)

- No `Color(red:green:blue:)`. Use `MAYNTheme.*`. Grandfathered files are
  documented in `design.md §10`; do not extend the list without updating §10.
- No `.pickerStyle(.segmented)` or `SegmentedPickerStyle()`. Use
  `FunctionSegmentedTabStrip`. The grandfathered shared Folder Preview browser
  call site is documented in `design.md §11`.
- No raw `Animation.easeOut(duration:)`, `.easeInOut(duration:)`,
  `.linear(duration:)`, or `.spring(...)`. Route through
  `MAYNMotion.<kind>Animation(reduceMotion:)` or
  `MAYNMotionBridge.effectiveDuration(_:)` so Reduce Motion is honored.

`swiftlint --strict` in `scripts/ci-build.sh` fails on any of the above.

## Hard Rules (Review-Enforced)

- No raw `TextField(...)` / `SecureField(...)` in product UI unless surrounded
  by MAYN-styled search chrome. Default to `MAYNTextField` /
  `MAYNSecureField`.
- No raw `.font(.system(size: N))` in product code unless it is in the
  `design.md §4.4` size table or documented debt/exception. Prefer semantic
  SwiftUI fonts.
- No raw `Divider()` in product surfaces. Use `MAYNDivider`, except inside
  SwiftUI context menus where the platform divider is required.
- No inline hotkey recorders on top-level tool pages. Display with
  `ShortcutChip` / `MAYNHotkeyDisplay`; edit in Hotkeys or the tool Settings
  tab with `HotkeyRecorder`.
- Every spatial animation must honor `@Environment(\.accessibilityReduceMotion)`
  or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- Disabled sidebar destinations stay visible but inert. Do not remove them from
  the sidebar when a feature is disabled.
- Do not add non-actionable "Ready" tags to Dashboard cards. Use warnings,
  progress, Off, or errors only when the state needs attention.
- Do not add a Start button to the Voice main page header. The header shows the
  shortcut chip only; start/stop belongs in the Dictate section or Command
  Center.

## Where To Find The System

- Tokens + most components: `Settings/MAYNSettingsUI.swift`
- Function page chrome + tab strip: `App/FunctionPageShell.swift`
- Dashboard lifecycle card wrapper: `App/Dashboard/FeatureToolCard.swift`
- Hotkey recorder: `Settings/HotkeyRecorder.swift`
- Per-app clipboard accent palette: `ClipboardDock/Views/Cards/AppIconColor.swift`
- Snippet cards/editor: `ClipboardDock/Views/Snippets/`
- Window control pages/settings: `WindowControl/`

## Components To Reach For First

| You want... | Use |
|---|---|
| A button | `MAYNButton` (`.primary` / `.secondary` / `.destructive`) |
| A text input | `MAYNTextField` or `MAYNSecureField` |
| A dropdown | `MAYNDropdown` |
| A 2-5 item tab switch | `FunctionSegmentedTabStrip` (`.header` or `.control`) |
| A settings page | `MAYNSettingsPage` + `MAYNSection` + `MAYNSettingsRow` + `MAYNDivider` |
| A tool page | `FunctionPageShell` + `FunctionPageScrollContent` |
| A dashboard feature card | `FeatureToolCard` wrapping `MAYNToolCard` |
| A status badge | `StatusPill` |
| A TCC permission row | `PermissionCard` |
| An instruction with optional drag target | `InstructionStrip` |
| A confirmation pill | `MAYNToast` |
| A read-only hotkey | `ShortcutChip` / `MAYNHotkeyDisplay` |
| A numeric field | `MAYNNumericStepper` |

If the need is not in the table, check `design.md §6` before inventing a new
primitive. New generic primitives live in `Settings/MAYNSettingsUI.swift` and
require a `design.md §6` entry.

## Accepted Exceptions (Do Not Generalize)

- `ClipboardDock/Views/DockTopBar/DockListTabs.swift` - custom drag-reorder tab
  strip and drop target; mirrors `FunctionSegmentedTabStrip` visuals.
- `ClipboardDock/Views/Cards/AppIconColor.swift` and `ClipCard` accent
  presentation - per-app/user pinboard color tuples.
- `Voice/UI/MiniVoiceHUD.swift` - v8 voice pill (universal 144x32, three slots:
  left status icon, centered label, right action). Near-black background, white
  ink, `#363636` border. During LLM **cleanup** (still labeled Transcribing), a gray
  **track** carries a **black** fill that wipes left→right with streamed cleanup
  progress (Typeless-style; short boot sweep before the first token when progress
  stays at zero), then snaps to full black when cleanup completes. Documented raw-RGB exception for HUD legibility over arbitrary desktops. Stop button always cancels; Cancelled pill exposes a 5s
  Undo. See `VoiceCoordinator` for the keyboard model (Esc, Return / numpad
  Enter) and `processCapturedAudio` for the shared live + undo replay path.
- `App/MainWindowRoot.swift` - seven dashboard function accent RGB tuples for
  feature identity only.
- `WindowControl/WindowSnapOverlayPanel.swift` - fixed black/light-gray OS-style
  drag overlay.
- SwiftUI context menus - use platform `Divider()`.

## Current Snippet Behavior

- Expansion modes are `Auto`, `Tab`, and `Off`.
- Snippet expansion runs from the main app CGEventTap and needs Accessibility.
- Snippets are sourced from the local `ClipboardDockModel`.
- Menu rows show body preview and keep the trigger visible.
- Dragging clipboard cards to the Snippets tab opens a prefilled in-panel
  `SnippetSheet` draft.
- Snippet cards intentionally mirror clipboard card background, dimensions,
  focused border, and unfocused border.

## Before Opening A PR Or Pushing

Run the `design.md §13` review checklist. The essentials:

- Every color / padding / height / radius / width / font / animation maps to a
  `MAYN*` token or documented exception.
- Tab switches use `FunctionSegmentedTabStrip`.
- Text input uses `MAYNTextField` / `MAYNSecureField` or the approved search
  chrome pattern.
- Reduce Motion: enable it in System Settings -> Accessibility -> Display,
  re-run the touched flow, and confirm no spatial motion remains.
- `swiftlint --strict` passes.
