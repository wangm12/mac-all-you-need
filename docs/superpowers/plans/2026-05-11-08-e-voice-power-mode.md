# Voice Power Mode Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add Plan 8e's first production Power Mode slice: per-app voice profiles, custom cleanup instructions, and optional auto-submit after paste.

**Architecture:** Reuse the 8a-owned `app_profiles` table in `clipboard.sqlite`; do not add migrations. Keep profile persistence in `Shared/Sources/Core/Voice/`, keep frontmost-app runtime behavior in `MacAllYouNeed/Voice/PowerMode/`, and expose profile CRUD in the existing Voice Settings tab. Store future fields such as ASR engine ID now, but only wire behavior that current runtime can honor: prompt context, language hint metadata, enable/disable, and auto-submit.

**Tech Stack:** Swift 5.9, GRDB, SwiftUI, XCTest, CGEvent.

---

## File Map

**Shared profile model/store**
- Create: `Shared/Sources/Core/Voice/VoiceAppProfile.swift`
- Create: `Shared/Sources/Core/Voice/VoiceAppProfileStore.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceAppProfileStoreTests.swift`

**Mac runtime**
- Modify: `MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift`
- Modify: `MacAllYouNeed/Voice/Cleanup/VoicePromptBuilder.swift`
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
- Create: `MacAllYouNeed/Voice/PowerMode/VoiceAutoSubmitService.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderTests.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceAutoSubmitServiceTests.swift`

**Settings UI**
- Modify: `MacAllYouNeed/Settings/VoiceSettingsView.swift`

## Task 1: Shared App Profile Store

**Files:**
- Create: `Shared/Sources/Core/Voice/VoiceAppProfile.swift`
- Create: `Shared/Sources/Core/Voice/VoiceAppProfileStore.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceAppProfileStoreTests.swift`

- [x] **Step 1: Write failing store tests**

Cover:
- `upsert` creates a profile for a bundle ID.
- `upsert` updates the existing row instead of duplicating.
- `fetch(bundleID:)`, `list()`, and `delete(id:)` work.
- Encoded JSON preserves fields for prompt, language, ASR engine ID, and auto-submit.

- [x] **Step 2: Verify RED**

Run:

```bash
cd Shared && swift test --filter VoiceAppProfileStoreTests
```

Expected: compile fails because the model/store do not exist.

- [x] **Step 3: Implement model and store**

Use the existing `app_profiles` table:
- `bundle_id` is unique.
- `display_name` is a top-level searchable column.
- `json` stores the versioned config payload.

- [x] **Step 4: Verify GREEN**

Run:

```bash
cd Shared && swift test --filter VoiceAppProfileStoreTests
```

## Task 2: Prompt Context Integration

**Files:**
- Modify: `MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift`
- Modify: `MacAllYouNeed/Voice/Cleanup/VoicePromptBuilder.swift`
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderTests.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceCleanupPipelineTests.swift`

- [x] **Step 1: Write failing prompt test**

Cover: when a profile instruction is present, the system prompt includes it as app-specific instructions.

- [x] **Step 2: Implement prompt context field**

Add an optional `appInstructions` field to `VoiceCleanupRequest`, `VoiceLLMRequest`, and `VoicePromptContext`. Preserve existing default initializers so current call sites keep compiling.

- [x] **Step 3: Verify**

Run targeted `VoicePromptBuilderTests` and `VoiceCleanupPipelineTests` via the direct `xcrun xctest` flow.

## Task 3: Auto-Submit Service

**Files:**
- Create: `MacAllYouNeed/Voice/PowerMode/VoiceAutoSubmitService.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceAutoSubmitServiceTests.swift`

- [x] **Step 1: Write failing service tests**

Cover:
- `.none` posts no event.
- `.returnKey` posts return key down/up.
- `.commandReturn` posts return key down/up with command flag.

- [x] **Step 2: Implement service**

Use an injectable event sink so tests do not post real keyboard events. Production sink posts `CGEvent` keyboard events.

- [x] **Step 3: Verify**

Run `VoiceAutoSubmitServiceTests`.

## Task 4: Runtime Wiring

**Files:**
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [x] **Step 1: Wire store into app startup**

`AppController` constructs `VoiceAppProfileStore(database: clipboardDatabase)` from the 8a-owned database and passes it to `VoiceCoordinator`.

- [x] **Step 2: Apply profile per dictation**

When dictation stops:
- Read `NSWorkspace.shared.frontmostApplication?.bundleIdentifier`.
- Fetch enabled profile for that bundle ID.
- Pass profile prompt into cleanup request.
- Post auto-submit only after paste event was posted.

- [x] **Step 3: Verify**

Run `build-for-testing` and the targeted voice test suite.

## Task 5: Settings Profile CRUD

**Files:**
- Modify: `MacAllYouNeed/Settings/VoiceSettingsView.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`

- [x] **Step 1: Add controller CRUD methods**

Expose list/upsert/delete methods for `VoiceAppProfileStore`.

- [x] **Step 2: Add Voice Settings section**

Add a compact "App Profiles" section with:
- enabled toggle
- bundle ID
- display name
- custom instruction text
- language picker
- ASR engine ID text field
- auto-submit picker
- Save/Delete controls

- [x] **Step 3: Verify**

Run SwiftFormat, SwiftLint, targeted tests, and signed app build.

## Acceptance Criteria

- [x] `cd Shared && swift test --filter VoiceAppProfileStoreTests` passes.
- [x] `VoicePromptBuilderTests`, `VoiceCleanupPipelineTests`, and `VoiceAutoSubmitServiceTests` pass.
- [x] `xcodegen generate` passes.
- [x] `xcodebuild build-for-testing -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS' -derivedDataPath .build/voice-mvp-xcode` passes.
- [x] `swiftformat --lint` and `swiftlint --strict` pass on touched files.
- [x] Signed app build passes.
