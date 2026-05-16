# Mac All You Need

A native macOS productivity app combining a Paste-style clipboard manager,
a FolderPreview-style Quick Look extension with PeekX-inspired analysis,
voice dictation, snippets, and a yt-dlp-powered universal video downloader.

## Status

Pre-alpha. Core local workflows are implemented, but distribution packaging
and notarized DMG release work are still deferred.

See `docs/superpowers/specs/` for design specs and `docs/superpowers/plans/`
for implementation plans.

## Design system

UI work in this repo follows a single normative spec: [`design.md`](./design.md).
It covers the MAYN tokens (`MAYNTheme` colors, `MAYNControlMetrics`,
`MAYNMotion`), the components catalog, the eight UI surfaces, the
Reduce-Motion contract, accepted exceptions, and the review checklist.

A subset of the rules is machine-enforced. `swiftlint --strict` (which
runs in `scripts/ci-build.sh`) fails the build on:

- Raw `Color(red:green:blue:)` outside the documented exceptions
- `.pickerStyle(.segmented)` (use `FunctionSegmentedTabStrip` instead)
- `Animation.easeOut(duration:)` / `.easeInOut(duration:)` / `.linear(duration:)`
  / `.spring(…)` (route through `MAYNMotion` so Reduce Motion is honored)

The custom rules live in `.swiftlint.yml`; each exclusion is annotated with
the `design.md` section that justifies it.

## Requirements

- Xcode 26+ with the macOS SDK installed
- macOS 14+
- Homebrew packages:

```bash
brew install libarchive swiftlint swiftformat xcodegen
```

- Node.js available at `/opt/homebrew/bin/node`, `/usr/local/bin/node`, or
  under `~/.nvm/versions/node`

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

Run the app build:

```bash
xcodebuild -project MacAllYouNeed.xcodeproj \
  -scheme MacAllYouNeed \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build
```

Or use the Makefile shortcuts:

```bash
make bootstrap   # fetch binaries and regenerate the Xcode project
make test        # run Shared package tests
make build       # build Debug
make release     # build Release and create dist/MacAllYouNeed.dmg
```

The Debug `.app` is written by Xcode into DerivedData, typically:

```text
~/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*/Build/Products/Debug/MacAllYouNeed.app
```

You can also open the project directly:

```bash
open MacAllYouNeed.xcodeproj
```

## Distribution

The official DMG target is:

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
the app plus an `/Applications` symlink, and writes the compressed DMG to:

```text
dist/MacAllYouNeed.dmg
```

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

Release packaging still depends on local Apple signing credentials and
provisioning being configured correctly in Xcode.

## Cleanup

Local build products and Xcode user state are intentionally not tracked. Safe
cleanup targets include:

```bash
rm -rf .build Shared/.build Shared/.swiftpm
rm -rf MacAllYouNeed.xcodeproj/xcuserdata MacAllYouNeed.xcworkspace/xcuserdata
rm -rf ~/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*
rm -f default.profraw Shared/default.profraw
```

Do not delete `Vendored/binaries/yt-dlp` or `Vendored/binaries/ffmpeg`; the
app build copies those into the app bundle for downloader runtime support.

After cleanup, verify ignored files before deleting anything else:

```bash
git clean -ndX
```

The equivalent Makefile target is:

```bash
make clean-cache
```

## Codex (Project MCP)

Use the repo-local launcher so `XcodeBuildMCP` is enabled only for this project/session:

```bash
./scripts/codex-project
```

## License

TBD before public launch.
