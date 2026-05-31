#!/usr/bin/env bash
# Optional cloud TTS after instant voice clone exists on the vendor dashboard.
# Requires API keys; does not upload reference audio (clone must already exist).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/docs/voice-cloning/test-script-en.txt"
OUT="${VOICE_CLONE_EVAL_DIR:-$ROOT/.build/voice-cloning-eval}"
TEXT="$(grep -v '^#' "$SCRIPT" | tr '\n' ' ' | sed 's/  */ /g' | xargs)"
mkdir -p "$OUT"

if [[ -n "${ELEVENLABS_API_KEY:-}" && -n "${ELEVENLABS_VOICE_ID:-}" ]]; then
  curl -sS -X POST "https://api.elevenlabs.io/v1/text-to-speech/${ELEVENLABS_VOICE_ID}" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$TEXT" '{text: $t, model_id: "eleven_multilingual_v2"}')" \
    --output "$OUT/elevenlabs-test-script.mp3"
  echo "wrote $OUT/elevenlabs-test-script.mp3"
else
  echo "skip ElevenLabs: set ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID (after creating clone)" >&2
fi

if [[ -n "${FISH_AUDIO_API_KEY:-}" && -n "${FISH_AUDIO_VOICE_ID:-}" ]]; then
  echo "Fish Audio: use dashboard or API docs — set FISH_AUDIO_API_KEY + FISH_AUDIO_VOICE_ID" >&2
  echo "  https://fish.audio/" >&2
else
  echo "skip Fish Audio: set FISH_AUDIO_API_KEY and FISH_AUDIO_VOICE_ID" >&2
fi
