#!/usr/bin/env python3
"""Import Typeless voice history into Mac All You Need (transcripts + training metadata).

Transcript rows are written directly to the App Group clipboard.sqlite.
Training-example rows are created with plaintext fields in encrypted_payload when
the optional `cryptography` package and Keychain device key are available; audio
is skipped (run the TypelessImport CLI locally to import encrypted audio).

Usage:
  python3 scripts/import-typeless-history.py [--dry-run] [--limit N]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

MODEL_ID = "typeless-import"
APP_GROUP = Path.home() / "Library/Group Containers/group.com.macallyouneed.shared"
TYPELESS_DB = Path.home() / "Library/Application Support/Typeless/typeless.db"
KEYCHAIN_SERVICE = "group.com.macallyouneed.shared"
KEYCHAIN_ACCOUNT = "device-key.v1"


@dataclass
class Row:
    id: str
    phrase: str
    replacement: str
    created_at: datetime
    duration_seconds: float
    app_bundle_id: str | None
    detected_language: str | None
    languages_json: str | None


def parse_created_at(text: str | None) -> datetime | None:
    if not text or not str(text).strip():
        return None
    text = str(text).strip()
    for fmt in (
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%d %H:%M:%S",
    ):
        try:
            dt = datetime.strptime(text.replace("Z", ""), fmt.replace("Z", ""))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_csv_line(line: str) -> list[str]:
    fields: list[str] = []
    current: list[str] = []
    in_quotes = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '"':
            if in_quotes and i + 1 < len(line) and line[i + 1] == '"':
                current.append('"')
                i += 2
                continue
            in_quotes = not in_quotes
            i += 1
            continue
        if ch == "," and not in_quotes:
            fields.append("".join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    fields.append("".join(current))
    return fields


def is_header(phrase: str, replacement: str) -> bool:
    p, r = phrase.lower(), replacement.lower()
    phrase_headers = {"phrase", "heard", "from", "source", "misrecognition"}
    replacement_headers = {"replacement", "to", "target", "correct", "fixed"}
    return p in phrase_headers and r in replacement_headers


def map_language(detected: str | None, languages_json: str | None) -> str:
    tokens: list[str] = []
    if detected:
        tokens.append(detected.strip().lower())
    if languages_json:
        try:
            parsed = json.loads(languages_json)
            if isinstance(parsed, list):
                tokens.extend(str(x).strip().lower() for x in parsed)
            elif isinstance(parsed, dict):
                tokens.extend(str(v).strip().lower() for v in parsed.values())
        except json.JSONDecodeError:
            pass

    def is_zh(t: str) -> bool:
        return t.startswith("zh") or "chinese" in t or t == "cmn"

    def is_en(t: str) -> bool:
        return t.startswith("en") or "english" in t

    has_zh = any(is_zh(t) for t in tokens)
    has_en = any(is_en(t) for t in tokens)
    if has_zh and has_en:
        return "mixed"
    if has_zh:
        return "zh"
    if has_en:
        return "en"
    return "unknown"


def load_typeless_rows(typeless_db: Path) -> list[Row]:
    conn = sqlite3.connect(f"file:{typeless_db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    rows: list[Row] = []

    legacy = conn.execute(
        """
        SELECT id, refined_text, edited_text, duration, created_at,
               focused_app_bundle_id, detected_language, languages
        FROM history
        WHERE status IN ('transcript', 'completed')
          AND refined_text IS NOT NULL
          AND trim(refined_text) != ''
        """
    ).fetchall()

    for item in legacy:
        created = parse_created_at(item["created_at"])
        if not created:
            continue
        phrase = (item["refined_text"] or "").strip()
        edited = (item["edited_text"] or "").strip()
        final = edited if edited else phrase
        rows.append(
            Row(
                id=item["id"],
                phrase=phrase,
                replacement=final,
                created_at=created,
                duration_seconds=float(item["duration"] or 0),
                app_bundle_id=(item["focused_app_bundle_id"] or "").strip() or None,
                detected_language=item["detected_language"],
                languages_json=item["languages"],
            )
        )

    modern = conn.execute(
        """
        SELECT id, refined_text, duration, created_at
        FROM history_v2
        WHERE status = 'completed'
          AND refined_text IS NOT NULL
          AND trim(refined_text) != ''
        """
    ).fetchall()

    for item in modern:
        created = parse_created_at(item["created_at"])
        if not created:
            continue
        phrase = (item["refined_text"] or "").strip()
        rows.append(
            Row(
                id=item["id"],
                phrase=phrase,
                replacement=phrase,
                created_at=created,
                duration_seconds=float(item["duration"] or 0),
                app_bundle_id=None,
                detected_language=None,
                languages_json=None,
            )
        )

    conn.close()
    rows.sort(key=lambda r: r.created_at, reverse=True)
    return rows


def millis(dt: datetime) -> int:
    return int(dt.timestamp() * 1000)


def load_device_key() -> bytes | None:
    try:
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-s",
                KEYCHAIN_SERVICE,
                "-a",
                KEYCHAIN_ACCOUNT,
                "-w",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None

    raw = result.stdout.strip()
    if not raw:
        return None
    # Keychain returns hex for binary keys in some setups; try hex decode first.
    try:
        if re.fullmatch(r"[0-9a-fA-F]+", raw) and len(raw) == 64:
            return bytes.fromhex(raw)
    except ValueError:
        pass
    return raw.encode("utf-8")[:32].ljust(32, b"\0") if len(raw) < 32 else raw.encode("latin-1")[:32]


def seal_payload(plaintext: bytes, key: bytes) -> bytes | None:
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        return None
    aes = AESGCM(key)
    nonce = os.urandom(12)
    ciphertext = aes.encrypt(nonce, plaintext, None)
    return nonce + ciphertext


def import_rows(
    rows: list[Row],
    mayn_db: Path,
    dry_run: bool,
    device_key: bytes | None,
) -> tuple[int, int, int]:
    imported = 0
    skipped = 0
    training = 0

    if dry_run:
        return len(rows), 0, 0

    conn = sqlite3.connect(mayn_db)
    now_ms = millis(datetime.now(timezone.utc))

    for row in rows:
        exists = conn.execute(
            "SELECT 1 FROM voice_transcripts WHERE id = ?", (row.id,)
        ).fetchone()
        if exists:
            skipped += 1
            continue

        ended = row.created_at + timedelta(seconds=row.duration_seconds or 1)
        duration_ms = max(0, int((ended - row.created_at).total_seconds() * 1000))
        language = map_language(row.detected_language, row.languages_json)

        conn.execute(
            """
            INSERT INTO voice_transcripts (
                id, started_at, ended_at, duration_ms, raw_text, cleaned_text,
                app_bundle_id, language, model_identifier, audio_path
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            """,
            (
                row.id,
                millis(row.created_at),
                millis(ended),
                duration_ms,
                row.phrase,
                row.replacement,
                row.app_bundle_id,
                language,
                MODEL_ID,
            ),
        )

        payload = {
            "rawText": row.phrase,
            "cleanedText": row.phrase,
            "finalText": row.replacement,
            "wasEdited": row.replacement != row.phrase,
            "quality": "medium",
            "qualityReason": "typeless_import",
        }
        encrypted: bytes | None = None
        if device_key and len(device_key) == 32:
            encrypted = seal_payload(json.dumps(payload).encode("utf-8"), device_key)

        if encrypted:
            example_id = os.urandom(16).hex()
            conn.execute(
                """
                INSERT INTO voice_training_examples (
                    id, transcript_id, app_bundle_id, language, model_identifier,
                    audio_path, encrypted_payload, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?)
                """,
                (
                    example_id,
                    row.id,
                    row.app_bundle_id,
                    language,
                    MODEL_ID,
                    encrypted,
                    now_ms,
                    now_ms,
                ),
            )
            training += 1

        imported += 1

    conn.commit()
    conn.close()
    return imported, skipped, training


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--typeless-db", type=Path, default=TYPELESS_DB)
    parser.add_argument("--mayn-container", type=Path, default=APP_GROUP)
    args = parser.parse_args()

    typeless_db = args.typeless_db.expanduser()
    mayn_db = args.mayn_container.expanduser() / "databases/clipboard.sqlite"

    if not typeless_db.is_file():
        print(f"error: Typeless database not found at {typeless_db}", file=sys.stderr)
        return 1
    if not mayn_db.is_file():
        print(f"error: MAYN database not found at {mayn_db}", file=sys.stderr)
        return 1

    if subprocess.run(["pgrep", "-x", "MacAllYouNeed"], capture_output=True).returncode == 0:
        print("error: Quit Mac All You Need (Cmd+Q) before importing.", file=sys.stderr)
        return 1

    rows = load_typeless_rows(typeless_db)
    if args.limit > 0:
        rows = rows[: args.limit]

    print(f"Scanned {len(rows)} Typeless rows", file=sys.stderr)
    print(f"Writing to {mayn_db}", file=sys.stderr)

    device_key = None if args.dry_run else load_device_key()
    if device_key:
        print("Loaded device key from Keychain for training examples.", file=sys.stderr)
    else:
        print(
            "warning: training examples skipped (install cryptography or use TypelessImport CLI for full import).",
            file=sys.stderr,
        )

    imported, skipped, training = import_rows(rows, mayn_db, args.dry_run, device_key)

    print("Typeless import complete" + (" (dry run)" if args.dry_run else ""))
    print(f"  imported:         {imported}")
    print(f"  skipped existing: {skipped}")
    print(f"  training rows:    {training}")
    print(f"  audio:            skipped (use TypelessImport CLI to import audio)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
