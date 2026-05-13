# Voice Dictation Module — Design Spec

**Status:** Draft (brainstormed 2026-05-11)
**Owner:** mingjie-father
**Project:** mac-all-you-need (Plan 8)
**Brainstorming source:** Typeless (cloud), VoiceInk (open Swift), OpenWhispr (Electron) — see Section 12

---

## 1. Overview

Add a native macOS dictation subsystem to mac-all-you-need that reaches feature parity with Typeless on the dictation core (recording, multi-lingual transcription, filler removal, translation, AI editing, per-app context) while running **local-first** (no audio leaves the Mac by default) and integrating tightly with the existing clipboard system.

### 1.1 Vision

> *"Press a key. Speak Chinese, English, or both mixed in one sentence. Get polished text pasted into any app — instantly, privately."*

### 1.2 Differentiator vs incumbents

| | Typeless | VoiceInk | OpenWhispr | **This project** |
|---|---|---|---|---|
| Cloud-only | ✅ | optional | optional | **❌ local-default** |
| zh+en code-switching | ✅ | ❌ | ❌ | **✅ via Qwen3-ASR / SenseVoice** |
| Translation | ✅ | ❌ | partial | **✅ LLM post-pass** |
| Per-app prompt profiles | ✅ tone | ✅ Power Mode | ❌ | **✅ Power Mode parity** |
| AI on selected text | ✅ | partial | ✅ agent | **✅ dedicated hotkey** |
| Native (not Electron) | n/a | ✅ Swift | ❌ | **✅ Swift + SwiftUI** |
| Unified with clipboard | ❌ | ❌ | ❌ | **✅ pin tab + FTS5 search** |
| ML training data export | ❌ | ❌ | ❌ | **✅ .jsonl + .wav** |

**Tagline:** "Your voice never leaves your Mac."

### 1.3 Non-goals (out of v1 scope)

- I (OS-level agent: "open my Gmail") — defer indefinitely
- K (cross-platform iOS/Win/Android) — Mac-only
- Multi-speaker diarization
- Meeting recording (system audio tap)
- Audio file batch transcription queue
- Sparkle auto-update for the voice subsystem (will use main app's existing channel when Plan 7 ships)

---

## 2. Decision Summary

| Dimension | Decision |
|---|---|
| ASR philosophy | Hybrid local-default |
| v1 features | A (recording) / B (transcription) / C (cleanup) / D (translation) / E (personalization) / F (per-app, full set) / G (AI on selection) / H (read-only text interaction) |
| ASR engine selection | User picker in onboarding; catalog of 5 engines |
| ASR engine catalog | Qwen3-ASR-0.6B (recommended default, batch, MLX) · Parakeet TDT v3 (streaming, FluidAudio) · SenseVoice-Small (lightweight, sherpa-onnx) · Whisper-large-v3-turbo (single-language max accuracy, WhisperKit) · Soniox (cloud, BYOK) |
| Translation | LLM post-pass merged into cleanup prompt; Soniox built-in as advanced option |
| History storage | Voice transcripts pinned tab in clipboard FTS5 + dedicated `voice_transcripts` table for ML training data |
| LLM cleanup default | Anthropic Claude Haiku 4.5 (BYOK) with Ollama local fallback |
| Activation modes | Toggle (MVP default) / Push-to-Talk / Hybrid / Auto-VAD |
| Default hotkey | `⌃⌥Space`; user-configurable recorder. Fn / Globe is optional because it can conflict with input-source switching. |
| Model distribution | Zero pre-bundled; onboarding guides first model download |
| Onboarding | 8 steps (Welcome → Mic → Accessibility → ASR → LLM → Hotkey → Languages → Try-it → Done) with bilingual welcome animation |
| AI Cleanup step | Skip-able (raw ASR + regex filler removal works without it) |
| Try-it step | In-onboarding mock input box + jump to real Notes app |
| HUD style | Notch HUD on MacBooks with notch; auto-fallback to Mini bottom-center HUD on iMac/external displays |
| Per-app depth | Full Power Mode parity (per-app prompt + ASR engine + language + auto-Enter key + hotkey override) |
| AI-on-selection trigger | Independent hotkey (default ⌥Fn) |
| Storage encryption | Reuse existing GRDB + AES-GCM stack |
| Architecture | Approach 1: Integrated into main app, no XPC, parallel module to existing Clipboard/Downloader/FolderPreview |
| Execution gate | Plan 8.0 technical spike must pass before Plan 8a implementation |

---

## 3. Architecture

### 3.1 High-level diagram

```
                         AppController (existing)
                                   │
                ┌──────────────────┼──────────────────┐
                │                  │                  │
         Clipboard (existing)  Downloader (exist)   ★ Voice (new)
                                                       │
                              ┌────────────────────────┼────────────────────────┐
                              │                        │                        │
                       AudioCapture              VoiceCoordinator           HUD UI
                       (AVAudioEngine)         (state machine)          (Notch + Mini)
                              │                        │                        ↑
                              ▼                        ▼                        │
                          16kHz mono ─────► TranscriptionPipeline ───────► partial preview
                                                   │
                            ┌──────────────────────┼──────────────────────┐
                            ▼                      ▼                      ▼
                     ASR Engine             Cleanup LLM           Storage
                     (5 engines via         (Anthropic /          ├─ ClipboardStore (existing)
                      protocol)              OpenAI / Ollama)     │   ↑ pin tab "Voice"
                            │                      │              ├─ VoiceTranscriptStore (new)
                            ▼                      ▼              │   ↑ ML training data
                       raw text +           cleaned text +        └─ AudioArchive (new, AES-GCM)
                       lang tokens          translated text             ↑ raw .wav files
                                                   │
                                                   ▼
                                         CursorPaster (paste injection)
                                                   │
                                          PowerMode (per-app context)
                                                   │
                                          AppContextDetector
                                          (NSWorkspace + AppleScript)
```

### 3.2 Module file structure

#### `MacAllYouNeed/Voice/` (new directory)

```
Voice/
  VoiceCoordinator.swift            ~250 LOC   state machine core
  VoiceHotkeyHandler.swift          ~120 LOC   registers with HotkeyRegistry

  Audio/
    AudioCaptureService.swift       ~200 LOC   AVAudioEngine recording
    AudioFormat.swift               ~50  LOC   16kHz mono Int16 conversion
    AudioVisualizerData.swift       ~80  LOC   60fps level meter

  ASR/
    TranscriptionEngine.swift       ~80  LOC   protocol
    TranscriptionResult.swift       ~60  LOC   unified return type (text + tokens + langs)
    Engines/
      Qwen3Engine.swift             ~250 LOC   MLX backend (Apache 2.0)
      SenseVoiceEngine.swift        ~300 LOC   sherpa-onnx wrapper (MIT)
      ParakeetEngine.swift          ~150 LOC   FluidAudio wrapper
      WhisperEngine.swift           ~200 LOC   WhisperKit wrapper
      SonioxEngine.swift            ~250 LOC   WebSocket cloud
    ModelManager.swift              ~300 LOC   HF download + progress + checksum
    ModelCatalog.swift              ~150 LOC   5 model metadata records
    LanguageDetector.swift          ~100 LOC   per-token LID handling

  Cleanup/
    LLMProvider.swift               ~80  LOC   protocol
    Providers/
      AnthropicProvider.swift       ~200 LOC   Claude Messages API
      OpenAICompatProvider.swift    ~200 LOC   OpenAI / Ollama / custom
    PromptBuilder.swift             ~250 LOC   per-app + dictionary + language
    FillerRemoval.swift             ~100 LOC   regex pre-pass
    CleanupPipeline.swift           ~200 LOC   orchestration + timeout + fallback

  PowerMode/
    AppContextDetector.swift        ~150 LOC   NSWorkspace frontmost
    AppProfile.swift                ~120 LOC   per-app config struct
    AppProfileStore.swift           ~150 LOC   GRDB persisted
    BrowserURLDetector.swift        ~200 LOC   11 browsers AppleScript (deferred to v1.1)
    AutoSendKeyService.swift        ~80  LOC   per-app Enter / Cmd+Enter

  Selection/
    SelectionAIService.swift        ~200 LOC   AI on selected text orchestration
    SelectedTextReader.swift        ~150 LOC   AX API + paste fallback
    SelectionHotkeyHandler.swift    ~80  LOC   ⌥Fn handling

  Storage/
    VoiceTranscript.swift           ~80  LOC   GRDB Record
    VoiceTranscriptStore.swift      ~250 LOC   CRUD + retention cleanup
    ClipboardBridge.swift           ~150 LOC   write-through to ClipboardStore (pin tab "Voice")
    AudioArchive.swift              ~200 LOC   encrypted .wav storage + auto-cleanup
    TrainingExporter.swift          ~150 LOC   export .jsonl + .wav.tar.gz

  UI/
    HUD/
      HUDController.swift           ~150 LOC   chooses Notch vs Mini per screen
      NotchHUDPanel.swift           ~250 LOC   NSPanel + custom Path notch shape
      MiniHUDPanel.swift            ~200 LOC   centered bottom floating panel
      AudioVisualizerView.swift     ~120 LOC   SwiftUI 60fps wave
      LanguageBadgeView.swift       ~80  LOC   zh / en / mixed badge
      PartialTranscriptView.swift   ~100 LOC   streaming preview text

    Settings/
      VoiceSettingsView.swift       ~150 LOC   Voice tab added to existing Settings window
      ASRModelSection.swift         ~250 LOC   model picker + download manager
      LLMProviderSection.swift      ~200 LOC   provider + key + test ping
      HotkeySection.swift           ~150 LOC   recorder + activation mode
      LanguagesSection.swift        ~120 LOC   multi-select languages
      DictionarySection.swift       ~200 LOC   custom vocabulary CRUD
      AppProfilesSection.swift      ~300 LOC   per-app prompt configuration
      AdvancedSection.swift         ~150 LOC   retention policy + training export

    Onboarding/
      VoiceOnboardingFlow.swift     ~200 LOC   8-step coordinator
      Steps/
        WelcomeStep.swift           ~150 LOC   bilingual typewriter animation
        MicPermissionStep.swift     ~120 LOC
        AccessibilityStep.swift     ~120 LOC
        ASREngineStep.swift         ~250 LOC   model cards + download
        LLMProviderStep.swift       ~200 LOC   provider + key
        HotkeyStep.swift            ~200 LOC   live keyboard preview
        LanguagesStep.swift         ~120 LOC
        TryItStep.swift             ~250 LOC   mock box + jump to real app
        DoneStep.swift              ~80  LOC
```

#### `Shared/Sources/Voice/` (new SwiftPM subdirectory)

```
Voice/
  Models/
    VoiceLanguage.swift             ~80  LOC   BCP-47 + Chinese dialects
    AudioSegment.swift              ~60  LOC
    DictationCommand.swift          ~80  LOC   "new line" / "句号" parser

  Algorithms/
    SlidingWindowChunker.swift      ~150 LOC   streaming wrapper for batch models
    WordAgreementEngine.swift       ~200 LOC   VoiceInk-style 3-pass token confirmation
    SileroVAD.swift                 ~100 LOC   wrapper for FluidAudio Silero
    SpokenPunctuation.swift         ~150 LOC   "句号" → "." multi-language

Shared/Tests/VoiceTests/
  AudioFormatTests.swift
  SlidingWindowTests.swift
  SpokenPunctuationTests.swift
  PromptBuilderTests.swift
  FillerRemovalTests.swift
  LanguageDetectionTests.swift
  WordAgreementTests.swift
```

#### SwiftPM dependencies (additions to `project.yml`)

```yaml
- package: KeyboardShortcuts          # global hotkeys + recorder UI
  url: https://github.com/sindresorhus/KeyboardShortcuts
- package: FluidAudio                 # Parakeet ASR + Silero VAD via CoreML
  url: https://github.com/FluidInference/FluidAudio
- package: WhisperKit                 # Whisper CoreML on Apple Silicon
  url: https://github.com/argmaxinc/WhisperKit
- package: mlx-swift                  # Qwen3-ASR backend
  url: https://github.com/ml-explore/mlx-swift
- package: SelectedTextKit            # Read currently selected text from any app
  url: https://github.com/tisfeng/SelectedTextKit
```

SenseVoice integration goes through a custom sherpa-onnx wrapper (no SPM yet); Soniox uses native `URLSessionWebSocketTask` (no SDK).

**Total new code estimate:** ~7000 LOC. Comparable to Plan 5 Downloader.

---

## 4. Component Detail

### 4.1 Audio Capture (`Voice/Audio/`)

- **AVAudioEngine** (not CoreAudio AUHAL like VoiceInk; AVAudioEngine is sufficient for our needs and integrates cleanly with `AVAudioApplication.requestRecordPermission`).
- Captures device default input at native format → converts to **16 kHz mono Int16 PCM** in real-time tap.
- Writes WAV file to encrypted archive (Section 4.6) AND emits `Data` chunks to streaming engines.
- Handles audio device hot-swap via `AVAudioEngine.configurationChange` notification.
- Supports system mute/unmute control during recording (via private `MediaController` similar to VoiceInk's mediaremote-adapter, optional).
- **Pre-allocated buffers**, no `malloc` in audio thread.
- Audio level metering at **60 fps** via `DispatchSourceTimer` on `qos: .userInteractive`.

### 4.2 ASR Engines (`Voice/ASR/`)

#### `TranscriptionEngine` protocol

```swift
protocol TranscriptionEngine {
    var id: ModelID { get }
    var isStreaming: Bool { get }
    var supportedLanguages: [VoiceLanguage] { get }
    var supportsCodeSwitching: Bool { get }

    func warmup() async throws
    func transcribe(_ audio: Data, hints: TranscriptionHints) async throws -> TranscriptionResult
    func transcribeStream(_ audioStream: AsyncStream<Data>, hints: TranscriptionHints) -> AsyncThrowingStream<PartialTranscription, Error>
}
```

#### Engine catalog

| Engine | Backend | Type | Size | License | Code-switch | Streaming |
|---|---|---|---|---|---|---|
| **Qwen3-ASR-0.6B** | mlx-swift | Batch | ~600 MB | Apache 2.0 | ★★★★★ | No (sliding-window wrap available) |
| **Parakeet TDT v3** | FluidAudio | Streaming | ~600 MB | CC-BY-4.0 | ★★ | Yes (native) |
| **SenseVoice-Small** | sherpa-onnx | Batch | 234 MB | MIT | ★★★★ | No |
| **Whisper-large-v3-turbo** | WhisperKit | Batch | 1.6 GB | MIT | ★★★ | No |
| **Soniox** | URLSessionWebSocketTask | Streaming | 0 (cloud) | BYOK | ★★★★★ | Yes |

#### Model storage

`~/Library/Application Support/com.you.MacAllYouNeed/Voice/Models/<model-id>/`

#### Model download

- HuggingFace mirror via URLSession + progress delegate.
- SHA256 verification.
- Resume on connection drop.
- Background download supports app-quit-resume across launches.

#### Language detection

- Engines emit per-token language labels where supported (Soniox; Qwen3 via Language ID heads; SenseVoice via `<|zh|>` / `<|en|>` tokens).
- For engines without per-token LID, we infer from script (CJK code points → Chinese, Latin → English) at the segment level.
- The detected language(s) feed into the LLM cleanup prompt (e.g. "Source language: zh+en mixed").

### 4.3 Cleanup Pipeline (`Voice/Cleanup/`)

#### Order of transformations

```
raw ASR text
   │
   ▼
FillerRemoval (regex pre-pass)
   ├── strip "[bracket]", "(parens)", "{curly}" hallucinations
   ├── strip "<TAG>...</TAG>" blocks
   ├── strip default fillers: uh, um, uhm, hmm, hm, mmm, 嗯, 呃, 那个 (case-insensitive, word-boundary)
   └── collapse whitespace
   │
   ▼
LLM Provider (Anthropic / OpenAI-compat / Ollama)
   ├── system prompt (per locale, per active app, with custom dict)
   └── user prompt: <TRANSCRIPT>{text}</TRANSCRIPT>
   │
   ▼
SpokenPunctuation pass
   ├── "句号" → "."
   ├── "comma" → ","
   ├── "new line" → "\n"
   └── numbers/dates normalization (delegated to LLM, this is a safety pass)
   │
   ▼
WordReplacement (user-defined dictionary)
   ├── longest-first matching
   ├── regex with lookaround for spaced languages
   └── substring for CJK / Thai / Hangul
   │
   ▼
Output text (cleaned, possibly translated)
```

#### Skip conditions

- `wordCount(rawText) < 3` → skip LLM, use raw + filler removal only.
- LLM timeout (default 7s) → fallback to raw + filler removal.
- LLM returns empty → fallback to raw + filler removal.

#### Translation

Same LLM call. The system prompt includes:

> If the source language differs from the target language **{target}**, translate the cleaned text to {target} as a {style} native speaker would write it. Otherwise, return the cleaned text unchanged.

Target language is set per-app (Power Mode) or globally in Settings.

#### Reasoning model handling

For Claude extended-thinking / GPT-5 reasoning / Gemini 3 Pro models, we strip `<thinking>`, `<think>`, `<reasoning>` blocks from the output before paste injection.

### 4.4 Power Mode (`Voice/PowerMode/`)

Per-app profile stored in GRDB. Active profile resolved on every `recordingStart` based on `NSWorkspace.shared.frontmostApplication`.

```swift
struct AppProfile {
    var bundleID: String                    // primary key
    var displayName: String
    var isExcluded: Bool                    // true → no dictation in this app
    var promptTemplate: PromptTemplateID?   // nil → use default
    var asrEngineOverride: ModelID?         // nil → use default
    var languageOverride: VoiceLanguage?    // nil → use default
    var llmProviderOverride: LLMProviderID? // nil → use default
    var llmModelOverride: String?
    var translationTarget: VoiceLanguage?
    var autoSendKey: AutoSendKey            // .none / .enter / .shiftEnter / .cmdEnter
    var hotkeyOverride: KeyboardShortcuts.Name?
    var useClipboardContext: Bool
    var useScreenCaptureContext: Bool       // ScreenCaptureKit + Vision OCR (deferred to v1.1)
    var useSelectedTextContext: Bool
}
```

Built-in default profiles for common apps (Mail, Slack, Notes, Cursor, Xcode, Messages, ChatGPT, Claude). User can edit or add new ones in Settings.

Browser per-URL profiles deferred to **v1.1** (requires 11 browser-specific AppleScripts).

### 4.5 AI on Selection (`Voice/Selection/`)

Triggered by independent hotkey (default ⌥Fn).

```
[user selects "今天的会议要讨论 deploy 这个 service"]
   │
   ▼
SelectionHotkeyHandler.fire ──► SelectionAIService.start
   │
   ▼
SelectedTextReader.read()
   ├── Try AXUIElement (most apps support)
   └── Fallback: synthesize Cmd+C → read pasteboard → restore (last resort)
   │
   ▼
[show HUD, user speaks the command]
   ▼
AudioCapture + TranscriptionPipeline ──► "translate to English"
   │
   ▼
SelectionAIService.execute({
    selectedText: "今天的会议要讨论...",
    command: "translate to English",
    appContext: profileForFrontmostApp
})
   │
   ▼
LLM call (system prompt: "you are a text editor, apply user command to text")
   │
   ▼
SelectedTextReplacer.replace(output)
   ├── Try AXUIElement.setValue
   └── Fallback: pasteboard + Cmd+V
```

Common commands the user speaks:
- "translate to English" / "translate to Chinese"
- "make this shorter"
- "make this longer"
- "change to formal tone"
- "summarize"
- "explain this"
- "fix grammar"
- arbitrary: "rewrite as if I'm a CTO presenting to investors"

### 4.6 Storage (`Voice/Storage/`)

#### Database placement

Voice metadata that must join back to clipboard history lives in the existing `clipboard.sqlite` database and must share the same `DatabaseQueue` as `ClipboardStore`. Do **not** open a second GRDB connection to `clipboard.sqlite`; the current app already treats one queue per SQLite file as an invariant to avoid write contention.

The searchable text index remains in the existing `search.sqlite` database through `SearchStore`. `ClipboardBridge` is responsible for writing the clipboard row and then upserting the cleaned transcript into `SearchStore`.

#### Schema additions to `clipboard.sqlite`

```sql
CREATE TABLE voice_transcripts (
    id TEXT PRIMARY KEY,                    -- UUID
    created_at INTEGER NOT NULL,            -- epoch ms
    raw_text TEXT NOT NULL,                 -- raw ASR output
    cleaned_text TEXT NOT NULL,             -- after LLM cleanup
    translated_text TEXT,                   -- if translation enabled
    user_edited_text TEXT,                  -- if user edited in history
    detected_languages TEXT NOT NULL,       -- JSON array of BCP-47 codes
    duration_ms INTEGER NOT NULL,
    asr_model_id TEXT NOT NULL,
    llm_provider TEXT,                      -- nil if cleanup skipped
    llm_model TEXT,
    source_app_bundle_id TEXT,
    source_app_name TEXT,
    audio_archive_id TEXT,                  -- FK to audio_archives
    is_pinned INTEGER NOT NULL DEFAULT 0,
    clipboard_record_id TEXT,               -- FK to clipboard_records(id)
    FOREIGN KEY (clipboard_record_id) REFERENCES clipboard_records(id) ON DELETE SET NULL
);

CREATE INDEX idx_voice_transcripts_created_at ON voice_transcripts(created_at DESC);

CREATE TABLE audio_archives (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,                -- relative to App Group container
    encrypted_size INTEGER NOT NULL,
    sha256 TEXT NOT NULL,
    created_at INTEGER NOT NULL
);

CREATE TABLE voice_dictionary (
    id TEXT PRIMARY KEY,
    word TEXT NOT NULL UNIQUE,
    replacement TEXT NOT NULL,              -- if word=replacement, it's a hot-word for ASR bias
    is_hot_word INTEGER NOT NULL DEFAULT 0, -- true → also passed as initial_prompt
    is_auto_learned INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);

CREATE TABLE app_profiles (
    bundle_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    config_json TEXT NOT NULL,              -- serialized AppProfile
    updated_at INTEGER NOT NULL
);

-- Add voice origin columns to existing clipboard_records if not present:
ALTER TABLE clipboard_records ADD COLUMN capture_origin TEXT NOT NULL DEFAULT 'clipboard';
-- Values: 'clipboard' | 'voice'
ALTER TABLE clipboard_records ADD COLUMN voice_transcript_id TEXT;
CREATE INDEX idx_clipboard_records_capture_origin ON clipboard_records(capture_origin, modified DESC);
```

#### Audio archive

- Path: `~/Library/Group Containers/group.com.you.MacAllYouNeed/Voice/Recordings/<uuid>.wav.enc`
- Encrypted with **AES-GCM** using the existing per-install master key (reuse `EncryptionService`).
- Auto-cleanup after `audioRetentionDays` (default 7) via `AudioCleanupManager`.
- Transcripts kept longer (default 30 days) for ML training data.
- Pinned transcripts never expire.

#### ClipboardBridge

When a voice transcript is finalized:
1. Save to `voice_transcripts` (full record, including audio reference).
2. Insert a parallel text row in `clipboard_records` through `ClipboardStore.append`, then set `capture_origin = 'voice'` and `voice_transcript_id = <uuid>` on that row.
3. Upsert the cleaned transcript into `SearchStore` with `kind = .clipboardItem` and `record_id = clipboard_record_id`.
4. Add a built-in `DockListSelector.voice` tab to the `⌘⇧V` dock that loads `clipboard_records WHERE capture_origin = 'voice' ORDER BY modified DESC`.
5. Search in the Voice tab uses the same `SearchStore` result IDs, then filters/joins through `capture_origin = 'voice'`.

This avoids a separate "voice clipboard" table, keeps paste-back on the existing `ClipboardRecord.text` path, and preserves current retention/pinboard behavior. If the schema change lands after users already have `clipboard.sqlite`, add it as the next `ClipboardStore.migrations` entry and include an idempotent migration test.

#### TrainingExporter

- Settings → Advanced → "Export voice training data"
- Output: `.tar.gz` containing `data.jsonl` (one transcript per line) + `audio/<id>.wav` files.
- JSONL schema: `{id, audio_path, raw_text, cleaned_text, user_edited_text, detected_languages, duration_ms, asr_model_id, source_app, created_at}`.
- Compatible with HuggingFace `datasets` library and standard ASR fine-tuning pipelines.

### 4.7 HUD (`Voice/UI/HUD/`)

#### `HUDController` chooses style per active screen

```swift
func presentHUD() {
    let screen = NSScreen.main
    if hasNotch(screen) {
        notchPanel.show(on: screen)
    } else {
        miniPanel.show(on: screen)
    }
}

func hasNotch(_ screen: NSScreen?) -> Bool {
    guard let screen = screen else { return false }
    return screen.safeAreaInsets.top > 0  // notch present
}
```

#### Notch HUD panel

- `NSPanel` with `.nonactivatingPanel`, `.floating` level, `.canJoinAllSpaces`, `.fullScreenAuxiliary`.
- Custom `NotchShape` Path renders a notch-aligned rounded rectangle directly under the physical notch.
- Computed from `screen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` / `safeAreaInsets.top`.
- Contents: audio visualizer (left), language badge (center), state indicator (right).
- Animation: slide down from notch on activate, slide up on dismiss.

#### Mini HUD panel

- `NSPanel`, same window flags as Notch.
- Position: `screen.visibleFrame.midX`, `screen.visibleFrame.minY + 80`.
- Two sizes: compact (184×40) for state-only, expanded (300×120) when streaming partial transcript visible.
- Contents same as Notch.

#### Audio visualizer

- 8-32 vertical bars (configurable density).
- Updated at 60 fps from `AudioVisualizerData` (RMS-based per-frame amplitude).
- Color shifts based on language detected (blue for en, red for zh, purple for mixed).

### 4.8 Settings (`Voice/UI/Settings/`)

"Voice" tab added to the existing Settings window. The app currently has 12 Settings tabs before Voice lands, so implementation must append Voice without assuming a fixed tab count. Sections:

1. **ASR Models** — picker, download manager, per-model info card, switch between installed models.
2. **AI Cleanup** — provider picker (Anthropic / OpenAI / Ollama / custom OpenAI-compat), API key field (Keychain), test ping button, model picker per provider, timeout slider.
3. **Hotkeys** — recorder for dictation hotkey + AI-on-selection hotkey, activation mode picker (PTT / Toggle / Hybrid / Auto-VAD), Hybrid threshold slider.
4. **Languages** — multi-select with auto-detect toggle.
5. **Dictionary** — CRUD for vocabulary + word replacement rules.
6. **App Profiles** — per-app config table, search/filter, "+ Add app" button, defaults for built-in apps.
7. **Advanced** — retention policies (audio days, transcript days), zero-retention toggle, training data export, model storage location.

### 4.9 Onboarding (`Voice/UI/Onboarding/`)

Triggered on first launch (after the existing 6-step onboarding completes, OR can be re-launched from Settings).

State persisted to `UserDefaults` per step (resume on quit).

#### 8 Steps

**Step 0: Welcome**
- Bilingual typewriter animation cycling through:
  - "Write emails 5x faster"
  - "用中英文混合 dictate"
  - "Translate as you speak"
  - "Polish your writing automatically"
- Single CTA: "Get Started"
- Footer: "Your voice never leaves your Mac"

**Step 1: Microphone Permission**
- Request via `AVAudioApplication.requestRecordPermission`.
- Live audio visualizer appears the moment permission is granted.
- Auto-advance after 1.5s of audio detected (so user knows it works).

**Step 2: Accessibility Permission**
- Explain: "Type into any app from voice"
- Deep-link to System Settings → Privacy & Security → Accessibility (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`).
- Poll `AXIsProcessTrusted()` every 500ms; auto-advance when granted.

**Step 3: Pick Your ASR Engine**
- Three primary cards: Qwen3-ASR-0.6B (recommended), Parakeet TDT v3 (streaming), SenseVoice-Small (lightweight).
- Hidden under "More options": Whisper-large-v3-turbo, Soniox cloud (BYOK).
- Selecting triggers download with progress bar. **Non-blocking**: user can proceed to Step 4 while download continues in background.

**Step 4: Pick Your AI Cleanup Provider** (skippable)
- Three cards: Anthropic Claude Haiku 4.5 (recommended), OpenAI gpt-5-nano, Ollama (local).
- API key text field with secure Keychain storage.
- "Test" button sends a tiny ping (e.g. "Reply with: ok") and shows ✓ or ✗.
- "Skip" button → uses raw ASR + regex filler removal.

**Step 5: Hotkey Setup**
- Visual Mac keyboard SVG with default `⌃⌥Space` highlighted; Fn / Globe may be offered as an advanced choice only when it does not conflict with system input switching.
- "Change" button opens `KeyboardShortcuts.Recorder` for any combo.
- Activation mode radio: **Toggle (MVP default)** / PTT / Hybrid / Auto-VAD.
- Hybrid threshold slider (default 500ms).
- "Test now" button: user presses the configured key, HUD appears as a preview (no real recording).

**Step 6: Languages**
- Multi-select checkboxes: 简体中文 / English / 繁體中文 / 粵語 / 日本語 / 한국어 / "More languages..."
- "Auto-detect everything" single toggle as alternative.
- Selected languages bias the ASR `initial_prompt` (or equivalent) per engine.

**Step 7: Try It Now!**
- In-window mock email editor.
- Suggested phrase displayed: *"嗨 mingjie, 我们今天 deploy 这个 service 到 production"*
- User presses the configured shortcut to start, speaks, then presses it again to stop. If PTT is selected, user holds and releases the shortcut instead.
- Mock editor shows: raw ASR (faded) → cleaned text (bold) → if translation enabled, target text (alternate color).
- Confirm "It works!" button enabled after at least one successful transcription.
- "Open Notes to try in a real app →" button (optional, validates paste injection works in a real text field).

**Step 8: Done**
- "All set! Press your voice shortcut anywhere on Mac to dictate."
- Optional: "Take a 2-min tour of advanced features" (per-app profiles, AI on selection, dictionary).
- Settings deep-link.

#### Polish

- Top progress indicator: "Step N of 8".
- Each step: Skip + Back + Next (where applicable).
- Smooth slide + fade transitions (250ms easeInOut).
- Inline error messages (no modal alerts).
- Resume on quit via `voiceOnboardingCurrentStep` UserDefault.

### 4.10 Coordinator (`VoiceCoordinator.swift`)

```swift
@MainActor
final class VoiceCoordinator: ObservableObject {
    enum State {
        case idle
        case starting
        case recording(startedAt: Date)
        case processing(durationMs: Int)
        case pasting
        case error(VoiceError)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var detectedLanguages: [VoiceLanguage] = []
    @Published private(set) var activeProfile: AppProfile?

    private let audioCapture: AudioCaptureService
    private let engineRegistry: TranscriptionEngineRegistry
    private let cleanupPipeline: CleanupPipeline
    private let cursorPaster: CursorPaster
    private let powerMode: PowerModeManager
    private let storage: VoiceTranscriptStore
    private let clipboardBridge: ClipboardBridge
    private let hud: HUDController

    func startRecording(activationMode: ActivationMode) async { ... }
    func stopRecording() async { ... }
    func cancel() async { ... }
}
```

State machine transitions are enforced; illegal transitions log a warning and remain in current state.

---

## 5. Data Flow Scenarios

### 5.1 Scenario A: Push-to-Talk dictation (main path)

```
t=0     User presses configured shortcut ──► HotkeyRegistry ──► VoiceCoordinator.startRecording()
                                                        │
t=10    AudioCaptureService.start() ─────────► AVAudioEngine starts
                                                        │
        PowerMode.detectFrontmostApp() ──────► AppProfile (e.g. Mail.app)
                                                        │
        HUDController.show(.notch) ──────────► NotchHUDPanel appears
                                                        │
t=10-5000  [user speaks]
        AudioCapture.onChunk ─────────────────► AudioVisualizerData (60fps → HUD)
                                          └───► CircularBuffer (audio accumulation)
                                                        │
t=5000  Toggle mode: user presses configured shortcut again ──► VoiceCoordinator.stopRecording()
        PTT mode: user releases configured shortcut ───────────► VoiceCoordinator.stopRecording()
                                                        │
        AudioCapture.stop() ──► finalAudio (16kHz Int16)
                                                        │
        TranscriptionEngine.transcribe(finalAudio)
             │
             ├─ Qwen3Engine.transcribe ─────► raw text + langs (latency measured in Plan 8.0)
             │
        FillerRemoval.regex ────────────────► raw - obvious fillers
             │
        CleanupPipeline.run({
            text: rawText,
            appProfile: mailProfile,
            customDict: userDict,
            targetLang: nil
        })
             │
             ├─ PromptBuilder.build ─────────► system + user prompt
             ├─ AnthropicProvider.invoke ────► Claude Haiku 4.5 (~400ms)
             └─ output: cleaned text
             │
        SpokenPunctuation.apply ────────────► "句号" → "."
             │
        CursorPaster.paste(cleanedText)
             ├─ ClipboardManager.save(currentClipboard)
             ├─ NSPasteboard.set(cleanedText)
             ├─ CGEvent Cmd+V (or AppleScript fallback)
             ├─ usleep(120ms)
             └─ ClipboardManager.restore() (after 450ms)
             │
        VoiceTranscriptStore.save({
            rawText, cleanedText, audioPath, appBundleID, language, model, timestamps
        })
             │
        ClipboardBridge.appendToClipboard(cleanedText, voiceTranscriptID: id)
             │
        AutoSendKey.sendIfConfigured(profile: mailProfile)
             │
        HUDController.dismiss() ────────────► HUD slides away
```

**Initial latency hypothesis on M3 Mac, 5s utterance:**
- Audio capture stop → 50ms
- ASR (Qwen3-0.6B batch through the selected local backend) → 250ms hypothesis
- Filler regex → 5ms
- LLM cleanup (Claude Haiku-class cloud model) → 400ms hypothesis, network dependent
- Punctuation pass → 5ms
- Paste injection → 50ms
- **Hypothesis:** ~760ms after key release

These numbers are planning assumptions, not acceptance criteria. Plan 8.0 must replace them with measured baselines before Plan 8a uses them for UX or architecture decisions.

### 5.2 Scenario B: AI on Selection

```
User selects "今天的会议要讨论 deploy 这个 service" in Notes ── press ⌥Fn
                                                        │
        SelectedTextReader.read() ──────────► AXUIElement → "今天的会议要讨论..."
                                                        │
        HUDController.show(.notch, mode: .selection)    │
                                                        │
        AudioCapture.start()                            │
                                                        │
        [user speaks "translate to English"]
                                                        │
        TranscriptionPipeline ──────────────► "translate to English"
                                                        │
        SelectionAIService.execute({
            selectedText: "今天的会议要讨论 deploy 这个 service",
            command: "translate to English",
            context: notesAppContext
        })
             │
             ├─ PromptBuilder.buildForSelection
             ├─ AnthropicProvider.invoke ────► "Today's meeting will discuss deploying this service"
             └─ output
             │
        SelectedTextReplacer.replace(output)
             ├─ Method 1: AXUIElement.setValue (works in Notes, Pages, most native apps)
             └─ Method 2: pasteboard + Cmd+V (fallback for resistant apps)
```

### 5.3 Scenario C: Model download (Onboarding step 3)

```
ASREngineStep.userPicked(qwen3) ──► ModelManager.download(qwen3)
                                                        │
        URLSession + delegate ──────────────► HuggingFace download
             │
             ├─ Progress events ─────────────► UI progress bar
             ├─ Resume on connection drop (HTTP Range requests)
             └─ SHA256 verification
             │
        Disk: ~/Library/Application Support/com.you.MacAllYouNeed/Voice/Models/qwen3-asr-0.6b/
             │
        Engine.warmup() ────────────────────► dummy inference to prewarm ANE
             │
        Notify VoiceCoordinator: model ready
```

### 5.4 Scenario D: Per-app context switch

```
NSWorkspace.didActivateApplicationNotification ──► AppContextDetector
                                                        │
        AppProfileStore.findProfile(bundleID) ──► profile (or default)
                                                        │
        VoiceCoordinator.setActiveProfile(profile)
             │
             ├─ Override ASR engine if specified
             ├─ Override language if specified
             ├─ Override LLM provider if specified
             ├─ Override prompt template if specified
             └─ Override hotkey if specified (re-register with HotkeyRegistry)
```

---

## 6. Error Handling Matrix

| Error | Detection | Handling |
|---|---|---|
| Mic permission denied | `AVAudioApplication.requestRecordPermission` returns false | HUD shows red error icon, link to System Settings |
| Accessibility permission missing | `AXIsProcessTrusted()` false | Paste fails → write to clipboard, HUD shows "Use ⌘V to paste" toast |
| Model download failed | `URLSession` error | Progress bar turns red + Retry button, partial file kept for resume |
| Model load OOM | catch MLX `loadError` / WhisperKit error | Toast: "Switch to a smaller model in Settings", suggest SenseVoice |
| ASR inference crash | protective `do/catch` around full pipeline | HUD shows "ASR error", audio kept for retry |
| LLM API key invalid | HTTP 401 | HUD warning, deep-link to Settings → Provider, fallback to raw ASR |
| LLM timeout (>7s) | `Task` timeout | Fallback to raw ASR + regex filler removal |
| Network failure (cleanup) | URLSession error | Same fallback as above |
| Audio device disconnect | `AVAudioEngine.configurationChange` | Switch to default device, restart capture |
| Utterance too short (<200ms) | duration check post-stop | Discard, HUD shows "Too short" toast |
| Cleanup returns empty text | empty string check | Fallback to raw ASR |
| Onboarding model download abandoned mid-flow | UserDefault state | Resume from same step on next launch |

---

## 7. Privacy & Security

- **Audio files** AES-GCM encrypted on disk (reuse existing `EncryptionService`).
- **API keys** stored in **Keychain** (reuse existing `KeychainService`).
- **Default retention:** audio 7 days, transcripts 30 days, configurable in Settings.
- **Zero-retention mode:** Settings toggle that auto-deletes audio + transcript immediately after paste.
- **Training data export** is **user-initiated only** (never automatic, never uploaded).
- **HuggingFace downloads** over HTTPS with **SHA256** integrity check.
- **LLM calls** use the user's own API key (BYOK); no traffic ever passes through our servers.
- **Tagline boundaries:** "Your voice never leaves your Mac" is **strictly true** for the local-ASR + local-LLM (Ollama) path. Cloud-LLM paths transmit ASR text output (never audio) to the configured LLM provider. Onboarding step 4 must explicitly state this distinction.
- **No telemetry** (consistent with the rest of mac-all-you-need).

---

## 8. Performance Hypotheses & Measurement Gates

Performance numbers start as hypotheses and become targets only after Plan 8.0 records local measurements on the intended hardware. Until then, implementation should optimize for a correct, cancellable, observable pipeline instead of chasing unproven millisecond budgets.

**Plan 8.0 partial measurement update (2026-05-11):** Qwen3-ASR f32 via FluidAudio 0.14.5 produced the exact zh/en synthetic fixture transcript on an M3 Max, but measured warm p50 processing time was ~1.11s for 3.28s audio and peak process memory was ~3.69GB. Parakeet TDT v3 processed the same fixture in ~0.12s but failed zh/en accuracy. Plan 8a must either validate Qwen3 int8 or design the MVP as a slower batch-Qwen path with clear HUD feedback; the original sub-250ms / <1.5GB assumptions are not valid for Qwen3 f32.

| Metric | Hypothesis | Plan 8.0 measurement gate |
|---|---|---|
| Cold ASR inference (Qwen3-0.6B, 5s audio) | Superseded for f32; first cached CLI run was 2.33s on 3.28s audio | Run fixed zh/en/mixed fixtures through the actual Swift backend; record p50/p95 and memory |
| Warm ASR inference | Superseded for f32; warm p50 was ~1.11s on 3.28s audio | Same fixture suite after model warmup; validate int8 before final v1 target |
| LLM cleanup (Claude Haiku-class cloud model, ~50 words) | < 600ms | Measure p50/p95 over 20 calls; record timeout/fallback rate |
| **End-to-end (key release → text pasted)** | **< 1s** | Instrument capture stop, ASR, cleanup, paste, clipboard restore; record p50/p95 |
| HUD appear latency (key press → HUD visible) | < 50ms | Measure from hotkey callback to visible panel |
| Audio visualizer frame rate | 60fps sustained | Verify under active recording and ASR model loaded |
| Memory footprint while idle (model unloaded) | < 100 MB additional | Compare app baseline before/after voice module idle |
| Memory footprint while recording (selected model loaded) | Superseded for Qwen3 f32; CLI peak process memory was ~3.69GB | Record resident memory during 30s recording and transcription; validate int8/lighter fallback |
| Streaming first-token latency (streaming engine only) | < 500ms | Measure only after a streaming engine is selected and integrated |
| Onboarding model download (default model over 50 Mbps) | < 2 min | Measure download, resume, checksum, and warmup separately |

---

## 9. Testing Strategy

### Unit (`Shared/Tests/VoiceTests/`)
- `AudioFormatTests` — PCM conversion correctness for various sample rates / channel counts.
- `SlidingWindowTests` — window boundary edge cases.
- `SpokenPunctuationTests` — Chinese + English punctuation tables, mixed-script edge cases.
- `PromptBuilderTests` — multi-context prompt assembly outputs.
- `FillerRemovalTests` — Chinese + English filler word rules, false-positive cases (e.g. don't strip "um" from "umbrella").
- `LanguageDetectionTests` — mixed-token classification accuracy.
- `WordAgreementTests` — 3-pass convergence + edge cases (empty stream, repeated tokens, language switches).

### Integration (`MacAllYouNeedTests/Voice/`)
- End-to-end record → ASR → cleanup → paste, simulated with fixed audio fixture files.
- Model download retry / resume.
- Per-app profile switching (mock NSWorkspace notification).
- ClipboardBridge sync to clipboard FTS5.
- AI on selection round-trip with synthetic AXUIElement.

### Manual QA matrix
- 5 ASR engines × 3 LLM providers × 4 activation modes = 60-combination sanity check.
- Chinese-English mixed phrase suite:
  - "我今天 deploy 这个 service 到 production"
  - "Let me check 一下 这个 PR"
  - "记得明天 9 点 standup"
  - "把这个 logic 重构一下"
  - "schedule 一个 1:1 with mingjie"
- Performance baselines recorded on M3 Mac:
  - Qwen3-0.6B inference time per 1s of audio
  - End-to-end latency (release → text)
  - HUD startup latency

### Performance benchmarks (`Shared/Tests/VoicePerfTests/`)
- Add a local-only benchmark suite for ASR/model tests that require downloaded models or Apple Silicon hardware.
- Keep deterministic non-model benchmarks in CI where possible.
- Output benchmark JSON from local runs; track regressions across commits after Plan 8.0 establishes baseline values.

---

## 10. Plan Decomposition

Total v1 ≈ 7000 LOC after spike validation. Decompose into **1 technical spike + 6 implementation sub-plans**:

| Plan | Title | Scope | LOC est. |
|---|---|---|---|
| **8.0** | Technical spike | Prove microphone permission/codesign, default hotkey/PTT feasibility, one local ASR Swift backend, paste injection + pasteboard restore, and benchmark instrumentation | ~300 |
| **8a** | Voice MVP | AudioCapture + Qwen3 single-engine + Mini HUD + Hotkey + paste injection + minimal Settings tab | ~1500 |
| **8b** | Onboarding | 8-step wizard + permissions handling + Settings tab full layout | ~1500 |
| **8c** | Cleanup pipeline | LLM provider abstraction + Anthropic + filler removal + dictionary + word replacement | ~1200 |
| **8d** | Multi-engine ASR | SenseVoice + Parakeet + Whisper + Soniox + ModelManager + Notch HUD | ~1500 |
| **8e** | Power Mode | AppContextDetector + AppProfileStore + AppProfilesSection + AutoSendKey | ~700 |
| **8f** | Advanced features | AI on selection + streaming (Parakeet/Soniox) + translation + ClipboardBridge + TrainingExporter + per-locale prompts | ~700 |

Each sub-plan gets its own `writing-plans` artefact with detailed task breakdown, dependency graph, and risk analysis.

### Plan 8.0 acceptance gates

Plan 8.0 must produce a short findings document before Plan 8a starts:

1. **Microphone/codesign gate:** app launches with `NSMicrophoneUsageDescription`, hardened-runtime audio input entitlement if required by the signing mode, and `AVAudioApplication.requestRecordPermission` succeeds or fails with a controlled onboarding message.
2. **Hotkey/PTT gate:** prove whether Fn/Globe can be captured with press/release semantics in this app. If not, choose a normal fallback shortcut and update the spec before implementation.
3. **ASR backend gate:** run one local ASR model through a Swift-callable path with fixed zh/en/mixed fixtures. Record accuracy notes, p50/p95 latency, memory, model load time, and packaging constraints.
4. **Paste gate:** paste dictated text into Notes/TextEdit plus one Electron app, restore the previous pasteboard content, and verify the fallback "press ⌘V" path when Accessibility is denied.
5. **Benchmark gate:** add lightweight instrumentation around capture stop, ASR, cleanup, paste, and restore so later plans can compare measured values instead of relying on speculative latency budgets.

---

## 11. Open Questions for Future Iterations

- **v1.1: Per-URL Power Mode profiles** for browsers (11 browser AppleScripts; lift from VoiceInk).
- **v1.1: ScreenCaptureKit + Vision OCR** for screen-capture context (Power Mode).
- **v2: Auto-learned dictionary** — diff user edits to transcripts in History, auto-add to word replacements.
- **v2: Personal Whisper LoRA fine-tune** workflow (uses TrainingExporter output).
- **v2: Multi-speaker diarization** (FluidAudio supports it natively).
- **v2: System audio tap** for meeting transcription (`CATapDescription`, macOS 14.2+).
- **v2: iOS companion app** — once Plan 2 (Sync Engine) is finally built.

---

## 12. References

### Researched competitors
- **Typeless** — typeless.com — cloud-only, AWS us-east-2, Soniox + Claude Haiku-class LLM stack hypothesized.
- **VoiceInk** — github.com/Beingpax/VoiceInk — native Swift, 4-engine support (whisper.cpp / FluidAudio Parakeet / Apple SpeechAnalyzer / 10 cloud providers), GPL source / paid binary.
- **OpenWhispr** — github.com/OpenWhispr/openwhispr — Electron, 4 local engines + 3 streaming cloud, 8-provider scoped LLM registry, MIT.

### Models researched
- **Qwen3-ASR-0.6B / 1.7B** — huggingface.co/Qwen — Apache 2.0, beats Whisper-v3 multilingual, 22 Chinese dialects, MLX/CoreML Swift wrappers exist.
- **NVIDIA Parakeet-TDT-0.6b-v3** — huggingface.co/nvidia — CC-BY-4.0, 25 European + Japanese + Chinese, 190× RTF on M4, FluidAudio production-grade Swift wrapper.
- **SenseVoice-Small** — huggingface.co/FunAudioLLM — MIT, 234 MB, 50+ languages, non-autoregressive (15× faster than Whisper-Large).
- **Whisper-large-v3-turbo** — huggingface.co/openai — MIT, 1.6 GB, mature Swift integration via WhisperKit.
- **Breeze ASR 25** — Taiwan team, 56% lower WER than Whisper-v2 on Mandarin-English code-switching (deferred — Qwen3 covers same use case better).
- **NVIDIA Nemotron Speech Streaming** — 0.6B, 2.12% WER, streaming, FluidAudio supports (deferred to v1.1).

### Cloud STT
- **Soniox** — soniox.com — 60+ languages, sub-200ms latency, native code-switching with per-token language labels, built-in translation 3600+ pairs.
- **Deepgram Nova-3** — deepgram.com — 49 languages, 200-400ms latency.

### Key Swift packages
- **FluidAudio** — github.com/FluidInference/FluidAudio — Parakeet + Silero VAD + diarization on CoreML.
- **WhisperKit** — github.com/argmaxinc/WhisperKit — Apple Silicon Whisper.
- **mlx-swift** — github.com/ml-explore/mlx-swift — MLX backend for Qwen3.
- **KeyboardShortcuts** — github.com/sindresorhus/KeyboardShortcuts — global hotkeys + recorder UI.
- **SelectedTextKit** — github.com/tisfeng/SelectedTextKit — read selected text from any app.
