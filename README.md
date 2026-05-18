# Mac All You Need

Native macOS productivity app that combines local clipboard history, voice
dictation, video downloads, folder previews, snippets, and window controls in a
single menu-bar app.

## Status

Pre-alpha. Core local workflows are implemented and the app can build a local
Release DMG, but public distribution, Sparkle appcast publishing, GitHub release
automation, and notarized/stapled official releases are still Plan 7 work.

See `docs/superpowers/specs/` for design specs and `docs/superpowers/plans/`
for implementation plans.

## Features

- **Clipboard** - encrypted clipboard history, searchable `Command-Shift-V`
  dock/popup, bottom dock, pinboards, multi-select, transforms, Quick Look,
  capture rules, paste behavior, and app exclusions.
- **Voice** - push-to-talk/toggle dictation into any app with local Qwen3-ASR,
  optional Groq Whisper cloud ASR, optional cleanup, dictionary replacements,
  transcript history, personalization profiles, voice HUD, and guided setup.
- **Downloads** - yt-dlp + ffmpeg queue, browser cookie import, metadata,
  pause/resume, browser-extension dispatch server, clipboard video URL detection,
  completed-download folder preview, and Dock progress.
- **Folder Preview** - Quick Look previews for folders and archives, plus a
  Browse Folder window with Files, Grid, and Analyze views.
- **Snippets** - reusable text snippets with `;trigger` expansion. Expansion can
  be Auto, Tab-confirmed, or Off. Drag clipboard items onto the Snippets tab in
  the dock to create prefilled snippet drafts.
- **Window Layouts** - global shortcuts for halves, corners, maximize, center,
  restore, and display movement, plus edge snap and ignored apps.
- **Window Grab** - modifier-drag windows from visible content areas, sharing
  Window Layouts settings and diagnostics.
- **Feature runtime** - Dashboard cards can enable/disable features, install or
  remove asset packs, show migration results, and keep disabled features visible
  but inert in navigation.

## App Surfaces

- Menu-bar Command Center with Clipboard, Voice, Downloads, and Snippets tabs.
- Main window with Dashboard plus first-class pages for every tool.
- Bottom clipboard dock with history, snippets, user pinboards, drag/drop, and
  keyboard shortcuts.
- System Settings entry for General, Permissions, Storage, and Advanced.
- Per-tool settings inside the corresponding main tool pages.
- Main onboarding feature picker and a separate 9-step voice onboarding wizard.

## Design System

UI work follows [`design.md`](./design.md). The shared implementation lives
mostly in `MacAllYouNeed/Settings/MAYNSettingsUI.swift` and
`MacAllYouNeed/App/FunctionPageShell.swift`.

Important rules:

- Use `MAYNTheme`, `MAYNControlMetrics`, `MAYNMotion`, and
  `MAYNMotionBridge`.
- Use `FunctionSegmentedTabStrip` for product-owned segmented controls.
- Use shared controls (`MAYNButton`, `MAYNTextField`, `MAYNDropdown`,
  `MAYNSettingsRow`, `StatusPill`, `ShortcutChip`) before adding local chrome.
- Respect Reduce Motion for every spatial animation.
- Tool pages display hotkeys; editing lives in Settings/tool settings.

A subset of design rules is enforced by `swiftlint --strict` through custom
rules in `.swiftlint.yml`.

## Requirements

- Xcode 26+ with the macOS SDK installed
- macOS 14+
- Homebrew packages:

```bash
brew install libarchive swiftlint swiftformat xcodegen
```

- Node.js available at `/opt/homebrew/bin/node`, `/usr/local/bin/node`, or under
  `~/.nvm/versions/node`

## Build

Fetch downloader binaries before the first build:

```bash
./scripts/fetch-binaries.sh
```

Regenerate the Xcode project after `project.yml` changes:

```bash
xcodegen generate
```

Run Shared package tests:

```bash
cd Shared
PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test
cd ..
```

Build the Debug app:

```bash
xcodebuild -project MacAllYouNeed.xcodeproj \
  -scheme MacAllYouNeed \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Makefile shortcuts:

```bash
make bootstrap   # fetch binaries and regenerate the Xcode project
make test        # run Shared package tests
make build       # build Debug
make release     # build Release and create dist/MacAllYouNeed.dmg
```

The Debug app is written by Xcode into DerivedData, typically:

```text
~/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*/Build/Products/Debug/MacAllYouNeed.app
```

Open the project:

```bash
open MacAllYouNeed.xcodeproj
```

## Distribution

The local Release DMG target is:

```text
dist/MacAllYouNeed.dmg
```

Create it with:

```bash
make release
```

or directly:

```bash
./scripts/package-dmg.sh
```

The script builds the Release app into repo-local `build/DerivedData`, stages
the app plus an `/Applications` symlink, and writes a compressed DMG.

For local development, notarization is skipped unless credentials are provided.
For official release builds, provide either a notary keychain profile:

```bash
NOTARY_KEYCHAIN_PROFILE="mac-all-you-need-notary" make release
```

or Apple ID credentials:

```bash
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID1234" \
APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
make release
```

To sign the DMG itself, also set:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID1234)" make release
```

Release packaging still depends on local Apple signing credentials and Xcode
provisioning being configured correctly.

## Cleanup

Local build products and Xcode user state are intentionally not tracked. Safe
cleanup targets include:

```bash
rm -rf .build Shared/.build Shared/.swiftpm
rm -rf MacAllYouNeed.xcodeproj/xcuserdata MacAllYouNeed.xcworkspace/xcuserdata
rm -rf ~/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*
rm -f default.profraw Shared/default.profraw
```

Do not delete `Vendored/binaries/yt-dlp` or `Vendored/binaries/ffmpeg`; the app
build copies those into the app bundle for downloader runtime support.

After cleanup, verify ignored files before deleting anything else:

```bash
git clean -ndX
```

The equivalent Makefile target is:

```bash
make clean-cache
```

## Codex Project MCP

Use the repo-local launcher so `XcodeBuildMCP` is enabled only for this project
session:

```bash
./scripts/codex-project
```

## License

TBD before public launch.
