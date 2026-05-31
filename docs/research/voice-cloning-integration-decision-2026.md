# Voice cloning — MAYN integration decision (2026-05-29)

**Status:** Adopted direction (research phase)  
**Depends on:** [voice-cloning-landscape-2026.md](voice-cloning-landscape-2026.md), [voice-cloning-vendor-evaluation-2026.md](voice-cloning-vendor-evaluation-2026.md)

---

## 1. Decision summary

| Question | Decision |
|----------|----------|
| Build in-app TTS / voice clone in MAYN v1? | **No** — out of scope; dictation product stays text-out |
| Use MAYN recordings for cloning? | **Yes** — via documented **reference pack** export, not ASR LoRA weights |
| Primary workflow for mingjie-father | **Standalone tools** (ElevenLabs / Fish cloud first; local OSS optional) |
| MAYN code change now? | **Toolkit only** — scripts + docs; no Settings UI or API keys in app |
| Future MAYN integration | **Phase B** — optional “Export voice clone pack” + Shortcuts doc; **Phase C** — in-app only if vendor winner + legal review |

---

## 2. Rationale

1. **Different model class** — Qwen3/Whisper LoRA improves transcription; TTS cloning does not ship from the existing [`voice-training`](../voice-training/README.md) pipeline.
2. **Competitor norm** — Consumer dictation apps (Typeless, Wispr, Superwhisper) do not ship “type in my voice” synthesis; keeps MAYN focused.
3. **Legal / trust** — Voice replication for outbound messages needs consent, labeling, and anti-impersonation discipline; better as an explicit user opt-in outside the dictation hot path.
4. **Corpus size** — Current **124 s** instant pack is enough to **trial** cloud instant clones; **pro quality** needs a separate studio read, not more desk dictation alone.
5. **Evaluation incomplete** — Cloud blind test pending API keys; Chatterbox local run failed (environment). Do not commit to in-app TTS before §2 scores in evaluation doc.

---

## 3. Phased integration options

### Phase A — Shipped with this research (now)

| Deliverable | Location |
|-------------|----------|
| Landscape research | [`voice-cloning-landscape-2026.md`](voice-cloning-landscape-2026.md) |
| Reference pack curation | [`scripts/voice-cloning/curate-reference-pack.sh`](../../scripts/voice-cloning/curate-reference-pack.sh) |
| Test script | [`docs/voice-cloning/test-script-en.txt`](../voice-cloning/test-script-en.txt) |
| Toolkit README | [`docs/voice-cloning/README.md`](../voice-cloning/README.md) |
| Cloud/local helper scripts | `scripts/voice-cloning/*.sh` |

**User action:** Upload `reference-pack/instant-merged.wav` to ElevenLabs/Fish; score evaluation doc.

### Phase B — Low-risk MAYN follow-up (recommended if cloning is kept)

| Item | Effort | Value |
|------|--------|-------|
| Settings / Advanced link: “Export voice clone reference pack…” | Small | Reuses curation script; zip `instant/` + `manifest.json` + consent README |
| Document macOS Shortcuts: text → ElevenLabs API → share WAV | Small | “Send voice note” without in-app TTS |
| Separate export preset: **TTS reference** vs **ASR training** | Medium | Avoids using messy dictation clips for pro TTS |

**Gate:** Complete cloud blind test; pick one primary vendor.

### Phase C — Defer

| Item | Why defer |
|------|-----------|
| In-app “Speak in my voice” tab | High UX, legal, and quality risk; duplicates vendor UIs |
| Bundled Chatterbox / Fish Speech | Large deps; model updates; support burden |
| Speech-to-speech live VC | Different product surface (RVC class) |

---

## 4. Parallel track: dictation ASR (unchanged)

Continue MAYN offline ASR path independently:

- Post-edit → promote `quality == high`
- Grow corpus toward **50+ clips / 30+ min**
- `make voice-training-pilot` on **Qwen3-ASR** when ready ([backlog](voice-personalization-backlog.md))

TTS cloning and ASR adaptation share **source WAVs** but not **models**.

---

## 5. Go / no-go gates for Phase B

| Gate | Status |
|------|--------|
| Reference pack regenerable from export | **Pass** |
| Instant pack ≥ 60 s clean speech | **Pass** (124 s) |
| Blind test winner on test script | **Pending** |
| User willing to use cloud for outbound voice | **Pending** (mingjie-father: either OK) |
| Legal review for synthetic outbound audio | **Pending** (personal use only → low risk) |

---

## 6. Recommended next steps for mingjie-father

1. **Today:** ElevenLabs + Fish instant clone using `docs/voice-cloning/reference-pack/instant-merged.wav` + full `test-script-en.txt`.
2. **This month:** Record **30 min** quiet studio read for pro clone if instant quality is insufficient.
3. **MAYN habit:** Keep saving training examples; edit pasted text for `high` ASR rows (orthogonal but valuable).
4. **Revisit Phase B** after filling evaluation scores — if winner is ElevenLabs, add Shortcuts + optional export zip only.
