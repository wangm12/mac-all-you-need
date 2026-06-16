# SenseVoice Small ASR Engine

**Date:** 2026-06-15
**Status:** Approved for implementation

## Context

Voice dictation currently uses autoregressive models (Qwen3-ASR via FluidAudio/CoreML, Parakeet via CoreML). These are accurate but have irreducible per-token inference overhead that limits how short the streaming chunks can be before quality degrades.

The user wants a non-autoregressive option: SenseVoice Small (FunASR / Alibaba). Non-autoregressive models decode the entire audio in a single forward pass — no token-by-token loop — making them 10–50x faster for short utterances. With AI cleanup enabled, ASR only needs to be "good enough" rather than perfect, so this trade-off is appropriate.

SenseVoice Small runs via mlx-audio-swift (same MLX framework used by Voxt). It handles Chinese, English, and mixed zh-en dictation, and includes built-in inverse text normalization (ITN: "三百" → "300").

## Model

| | |
|---|---|
| HuggingFace repo | `mlx-community/SenseVoiceSmall` |
| Size | ~900 MB |
| Languages | zh, en, yue, ja, ko + auto-detect |
| Runtime | MLX (Apple Neural Engine on Apple Silicon) |
| Mode | Batch only (no streaming session) |
| ITN | Yes (spoken numbers/dates → written form) |

## Integration Approach

Add SenseVoice as a fourth local model option alongside Qwen3-F32, Qwen3-Int8, and Parakeet. It appears in the existing Voice → Models picker and is downloaded on demand via VoiceModelManager — identical UX to the other local models.

Batch inference is sufficient because SenseVoice is fast enough (<100ms for a 5s clip) that the latency difference vs. a streaming session is imperceptible.

## Architecture

### New dependency

`mlx-audio-swift` (GitHub: `hehehai/mlx-audio-swift`, revision `a1c7b11`) added to `MacAllYouNeed` target (app-only — not Shared, since MLX is Apple Silicon only and the Shared package runs tests cross-platform).

Linked products: `MLXAudioCore`, `MLXAudioSTT`.

### New files

**`MacAllYouNeed/Voice/ASR/SenseVoiceEngine.swift`**

```swift
actor SenseVoiceEngine: VoiceTranscriptionEngine {
    nonisolated var modelIdentifier: String { "sense-voice-small" }
    nonisolated var capabilities: VoiceASRCapabilities {
        .init(supportsStreaming: false, requiresNetwork: false, emitsPartials: false)
    }
    func transcribe(samples: [Float], sampleRate: Double, options: VoiceTranscriptionOptions) async throws -> VoiceTranscriptionResult
    func warmup() async  // lazy-loads model into memory
}
```

Inference path (from Voxt `runSenseVoiceInference`):
1. Resample to 16kHz if needed (reuse `AudioCaptureService.resample`)
2. `model.generate(audio: MLXArray(samples), language: hint, useITN: true, verbose: false)`
3. Return `VoiceTranscriptionResult(text: output.text, language: .mixed, modelIdentifier: "sense-voice-small")`

Model is loaded lazily on first `transcribe()` call (or eagerly via `warmup()`). Stored as an optional actor-isolated property; `warmup()` is idempotent.

### Modified files

**`MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift`** — `VoiceASRModelID`:
- Add `case senseVoiceSmall = "sense-voice-small"`
- `runtime` → `.sensevoice` (new case)
- `title` → `"SenseVoice Small"`
- `subtitle` → `"Non-autoregressive · Chinese & English · ~900 MB"`
- `diskLabel` → `"~900 MB"`

**`MacAllYouNeed/Voice/VoiceModelCatalog.swift`** — `VoiceModelRuntime`:
- Add `case sensevoice`
- Update `localASRModels` catalog to include `senseVoiceSmall` descriptor

**`MacAllYouNeed/Voice/ASR/VoiceLocalASREngine.swift`**:
- Add `private let senseVoice = SenseVoiceEngine()`
- Route `.sensevoice` → `senseVoice` in `transcribe()` and `warmup()`
- `capabilities` computed property: returns SenseVoice caps when `.sensevoice` selected

**`MacAllYouNeed/Voice/VoiceModelManager.swift`** (or wherever model download lives):
- Add `senseVoiceSmall` download entry: repo `mlx-community/SenseVoiceSmall`, cache dir `sense-voice-small/`
- `isLocalASRModelInstalled(.senseVoiceSmall)` checks for required model files

**All exhaustive switches on `VoiceASRModelID` and `VoiceModelRuntime`** — compiler will flag; update each to handle the new cases.

## Data flow (with cleanup on)

```
User speaks (3s chunks → Qwen3 partials in HUD)
  ↓ [if SenseVoice selected: no live chunks, just accumulate]
User releases key
  ↓
SenseVoiceEngine.transcribe() → <100ms → raw text
  ↓
AI cleanup (LLM) → cleaned text     ← quality comes from here
  ↓
Paste into focused field
```

When SenseVoice is selected, the live-ASR session is skipped (engine doesn't conform to `VoiceLiveTranscriptionEngine`), so recording goes straight to batch on key release. The fast batch inference means the user waits less on ASR and more time is available for LLM cleanup quality.

## What does NOT change

- Pipeline phases (ASR → Cleanup → Paste) are identical
- HUD states unchanged
- Cleanup settings unchanged
- OpenAI Realtime and cloud engines unchanged
- Shared package unchanged (no new SPM dependency in Shared)

## Error handling

- Model not downloaded → `VoiceLocalASREngineError.modelNotInstalled` (existing path)
- MLX inference throws → propagate as ASR error → existing `failPipeline` path
- macOS < 15 or Intel Mac → SenseVoice hidden from model picker (MLX requires Apple Silicon; add guard in `VoiceModelCatalog`)

## Verification

1. `xcodebuild build` compiles cleanly with new SPM dependency
2. Model downloads and `isLocalASRModelInstalled` returns true
3. Select SenseVoice → dictate 5s Chinese+English → text appears correctly
4. Dictate "三百五十块" → with ITN enabled → "350块" in output
5. Cleanup on + SenseVoice: total latency noticeably faster than Qwen3 for short clips
6. All existing voice tests pass: `cd Shared && swift test`
