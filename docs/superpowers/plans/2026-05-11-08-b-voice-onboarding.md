# Plan 8b: Voice Onboarding

**Goal:** Add a voice-specific onboarding flow that can run after the existing app onboarding and can be relaunched from Voice Settings. The flow should make the current 8a/8c/8e voice subsystem testable by a user without adding new database migrations or depending on future 8d engines.

**Source spec:** `docs/superpowers/specs/2026-05-11-voice-dictation-design.md` §4.9
**Master plan:** `docs/superpowers/plans/2026-05-11-08-voice-master.md`

## Scope Decisions

- Keep voice onboarding separate from the existing 6-step app onboarding. Existing `OnboardingState` remains the owner for first-launch app setup.
- Persist voice onboarding progress in App Group `UserDefaults` with `voiceOnboardingCurrentStep` and `voiceOnboardingCompleted`, matching the spec's resume-on-quit requirement.
- Use current production capabilities honestly:
  - Qwen3-ASR is the only runtime ASR engine available from 8a; onboarding can display the future catalog but only Qwen is selectable/preparable now.
  - LLM providers reuse 8c settings/keychain behavior.
  - Hotkey/language settings reuse 8a stores.
  - Try-it uses the real `VoiceCoordinator` plus an in-window text editor and Notes opener.
- Do not add schema migrations. Plan 8a owns all voice DB migration work.

## Tasks

### Task 1: Add Voice Onboarding State
What changes:
- Add a small voice onboarding step enum, progress store, and language selection model.
- Persist current step, completion, and selected language IDs via App Group `UserDefaults`.

Files/areas:
- Create `MacAllYouNeed/Voice/UI/Onboarding/VoiceOnboardingState.swift`
- Create `MacAllYouNeedTests/Voice/VoiceOnboardingStateTests.swift`

Depends on:
- Existing `AppGroupSettings`

Parallelization: sequential
Suggested executor: main agent
Verification:
- `xcrun xctest -XCTest MacAllYouNeedTests.VoiceOnboardingStateTests ...`
Workflow verification: not applicable; pure state/persistence.
Risk:
- Low. Key names must match spec and avoid colliding with general onboarding.

### Task 2: Add Voice Onboarding Window and Wizard
What changes:
- Add `VoiceOnboardingWindowController`.
- Add `VoiceOnboardingWizardView` with Welcome, Microphone, Accessibility, ASR, LLM, Hotkey, Languages, Try It, and Done screens.
- Add live progress, Back/Skip/Next controls, inline status text, and resume from the saved step.

Files/areas:
- Create `MacAllYouNeed/Voice/UI/Onboarding/VoiceOnboardingWindowController.swift`
- Create `MacAllYouNeed/Voice/UI/Onboarding/VoiceOnboardingWizardView.swift`

Depends on:
- Task 1
- Existing `VoiceActivationSettingsStore`, `VoiceASRSettingsStore`, `VoiceCleanupSettingsStore`, `HotkeyRecorder`, `VoiceCoordinator`

Parallelization: sequential
Suggested executor: main agent
Verification:
- Xcode build-for-testing
- `swiftformat --lint` and `swiftlint --strict` on touched files
Workflow verification:
- Manual launch from Settings, navigate all steps, confirm persistence by closing/reopening.
Risk:
- Medium. SwiftUI/AppKit UI must compile cleanly and avoid triggering real model downloads unless the user clicks Prepare.

### Task 3: Wire AppController and Settings Entry Point
What changes:
- Retain a voice onboarding window controller in `AppController`.
- After general onboarding completes, show voice onboarding if not completed.
- Add Voice Settings setup section with current status and "Open voice setup" / "Restart voice setup".
- Reset voice onboarding state when resetting all local data.

Files/areas:
- Modify `MacAllYouNeed/App/AppController.swift`
- Modify `MacAllYouNeed/App/AppControllerOnboarding.swift`
- Modify `MacAllYouNeed/Settings/VoiceSettingsView.swift`
- Modify `MacAllYouNeed/Settings/AdvancedSettingsView.swift`

Depends on:
- Task 2

Parallelization: sequential
Suggested executor: main agent
Verification:
- Xcode build-for-testing
- Targeted settings/onboarding test from Task 1
Workflow verification:
- Launch app with general onboarding complete and voice onboarding incomplete; voice onboarding appears.
- Open Voice Settings and relaunch the wizard.
Risk:
- Medium. The startup trigger must not suppress the existing app onboarding.

### Task 4: Implement ASR Preparation and Try-It Hooks
What changes:
- ASR step can start a non-blocking Qwen3 model preparation task.
- Try-It step includes an editable mock field, "Start recording", "Stop and insert", and "Open Notes" actions.
- Done marks voice onboarding complete.

Files/areas:
- `MacAllYouNeed/Voice/UI/Onboarding/VoiceOnboardingWizardView.swift`

Depends on:
- Task 2

Parallelization: sequential
Suggested executor: main agent
Verification:
- Xcode build-for-testing
- Manual smoke with microphone permission already granted.
Workflow verification:
- In the wizard, start/stop a short dictation and confirm text is inserted into the focused mock field or copied for manual paste.
Risk:
- Medium. Real ASR/model behavior is heavy; UI must gracefully report errors without blocking navigation.

### Task 5: Spec and Code Review
What changes:
- Run a fresh review against spec §4.9 and the master plan.
- Use a subagent for an independent spec/code review if available; main agent verifies any findings locally.

Files/areas:
- Whole 8b diff, no new code ownership.

Depends on:
- Tasks 1-4

Parallelization: can run after Task 4
Suggested executor: subagent review + main agent verification
Verification:
- `swiftformat --lint` touched files
- `swiftlint --strict` touched files
- `xcodebuild build-for-testing`
- `xcrun xctest -XCTest MacAllYouNeedTests.VoiceOnboardingStateTests ...`
Workflow verification:
- Manual Settings → Voice → Open voice setup path.
Risk:
- Low. Review is advisory; main agent remains responsible for final acceptance.

## Acceptance Criteria

- [x] Voice onboarding state defaults to welcome, persists current step, persists language choices, and marks completion.
- [x] All onboarding screens are reachable in order: Welcome → Microphone → Accessibility → ASR → LLM → Hotkey → Languages → Try It → Done.
- [x] Closing/reopening the wizard resumes from the persisted step.
- [x] Voice Settings can open/restart voice setup.
- [x] Existing general onboarding still runs first; voice onboarding runs only after general onboarding is completed.
- [x] No non-8a schema migration is added.
- [x] Focused state tests pass.
- [x] `swiftformat --lint`, `swiftlint --strict`, and Xcode build-for-testing pass on touched files/target.

## Post-Review Fix Evidence

- Fixed restart/open behavior by rebuilding the SwiftUI root view each time the voice onboarding window is shown.
- Added explicit auto-detect language mode, single-language ASR biasing, and draft API-key provider construction tests.
- Added microphone onboarding with `AVAudioApplication.requestRecordPermission`, live capture level display, and audio-detected auto-advance.
- Added ASR primary/more-options grouping and Qwen3 preparation progress.
- Added real LLM provider ping from unsaved draft settings.
- Added hotkey visual preview, current Toggle/PTT mode selection, and disabled future Hybrid/Auto-VAD affordances.
- Added Try It raw/cleaned transcript display and gated Next on explicit "It works!" confirmation.
- Post-review P1s fixed: shortcut-driven Try It can now enable confirmation, LLM footer Skip disables cleanup fallback without deleting stored keys, and provider defaults/cards now use Claude Haiku 4.5 + `gpt-5-nano` catalog names.
- Verified on 2026-05-11 with focused voice tests, `swiftformat --lint`, `swiftlint --strict`, `xcodebuild build-for-testing`, and signed app `xcodebuild build`.
