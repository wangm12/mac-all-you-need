# O3b voice training pilot report (2026-05-29)

Pilot run on mingjie-father's Mac from **existing** App Group data (no new dictation required).

## Corpus you already had

| Metric | Value |
|--------|-------|
| Voice History (`voice_transcripts`) | **620** |
| Training examples (`voice_training_examples`) | **39** (all with encrypted WAV on disk) |
| Exportable with audio (1–30 s) | **39** |
| `quality == high` | **0** |
| `quality_reason` | 30× `post_edit_verification_unavailable`, 9× `awaiting_post_edit_verification` |
| ASR models in export | 32× `qwen3-asr-0.6b-f32`, 7× `groq-whisper-large-v3-turbo` |
| Total speech in export | **~4.1 min** (far below 30 min / 50-utterance pilot guidance) |
| Avg char diff `raw_text` → `user_edited_text` | **~0.24** (labels differ from raw ASR on many clips) |

**Important:** The in-app **Export** button uses the **high-only** filter. With your current DB, that would export **0** rows. Training data exists, but it has not been promoted to `high` yet (post-edit verification did not run or could not observe edits).

## What we did

1. **Exported** 39 clips via `VoiceTrainingCorpusPilotTests` + `MAYN_PILOT_EXPORT_PATH` (equivalent to `--any-quality`).
2. **Prepared** HF dataset: 35 train / 4 validation (`scripts/voice-finetune-mac/prepare-dataset.py`).
3. **Trained** a **smoke** LoRA: `mlx-community/whisper-tiny`, **12 steps** only (~20 s on M4 Max class hardware).
4. **Adapters written** under `.build/voice-finetune-pilot/whisper-tiny-lora/adapters` (local build tree, not in git).

Training loss averaged ~3.58 — proves the pipeline runs; **not** enough data or steps for a useful personal model.

## Evaluation results

| Check | Result |
|-------|--------|
| MAYN dictation uses new adapter? | **No** — [v2 in-app adapter loading](voice-personalization-backlog.md) not implemented |
| mlx_audio transcribe base vs LoRA | **Blocked** — HF processor files missing for `mlx-community/whisper-tiny` in cache |
| Engine alignment | **Mixed** — labels mostly Qwen3 local ASR; smoke train used **whisper-tiny** |
| Corpus size gate | **Fail** — need more minutes + `high` quality rows |

## What you should do next

1. Keep **Save training examples** on; after each dictation **edit the pasted text** and wait ~2 s so quality can become `high`.
2. Re-export when you have **≥50** clips and **≥30 min** (check counts in Personalization or `make voice-training-stats`).
3. For MAYN’s default local engine, fine-tune **Qwen3-ASR** (mlx-tune example 17), not whisper-tiny, once the corpus is large enough.
4. Repeat O3b with a full training run before investing in [v2 adapter loading](voice-personalization-backlog.md).

## Reproduce locally

```bash
# Quit Mac All You Need first (Cmd+Q)
make voice-training-stats
make voice-training-pilot    # export → HF dataset → whisper-tiny smoke (12 steps)
```

See also: [`docs/voice-training/README.md`](../voice-training/README.md), [`voice-personalization-backlog.md`](voice-personalization-backlog.md).
