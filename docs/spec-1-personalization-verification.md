# Spec 1 Personalization — Manual Verification Checklist

Run this after all 12 tasks land on `feature/voice-personalization`.
Build via Xcode with `MacAllYouNeed` scheme, debug config, macOS destination.

---

## Prerequisites

- App built and running from this branch.
- Voice onboarding completed (microphone + accessibility permissions granted).
- At least one LLM cleanup provider configured (Groq, Anthropic, OpenAI-compatible, or Ollama).
- TextEdit open and ready.

---

## Checklist

### 1. Fresh install / empty state

- [ ] Open the app → Voice tab → **Personalization** sub-tab.
- [ ] Empty state copy is visible: *"Personalization starts after you paste dictation and edit it."*
- [ ] "Personal style notes" text editor is present and empty.
- [ ] "Learn from edits" toggle is **ON** by default.
- [ ] No context rows appear (not even Global) until first interaction.

---

### 2. First learning sample (TextEdit)

- [ ] Dictate "hello world" into TextEdit.
- [ ] After pasting, edit the pasted text to "Hello, world." and stop typing.
- [ ] Wait ~2 seconds.
- [ ] Return to Personalization tab.
- [ ] A **TextEdit** context row appears with sample count = 1 and a relative timestamp.
- [ ] Expanding the TextEdit row shows empty overrides (no ASR/auto-submit/custom prompt set).

---

### 3. Large-document anchor (privacy isolation)

- [ ] In TextEdit, create a document with 3+ existing paragraphs.
- [ ] Dictate "hello world" at the end of the document.
- [ ] Edit the pasted text to "Hello, world." without editing the surrounding paragraphs.
- [ ] After ~2s idle, verify sample count increments.
- [ ] In the DB (Console log), verify the logged byte counts are small (≈11B before, ≈13B after) — NOT the full document size. The surrounding paragraphs must NOT appear in the sample.

---

### 4. Repeated learning

- [ ] Repeat step 2 four more times (5 total samples).
- [ ] Verify TextEdit context row shows sample count = 5.

---

### 5. Focus switch cancels learning

- [ ] Dictate into TextEdit.
- [ ] Immediately switch to another app (e.g. Safari) BEFORE the 1.5s idle fires.
- [ ] Verify sample count does NOT increment.

---

### 6. Auto-submit profile — no learning

- [ ] Open Personalization → expand the TextEdit context row.
- [ ] Set Auto-submit to "Return".
- [ ] Dictate into TextEdit.
- [ ] Verify no new sample is created (auto-submit profiles are excluded from learning).
- [ ] Reset the auto-submit override back to "None".

---

### 7. Disable learning — no new samples

- [ ] Toggle "Learn from edits" OFF in the Personalization tab.
- [ ] Dictate into TextEdit and edit the result.
- [ ] Verify sample count does NOT increase.
- [ ] Re-enable "Learn from edits" for subsequent steps.

---

### 8. Secure field / password manager — no learning

- [ ] If 1Password is installed: trigger Quick Access or a password field.
- [ ] Attempt a dictation paste into the field.
- [ ] Verify no sample is created for `com.1password.*`.
- [ ] If 1Password is not available: confirm via Console that
  `VoicePersonalizationPrivacyFilter` rejects the `AXSecureTextField` subrole on
  any macOS password field (e.g. System Preferences login).

---

### 9. Personal style notes injected into prompt

- [ ] In the Personalization tab, set style notes to "Use British spelling."
- [ ] Enable verbose Console logging for subsystem `com.macallyouneed.voice`.
- [ ] Dictate a sentence.
- [ ] Verify the outgoing LLM cleanup request (visible in Console) contains
  `<STYLE_NOTES>` with "Use British spelling." inside.
- [ ] Clear style notes afterward.

---

### 10. Summarizer trigger (manual seed)

> This step requires seeding 20 samples. You can repeat step 2 twenty times,
> or use a debug seeding script if one exists.

- [ ] After 20+ samples in any context, dictate again.
- [ ] Verify in Console: summarizer fires and logs
  `Summarizer: [provider] ~N tokens, 20 samples`.
- [ ] After ~1-2s, open DB via Console or debug tooling and confirm:
  - `encrypted_summary` on the context row is non-NULL.
  - The previously unsummarized samples have `summarized = 1`.
  - No samples older than 30 days remain (expiry ran).

---

### 11. Clear all personalization data

- [ ] Click "Clear all personalization data" → confirm alert.
- [ ] All context rows disappear.
- [ ] Sample count on any previously shown context is now 0.
- [ ] Confirm via SQLite: `SELECT COUNT(*) FROM voice_personalization_samples` → 0.
- [ ] Confirm via SQLite: `SELECT COUNT(*) FROM voice_personalization_contexts` → 0.

---

### 12. app_profiles table absent

- [ ] Open the SQLite DB file at the App Group container path.
- [ ] Run `PRAGMA table_info(app_profiles)` → returns **empty** (table does not exist).
- [ ] Run `PRAGMA table_info(voice_personalization_contexts)` → returns column list.

---

### 13. Existing dictation flow unaffected

- [ ] Full voice flow: dictate → cleanup → paste works correctly.
- [ ] Clipboard history still captures the pasted text.
- [ ] Dictionary replacements still apply during cleanup.
- [ ] Voice History tab still lists recent transcripts.
- [ ] ASR model selection in the Models tab still works.
- [ ] Voice Settings (cleanup provider, timeout, API key) still save correctly.

---

### 14. AX polling CPU stress (baseline)

- [ ] Open Activity Monitor → find the MacAllYouNeed process.
- [ ] Dictate a short phrase. After paste, observe CPU over the next 60 seconds.
- [ ] CPU should not spike above ~2% sustained during the monitoring window.
- [ ] Record baseline CPU reading for future comparison: `_____ %`

---

## Known limitations / deferred items

- Summarizer output is capped at 1500 chars and `<>`-sanitized; deliberate.
- `cappedExamples` uses a greedy prefix/suffix diff that can underestimate the
  edit span when a word appears unchanged after the edit point. Acceptable for v1.
- No keyboard-level input monitoring — all learning is from AX text field values.
- Safari and browsers in private mode are NOT explicitly blocked (excluded from
  the deny-list); rely on `learnFromEditsEnabled` toggle and the fact that most
  browser text areas expose `AXTextArea` role, which is in the allowlist.
  Browser paste-then-edit is allowed by design.
- The `ClipboardDockModelTests` crash (exit 133) is pre-existing from main
  and unrelated to this feature. Track separately.
