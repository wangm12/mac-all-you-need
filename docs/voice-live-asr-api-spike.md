# Voice Live ASR API Spike

**Date:** 2026-06-08  
**FluidAudio pin:** 0.14.5 (`Shared/Package.resolved`)

## Result: Qwen3 streaming API is available

Verified in Xcode SwiftPM checkout:

`SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3StreamingManager.swift`

| Symbol | Availability | Notes |
|--------|--------------|-------|
| `Qwen3StreamingManager` | `@available(macOS 15, iOS 18, *)` | `actor` |
| `Qwen3StreamingConfig` | public | `minAudioSeconds`, `chunkSeconds`, `maxAudioSeconds`, `language` |
| `addAudio(_ samples: [Float])` | async throws | Returns `Qwen3StreamingResult?` when chunk ready |
| `finish()` | async throws | Final `Qwen3StreamingResult` with `isFinal: true` |
| Result shape | full-window transcript | `transcript` is the entire accumulated window text, not deltas |

## Implementation decision

- Live ASR uses `Qwen3LongFormLiveSession`: segment commit every 25s with 2s overlap, merge on finish.
- Feed audio via a single polling task (50ms) draining new samples from `AudioCaptureService` — no per-tap detached tasks.
- On stop, call `finish()` (tail-only inference for long recordings) and pass result as `presetASRResult`.
- Batch `Qwen3AsrManager.transcribe` with overlapping windows remains fallback when live session fails.

## Parakeet streaming

`SlidingWindowAsrManager` exists but is deferred to a follow-up after Qwen3 live path is stable.
