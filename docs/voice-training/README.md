# Voice offline training (export → fine-tune)

Personal ASR LoRA on Apple Silicon (M4 Max 64 GB is sufficient). This workflow is **offline**: export clips from your Mac All You Need App Group, prepare a HuggingFace dataset, and fine-tune with [mlx-tune](https://github.com/ARahim3/mlx-tune).

**Product note:** MAYN v1 does **not** load custom adapters during dictation. Adapters are for experimentation and future v2 in-app loading — see [`docs/research/voice-personalization-backlog.md`](../research/voice-personalization-backlog.md).

## Quick start (Make)

Quit Mac All You Need (`Cmd+Q`) before export.

```bash
make voice-training-stats      # row counts from your App Group DB
make voice-training-export     # .build/voice-export/mayn-voice-training.tar.gz
make voice-training-pilot      # export + HF dataset + whisper-tiny smoke (12 steps)
```

| Target | What it does |
|--------|----------------|
| `make voice-training-stats` | Print corpus counts (no files written) |
| `make voice-training-export` | Export archive (default: all qualities with audio) |
| `make voice-training-extract` | Untar export to `.build/voice-export/extracted` |
| `make voice-training-venv` | Python venv under `.build/voice-finetune-pilot/venv` |
| `make voice-training-prepare` | Build HF dataset from export |
| `make voice-training-train-smoke` | Whisper-tiny LoRA smoke train |
| `make voice-training-pilot` | Full smoke pipeline |
| `make voice-training-clean` | Remove `.build/voice-export` and `.build/voice-finetune-pilot` |

Override paths:

```bash
make voice-training-export VOICE_EXPORT_TAR=~/Desktop/mayn-voice.tar.gz
make voice-training-train-smoke VOICE_TRAIN_MAX_STEPS=24
```

Scripts live in [`scripts/voice-training/`](../../scripts/voice-training/). Python helpers: [`scripts/voice-finetune-mac/`](../../scripts/voice-finetune-mac/).

## In-app export (UI)

**Personalization** or **Advanced** → **Export training data…**

Default filter is **high** quality only. If export is empty, use the Make path (`MAYN_EXPORT_ANY_QUALITY=1`) or rate more examples until post-edit verification promotes rows to `high`.

Guidance: ≥ **50** utterances and ≥ **30 minutes** total speech before expecting meaningful LoRA gains.

## Prerequisites

1. macOS 14+, Xcode toolchain, `brew install libarchive` (for Shared tests).
2. **Python 3.12** recommended (`brew install python@3.12`). Some 3.14 builds break HuggingFace `datasets` fingerprinting.
3. Dictation history with training examples and audio in the App Group container:
   `~/Library/Group Containers/group.com.macallyouneed.shared`

## Production fine-tune (after pilot)

Match the engine you dictate with:

| Engine | mlx-tune path |
|--------|----------------|
| **Qwen3-ASR** (MAYN default local) | Example `17_qwen3_asr_finetuning.py` |
| **Parakeet** (FluidAudio) | Examples `50`–`53` |
| **Whisper** (Groq / Whisper ASR) | Example 13; smoke script uses `whisper-tiny` only |

```bash
make voice-training-export voice-training-prepare
# Then run mlx-tune with --dataset-path $(pwd)/.build/voice-finetune-pilot/hf-dataset
```

Evaluate on held-out phrases (names, jargon). Document in `docs/research/voice-training-pilot-*.md`.

## Related docs

- Adoption verification: [`docs/voice-personalization-adoption-verification.md`](../voice-personalization-adoption-verification.md)
- Research + backlog: [`docs/research/voice-personalization-and-training.md`](../research/voice-personalization-and-training.md), [`docs/research/voice-personalization-backlog.md`](../research/voice-personalization-backlog.md)
- Pilot report (example): [`docs/research/voice-training-pilot-o3b-2026-05-29.md`](../research/voice-training-pilot-o3b-2026-05-29.md)

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Export says app is running | `Cmd+Q` Mac All You Need |
| UI export returns 0 rows | Corpus may have no `high` rows; use `make voice-training-export` |
| `swift test` export fails in sandbox | Run from Terminal.app, not restricted CI sandboxes |
| `datasets` / fingerprint errors | Use Python 3.12 venv (`make voice-training-venv`) |
| Uber pip index | Scripts use `https://pypi.org/simple` |
| Adapter not used in app | Expected until v2 — see backlog |
