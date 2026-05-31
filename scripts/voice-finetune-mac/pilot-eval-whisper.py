#!/usr/bin/env python3
"""Quick CER on validation split: base whisper-tiny vs pilot LoRA."""

from __future__ import annotations

import argparse
from pathlib import Path

import soundfile as sf
from datasets import load_from_disk

try:
    from mlx_tune.ocr import compute_cer
except ImportError:
    def compute_cer(pred: str, ref: str) -> float:
        pred, ref = pred.strip(), ref.strip()
        if not ref:
            return 0.0
        dist = sum(a != b for a, b in zip(pred, ref)) + abs(len(pred) - len(ref))
        return dist / max(len(ref), 1)


def transcribe(model, path: str) -> str:
    audio, _ = sf.read(path, dtype="float32", always_2d=False)
    if getattr(audio, "ndim", 1) > 1:
        audio = audio.mean(axis=1)
    result = model.generate(audio)
    if isinstance(result, str):
        return result.strip()
    if hasattr(result, "text"):
        return str(result.text).strip()
    return str(result).strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--adapter", type=Path, required=True)
    parser.add_argument("--model", default="mlx-community/whisper-tiny")
    args = parser.parse_args()

    from mlx_audio.stt import load

    eval_rows = load_from_disk(str(args.dataset))["validation"]
    base = load(args.model)
    tuned = load(args.model, adapter_path=str(args.adapter))

    print("reference | base | +lora | base_cer | lora_cer")
    base_cers, lora_cers = [], []
    for row in eval_rows:
        ref = row["sentence"]
        path = row["audio"]
        b = transcribe(base, path)
        t = transcribe(tuned, path)
        bc = compute_cer(b, ref)
        tc = compute_cer(t, ref)
        base_cers.append(bc)
        lora_cers.append(tc)
        print(f"{ref[:40]!r} | {b[:40]!r} | {t[:40]!r} | {bc:.3f} | {tc:.3f}")

    avg_b = sum(base_cers) / len(base_cers)
    avg_t = sum(lora_cers) / len(lora_cers)
    print(f"\navg_cer base={avg_b:.3f} lora={avg_t:.3f} delta={avg_t - avg_b:+.3f} (n={len(base_cers)})")


if __name__ == "__main__":
    main()
