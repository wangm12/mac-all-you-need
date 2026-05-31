#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

if [[ ! -d "$VOICE_VENV" ]]; then
  echo "==> Creating venv at $VOICE_VENV ($VOICE_PYTHON)" >&2
  "$VOICE_PYTHON" -m venv "$VOICE_VENV"
fi

# shellcheck source=/dev/null
source "$VOICE_VENV/bin/activate"

pip install -q --index-url https://pypi.org/simple \
  datasets soundfile mlx mlx-lm mlx-tune mlx-audio 2>&1 | tail -5

echo "venv ready: $VOICE_VENV"
