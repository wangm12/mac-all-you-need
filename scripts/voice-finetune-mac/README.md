# mlx-tune helpers (Python)

Low-level scripts used by **`make voice-training-*`**. Start with the main guide:

**[`docs/voice-training/README.md`](../../docs/voice-training/README.md)**

| File | Role |
|------|------|
| `prepare-dataset.py` | `data.jsonl` + audio → HuggingFace dataset |
| `pilot-train-whisper-tiny.py` | Smoke LoRA (not production Qwen3 training) |
| `pilot-eval-whisper.py` | Optional phrase eval (needs HF processor assets) |
| `smoke-pilot.sh` | Legacy wrapper — prefer `make voice-training-pilot` |

Shell orchestration: [`scripts/voice-training/`](../voice-training/).
