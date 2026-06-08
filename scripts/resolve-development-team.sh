#!/usr/bin/env bash
# Resolves DEVELOPMENT_TEAM for signed xcodebuild invocations.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

resolve_development_team() {
  if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    echo "$DEVELOPMENT_TEAM"
    return 0
  fi

  local xcconfig="$ROOT/Config/Signing.local.xcconfig"
  if [[ -f "$xcconfig" ]]; then
    local from_local
    from_local=$(awk -F= '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2);
      print $2;
      exit
    }' "$xcconfig")
    if [[ -n "$from_local" ]]; then
      echo "$from_local"
      return 0
    fi
  fi

  local shared="$ROOT/Config/Signing.xcconfig"
  if [[ -f "$shared" ]]; then
    local from_shared
    from_shared=$(awk -F= '/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ {
      gsub(/[[:space:]]/, "", $2);
      print $2;
      exit
    }' "$shared")
    if [[ -n "$from_shared" ]]; then
      echo "$from_shared"
      return 0
    fi
  fi

  return 1
}

require_development_team() {
  local team
  if ! team=$(resolve_development_team); then
    cat >&2 <<'EOF'
error: DEVELOPMENT_TEAM is not set for signed Release builds.

Fix one of:
  1. export DEVELOPMENT_TEAM=<your-team-id>   # Xcode → Settings → Accounts
  2. cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
     then edit DEVELOPMENT_TEAM in Config/Signing.local.xcconfig
  3. Sign in to Xcode (Settings → Accounts) so automatic provisioning can run

EOF
    exit 1
  fi
  echo "$team"
}
