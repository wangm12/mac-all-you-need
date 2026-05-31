# Pro voice clone — studio read checklist

Use this when instant clone quality (1–5 min from MAYN dictation) is not good enough. **Professional** tiers (ElevenLabs PVC, etc.) want **30–60+ minutes** of clean, consistent speech — not keyboard-heavy dictation clips.

## Before recording

- Quiet room, single mic, fixed distance (~15–20 cm).
- Same device/settings for entire session.
- Turn off notifications; close MAYN dictation (avoid duplicate room tone in reference).

## What to read

- Phonetically diverse sentences (vendor scripts often provide these).
- Include your real vocabulary: product names, contacts, technical terms you dictate.
- Mix statement, question, and list intonation.
- Avoid whispering, shouting, or heavy emotion unless that is your only use case.

## What not to use

- MAYN `voice_training_examples` dictation clips as the **sole** pro source (clicks, pauses, variable apps).
- Music, phone speaker playback, or multi-speaker audio.

## After recording

1. Export WAV (mono, 44.1 kHz or vendor requirement).
2. Keep a separate folder from ASR training export.
3. Upload to vendor **Professional Voice Cloning** flow.
4. Re-run [`test-script-en.txt`](test-script-en.txt) and update [evaluation doc](../research/voice-cloning-vendor-evaluation-2026.md).
