# Spec 2 Track 2 — Groq Whisper ASR Provider

Status: ✅ COMPLETE
Branch: main
Completed: 2026-05-15

## Task List

### T1: GroqASRSettings — provider + model enums, settings struct, store
- Status: [x] done

### T2: GroqASRKeyStore — Keychain storage for Groq API key
- Status: [x] done

### T3: GroqASREngine — VoiceTranscriptionEngine impl (WAV encode + HTTP)
- Status: [x] done

### T4: Extend VoiceASRSettings — add providerKind field
- Status: [x] done

### T5: AppController — select engine based on provider setting
- Status: [x] done

### T6: VoiceSettingsView — ASR provider UI section (BYOK, Test button)
- Status: [x] done

### T7: Tests — GroqASREngine (WAV format, request shape, response parsing)
- Status: [x] done — 9/9 pass

### T8: Build + verify
- Status: [x] done — TEST BUILD SUCCEEDED


## Resume Instructions
If session drops, read this file and continue from the first incomplete task.
Run: `git log --oneline -10` to see what's been committed.

## Task List

### T1: GroqASRSettings — provider + model enums, settings struct, store
- File: `MacAllYouNeed/Voice/ASR/GroqASRSettings.swift`
- Status: [ ] pending

### T2: GroqASRKeyStore — Keychain storage for Groq API key
- File: `MacAllYouNeed/Voice/ASR/GroqASRKeyStore.swift`
- Status: [ ] pending

### T3: GroqASREngine — VoiceTranscriptionEngine impl (WAV encode + HTTP)
- File: `MacAllYouNeed/Voice/ASR/GroqASREngine.swift`
- Status: [ ] pending

### T4: Extend VoiceASRSettings — add providerKind field
- File: `MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift`
- Status: [ ] pending

### T5: AppController — select engine based on provider setting
- File: `MacAllYouNeed/App/AppController.swift`
- Status: [ ] pending

### T6: VoiceSettingsView — ASR provider UI section (BYOK, Test button)
- File: `MacAllYouNeed/Settings/VoiceSettingsView.swift`
- Status: [ ] pending

### T7: Tests — GroqASREngine (WAV format, request shape, response parsing)
- File: `MacAllYouNeedTests/Voice/GroqASREngineTests.swift`
- Status: [ ] pending

### T8: Build + verify
- Status: [ ] pending

## Key Design Decisions
- `GroqASREngine` implements existing `VoiceTranscriptionEngine` protocol (no protocol changes)
- WAV: PCM Float32 → Int16 → RIFF WAV in-memory
- Endpoint: POST https://api.groq.com/openai/v1/audio/transcriptions
- Auth: Bearer token from Keychain
- Groq failure → throw (no silent fallback to Qwen3, UX shows error)
- Default: local Qwen3 (preserves privacy-first default)
- Language: pass nil for auto (Whisper handles code-switching natively)
