# Spec 2 — Voice Pipeline Latency (TODO)

Status: **Deferred. Frame after Spec 1 (Personalization) is in flight.**
Owner: mingjie-father
Created: 2026-05-14

## Goal
Reduce post-release latency of voice dictation to feel as fast as Typeless. Today the user waits for batch ASR + cleanup *after* releasing the hotkey; goal is for most of the work to overlap with recording so post-release wait is near-instant.

## Current state (verified 2026-05-14)
- ASR backend: **local Qwen3-ASR 0.6B** (f32 ~1.75 GB or int8 ~900 MB) via `FluidAudio` + CoreML, macOS 15+.
- Code path: `MacAllYouNeed/Voice/ASR/Qwen3Engine.swift:18` → `Qwen3AsrManager.transcribe(audioSamples:maxNewTokens:512)`.
- ASR is **batch-only**. Qwen3-ASR is encoder-decoder, no native streaming mode.
- Cleanup: user-supplied LLM provider (cloud).
- Pipeline today: `record → wait → batch ASR → wait → LLM cleanup → paste`. Two serial waits post-release.

## Locked design decisions (from frame on 2026-05-14)
- **No partial-transcript HUD.** Silent recording, paste full result on release. Typeless-style.
- **No engine swap in v1.** Stick with Qwen3-ASR; do not swap to WhisperKit / SFSpeechRecognizer / Parakeet unless accuracy floor cannot be met.
- **Cleanup model:** keep user choice, but default to a fast cloud model. Recommended presets: Groq Llama 3.1 8B Instant, Gemini 2.0 Flash, Claude Haiku 3.5, GPT-4o-mini. Default to Groq.
- **Bundled local cleanup model:** rejected for v1 (binary bloat, model management UX). Cloud only.
- **Sequence:** ship after Spec 1 (Personalization). Spec 2's prompt assembly must consume Spec 1's few-shot + summary outputs; building Spec 2 first means retrofit.

## Approach options (decide in frame)

### A. VAD-segmented transcription (recommended)
- Run Voice Activity Detector during recording.
- On each detected pause boundary, transcribe completed segment in background.
- On hotkey release, transcribe only final tail (audio since last pause).
- Concatenate segment outputs.
- Pros: minimal extra compute, no overlapping re-encoding, model never spans pauses anyway.
- Cons: depends on VAD quality; check whether `FluidAudio` already exposes a VAD utility.

### B. Chunked-prefix transcription (fallback)
- Every N seconds (e.g. 3s), transcribe the buffer-so-far on a background actor.
- On release, transcribe final tail.
- Pros: simpler logic, no VAD dependency.
- Cons: Qwen3 re-encodes overlapping audio each pass — wasteful CPU/GPU during recording.

### C. Engine swap to streaming-native model (only if A and B fail accuracy floor)
- Candidates: WhisperKit (chunked streaming), Apple SFSpeechRecognizer, Parakeet RNN-T.
- Multi-week effort, model management UX, accuracy regression risk.

## Acceptance criteria
- **ASR accuracy:** ≤5% WER regression vs. current batch on a held-out personal sample of 20 mixed Chinese/English dictations.
- **Cleanup quality:** no perceived quality drop in ≥90% of dictations after one week of dogfood (count manual re-edits vs. baseline).
- **Latency:** post-release wait ≤500ms p50 for typical dictations (5–15s of audio) on M-series Mac.

## Open questions to resolve in Spec 2 frame
1. Does `FluidAudio` already expose a VAD utility, or do we need a separate VAD (Silero, WebRTC VAD)?
2. Are we willing to ship a "Recommended provider: Groq" onboarding step that helps users get a free API key? Affects default cleanup latency story.
3. What's the fallback if user's network is offline at cleanup time? Skip cleanup and paste raw transcript? Show error? Local fallback?
4. Does Qwen3-ASR's `maxNewTokens: 512` limit apply per chunk or per total utterance? Affects long-dictation handling under both A and B.
5. Memory cost of holding multiple `Qwen3AsrManager` instances vs. serializing chunks through one — measure before deciding.

## First experiment when this spec is opened
Before any code changes: run a 20-sample WER comparison.
- Record 20 mixed dictations (representative of normal use).
- Transcribe each via current batch path (baseline).
- Transcribe each via simulated VAD-segmented path (split at silences, transcribe segments separately, concatenate).
- Compare WER. If regression ≤5%, proceed with Approach A. Otherwise, evaluate B; if still failing, revisit Approach C.

## Composition with Spec 1 (Personalization)
- Cleanup prompt assembly must consume:
  - Personalization summary (lazy-distilled, ~150–200 tokens)
  - Few-shot examples (last ~5 raw before/after pairs from current app + global context)
  - Personal style notes (free-text user input)
- Total cleanup prompt budget: ~800–1500 input tokens. Verify recommended fast cloud models handle this without latency regression.

## Out of scope for v1
- Streaming display of partial transcripts (rejected — Typeless-style silent paste).
- Local cleanup model bundled in app (rejected — binary bloat).
- Per-app ASR model selection (handled by Spec 1's progressive disclosure).
- ASR model training / fine-tuning on user audio.

## Next stage when revisiting
Run `mingjie-frame` on this spec. First job of the frame: answer Open Question #1 (VAD availability in FluidAudio) and run the 20-sample WER experiment. Without those data points, any plan is guessing.
