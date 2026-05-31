#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

rm -rf "$VOICE_EXPORT_DIR" "$VOICE_FINETUNE_DIR"
echo "Removed $VOICE_EXPORT_DIR and $VOICE_FINETUNE_DIR"
