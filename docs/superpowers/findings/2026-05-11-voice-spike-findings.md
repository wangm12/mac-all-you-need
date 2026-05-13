# Voice Spike (Plan 8.0) - Findings

**Date:** 2026-05-11
**Branch/worktree:** main workspace, dirty before spike started
**Hardware tested:** Apple M3 Max, 64 GB RAM
**macOS version:** 26.3.1 (Build 25D771280a)

## Summary

| Gate | Status | Headline finding |
|---|---|---|
| 1 - Mic permission + capture | Pass | Signed hardened-runtime app required `com.apple.security.device.audio-input`; after adding it, microphone permission and 3s capture passed with non-zero peak. |
| 2 - Fn / Globe hotkey PTT | Pass with caveat | Fn produced DOWN/UP transitions, but real use can conflict with macOS input-source switching. MVP should default to a normal configurable shortcut. |
| 3 - ASR backend | Pass with caveat | Qwen3-ASR via FluidAudio produced the exact zh/en fixture transcript. Parakeet is much faster but failed the zh/en accuracy bar. |
| 4 - Paste injection | Pass | Signed app with Accessibility permission pasted into TextEdit, Notes, and Cursor/VS Code; pasteboard restore path executed. |
| 5 - Benchmark instrumentation | Pass with caveat | In-app machine-work benchmark p50 total was 668.5ms; Instruments signpost visualization still needs optional manual confirmation. |

## Detailed Findings

### Gate 1 - Microphone Permission + Capture

- `project.yml` now generates `NSMicrophoneUsageDescription` into `MacAllYouNeed/Info.plist`.
- Built app verification confirmed the generated bundle contains the microphone usage string.
- Initial signed hardened-runtime build returned `AVCaptureDevice.requestAccess(.audio): granted=false` and did not appear in System Settings -> Microphone. Root cause: hardened-runtime signing needed `com.apple.security.device.audio-input`.
- Added `com.apple.security.device.audio-input` to `MacAllYouNeed/MacAllYouNeed.entitlements`, rebuilt the signed app, reset Microphone TCC for `com.macallyouneed.app`, and relaunched with `--voice-spike`.
- Manual Gate 1 pass result:
  - `AVCaptureDevice.requestAccess(.audio): granted=true`
  - Input format: 48,000Hz, 1 channel.
  - Captured 144,000 frames = 3.00s.
  - Peak level: 0.2727.
  - Wall-clock elapsed: 3.12s.
  - `OK: audio captured successfully.`

### Gate 2 - Fn / Globe Hotkey PTT

- Implemented a hidden Spike gate using both global and local `.flagsChanged` monitors.
- Manual test passed: pressing/releasing Fn while another app was frontmost produced repeated transitions:
  - `[1.00s] Fn DOWN (keyCode=63)`, `[1.33s] Fn UP`
  - `[2.60s] Fn DOWN (keyCode=63)`, `[2.98s] Fn UP`
  - `[3.83s] Fn DOWN (keyCode=63)`, `[4.16s] Fn UP`
  - Additional rapid DOWN/UP pairs were observed between 7.50s and 8.87s.
- The spike ended with one final `[9.94s] Fn DOWN` before the 10s test window closed, so it printed `WARN: only partial Fn transition data observed`. This is a timeout-boundary artifact, not evidence that Fn release is generally unavailable.
- Later manual testing showed Fn / Globe can conflict with input-source switching. Plan 8a should default to a normal configurable shortcut (`⌃⌥Space`) and keep Fn / Globe as an optional user choice only when it works well on that machine.
- Production hotkey logic must defensively synthesize/cancel a held state on app deactivation, timeout, or monitor teardown for hold-to-talk mode.

### Gate 3 - ASR Backend

Fixture:

- Path: `MacAllYouNeed/VoiceSpike/Resources/zh-en-mixed-5s.wav`
- Generated locally with `say -v Tingting`
- Format: 16 kHz, mono, Int16 WAV
- Duration: 3.277938s
- Ground truth: `我今天要 deploy 这个 service 到 production`

Qwen3-ASR via FluidAudio 0.14.5:

- Command: `.build/debug/fluidaudiocli qwen3-transcribe <fixture> --language zh`
- First run downloaded Qwen3 f32 model files from HuggingFace and loaded the model.
- Transcript: `我今天要 deploy 这个 service 到 production。`
- Accuracy: pass, exact phrase with terminal punctuation.
- Warm processing times across 3 separate CLI runs: 2.33s, 1.10s, 1.11s.
- Warm p50 processing time: 1.11s for 3.28s audio.
- Peak process memory: ~3.69 GB.

Parakeet TDT v3 via FluidAudio 0.14.5:

- Command: `.build/debug/fluidaudiocli transcribe <fixture>`
- Transcript: `What's in tier y'all deploy digger service thou production?`
- Processing time: 0.12s for 3.28s audio after model cache warmup.
- Peak process memory: ~0.08 GB in the CLI run.
- Accuracy: fail for zh/en code-switching; it preserved English keywords but mangled the Chinese portion.

Recommendation for Plan 8a:

- Use Qwen3-ASR as the v1 default only if memory budget is acceptable or the int8 variant is validated.
- Keep Parakeet as a fast streaming/fallback candidate, not the default zh/en code-switching engine.
- The UI must handle Qwen3 as a slower batch engine; do not design around a sub-250ms warm ASR assumption.

### Gate 4 - Paste Injection

- Implemented `SpikePasteGate` with pasteboard snapshot, string write, CGEvent Cmd+V, and pasteboard restore.
- Unattended benchmark entry point exists for Gate 5.
- The unsigned/ad-hoc build reported `AXIsProcessTrusted: false` even after Accessibility appeared granted in System Settings. Root cause: the running app was the `.build/voice-spike-xcode` ad-hoc build, while the granted app entry did not apply to that identity.
- Rebuilt and relaunched a normally signed spike build from `.build/voice-spike-signed` with `--voice-spike`; the signed app identity was `Identifier=com.macallyouneed.app`, `TeamIdentifier=2N55H39FC4`, `Authority=Apple Development`.
- Signed build result: `AXIsProcessTrusted: true`.
- Manual acceptance matrix passed:
  - TextEdit: paste succeeded; screenshot evidence showed `Hello from Voice Spike - paste injection test`.
  - Notes: paste succeeded.
  - Cursor / VS Code-class Electron app: paste succeeded.
- Pasteboard restore path executed during the manual run (`Pasteboard restore: 570 us` in one reported run). Manual post-paste clipboard restore was confirmed acceptable by the tester.

### Gate 5 - Benchmark Instrumentation

- Implemented `OSSignposter` intervals for `modelLoad`, `inference`, and `paste`.
- Implemented in-app Qwen3 benchmark path with five ASR+paste passes.
- In-app signed build benchmark completed on the real machine:
  - Fixture load: 3ms for 52,447 samples / 3.28s.
  - Model load: 8,717ms.
  - ASR pass timings: 669ms, 655ms, 665ms, 669ms, 668ms.
  - Median ASR inference: 668ms.
  - Median pasteboard set: 167us.
  - Median CGEvent post: 24us.
  - Median pasteboard restore: 441us.
  - Median machine-work total: 668.5ms.
  - Last transcript: `我今天要 deploy 这个 service 到 production。`
- Optional manual pending: verify the signposts in Instruments under subsystem `com.macallyouneed.spike`.

## Real Measured Latencies

| Stage | Original hypothesis | Measured | Notes |
|---|---:|---:|---|
| Qwen3 f32 ASR, warm p50 | <250ms | 1.11s | 3.28s synthetic zh/en fixture, CLI, M3 Max |
| Qwen3 in-app signed ASR median | <250ms | 668ms | 5-run real app benchmark, 3.28s zh/en fixture |
| Qwen3 in-app signed model load | <400ms cold-ish | 8.717s | Real app benchmark after signed rebuild |
| Qwen3 f32 ASR, first measured warm run | <400ms cold-ish | 2.33s | After model files were cached; still included one slower setup path |
| Qwen3 peak process memory | <1.5GB | ~3.69GB | f32 model variant |
| Parakeet ASR warm | <250ms | 0.12s | Fast, but failed zh/en accuracy bar |
| Paste injection | 50ms | <1ms median machine work | Pasteboard set 167us, CGEvent post 24us, restore 441us |
| End-to-end machine path | <1s | 668.5ms machine work | Excludes user focus delay and model load; signed in-app benchmark |

## Recommendations For Plan 8a

1. **Default ASR engine:** Qwen3-ASR, but validate int8 before committing to f32 as default because f32 CLI peak memory was ~3.69GB and in-app resident memory still exceeded the original budget.
2. **Default hotkey:** use `⌃⌥Space` as the normal configurable MVP default. Fn is physically capturable, but should not be the default because it can collide with input-source switching.
3. **Paste path:** CGEvent direct path is viable when the app is normally signed and Accessibility is granted. Production must make the Accessibility requirement explicit and avoid validating paste behavior only against ad-hoc builds.
4. **Required entitlements:** signed hardened-runtime app requires `com.apple.security.device.audio-input` plus `NSMicrophoneUsageDescription` for microphone capture.
5. **Spec divergences:** update performance assumptions: Qwen3 f32 is accurate but materially slower and heavier than the original hypotheses.

## Verification Evidence

- `xcodegen generate` succeeded after adding spike files/resources and FluidAudio.
- `xcodebuild build -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -destination "platform=macOS" -derivedDataPath .build/voice-spike-xcode CODE_SIGNING_ALLOWED=NO` succeeded.
- `swiftformat --lint MacAllYouNeed/VoiceSpike MacAllYouNeedTests/VoiceSpike MacAllYouNeed/Settings/SettingsRoot.swift` passed.
- `swiftlint lint --strict MacAllYouNeed/VoiceSpike MacAllYouNeedTests/VoiceSpike MacAllYouNeed/Settings/SettingsRoot.swift` passed.
- `xcodebuild build -workspace MacAllYouNeed.xcworkspace -scheme MacAllYouNeed -destination "platform=macOS" -derivedDataPath .build/voice-spike-signed` succeeded after moving the hidden Spike Settings tab to the first tab in spike mode.
- Same signed build succeeded after adding `com.apple.security.device.audio-input`; codesign entitlement inspection confirmed the audio-input entitlement was embedded.
- `xcodebuild test ... -only-testing:MacAllYouNeedTests/SpikeLaunchArgTests` could not run because the test target currently fails to compile unrelated existing tests in `ClipboardDockModelListSwitchingTests.swift` (`DockListSelector.pinned`, `PinnedPinboard.reservedName`).

## Remaining Hard Gates Before Plan 8a

- Optional Gate 5 Instruments signpost visibility.
- Qwen3 int8 validation if Plan 8a needs a lower-memory default.
