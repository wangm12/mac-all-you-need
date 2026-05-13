# Voice Cleanup Pipeline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Plan 8c cleanup layer: deterministic local cleanup, optional LLM cleanup providers, prompt building, and user dictionary replacement before paste.

**Architecture:** Keep runtime cleanup under `MacAllYouNeed/Voice/Cleanup/` because it feeds directly into `VoiceCoordinator` and can later call provider settings/keychain from the app. Keep DB-backed dictionary CRUD in `Shared/Sources/Core/Voice/` because it uses the 8a-owned `voice_dictionary` table and should be testable with SwiftPM.

**Tech Stack:** Swift 5.9, Swift concurrency, URLSession, GRDB, XCTest.

---

## File Map

**App cleanup runtime**
- Create: `MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift`
- Create: `MacAllYouNeed/Voice/Cleanup/VoicePromptBuilder.swift`
- Create: `MacAllYouNeed/Voice/Cleanup/Providers/AnthropicVoiceProvider.swift`
- Create: `MacAllYouNeed/Voice/Cleanup/Providers/OpenAICompatibleVoiceProvider.swift`
- Modify: `MacAllYouNeed/Voice/Cleanup/VoiceLocalTextCleaner.swift`
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceCleanupPipelineTests.swift`
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderTests.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceLLMProviderTests.swift`

**Shared dictionary**
- Create: `Shared/Sources/Core/Voice/VoiceDictionaryEntry.swift`
- Create: `Shared/Sources/Core/Voice/VoiceDictionaryStore.swift`
- Create: `Shared/Sources/Core/Voice/VoiceWordReplacement.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceDictionaryStoreTests.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceWordReplacementTests.swift`

## Task 1: Cleanup Pipeline Shell

**Files:**
- Create: `MacAllYouNeed/Voice/Cleanup/VoiceCleanupPipeline.swift`
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceCleanupPipelineTests.swift`

- [x] **Step 1: Write failing pipeline tests**

Cover:
- No provider returns `VoiceLocalTextCleaner.clean(rawText)`.
- Provider receives the locally cleaned text, not raw ASR text.
- Empty provider output falls back to local cleanup.
- Short transcripts skip provider.

- [x] **Step 2: Run tests and verify RED**

Run the direct xctest flow used by this repo:

```bash
xcodebuild build-for-testing -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS' -derivedDataPath .build/voice-mvp-xcode
TEST_BIN='.build/voice-mvp-xcode/Build/Products/Debug/MacAllYouNeed.app/Contents/PlugIns/MacAllYouNeedTests.xctest/Contents/MacOS/MacAllYouNeedTests'
install_name_tool -add_rpath @loader_path/../../../../MacOS "$TEST_BIN" 2>/dev/null || true
codesign --force --sign - "$TEST_BIN"
xcrun xctest -XCTest MacAllYouNeedTests.VoiceCleanupPipelineTests .build/voice-mvp-xcode/Build/Products/Debug/MacAllYouNeed.app/Contents/PlugIns/MacAllYouNeedTests.xctest
```

Expected: compile fails because `VoiceCleanupPipeline` does not exist.

- [x] **Step 3: Implement pipeline shell**

Add request/result types, `VoiceLLMProvider`, local pre-pass, timeout, empty-output fallback, and short-text skip.

- [x] **Step 4: Wire coordinator through pipeline**

Replace direct `VoiceLocalTextCleaner.clean(result.text)` in `VoiceCoordinator` with `VoiceCleanupPipeline.clean(...)`.

- [x] **Step 5: Verify GREEN**

Run `VoiceCleanupPipelineTests`, `VoiceLocalTextCleanerTests`, lint, and a signed app build.

## Task 2: Dictionary Store And Replacement

**Files:**
- Create: `Shared/Sources/Core/Voice/VoiceDictionaryEntry.swift`
- Create: `Shared/Sources/Core/Voice/VoiceDictionaryStore.swift`
- Create: `Shared/Sources/Core/Voice/VoiceWordReplacement.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceDictionaryStoreTests.swift`
- Test: `Shared/Tests/CoreTests/Voice/VoiceWordReplacementTests.swift`

- [x] **Step 1: Write failing dictionary tests**

Cover save/list/delete and longest-first replacement. Latin replacements must respect word boundaries; CJK replacements can use substring matching.

- [x] **Step 2: Implement store and replacement**

Use the existing 8a `voice_dictionary` table. Do not add a new migration from Plan 8c.

- [x] **Step 3: Verify**

Run:

```bash
cd Shared && swift test --filter VoiceDictionaryStoreTests
cd Shared && swift test --filter VoiceWordReplacementTests
```

## Task 3: Prompt Builder

**Files:**
- Create: `MacAllYouNeed/Voice/Cleanup/VoicePromptBuilder.swift`
- Test: `MacAllYouNeedTests/Voice/VoicePromptBuilderTests.swift`

- [x] **Step 1: Write failing prompt tests**

Cover zh/en mixed instructions, app context, dictionary entries, translation target, and "return only cleaned text".

- [x] **Step 2: Implement prompt builder**

Keep prompts deterministic and provider-agnostic. Strip thinking/reasoning tags after provider output in the pipeline, not in provider-specific code.

## Task 4: Provider Implementations

**Files:**
- Create: `MacAllYouNeed/Voice/Cleanup/Providers/AnthropicVoiceProvider.swift`
- Create: `MacAllYouNeed/Voice/Cleanup/Providers/OpenAICompatibleVoiceProvider.swift`
- Test: `MacAllYouNeedTests/Voice/VoiceLLMProviderTests.swift`

- [x] **Step 1: Write URLProtocol-backed tests**

No real network calls in tests. Cover request shape, API-key header, model field, response parsing, and HTTP error surfacing.

- [x] **Step 2: Implement Anthropic provider**

Messages API compatible with BYOK. Provider must never receive audio, only text.

- [x] **Step 3: Implement OpenAI-compatible provider**

Support OpenAI, Ollama, and custom OpenAI-compatible base URL with the same implementation.

## Task 5: Settings And Runtime Wiring

**Files:**
- Modify: `MacAllYouNeed/Settings/VoiceSettingsView.swift`
- Modify: `MacAllYouNeed/App/AppController.swift`
- Modify: `MacAllYouNeed/Voice/VoiceCoordinator.swift`

- [x] **Step 1: Add provider setting model**

Persist provider selection, model, timeout, and cleanup-enabled toggle. Store API keys in Keychain only.

- [x] **Step 2: Add Settings controls**

Provider picker, model text field, timeout slider, and "Test" button. Keep cleanup skippable.

- [x] **Step 3: Wire runtime**

Instantiate the selected provider only when cleanup is enabled and a provider is configured. Fallback to local cleanup on every provider error.

## Acceptance Criteria

- [x] `VoiceCleanupPipelineTests` pass.
- [x] `VoiceLocalTextCleanerTests` pass.
- [x] `cd Shared && swift test --filter VoiceDictionaryStoreTests` passes.
- [x] `cd Shared && swift test --filter VoiceWordReplacementTests` passes.
- [x] Provider tests pass without real network.
- [x] `xcodegen generate` passes.
- [x] Signed app build passes.
- [ ] Manual dictation still pastes when no LLM provider is configured.
