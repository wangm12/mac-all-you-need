#!/usr/bin/env bash
# Build a voice-cloning reference pack from MAYN voice-training export.
# Prefers longer, single-speaker clips; targets ~120s for instant clone tier.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXTRACTED="${VOICE_CLONE_EXPORT_DIR:-$ROOT/.build/voice-export/extracted}"
OUT="${VOICE_CLONE_PACK_DIR:-$ROOT/docs/voice-cloning/reference-pack}"
INSTANT_TARGET_SEC="${VOICE_CLONE_INSTANT_TARGET_SEC:-120}"
JSONL="$EXTRACTED/data.jsonl"
AUDIO_SRC="$EXTRACTED/audio"

if [[ ! -f "$JSONL" ]]; then
  echo "error: missing $JSONL — run: Cmd+Q app, make voice-training-export voice-training-extract" >&2
  exit 1
fi

mkdir -p "$OUT/instant" "$OUT/all-clips"
rm -f "$OUT/instant"/*.wav "$OUT/all-clips"/*.wav 2>/dev/null || true

python3 - "$JSONL" "$AUDIO_SRC" "$OUT" "$INSTANT_TARGET_SEC" <<'PY'
import json
import shutil
import sys
from pathlib import Path

jsonl_path, audio_src, out_dir, target_sec = sys.argv[1:5]
target_ms = int(float(target_sec) * 1000)
out = Path(out_dir)
audio_src = Path(audio_src)

rows = []
with open(jsonl_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))

# Prefer longer clips; deprioritize very short or duplicate-heavy raw_text
def score(row):
    dur = int(row.get("duration_ms") or 0)
    raw = (row.get("raw_text") or "")
    cleaned = (row.get("cleaned_text") or row.get("user_edited_text") or "")
    dup_penalty = 0
    if raw and cleaned and raw.count(cleaned) > 1:
        dup_penalty = 500
    return dur - dup_penalty

rows.sort(key=score, reverse=True)

manifest = []
total_ms = 0
instant_ids = []

for row in rows:
    eid = row["id"]
    src = audio_src / f"{eid}.wav"
    if not src.is_file():
        continue
    dest_all = out / "all-clips" / f"{eid}.wav"
    shutil.copy2(src, dest_all)
    manifest.append(
        {
            "id": eid,
            "duration_ms": row.get("duration_ms"),
            "quality": row.get("quality"),
            "source_app": row.get("source_app"),
            "text_preview": (row.get("cleaned_text") or "")[:80],
            "in_instant_pack": False,
        }
    )

for row in rows:
    if total_ms >= target_ms:
        break
    eid = row["id"]
    src = audio_src / f"{eid}.wav"
    if not src.is_file():
        continue
    dur = int(row.get("duration_ms") or 0)
    dest = out / "instant" / f"{eid}.wav"
    shutil.copy2(src, dest)
    total_ms += dur
    instant_ids.append(eid)

for entry in manifest:
    if entry["id"] in instant_ids:
        entry["in_instant_pack"] = True

summary = {
    "source_export": str(Path(jsonl_path).parent),
    "total_clips": len(manifest),
    "instant_clip_count": len(instant_ids),
    "instant_total_ms": total_ms,
    "instant_target_ms": target_ms,
    "note": "Instant pack is best-effort until corpus exceeds target; record studio read for pro clone.",
    "clips": manifest,
}

(out / "manifest.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

# Concat list for ffmpeg (optional single reference file)
concat_lines = []
for eid in instant_ids:
    p = out / "instant" / f"{eid}.wav"
    if p.is_file():
        concat_lines.append(f"file '{p.resolve()}'")
(out / "instant-concat.txt").write_text("\n".join(concat_lines) + ("\n" if concat_lines else ""), encoding="utf-8")

print(f"voice-cloning reference pack: {out}")
print(f"  all-clips: {len(manifest)}")
print(f"  instant:   {len(instant_ids)} clips, {total_ms/1000:.1f}s (target {target_ms/1000:.0f}s)")
PY

# Optional: merge instant clips into one WAV for vendors that want a single file
if command -v ffmpeg >/dev/null 2>&1 && [[ -s "$OUT/instant-concat.txt" ]]; then
  ffmpeg -y -f concat -safe 0 -i "$OUT/instant-concat.txt" -c copy "$OUT/instant-merged.wav" 2>/dev/null \
    || ffmpeg -y -f concat -safe 0 -i "$OUT/instant-concat.txt" -c:a pcm_s16le "$OUT/instant-merged.wav"
  echo "  merged:    $OUT/instant-merged.wav"
else
  echo "  merged:    skipped (ffmpeg missing or no clips)"
fi
