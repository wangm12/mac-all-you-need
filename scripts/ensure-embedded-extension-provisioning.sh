#!/usr/bin/env bash
# Preflight: embedded appex targets need a Mac App Development profile per bundle ID.
# FinderHistoryExtension (com.macallyouneed.app.finderhistory) is new — register once in Xcode.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT="${PROJECT:-$ROOT/MacAllYouNeed.xcodeproj}"

# shellcheck source=scripts/resolve-development-team.sh
source "$ROOT/scripts/resolve-development-team.sh"

if [[ "${CODE_SIGNING_ALLOWED:-}" == "NO" ]]; then
  exit 0
fi

TEAM="$(require_development_team)"

# Bundle IDs for embedded, signed appex targets (keep in sync with project.yml).
REQUIRED_BUNDLE_IDS=(
  com.macallyouneed.app.finderhistory
)

profile_search_dirs=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

profile_covers_bundle() {
  local bundle_id="$1"
  local profile_path team_prefix encoded
  team_prefix="${TEAM}."
  encoded="${team_prefix}${bundle_id}"

  local dir
  for dir in "${profile_search_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    local profile
    for profile in "$dir"/*.{provisionprofile,mobileprovision}; do
      [[ -f "$profile" ]] || continue
      if security cms -D -i "$profile" 2>/dev/null | grep -qF "$encoded"; then
        return 0
      fi
    done
  done
  return 1
}

missing=()
for bundle_id in "${REQUIRED_BUNDLE_IDS[@]}"; do
  if ! profile_covers_bundle "$bundle_id"; then
    missing+=("$bundle_id")
  fi
done

if [[ "${#missing[@]}" -eq 0 ]]; then
  exit 0
fi

echo "==> Missing provisioning profile(s) for team $TEAM:" >&2
for bundle_id in "${missing[@]}"; do
  echo "    - $bundle_id" >&2
done

probe_log="$(mktemp)"
trap 'rm -f "$probe_log"' EXIT

set +e
xcodebuild \
  -project "$PROJECT" \
  -target FinderHistoryExtension \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates \
  "DEVELOPMENT_TEAM=$TEAM" \
  -showBuildSettings \
  >"$probe_log" 2>&1
probe_status=$?
set -e

if grep -q "No Accounts" "$probe_log"; then
  cat >&2 <<EOF
error: Xcode has no Apple ID account for automatic signing.

One-time setup (signed Release / make release):
  1. Open Xcode.app → Settings → Accounts → add your Apple ID.
  2. Select team $TEAM (Personal Team is fine).
  3. Open $PROJECT, select target FinderHistoryExtension → Signing & Capabilities.
  4. Ensure "Automatically manage signing" is on and wait for
     "Registering bundle identifier com.macallyouneed.app.finderhistory".
  5. Run: make release

Unsigned local DMG (no Apple account needed):
  CODE_SIGNING_ALLOWED=NO make release

EOF
  exit 1
fi

if [[ "$probe_status" -ne 0 ]]; then
  tail -8 "$probe_log" >&2 || true
fi

echo "==> Attempting to create profile via xcodebuild -allowProvisioningUpdates" >&2
set +e
xcodebuild \
  -project "$PROJECT" \
  -target FinderHistoryExtension \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates \
  "DEVELOPMENT_TEAM=$TEAM" \
  build \
  >"$probe_log" 2>&1
provision_status=$?
set -e

still_missing=()
for bundle_id in "${missing[@]}"; do
  if ! profile_covers_bundle "$bundle_id"; then
    still_missing+=("$bundle_id")
  fi
done

if [[ "$provision_status" -eq 0 && "${#still_missing[@]}" -eq 0 ]]; then
  echo "==> Provisioning profile ready for Finder History extension" >&2
  exit 0
fi

if grep -q "No Accounts" "$probe_log"; then
  cat >&2 <<EOF
error: Xcode has no Apple ID account for automatic signing.

One-time setup (signed Release / make release):
  1. Open Xcode.app → Settings → Accounts → add your Apple ID.
  2. Select team $TEAM (Personal Team is fine).
  3. Open $PROJECT, select target FinderHistoryExtension → Signing & Capabilities.
  4. Ensure "Automatically manage signing" is on and wait for
     "Registering bundle identifier com.macallyouneed.app.finderhistory".
  5. Run: make release

Unsigned local DMG (no Apple account needed):
  CODE_SIGNING_ALLOWED=NO make release

EOF
  exit 1
fi

if grep -q "com.macallyouneed.app.finderhistory" "$probe_log"; then
  tail -12 "$probe_log" >&2 || true
fi

cat >&2 <<EOF
error: could not obtain a provisioning profile for:
$(printf '  - %s\n' "${still_missing[@]}")

Open FinderHistoryExtension in Xcode Signing & Capabilities, then run: make release

EOF
exit 1
