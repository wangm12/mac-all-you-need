#!/usr/bin/env python3
"""Convert MAYN voice export (data.jsonl + audio/) to a HuggingFace datasets folder."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from datasets import Dataset, DatasetDict


def load_jsonl(export_dir: Path) -> list[dict]:
    jsonl_path = export_dir / "data.jsonl"
    rows: list[dict] = []
    with jsonl_path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            audio_rel = row.get("audio_path")
            if not audio_rel:
                continue
            audio_abs = export_dir / audio_rel
            if not audio_abs.is_file():
                raise FileNotFoundError(f"Missing audio file: {audio_abs}")
            rows.append(
                {
                    "audio": str(audio_abs.resolve()),
                    "sentence": row.get("user_edited_text") or row.get("cleaned_text") or "",
                    "id": row.get("id"),
                }
            )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--eval-fraction", type=float, default=0.1)
    args = parser.parse_args()

    rows = load_jsonl(args.export_dir)
    if not rows:
        raise SystemExit("No rows found in data.jsonl")

    split_idx = max(1, int(len(rows) * (1 - args.eval_fraction)))
    train_rows = rows[:split_idx]
    eval_rows = rows[split_idx:] or rows[-1:]

    dataset = DatasetDict(
        {
            "train": Dataset.from_list(train_rows),
            "validation": Dataset.from_list(eval_rows),
        }
    )
    args.output.mkdir(parents=True, exist_ok=True)
    dataset.save_to_disk(str(args.output))
    print(f"Wrote {len(train_rows)} train / {len(eval_rows)} validation rows to {args.output}")


if __name__ == "__main__":
    main()
