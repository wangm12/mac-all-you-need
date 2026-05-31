#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

if [[ ! -f "$VOICE_EXPORT_TAR" ]]; then
  echo "error: missing $VOICE_EXPORT_TAR — run: make voice-training-export" >&2
  exit 1
fi

rm -rf "$VOICE_EXPORT_EXTRACTED"
mkdir -p "$VOICE_EXPORT_EXTRACTED"
tar -xzf "$VOICE_EXPORT_TAR" -C "$VOICE_EXPORT_EXTRACTED"
echo "Extracted to $VOICE_EXPORT_EXTRACTED"
