# MacAllYouNeed — UI working notes

This file applies when editing code under `MacAllYouNeed/`. The full
normative spec is [`../design.md`](../design.md) — read it before adding
any new color, font, spacing, animation, control, or page chrome.

## Hard rules (machine-enforced via `.swiftlint.yml`)

- No `Color(red:green:blue:)`. Use `MAYNTheme.*`. Four files are
  grandfathered with `design.md §10` annotations — do not extend the
  list without updating §10.
- No `.pickerStyle(.segmented)` or `SegmentedPickerStyle()`. Use
  `FunctionSegmentedTabStrip`. The single grandfathered call site is
  `Shared/Sources/UI/FolderPreview/FolderPreviewView.swift`; migrate
  it when you next touch that file.
- No raw `Animation.easeOut(duration:)`, `.easeInOut(duration:)`,
  `.linear(duration:)`, or `.spring(…)`. Route through
  `MAYNMotion.<kind>Animation(reduceMotion:)` or
  `MAYNMotionBridge.effectiveDuration(_:)` so Reduce Motion is honored.

`swiftlint --strict` in `scripts/ci-build.sh` fails on any of the above.

## Hard rules (review-enforced — not yet linted)

- No raw `TextField(…)` / `SecureField(…)` in product UI unless
  surrounded by MAYN-styled chrome (the `DockSearchField` /
  `VoiceDictionarySearchField` pattern is the only accepted exception).
  Default: use `MAYNTextField` / `MAYNSecureField`.
- No raw `.font(.system(size: N))` in product code. Use semantic
  SwiftUI fonts (`.caption`, `.callout`, `.body`, `.title3`, `.title2`)
  or the size-table entries in `design.md §4.4`.
- No raw `Divider()` in product surfaces. Use `MAYNDivider`.
- No inline hotkey recorders on tool pages. Display with `ShortcutChip`
  / `MAYNHotkeyDisplay`; edit only on the Hotkeys settings page (or the
  tool's settings page) using `HotkeyRecorder`.
- Every spatial animation must honor `@Environment(\.accessibilityReduceMotion)`
  or `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

## Where to find the system

- Tokens + most components: `Settings/MAYNSettingsUI.swift` (despite the
  name, this is the app-wide design-system file)
- Function page chrome + tab strip: `App/FunctionPageShell.swift`
- Hotkey recorder (Settings only): `Settings/HotkeyRecorder.swift`
- Per-app clipboard accent palette: `ClipboardDock/Views/Cards/AppIconColor.swift`

## Components you should reach for first

| You want… | Use |
|---|---|
| A button | `MAYNButton` (`.primary` / `.secondary` / `.destructive`) |
| A text input | `MAYNTextField` (or `MAYNSecureField` for keys/passwords) |
| A dropdown | `MAYNDropdown` |
| A 2–5 item tab switch | `FunctionSegmentedTabStrip` (`.header` or `.control` size) |
| A settings page | `MAYNSettingsPage` + `MAYNSection` + `MAYNSettingsRow` + `MAYNDivider` |
| A tool page in the main window | `FunctionPageShell` + `FunctionPageScrollContent` |
| A status badge | `StatusPill` (`.neutral` / `.success` / `.warning` / `.danger` / `.progress`) |
| A TCC permission row | `PermissionCard` |
| An instruction with optional drag target | `InstructionStrip` |
| A confirmation pill | `MAYNToast` |
| A read-only hotkey | `ShortcutChip` / `MAYNHotkeyDisplay` |
| A 30pt-height numeric field | `MAYNNumericStepper` |
| A large interactive home-page card | `MAYNToolCard` |

If your need isn't in the table, check `design.md §6` before inventing
a new primitive. New primitives live in `Settings/MAYNSettingsUI.swift`
and require a one-line entry in §6.

## Accepted exceptions (do not generalize)

- `ClipboardDock/Views/DockTopBar/DockListTabs.swift` — custom drag-reorder
  tab strip; cannot use `FunctionSegmentedTabStrip`. Mirror its visual
  language (already does).
- `ClipboardDock/Views/Cards/AppIconColor.swift` + `ClipCardAccentPresentation`
  — per-app brand RGB tuples; the only place raw RGB is allowed.
- `Voice/UI/MiniVoiceHUD.swift` — near-black processing background for
  HUD legibility against arbitrary desktops.
- `App/MainWindowRoot.swift` — five function-tab indicator colors are
  brand affordances; do not extend the pattern to chrome.

## Before opening a PR (or pushing to main)

Run the §13 review checklist from `design.md`. The essentials:

- Every color / padding / height / radius / width / font / animation
  maps to a `MAYN*` token (or is a documented §10 exception).
- Tab switches use `FunctionSegmentedTabStrip`.
- Text input uses `MAYNTextField` / `MAYNSecureField` (or is a
  chromed-search-field pattern).
- Reduce Motion: enable in System Settings → Accessibility → Display,
  re-run the touched flow, confirm no spatial motion remains.
- `swiftlint --strict` passes.
