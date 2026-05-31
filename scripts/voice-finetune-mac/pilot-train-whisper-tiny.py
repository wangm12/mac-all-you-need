#!/usr/bin/env python3
"""Smoke LoRA on whisper-tiny using mlx-tune (pilot only — small corpora)."""

from __future__ import annotations

import argparse
from pathlib import Path

import soundfile as sf
from datasets import load_from_disk
from mlx_tune import FastSTTModel, STTSFTConfig, STTSFTTrainer, STTDataCollator


def materialize_audio_paths(dataset):
    def _map(batch):
        audio = []
        for path in batch["audio"]:
            array, sampling_rate = sf.read(path, dtype="float32", always_2d=False)
            if getattr(array, "ndim", 1) > 1:
                array = array.mean(axis=1)
            audio.append({"array": array, "sampling_rate": int(sampling_rate)})
        return {"audio": audio, "sentence": batch["sentence"]}

    return dataset.map(_map, batched=True, batch_size=8)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-steps", type=int, default=15)
    parser.add_argument("--model", default="mlx-community/whisper-tiny")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    dataset = load_from_disk(str(args.dataset))
    train = materialize_audio_paths(dataset["train"])
    eval_ds = materialize_audio_paths(dataset["validation"])

    model, processor = FastSTTModel.from_pretrained(args.model)
    model = FastSTTModel.get_peft_model(model, r=8, lora_alpha=8)

    collator = STTDataCollator(
        model=model,
        processor=processor,
        audio_column="audio",
        text_column="sentence",
    )
    config = STTSFTConfig(
        max_steps=args.max_steps,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=2,
        learning_rate=1e-4,
        logging_steps=1,
        output_dir=str(args.output),
        warmup_steps=2,
    )

    trainer = STTSFTTrainer(
        model=model,
        args=config,
        train_dataset=train,
        eval_dataset=eval_ds,
        data_collator=collator,
    )
    trainer.train()
    print(f"Pilot training finished. Check {args.output}")


if __name__ == "__main__":
    main()
