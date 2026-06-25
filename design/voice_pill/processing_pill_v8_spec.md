# Processing Pill — Centered Native (2026-06-16)

Supersedes slot-based v8 for runtime HUD behavior. See also:
- [`updated_design/MAYN_Voice_HUD_Text_Alert_Trigger_Spec.md`](updated_design/MAYN_Voice_HUD_Text_Alert_Trigger_Spec.md)
- [`updated_design/mayn_voice_pill_centered_final.html`](updated_design/mayn_voice_pill_centered_final.html)

## Summary

- **One graphite pill** (`#1c1c1e`, 32px) with **centered content** on the full pill width.
- **Recording:** centered waveform only — no `Listening`, no partials, no check/finish icons.
- **Processing:** centered `Transcribing` or `Still working...` with white wipe overlay (`~14.5%` opacity).
- **Helpers:** caption text above pill (no background/border/shadow) via `VoiceCaptionPresenter`.
- **Blocking:** action-required cards via `VoiceAlertPresenter`.

## Sizes

| State | Width |
|---|---:|
| Recording / warmup / clipboard fallback | 144px |
| Transcribing | 164px |
| Still working... | 172px |
| Terminal / short error | 160–180px |

## Layers

| Layer | Owner |
|-------|-------|
| Pill | `MiniVoiceHUD` |
| Wipe | `MiniVoiceThinkingProgressBridge` |
| Caption | `VoiceCaptionPresenter` |
| Blocking alert | `VoiceAlertPresenter` |

## Copy source

All user-facing strings live in `VoiceHUDCopy.swift`.
