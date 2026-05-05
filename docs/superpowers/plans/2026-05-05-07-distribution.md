# Plan 7: Distribution & Release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the app. Add Sparkle 2 auto-updates with EdDSA-signed appcast, finalize hardened-runtime entitlements, build a notarized + stapled DMG, and automate the release via GitHub Actions on tag push.

**Architecture:** A `release.sh` script orchestrates `xcodebuild archive` → `xcodebuild -exportArchive` → `xcrun notarytool submit --wait` → `xcrun stapler staple` → `create-dmg`. The Sparkle appcast is a static `appcast.xml` file hosted on GitHub Pages; each release appends an `<item>` with EdDSA signature + new version. GitHub Actions runs the script on `v*` tag pushes after CI passes; secrets (Developer ID certificate as base64 P12, app-specific password for notarytool, Sparkle EdDSA private key) live in GitHub Actions secrets. Quick Look extension and clipboard daemon are signed with the same Developer ID as the host app; Hardened Runtime is on for all bundles.

**Tech Stack:** Sparkle 2.x (SwiftPM), `create-dmg` (Homebrew), `notarytool`, `stapler`, GitHub Actions, EdDSA via Sparkle's `generate_keys` tool.

**Reads from spec:** §10 (entire), §3 (decisions 1, 2, 8).

**Depends on:** All prior plans. Cannot ship until 0–6 are green.

**Produces working software:** `git tag v0.1.0 && git push --tags` triggers CI, which produces a notarized `MacAllYouNeed-0.1.0.dmg` attached to a GitHub Release, and an updated `appcast.xml` published to GitHub Pages. Existing installs auto-update via Sparkle.

---

## File structure (added)

```
scripts/
├── release.sh                      # the build pipeline
├── sign-and-notarize.sh
├── make-dmg.sh
├── publish-appcast.sh              # appends new release to appcast.xml + signs
└── sparkle-keys/                   # local-only, NEVER committed
    ├── ed25519_priv.pem
    └── ed25519_pub.pem

.github/workflows/
├── ci.yml                          # (existing from Plan 0)
└── release.yml                     # NEW: triggered on `v*` tags

docs/
└── release/
    ├── RELEASE_CHECKLIST.md
    └── SIGNING_SETUP.md            # one-time developer setup steps

CHANGELOG.md                        # NEW

appcast/                            # NEW: published as GitHub Pages
└── appcast.xml
```

---

## Task 7.1: Add Sparkle 2 dependency

**Files:**
- Modify: `Shared/Package.swift` (add Sparkle to UI target)
- Modify: `MacAllYouNeed/MacAllYouNeedApp.swift` (init `SPUStandardUpdaterController`)
- Modify: `MacAllYouNeed/Info.plist` (add `SUFeedURL`, `SUPublicEDKey`)

- [ ] **Step 1: Add to Package.swift**

In `Shared/Package.swift`, add to `dependencies`:

```swift
.package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
```

Add to `UI` target dependencies:

```swift
.product(name: "Sparkle", package: "Sparkle"),
```

- [ ] **Step 2: Generate EdDSA keys (one-time)**

```bash
mkdir -p scripts/sparkle-keys
echo "scripts/sparkle-keys" >> .gitignore
swift package --package-path Shared resolve
# Sparkle ships generate_keys tool inside the resolved package:
.build/checkouts/Sparkle/bin/generate_keys
```

This emits a private key into Keychain and prints the public key. **Save the public key** — it goes into `Info.plist`. **Save the private key locally** — it signs each appcast item.

For CI: export the private key for safe storage as a GitHub Actions secret using Sparkle's `generate_keys --account` to assign a service name; CI installs it back into the runner Keychain at release time.

- [ ] **Step 3: Wire updater into the app**

```swift
import SwiftUI
import Sparkle

@main
struct MacAllYouNeedApp: App {
    @State private var controller: AppController = try! AppController()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        MenuBarExtra(...) {
            AppMenuBarContent(controller: controller, updater: updaterController.updater)
        }
        Settings { SettingsRoot(controller: controller) }
        WindowGroup("Onboarding", id: "onboarding") {
            if controller.onboarding != .completed { OnboardingWizardView(controller: controller) }
        }
    }
}
```

- [ ] **Step 4: Add Sparkle keys to Info.plist**

```xml
<key>SUFeedURL</key>
<string>https://wangm12.github.io/mac-all-you-need/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>PASTE-THE-BASE64-PUBLIC-KEY-HERE</string>
<key>SUEnableInstallerLauncherService</key>
<true/>
```

- [ ] **Step 5: Build to confirm**

```bash
xcodebuild -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -configuration Debug build
```

- [ ] **Step 6: Commit**

```bash
git add Shared/Package.swift MacAllYouNeed/Info.plist MacAllYouNeed/MacAllYouNeedApp.swift .gitignore
git commit -m "feat(updates): add Sparkle 2 with EdDSA appcast"
```

---

## Task 7.2: Final entitlements + Hardened Runtime config

**Files:**
- Modify: `MacAllYouNeed/MacAllYouNeed.entitlements`
- Modify: `ClipboardDaemon/ClipboardDaemon.entitlements`
- Modify: `FolderPreview/FolderPreview.entitlements`

Final entitlement set per spec §10. Tighter than Plan 0; only includes flags actually needed.

- [ ] **Step 1: Main app**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.macallyouneed.shared</string>
    </array>
    <!-- Required because we ship and exec yt-dlp + ffmpeg from Resources/ and from
         the App Group container (after verified updates). Apple flags this entitlement
         in notarization warnings; we accept that. -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <!-- Optional. Add only if profiling shows PyInstaller bundle requires it. -->
    <!-- <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
         <true/> -->
</dict>
</plist>
```

- [ ] **Step 2: Daemon**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.macallyouneed.shared</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Quick Look extension**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.macallyouneed.shared</string>
    </array>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Verify all targets have Hardened Runtime enabled**

In each target → Signing & Capabilities → "Hardened Runtime" capability is present.

- [ ] **Step 5: Commit**

```bash
git add MacAllYouNeed/MacAllYouNeed.entitlements ClipboardDaemon/ClipboardDaemon.entitlements FolderPreview/FolderPreview.entitlements
git commit -m "chore(signing): final entitlement set for Hardened Runtime + App Group"
```

---

## Task 7.3: `release.sh` build pipeline

**Files:**
- Create: `scripts/release.sh`
- Create: `scripts/sign-and-notarize.sh`
- Create: `scripts/make-dmg.sh`

- [ ] **Step 1: Implement `release.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: release.sh <version> (e.g. 0.1.0)}"
DEVELOPER_ID="${DEVELOPER_ID:?DEVELOPER_ID env var required (e.g. \"Developer ID Application: Mingjie Wang (TEAMID)\")}"
APPLE_ID="${APPLE_ID:?APPLE_ID env var required}"
APP_PASSWORD="${APP_PASSWORD:?APP_PASSWORD env var required (app-specific password)}"
TEAM_ID="${TEAM_ID:?TEAM_ID env var required}"

WORKSPACE="MacAllYouNeed.xcworkspace"
SCHEME="MacAllYouNeed"
ARCHIVE="build/MacAllYouNeed-${VERSION}.xcarchive"
EXPORT_DIR="build/export-${VERSION}"

mkdir -p build

echo "==> Updating CFBundleVersion"
agvtool new-marketing-version "${VERSION}"
agvtool new-version -all "${VERSION}"

echo "==> Archiving"
xcodebuild \
  -workspace "${WORKSPACE}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE}" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
  archive

echo "==> Exporting"
cat > build/exportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>${DEVELOPER_ID}</string>
    <key>teamID</key><string>${TEAM_ID}</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist build/exportOptions.plist

APP_PATH="${EXPORT_DIR}/MacAllYouNeed.app"

echo "==> Notarizing"
ditto -c -k --keepParent "${APP_PATH}" "build/MacAllYouNeed-${VERSION}.zip"
xcrun notarytool submit "build/MacAllYouNeed-${VERSION}.zip" \
  --apple-id "${APPLE_ID}" --password "${APP_PASSWORD}" --team-id "${TEAM_ID}" --wait

echo "==> Stapling"
xcrun stapler staple "${APP_PATH}"

echo "==> Creating DMG"
bash scripts/make-dmg.sh "${VERSION}" "${APP_PATH}"

echo "==> Done. Artifacts in build/"
ls -la "build/"
```

- [ ] **Step 2: Implement `make-dmg.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="$1"
APP_PATH="$2"
DMG_PATH="build/MacAllYouNeed-${VERSION}.dmg"

if ! command -v create-dmg >/dev/null; then
  echo "create-dmg not installed; run: brew install create-dmg" >&2
  exit 1
fi

create-dmg \
  --volname "Mac All You Need ${VERSION}" \
  --window-pos 200 120 \
  --window-size 720 420 \
  --icon-size 100 \
  --icon "MacAllYouNeed.app" 180 200 \
  --hide-extension "MacAllYouNeed.app" \
  --app-drop-link 540 200 \
  "${DMG_PATH}" \
  "${APP_PATH}"

echo "DMG: ${DMG_PATH}"
```

- [ ] **Step 3: Make executable + commit**

```bash
chmod +x scripts/release.sh scripts/make-dmg.sh
git add scripts/release.sh scripts/make-dmg.sh
git commit -m "build(release): release.sh and make-dmg.sh"
```

---

## Task 7.4: `publish-appcast.sh` — sign + append release item

**Files:**
- Create: `appcast/appcast.xml` (initial empty appcast)
- Create: `scripts/publish-appcast.sh`

- [ ] **Step 1: Initial appcast**

```xml
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mac All You Need</title>
    <link>https://wangm12.github.io/mac-all-you-need/appcast.xml</link>
    <description>Auto-update feed</description>
    <language>en</language>
  </channel>
</rss>
```

- [ ] **Step 2: Publish script**

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: publish-appcast.sh <version>}"
DMG_PATH="build/MacAllYouNeed-${VERSION}.dmg"
DOWNLOAD_URL="${DOWNLOAD_URL:?DOWNLOAD_URL env var required (release URL)}"
SPARKLE_PRIV_PEM="${SPARKLE_PRIV_PEM:?SPARKLE_PRIV_PEM env var required}"

if [[ ! -f "${DMG_PATH}" ]]; then echo "DMG missing: ${DMG_PATH}" >&2; exit 1; fi

# Sparkle ships sign_update inside the resolved package
SIGN_TOOL=".build/checkouts/Sparkle/bin/sign_update"
if [[ ! -x "${SIGN_TOOL}" ]]; then
  swift package --package-path Shared resolve
fi

LENGTH=$(stat -f%z "${DMG_PATH}")
SIGNATURE=$("${SIGN_TOOL}" --ed-key-file "${SPARKLE_PRIV_PEM}" "${DMG_PATH}" | awk -F'"' '/sparkle:edSignature/{print $2}')
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")

ITEM="<item>
  <title>Version ${VERSION}</title>
  <pubDate>${PUBDATE}</pubDate>
  <sparkle:version>${VERSION}</sparkle:version>
  <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
  <enclosure
    url=\"${DOWNLOAD_URL}\"
    sparkle:edSignature=\"${SIGNATURE}\"
    length=\"${LENGTH}\"
    type=\"application/octet-stream\" />
</item>"

# Insert before </channel>
sed -i.bak "s|</channel>|${ITEM}\n</channel>|" appcast/appcast.xml
rm appcast/appcast.xml.bak

echo "Updated appcast/appcast.xml with v${VERSION}"
```

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/publish-appcast.sh
git add appcast/appcast.xml scripts/publish-appcast.sh
git commit -m "build(release): publish-appcast.sh + initial appcast skeleton"
```

---

## Task 7.5: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Workflow**

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 15
        run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer

      - name: Install create-dmg
        run: brew install create-dmg swiftlint swiftformat

      - name: Import Developer ID certificate
        env:
          DEV_ID_P12_BASE64: ${{ secrets.DEV_ID_P12_BASE64 }}
          DEV_ID_P12_PASSWORD: ${{ secrets.DEV_ID_P12_PASSWORD }}
        run: |
          echo "$DEV_ID_P12_BASE64" | base64 --decode -o devid.p12
          security create-keychain -p "ci" build.keychain
          security set-keychain-settings build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "ci" build.keychain
          security import devid.p12 -k build.keychain -P "$DEV_ID_P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "ci" build.keychain
          rm devid.p12

      - name: Run release script
        env:
          DEVELOPER_ID: ${{ secrets.DEVELOPER_ID }}
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APP_PASSWORD: ${{ secrets.APP_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
        run: |
          VERSION="${GITHUB_REF#refs/tags/v}"
          ./scripts/release.sh "$VERSION"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VERSION="${GITHUB_REF#refs/tags/v}"
          gh release create "v$VERSION" \
            "build/MacAllYouNeed-$VERSION.dmg" \
            --title "v$VERSION" \
            --notes-file CHANGELOG.md

      - name: Update appcast
        env:
          DOWNLOAD_URL: https://github.com/${{ github.repository }}/releases/download/${{ github.ref_name }}/MacAllYouNeed-${{ github.ref_name }}.dmg
          SPARKLE_PRIV_PEM_BASE64: ${{ secrets.SPARKLE_PRIV_PEM_BASE64 }}
        run: |
          VERSION="${GITHUB_REF#refs/tags/v}"
          mkdir -p scripts/sparkle-keys
          echo "$SPARKLE_PRIV_PEM_BASE64" | base64 --decode -o scripts/sparkle-keys/ed25519_priv.pem
          export SPARKLE_PRIV_PEM=scripts/sparkle-keys/ed25519_priv.pem
          export DOWNLOAD_URL="${DOWNLOAD_URL//${{ github.ref_name }}/$VERSION}"
          ./scripts/publish-appcast.sh "$VERSION"
          rm scripts/sparkle-keys/ed25519_priv.pem

      - name: Commit appcast back to main
        run: |
          git config user.name "github-actions"
          git config user.email "actions@users.noreply.github.com"
          git add appcast/appcast.xml
          git commit -m "chore(release): update appcast for v${GITHUB_REF#refs/tags/v}" || true
          git push origin HEAD:main
```

- [ ] **Step 2: Configure GitHub Pages to serve `appcast/` directory**

In the repository settings → Pages → Build from `main` branch, `/appcast` folder.

The `SUFeedURL` in `Info.plist` (Task 7.1) must point at the resulting public URL.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: release workflow on v* tag push"
```

---

## Task 7.6: Documentation — release checklist + signing setup

**Files:**
- Create: `docs/release/RELEASE_CHECKLIST.md`
- Create: `docs/release/SIGNING_SETUP.md`
- Create: `CHANGELOG.md`

- [ ] **Step 1: Release checklist**

```markdown
# Release Checklist

Before tagging:

- [ ] CHANGELOG.md has an unreleased section ready to roll
- [ ] All Plans 0–6 tasks are checked off
- [ ] `./scripts/ci-build.sh` is green locally
- [ ] Manual smoke test on macOS 14.x and 15.x
- [ ] Privacy: confirm `os.Logger` strings don't leak user content
- [ ] App Group container ID matches in all 3 target entitlements
- [ ] Sparkle public key in Info.plist matches the private key on the release machine

Release:

- [ ] `git tag v<version> && git push --tags`
- [ ] Watch the Release workflow
- [ ] Verify the GitHub Release has `MacAllYouNeed-<version>.dmg`
- [ ] Verify `appcast/appcast.xml` updated and pushed back to main
- [ ] On a previously-installed copy, "Check for Updates" pulls the new version
- [ ] On a clean Mac, download DMG, drag-install, launch, run through onboarding

Hotfix path:

- [ ] Bump patch version (vx.y.Z+1)
- [ ] Same flow as a normal release
```

- [ ] **Step 2: Signing setup**

```markdown
# One-time signing setup

## Apple Developer

1. Enroll in the Apple Developer Program ($99/year).
2. In developer.apple.com → Certificates: create a "Developer ID Application" certificate.
3. Download the .cer, double-click to install in Keychain.
4. Export from Keychain as a `.p12` (set a password).

## App-specific password

1. appleid.apple.com → Sign-In and Security → App-Specific Passwords.
2. Generate one labeled "MacAllYouNeed Notarization".

## Sparkle EdDSA keys

```bash
swift package --package-path Shared resolve
.build/checkouts/Sparkle/bin/generate_keys
```

Store the private key in `scripts/sparkle-keys/ed25519_priv.pem` (gitignored).
Paste the public key into `MacAllYouNeed/Info.plist` under `SUPublicEDKey`.

## GitHub Actions secrets

Set these in repo settings → Secrets and variables → Actions:

- `DEVELOPER_ID` — `"Developer ID Application: Your Name (TEAMID)"`
- `TEAM_ID` — your Apple team ID
- `APPLE_ID` — your Apple ID email
- `APP_PASSWORD` — the app-specific password
- `DEV_ID_P12_BASE64` — `base64 -i devid.p12`
- `DEV_ID_P12_PASSWORD` — the password you set on the .p12
- `SPARKLE_PRIV_PEM_BASE64` — `base64 -i scripts/sparkle-keys/ed25519_priv.pem`
```

- [ ] **Step 3: CHANGELOG.md skeleton**

```markdown
# Changelog

## Unreleased

## v0.1.0 — TBD

- Initial release: clipboard manager, FolderPreview Quick Look extension, video downloader.
```

- [ ] **Step 4: Commit**

```bash
git add docs/release CHANGELOG.md
git commit -m "docs: release checklist, signing setup, changelog"
```

---

## Task 7.7: First end-to-end release dry run (`v0.0.1`)

**Files:** none.

- [ ] **Step 1: Tag a pre-release locally**

```bash
git tag v0.0.1
git push origin v0.0.1
```

- [ ] **Step 2: Watch GitHub Actions**

The release workflow runs. If it fails:
- Notarization → check the notarytool log (printed in the workflow output).
- Signing → confirm certificate import succeeded; common failure is the `.p12` password being wrong.
- Sparkle signing → confirm private key was decoded successfully.

- [ ] **Step 3: Validate artifact**

Download the released DMG. On a clean test machine (or new user account):

```bash
spctl -a -v MacAllYouNeed.app
# Expected: "MacAllYouNeed.app: accepted"
codesign -dv --verbose=4 MacAllYouNeed.app
# Expected: signed by your Developer ID, with Hardened Runtime
```

Drag to /Applications, launch, run onboarding. Note any first-launch issues.

- [ ] **Step 4: Test auto-update**

Tag `v0.0.2` with a trivial change. After the new release lands, on the previously-installed v0.0.1 copy: open Sparkle's "Check for Updates" (a Settings → Advanced button — add it if not already there: `updaterController.checkForUpdates(nil)`).

Expected: Sparkle finds v0.0.2, shows release notes, installs it.

- [ ] **Step 5: Document any issues found**

Add an issue log to `docs/release/RELEASE_CHECKLIST.md` for each surprise; we want this loop to be boring by v1.0.

---

## Self-review checklist

```bash
./scripts/ci-build.sh
./scripts/release.sh 0.0.1   # locally, requires DEVELOPER_ID/APPLE_ID/APP_PASSWORD/TEAM_ID env
```

Manual:
- DMG installs cleanly on a Mac with no prior app artifacts.
- `spctl -a -v` accepts the app.
- Sparkle "Check for updates" works.

**Spec coverage:**

- [x] §10 code signing pipeline (xcodebuild → notarytool → stapler) — Task 7.3
- [x] §10 hardened runtime entitlements (only-if-measured set) — Task 7.2
- [x] §10 Sparkle 2 with EdDSA appcast — Tasks 7.1, 7.4
- [x] §10 GitHub Releases distribution — Task 7.5
- [x] §10 signing spike noted (App Group / Quick Look reach) — verified in Plan 0 / 4 manual tests; Task 7.7 confirms in production conditions

**Out of scope (later):**
- Public landing page (separate website project)
- License selection (deferred per spec §10)
- macOS 15 / 16 specific QA matrix
- Migration of an unsandboxed pre-release to a future Mac App Store version

---

## After this plan

You shipped. Remember to:

1. Tag annual maintenance: yt-dlp updates often, ffmpeg less so. Keep `Vendored/binaries/manifest.json` fresh; ship a point release every quarter at minimum.
2. Watch the v2 backlog in `docs/superpowers/specs/2026-05-05-mac-all-you-need-design.md` §13 — the Chrome extension is the highest-value next item.
3. Open feedback channels before going wide. Even a Google Form linked from the menu-bar Help menu beats nothing.
