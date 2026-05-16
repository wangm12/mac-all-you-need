#!/usr/bin/env bash
set -euo pipefail

# Build one or more feature pack zips, sign their executables, compute per-file SHAs,
# and update MacAllYouNeed/Resources/FeaturePackManifest.json with real values.
#
# Usage:
#   MAYN_DEV_ID="Developer ID Application: Acme (TEAMID)" \
#   scripts/build-feature-packs.sh <wrapper-version>
#
# Output:
#   release-artifacts/Downloader-<pack-version>.zip
#
# This script does NOT publish to GitHub. Plan 7's release workflow uploads
# release-artifacts/*.zip to the matching GitHub Release as a release asset.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <wrapper-version>" >&2
    exit 64
fi

WRAPPER_VERSION="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDORED="$ROOT/Vendored/binaries"
OUT_DIR="$ROOT/release-artifacts"
MANIFEST_PATH="$ROOT/MacAllYouNeed/Resources/FeaturePackManifest.json"
PACK_NAME="Downloader"
PACK_VERSION="1.0.0"   # bump when binaries change in a way that's tied to a wrapper version
PACK_FILE_NAME="${PACK_NAME}-${PACK_VERSION}.zip"
PACK_OUT="$OUT_DIR/$PACK_FILE_NAME"

if [ -z "${MAYN_DEV_ID:-}" ]; then
    echo "error: MAYN_DEV_ID env var must be set, e.g.:" >&2
    echo "  export MAYN_DEV_ID=\"Developer ID Application: Your Name (TEAMID)\"" >&2
    exit 65
fi

# Extract the team identifier from the identity string (last (TEAMID) group).
TEAM_ID="$(echo "$MAYN_DEV_ID" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
if [ -z "$TEAM_ID" ]; then
    echo "error: could not extract Team ID from MAYN_DEV_ID '$MAYN_DEV_ID'" >&2
    exit 66
fi

echo "==> Wrapper version: $WRAPPER_VERSION"
echo "==> Pack version: $PACK_VERSION"
echo "==> Team ID: $TEAM_ID"

# Fetch the binaries via the existing script (no-op if they already exist with matching SHAs).
"$ROOT/scripts/fetch-binaries.sh"

# Sign yt-dlp + ffmpeg with the MAYN Developer ID.
for bin in yt-dlp ffmpeg; do
    echo "==> Signing $bin"
    codesign --force --sign "$MAYN_DEV_ID" --timestamp --options=runtime "$VENDORED/$bin"
    codesign --verify --strict --verbose=2 "$VENDORED/$bin"
done

# Compute per-file SHA-256.
YT_SHA="$(shasum -a 256 "$VENDORED/yt-dlp" | awk '{print $1}')"
FF_SHA="$(shasum -a 256 "$VENDORED/ffmpeg" | awk '{print $1}')"
YT_BYTES="$(stat -f%z "$VENDORED/yt-dlp")"
FF_BYTES="$(stat -f%z "$VENDORED/ffmpeg")"
echo "==> yt-dlp sha256: $YT_SHA ($YT_BYTES bytes)"
echo "==> ffmpeg sha256: $FF_SHA ($FF_BYTES bytes)"

# Build a pack-internal manifest.json (mirrors the per-file entries; consumed by yt-dlp updater later).
cat > "$VENDORED/manifest.json" <<EOF
{
  "version": "$PACK_VERSION",
  "files": ["yt-dlp", "ffmpeg"]
}
EOF

# Build the zip.
mkdir -p "$OUT_DIR"
rm -f "$PACK_OUT"
(cd "$VENDORED" && zip -X -j "$PACK_OUT" yt-dlp ffmpeg manifest.json) > /dev/null
ZIP_SHA="$(shasum -a 256 "$PACK_OUT" | awk '{print $1}')"
ZIP_BYTES="$(stat -f%z "$PACK_OUT")"
echo "==> Built $PACK_FILE_NAME ($ZIP_BYTES bytes, sha256 $ZIP_SHA)"

# Get the GitHub repo from origin remote (owner/repo).
REPO_SLUG="$(git -C "$ROOT" remote get-url origin | sed -E 's#.*github.com[/:]([^/]+/[^/.]+)(\.git)?#\1#')"
RELEASE_URL="https://github.com/${REPO_SLUG}/releases/download/v${WRAPPER_VERSION}/${PACK_FILE_NAME}"

# Codesign requirement string — the same string is evaluated at install time.
CODESIGN_REQ="anchor apple generic and certificate leaf [subject.OU] = \"$TEAM_ID\""

# Rewrite the bundled manifest using python3 (avoids fragile sed on JSON).
python3 - "$MANIFEST_PATH" "$PACK_VERSION" "$RELEASE_URL" "$ZIP_SHA" "$ZIP_BYTES" "$YT_SHA" "$YT_BYTES" "$FF_SHA" "$FF_BYTES" "$CODESIGN_REQ" "$WRAPPER_VERSION" <<'PY'
import json, sys

path, pack_version, url, zip_sha, zip_bytes, yt_sha, yt_bytes, ff_sha, ff_bytes, codesign_req, wrapper_version = sys.argv[1:]

with open(path) as f:
    m = json.load(f)

m["wrapperVersion"] = wrapper_version
m["packs"]["downloader"] = {
    "version": pack_version,
    "url": url,
    "zipSha256": zip_sha,
    "sizeBytes": int(zip_bytes),
    "files": {
        "yt-dlp": {"sha256": yt_sha, "executable": True, "maxBytes": int(yt_bytes) + 1_000_000},
        "ffmpeg":  {"sha256": ff_sha, "executable": True, "maxBytes": int(ff_bytes) + 5_000_000},
    },
    "codesignRequirement": codesign_req,
}

with open(path, "w") as f:
    json.dump(m, f, indent=2)
    f.write("\n")

print(f"==> Updated {path}")
PY

echo "==> Done. Pack is at $PACK_OUT, manifest is at $MANIFEST_PATH."
echo "    Next: commit the manifest, build the wrapper DMG, and upload both as the same GitHub Release."
