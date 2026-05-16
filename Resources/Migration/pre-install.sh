#!/bin/bash
# pre-install.sh — runs from inside the NEW MAYN bundle before Sparkle swaps in the new app.
# Best-effort: copies yt-dlp + ffmpeg from the OLD bundle's Resources/ into the App Group's
# Features/downloader/<NEW_VERSION>/ directory so the new (small) wrapper finds them already
# in place — no re-download for upgraders.
#
# Arguments:
#   $1  Path to the currently-installed (OLD) MAYN app bundle.
#   $2  Marketing version of the NEW bundle (e.g. "2.0.0").
#
# Exits 0 unconditionally so a failure here cannot block the Sparkle install. The new app's
# Migrator will see no binaries on disk and fall back to "needs download" via the What's New
# sheet — that's the documented graceful-degradation path (spec § 12 Risk 8).
set -euo pipefail

OLD_APP="${1:-}"
NEW_VERSION="${2:-}"

if [ -z "$OLD_APP" ] || [ -z "$NEW_VERSION" ]; then
    echo "pre-install: missing arguments (OLD_APP=$OLD_APP, NEW_VERSION=$NEW_VERSION); skipping" >&2
    exit 0
fi

APPGROUP_BASE="$HOME/Library/Application Support/MacAllYouNeed"
DST="$APPGROUP_BASE/Features/downloader/$NEW_VERSION"

mkdir -p "$DST" || exit 0
mkdir -p "$APPGROUP_BASE/Features" || exit 0

for bin in yt-dlp ffmpeg; do
    src="$OLD_APP/Contents/Resources/$bin"
    if [ -f "$src" ]; then
        cp -p "$src" "$DST/$bin" || true
        chmod +x "$DST/$bin" 2>/dev/null || true
    fi
done

# Marker tells the new app's Migrator that the script ran (for diagnostics + cleanup).
touch "$APPGROUP_BASE/Features/.sparkle-migration-pending" || true

exit 0
