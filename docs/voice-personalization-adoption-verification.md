# Voice Personalization Adoption — Verification

Extends [`spec-1-personalization-verification.md`](spec-1-personalization-verification.md) (M0 inference) with adoption milestones M1–M5.

## Automated

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test \
  --filter VoicePersonalizationStoreTests \
  --filter VoiceTrainingExporterTests

xcodebuild test -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:MacAllYouNeedTests/VoicePromptBuilderPersonalizationTests
```

Full gate: `./scripts/ci-build.sh`

## M1 — Copy (A2)

- [ ] Personalization tab shows empty-state guidance when learning is on and no apps yet.
- [ ] Onboarding AI cleanup step mentions Accessibility + encrypted local samples + cloud summarization.

## M2 — Pinned examples (A1)

- [ ] Add pinned pair on Personalization → Cleanup examples.
- [ ] Dictate; Console cleanup request shows pinned pair in `<EXAMPLES>` before auto-learned rows.

## M3 — Training list (O1)

- [ ] Voice Settings → Training examples lists rows; filter High/Medium works; Delete removes row.

## M4 — Export (O2)

- [ ] Personalization or Advanced → Export produces `.tar.gz` with `data.jsonl` + `audio/*.wav`.
- [ ] **Make path:** quit app, then `make voice-training-export` (see [`docs/voice-training/README.md`](voice-training/README.md)).
- [ ] `make voice-training-prepare` (or `prepare-dataset.py`) runs without error on export.

## M5 — Offline MLX (O3 / O3b)

- [ ] Follow [`docs/voice-training/README.md`](voice-training/README.md) on M4 Max (`make voice-training-pilot` for smoke).
- [ ] Record phrase accuracy on 10 held-out clips in `eval/O3b-report.md` (gitignored dogfood folder).
