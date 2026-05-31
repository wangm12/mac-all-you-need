# Voice cloning toolkit (MAYN)

Curate dictation WAVs for **text-to-speech voice cloning** (ElevenLabs, Fish Audio, local OSS). This is **not** the ASR fine-tune path — see [`docs/voice-training/README.md`](../voice-training/README.md).

## Prerequisites

1. Training examples with audio in the App Group container.
2. Quit Mac All You Need (`Cmd+Q`).
3. Export and extract:

```bash
make voice-training-export voice-training-extract
```

## Build reference pack

```bash
./scripts/voice-cloning/curate-reference-pack.sh
```

Outputs:

| Path | Purpose |
|------|---------|
| `reference-pack/instant/` | Best clips toward ~2 min instant clone |
| `reference-pack/instant-merged.wav` | Single file upload (if ffmpeg present) |
| `reference-pack/all-clips/` | Full export snapshot |
| `reference-pack/manifest.json` | Clip metadata and selection |

Override paths:

```bash
VOICE_CLONE_EXPORT_DIR=/path/to/extracted ./scripts/voice-cloning/curate-reference-pack.sh
VOICE_CLONE_INSTANT_TARGET_SEC=120 ./scripts/voice-cloning/curate-reference-pack.sh
```

## Evaluation script

Read or synthesize [`test-script-en.txt`](test-script-en.txt) on every vendor for apples-to-apples comparison. Record scores in [`docs/research/voice-cloning-vendor-evaluation-2026.md`](../research/voice-cloning-vendor-evaluation-2026.md).

## Cloud vendors (manual)

1. Upload `reference-pack/instant-merged.wav` or individual `instant/*.wav` files.
2. Create instant voice clone.
3. Paste test script (skip `#` comment lines).
4. Export MP3/WAV to `.build/voice-cloning-eval/` (gitignored).

API keys (optional automation):

```bash
export ELEVENLABS_API_KEY=...
export FISH_AUDIO_API_KEY=...
./scripts/voice-cloning/synthesize-cloud.sh   # when implemented; see evaluation doc
```

## Local OSS (Chatterbox smoke)

```bash
./scripts/voice-cloning/run-chatterbox-smoke.sh
```

Requires Python 3.10+ and network for first-time model download.

## Research docs

- Landscape: [`docs/research/voice-cloning-landscape-2026.md`](../research/voice-cloning-landscape-2026.md)
- Evaluation: [`docs/research/voice-cloning-vendor-evaluation-2026.md`](../research/voice-cloning-vendor-evaluation-2026.md)
- Integration decision: [`docs/research/voice-cloning-integration-decision-2026.md`](../research/voice-cloning-integration-decision-2026.md)

## Pro clone checklist

When corpus grows beyond pilot size, see [`pro-read-checklist.md`](pro-read-checklist.md):

- Record **30–60 minutes** clean studio read (single mic, no keyboard).
- Use ElevenLabs **Professional Voice Cloning** or Fish equivalent.
- Keep dictation exports for **ASR** separate from studio reads for **TTS**.

## Make targets

```bash
make voice-clone-curate              # after voice-training-extract
make voice-clone-chatterbox-smoke    # optional local OSS smoke
```
