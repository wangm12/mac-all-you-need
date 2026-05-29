# Voice Personalization & Training — Product Spec v1

**Status:** Normative (research-backed)  
**Date:** 2026-05-29  
**Research:** [`docs/research/voice-personalization-and-training.md`](../research/voice-personalization-and-training.md)  
**Related:** [`docs/spec-1-personalization-plan-v2.md`](../spec-1-personalization-plan-v2.md), [`docs/superpowers/specs/2026-05-11-voice-dictation-design.md`](../superpowers/specs/2026-05-11-voice-dictation-design.md) (Plan 8f)

---

## 1. Purpose

Define two parallel product tracks for voice:

1. **Inference-time personalization** — improve LLM cleanup on the next dictation without changing model weights.
2. **Offline training corpus** — collect exportable `(audio, labels)` for optional external ASR adaptation (Whisper LoRA class).

This spec is the single normative reference for data definitions, privacy gates, and phased delivery. Implementation details live in code and older task specs; this document resolves product boundaries after competitor, paper, and OSS research.

---

## 2. Definitions

| Term | Storage | Purpose |
|------|---------|---------|
| **Transcript** | `voice_transcripts` | User-visible history; raw + cleaned text; optional `audio_path`. |
| **Personalization sample** | `voice_personalization_samples` | Encrypted `{before, after}` edit pair tied to a **context**; feeds few-shot examples + summarizer. |
| **Training example** | `voice_training_examples` | Export-oriented row: `rawText`, `cleanedText`, `finalText`, optional encrypted WAV; quality metadata. |
| **Context** | `voice_personalization_contexts` | Per-app or global profile: style notes, summary, overrides, enable flag. |

**Rule:** Personalization samples require a **real edit observation** (pasted cleanup vs user’s final field text). Training examples may exist without a personalization sample (e.g. import, or post-edit verification failed).

---

## 3. Inference-time personalization track

### 3.1 User-facing behavior

- **Learn from edits** (`learnFromEditsEnabled`): After paste, MAYN may observe the focused text field and store edit pairs.
- **Writing style notes** (global context): User-authored instructions always injected when personalization is active.
- **Per-app controls:** User can disable learning for an app; disable = **no** personalization fields for that app (no global fallback).
- **Summarized style:** Background job collapses old samples into an encrypted summary (uses configured text-generation / cleanup provider).

### 3.2 Pipeline (normative)

```
stopRecordingAndPaste → ASR → cleanup(prompt with personalization) → paste
  → save transcript
  → LearningPhase → PostEditLearningMonitor (if enabled, not auto-submit, privacy pass)
  → append personalization sample
  → update training example finalText + quality (if save training examples on)
  → maybeRun summarizer
```

**Code anchors:** `VoiceCoordinator`, `LearningPhase`, `VoicePostEditLearningMonitor`, `VoicePersonalizationSummarizer`, `VoicePromptBuilder`.

### 3.3 Prompt injection (normative order)

In `VoicePromptBuilder.systemPrompt`, after base cleanup rules:

1. App bundle / instructions / translation  
2. `<STYLE_NOTES>` (global user notes)  
3. `<STYLE_SUMMARY>` (distilled from samples)  
4. `<EXAMPLES>` — up to 5 pairs, 512 chars each, 2048 total; prefix: treat as user data, not instructions  
5. Dictionary replacements  

### 3.4 Privacy gates (must not regress)

- Capture only on allowlisted AX roles; reject `AXSecureTextField`.
- Deny listed password-manager / keychain bundles (`VoicePersonalizationPrivacyFilter`).
- Fail-closed on focus/bundle/PID change during observation.
- No logging of raw before/after (privacy `.private` metadata only).
- Skip learning when auto-submit is configured for the active context.
- Caps: 2 KB per before/after span; 60 s observation timeout.

### 3.5 Research gaps vs competitors (planned)

| Feature | Priority | Notes |
|---------|----------|-------|
| Manual **input/output example pairs** in UI (Superwhisper-style) | P1 | Complements automatic learning |
| **Retrieval-based** example selection (GEC literature) | P2 | Replace “newest 5 only” when sample count large |
| Auto-dictionary from corrections (Wispr-style) | P3 | Design doc v2; separate from personalization samples |

---

## 4. Offline training track

### 4.1 User-facing behavior

- **Save training examples** (`saveTrainingExamplesEnabled`): Persist encrypted WAV + text rows for future export; enables Retry/Download in history when audio exists.
- **Save audio recordings** (`voice.history.saveAudio`): May persist WAV without creating a training row (history-only).
- **Export** (not built): User-initiated export to `.tar.gz` for external training (Plan 8f).
- **In-app fine-tune:** **Out of scope** for v1; optional documented scripts outside the app.

### 4.2 Quality ladder (normative)

| Quality | When | Use in export |
|---------|------|----------------|
| `low` / import | Typeless import, no verification | Optional, tagged `typeless_import` |
| `medium` | Default at save; post-edit unavailable | Exclude from default export |
| `high` | Post-edit monitor confirmed `finalText` | **Include** in default export |

`qualityReason` strings are diagnostic (e.g. `awaiting_post_edit_verification`, `post_edit_final_text_observed`, `typeless_import`).

### 4.3 TrainingExporter (Plan 8f — normative)

**Trigger:** Settings → Advanced (or Personalization) → “Export voice training data…”

**Output:** `.tar.gz` containing:

- `data.jsonl` — one JSON object per line  
- `audio/<id>.wav` — decrypted at export time from `.aesgcm` store  

**JSONL schema (v1):**

```json
{
  "id": "uuid",
  "transcript_id": "uuid",
  "audio_path": "audio/<id>.wav",
  "raw_text": "…",
  "cleaned_text": "…",
  "user_edited_text": "…",
  "was_edited": true,
  "language": "en",
  "asr_model_id": "qwen3-asr-0.6b-f32",
  "source_app": "com.apple.TextEdit",
  "quality": "high",
  "quality_reason": "post_edit_final_text_observed",
  "duration_ms": 12340,
  "created_at": "ISO-8601"
}
```

**Default export filter:** `quality == high` and `audio_path` present and duration 1–30 s (Whisper training convention per research P9).

**Compatibility:** HuggingFace `datasets`, Listenr-style `manifest.jsonl`, [finetune-openai-whisper](https://github.com/farisalasmary/finetune-openai-whisper) field mapping (`text` ← `user_edited_text` or `cleaned_text` per export mode).

### 4.4 External fine-tune (out of app)

**Deliverable:** `scripts/finetune-whisper-lora/` (or doc pointing to Listenr) — not required in app bundle.

**Minimum dataset guidance (informative):**

- Pilot LoRA: ≥ 30 minutes speech, ≥ 50 verified (`high`) utterances, single primary language.  
- Diminishing returns below ~10 minutes; domain terms need manual dictionary + examples.

**Optional future:** Select exported adapter in ASR settings (v2); not v1.

---

## 5. Typeless import policy

| Target table | Policy |
|--------------|--------|
| `voice_transcripts` | Import `refined_text` as cleaned/raw; `model_identifier = typeless-import` |
| `voice_training_examples` | Swift CLI only: OGG→WAV, `cleaned = final = refined`, `quality` import-tier, `quality_reason = typeless_import` |
| `voice_personalization_samples` | **Do not import** — no reliable before/after |

Python transcript-only import remains valid for history; does not satisfy training/export audio needs.

---

## 6. Settings & consent copy (normative)

| Setting | Copy requirement |
|---------|------------------|
| Learn from edits | Explain AX read of focused field after paste; encrypted local storage |
| Save training examples | Local only; not uploaded; enables audio for history actions |
| Summarization | If cloud provider used for summary, same disclosure as cleanup (spec-1 B4) |

---

## 7. Phased delivery table

| ID | Deliverable | Track | Status |
|----|-------------|-------|--------|
| I1 | Post-edit monitor + store + summarizer + prompt injection | Inference | Shipped |
| I2 | Personalization page + app controls | Inference | Shipped |
| I3 | Manual example editor in UI | Inference | Planned |
| I4 | Example retrieval (similarity) | Inference | Planned |
| O1 | Training example list UI | Offline | Planned |
| O2 | TrainingExporter | Offline | Planned (8f) |
| O3 | `scripts/finetune-whisper-lora` + README | Offline | Planned |
| O4 | Auto-learned dictionary | Inference | Deferred (design v2) |
| O5 | In-app LoRA / adapter picker | Offline | Deferred |

---

## 8. Decision log (research conclusions)

| Decision | Rationale |
|----------|-----------|
| Two tracks, not one | Industry separates prompt adaptation (inference) from ASR fine-tune (offline) |
| No in-app training v1 | Listenr proves power-user path; consumer apps don’t ship it |
| Keep post-edit learning | Rare differentiator; aligns with GEC “learning from edits” literature |
| Export `high` + audio only by default | Reduces garbage in LoRA sets |
| No Typeless → personalization samples | Synthetic pairs would poison few-shot prompts |
| GPL VoiceInk = patterns only | License compliance |

**User choice after research (workshop §9 in findings doc):** Default implementation order = I3 then O2; override if product priority shifts.

---

## 9. Verification

- Inference: [`docs/spec-1-personalization-verification.md`](../spec-1-personalization-verification.md)  
- Unit: `VoicePostEditLearningMonitorTests`, `VoicePromptBuilderPersonalizationTests`, `VoicePersonalizationStoreTests`  
- Export (when built): golden JSONL fixture + round-trip decrypt test  

---

## 10. Changelog

| Date | Change |
|------|--------|
| 2026-05-29 | v1 — initial normative spec from research pass |
