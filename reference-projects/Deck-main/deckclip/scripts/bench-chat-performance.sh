#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    source "$HOME/.cargo/env"
fi

CARGO="${CARGO:-cargo}"
MODE="${MODE:-release}"

export DECKCLIP_PERF_MESSAGES="${DECKCLIP_PERF_MESSAGES:-4000}"
export DECKCLIP_PERF_CHARS="${DECKCLIP_PERF_CHARS:-256}"
export DECKCLIP_PERF_WIDTH="${DECKCLIP_PERF_WIDTH:-96}"
export DECKCLIP_PERF_VIEWPORT_HEIGHT="${DECKCLIP_PERF_VIEWPORT_HEIGHT:-24}"
export DECKCLIP_PERF_CACHED_PASSES="${DECKCLIP_PERF_CACHED_PASSES:-1000}"
export DECKCLIP_PERF_SLICE_PASSES="${DECKCLIP_PERF_SLICE_PASSES:-2000}"
export DECKCLIP_PERF_STREAM_DELTAS="${DECKCLIP_PERF_STREAM_DELTAS:-1000}"

declare -a PROFILE_ARGS=()
if [[ "$MODE" == "release" ]]; then
    PROFILE_ARGS+=(--release)
fi

echo "== DeckClip Chat Perf =="
echo "mode:             $MODE"
echo "messages:         $DECKCLIP_PERF_MESSAGES"
echo "bytes per entry:  $DECKCLIP_PERF_CHARS"
echo "width:            $DECKCLIP_PERF_WIDTH"
echo "viewport height:  $DECKCLIP_PERF_VIEWPORT_HEIGHT"
echo "cached passes:    $DECKCLIP_PERF_CACHED_PASSES"
echo "slice passes:     $DECKCLIP_PERF_SLICE_PASSES"
echo "stream deltas:    $DECKCLIP_PERF_STREAM_DELTAS"
echo

cd "$PROJECT_DIR"
"$CARGO" test -p deckclip chat_render_perf_report "${PROFILE_ARGS[@]}" --no-run >/dev/null
/usr/bin/time -l "$CARGO" test -p deckclip chat_render_perf_report "${PROFILE_ARGS[@]}" -- --ignored --nocapture