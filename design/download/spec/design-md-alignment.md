# design.md alignment checklist

- Colors are limited to `MAYNTheme` semantic tokens and the Downloads feature accent only in sidebar/iconography contexts.
- Page chrome uses `FunctionPageShell`.
- Main tabs use `FunctionSegmentedTabStrip`.
- Settings use `MAYNSection` and `MAYNSettingsRow`.
- Buttons use MAYN button roles: primary, secondary, destructive.
- Status uses `StatusPill` states: neutral, progress, success, warning, danger.
- URL entry uses a focused Add URL sheet instead of an ad-hoc list header composer.
- The only new surface proposed is `DownloadJobRow`, justified by video thumbnail + progress + process phase requirements.
- Animated GIF represents phase/progress state changes only; implementation must route motion through `MAYNMotion`.
