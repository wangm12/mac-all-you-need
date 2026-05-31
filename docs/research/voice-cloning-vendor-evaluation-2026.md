# Voice cloning vendor evaluation (2026-05-29)

**Status:** Partial — reference pack curated; cloud APIs not run (no keys); local Chatterbox blocked  
**Test script:** [`docs/voice-cloning/test-script-en.txt`](../voice-cloning/test-script-en.txt)  
**Reference audio:** [`docs/voice-cloning/reference-pack/`](../voice-cloning/reference-pack/) (regenerate with `./scripts/voice-cloning/curate-reference-pack.sh`)

---

## 1. Reference corpus used

| Metric | Value |
|--------|-------|
| Source | `.build/voice-export/extracted` (39 MAYN training clips) |
| Instant pack | **9 clips, 124.1 s** → `instant-merged.wav` |
| Pro-read pack | **Not built** — need 30+ min studio read (corpus is dictation, not narration) |
| Quality tier | All `medium` (`high` = 0 in DB) |

Upload **`instant-merged.wav`** (or `instant/*.wav`) to cloud clone UIs.

---

## 2. Evaluation matrix

Score each 1–5 after blind listen (5 = “I’d send this as me”). Leave blank until you run the vendor.

| Vendor | Ran? | Naturalness | Prosody | Names/numbers | “Sounds like me” | Notes |
|--------|------|-------------|---------|---------------|----------------|-------|
| ElevenLabs Instant | No | — | — | — | — | Needs `ELEVENLABS_API_KEY` + dashboard clone |
| Fish Audio | No | — | — | — | — | Needs account + clone |
| Descript Overdub | No | — | — | — | — | Manual; English; Voice ID consent |
| Chatterbox (local) | **Attempted** | — | — | — | — | See §3 |
| Apple Personal Voice | No | — | — | — | — | Subjective via Live Speech; no WAV export |

---

## 3. Automated / agent runs

### Chatterbox (`./scripts/voice-cloning/run-chatterbox-smoke.sh`)

| Attempt | Result |
|---------|--------|
| Full test script (~100 words), Python 3.14 venv | **Killed (SIGKILL)** during diffusion sampling — likely memory pressure on long generation |
| Short smoke sentence, Python 3.12 venv | **Failed** at model init: `TypeError: 'NoneType' object is not callable` on `perth.PerthImplicitWatermarker()` (resemble-perth / chatterbox-tts install issue) |

**Workaround for mingjie-father:**

```bash
# Use public PyPI only (Uber artifactory 401s otherwise)
PIP_INDEX_URL=https://pypi.org/simple PIP_EXTRA_INDEX_URL= \
  ./scripts/voice-cloning/run-chatterbox-smoke.sh

# Or clone upstream and editable install:
# git clone https://github.com/resemble-ai/chatterbox && pip install -e .
```

Re-run after fix; compare ` .build/voice-cloning-eval/chatterbox-smoke-short.wav` to cloud outputs.

### Cloud (`./scripts/voice-cloning/synthesize-cloud.sh`)

Skipped — `ELEVENLABS_API_KEY` and `FISH_AUDIO_API_KEY` not set in environment.

**Manual cloud steps:**

1. Upload `docs/voice-cloning/reference-pack/instant-merged.wav` to [ElevenLabs](https://elevenlabs.io/voice-cloning) and [Fish Audio](https://fish.audio/).
2. Create instant voice clone.
3. Paste test script (skip `#` lines from `test-script-en.txt`).
4. Export MP3/WAV to `.build/voice-cloning-eval/`.
5. Fill scoring table in §2.

Optional API after clone exists:

```bash
export ELEVENLABS_API_KEY=...
export ELEVENLABS_VOICE_ID=...
./scripts/voice-cloning/synthesize-cloud.sh
```

---

## 4. Preliminary recommendation (without blind scores)

Until cloud listening tests complete:

| Use case | Start here |
|----------|------------|
| Fastest “does it sound like me?” | **ElevenLabs Instant** + **Fish Audio** with `instant-merged.wav` |
| Privacy / local | Fix **Chatterbox** install or try **Fish Speech** self-host |
| Edit existing recordings | **Descript Overdub** |
| System typed speech only | **Apple Personal Voice** |
| Dictation accuracy (not TTS) | MAYN **ASR export** — separate track |

---

## 5. Re-run checklist

- [ ] Quit MAYN → `make voice-training-export voice-training-extract` (refresh corpus)
- [ ] `./scripts/voice-cloning/curate-reference-pack.sh`
- [ ] Cloud clones + full test script synthesis
- [ ] Local OSS smoke (Chatterbox or Fish Speech)
- [ ] Blind score §2 table
- [ ] Update [integration decision](voice-cloning-integration-decision-2026.md) with winner
