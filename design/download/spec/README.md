# Mac All You Need Downloads Redesign Pack

This pack applies `design.md` as the normative source of truth. The goal is not to introduce a new visual language for Downloads; it is to make Downloads feel native to the rest of Mac All You Need.

## Included screens

- `01_main_queue` — main Downloads Queue tab using `FunctionPageShell` and a tokenized `DownloadJobRow`.
- `02_main_completed` — Completed tab focused on file actions.
- `03_main_settings` — Settings tab composed as `MAYNSection` + `MAYNSettingsRow`.
- `04_command_center` — menu-bar Command Center Downloads tab at 500×600 popover scale.
- `05_add_url_sheet` — focused URL enqueue sheet; replaces the permanent URL bar inside the list.
- `06_failed_state` — failed row with real yt-dlp error inline.
- `07_empty_state` — neutral empty state with Paste URL and Add URL actions.
- `08_components` — component sheet for implementation handoff.
- `09_dark_main_queue` — dark-mode queue check using the same tokens.

## Key UI decisions

1. **Use existing chrome.** The main page stays inside `FunctionPageShell`; the tab switch is `FunctionSegmentedTabStrip`; settings are regular `MAYNSection` rows.
2. **No permanent URL composer in the list.** The list should stay a status surface. Add/Paste opens a focused sheet or enqueue affordance.
3. **Introduce one domain component: `DownloadJobRow`.** A download row needs thumbnail, progress, phase, speed, ETA, and actions, so it cannot be a normal settings row. It should still consume `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`, and `StatusPill`.
4. **Semantic color only.** Active progress uses `MAYNTheme.progress`; completed uses `success`; paused/recoverable uses `warning`; failed/destructive uses `danger`; everything else is neutral. The Downloads feature accent stays limited to sidebar/dashboard iconography.
5. **Failure text is first-class.** The failed row shows the captured yt-dlp error inline and leaves room for tooltip/expanded stderr details.

## Implementation notes

- Keep content inside `FunctionPageScrollContent` max width unless a future product decision changes the global layout contract.
- Use `MAYNButton` for Add URL, Paste URL, Retry Failed, Open Folder, and row action buttons where text is visible. Icon-only row actions can be a small wrapper that reuses MAYN button hover/press motion.
- Use `.help(record.lastError)` on failed state labels and error rows.
- Use `MAYNMotion.controlAnimation(reduceMotion:)` for row phase/progress state transitions, and avoid spatial motion when Reduce Motion is enabled.
