# SenseVoice Small ASR Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SenseVoice Small as a fourth local ASR option in the Voice → Models picker — non-autoregressive, batch, ~900 MB, zh-en, downloadable on demand.

**Architecture:** `SenseVoiceEngine` actor uses `MLXAudioSTT.SenseVoiceModel.fromDirectory(url)` for model loading and `model.generate(audio:language:useITN:verbose:)` for inference. Model files are downloaded from HuggingFace `mlx-community/SenseVoiceSmall` via a new `SenseVoiceModels` helper that mirrors the `Qwen3AsrModels`/`AsrModels` pattern. Routing goes through the existing `VoiceLocalASREngine` switch on `VoiceASRModelID.runtime`.

**Tech Stack:** Swift, mlx-audio-swift (revision `a1c7b11`, `hehehai/mlx-audio-swift`), MLXAudioCore, MLXAudioSTT, existing DownloadUtils, existing VoiceModelCatalog pattern.

---

## File Map

| Action | File | What changes |
|---|---|---|
| **Add dep** | `MacAllYouNeed.xcodeproj/project.pbxproj` (via xcodegen) | mlx-audio-swift package + MLXAudioCore + MLXAudioSTT link |
| **Create** | `MacAllYouNeed/Voice/ASR/SenseVoiceEngine.swift` | Actor: load model, transcribe, warmup |
| **Create** | `MacAllYouNeed/Voice/ASR/SenseVoiceModels.swift` | Download, cache dir, install check |
| **Modify** | `MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift` | Add `senseVoiceSmall` case to `VoiceASRModelID`; new `runtime`, `title`, `subtitle`, `diskLabel` |
| **Modify** | `MacAllYouNeed/Voice/VoiceModelCatalog.swift` | Add `sensevoice` to `VoiceModelRuntime`; add descriptor to `localASRModels`; update `isLocalASRModelInstalled`, `localASRCacheDirectory`, `downloadLocalASRModel`, `deleteLocalASRModel` |
| **Modify** | `MacAllYouNeed/Voice/ASR/VoiceLocalASREngine.swift` | Add `SenseVoiceEngine` instance; route `.sensevoice` in transcribe/warmup/capabilities |
| **Modify** | All exhaustive switches on `VoiceASRModelID` / `VoiceModelRuntime` | Compiler flags each one — add `.senseVoiceSmall` / `.sensevoice` |

---

## Task 1: Add mlx-audio-swift SPM dependency

**Files:**
- Modify: `project.yml` (xcodegen source)

- [ ] **Check the project.yml for how existing SPM packages are declared**

```bash
grep -A5 "FluidAudio\|packages:" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -30
```

- [ ] **Add mlx-audio-swift to project.yml under the MacAllYouNeed target's packages**

In `project.yml`, under `MacAllYouNeed` target packages, add:

```yaml
- package: mlx-audio-swift
  product: MLXAudioCore
- package: mlx-audio-swift
  product: MLXAudioSTT
```

And in the top-level `packages:` section add:

```yaml
mlx-audio-swift:
  url: https://github.com/hehehai/mlx-audio-swift
  revision: a1c7b11b68b16f1591bb0ff586372dde9b265135
```

- [ ] **Regenerate the Xcode project**

```bash
xcodegen generate
```

- [ ] **Verify build with new dependency**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E "error:|Build succeeded|BUILD FAILED" | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Commit**

```bash
git add project.yml MacAllYouNeed.xcodeproj/project.pbxproj Shared/Package.resolved
git commit -m "feat(voice): add mlx-audio-swift dependency for SenseVoice"
```

---

## Task 2: SenseVoiceModels helper (download + install check)

**Files:**
- Create: `MacAllYouNeed/Voice/ASR/SenseVoiceModels.swift`

This mirrors the pattern of `Qwen3AsrModels` / `AsrModels`. It knows:
1. Where to store model files on disk
2. Which files must be present for "installed" to return true
3. How to download from HuggingFace

- [ ] **Create SenseVoiceModels.swift**

```swift
import Foundation

/// Manages the on-disk lifecycle of the SenseVoice Small MLX model.
/// Model source: https://huggingface.co/mlx-community/SenseVoiceSmall
enum SenseVoiceModels {
    static let huggingFaceRepo = "mlx-community/SenseVoiceSmall"

    /// Required files that must all be present for the model to be usable.
    static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "tokenizer.json",
        "tokenizer_config.json",
        "special_tokens_map.json",
    ]

    static func defaultCacheDirectory() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("com.macallyouneed.shared")
            .appendingPathComponent("models")
            .appendingPathComponent("sense-voice-small")
    }

    static func modelsExist(at directory: URL) -> Bool {
        requiredFiles.allSatisfy { file in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(file).path
            )
        }
    }

    @discardableResult
    static func download(
        progressHandler: DownloadUtils.ProgressHandler? = nil
    ) async throws -> URL {
        let directory = defaultCacheDirectory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let baseURL = URL(string: "https://huggingface.co")!
        for file in requiredFiles {
            let destination = directory.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            let fileURL = baseURL
                .appendingPathComponent(huggingFaceRepo)
                .appendingPathComponent("resolve/main")
                .appendingPathComponent(file)
            try await DownloadUtils.downloadFile(
                from: fileURL,
                to: destination,
                progressHandler: progressHandler
            )
        }
        return directory
    }
}
```

- [ ] **Check that DownloadUtils.downloadFile exists with this signature**

```bash
grep -n "func downloadFile\|static func download" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/DownloadUtils.swift 2>/dev/null | head -10
grep -rn "func downloadFile\|static func download" /Users/mingjie.wang/Documents/personal/mac-all-you-need/Shared --include="*.swift" | head -10
```

If `DownloadUtils.downloadFile` does not exist with that exact signature, adapt the call to match the actual API. The key requirement: download a single file from a URL to a local path with optional progress.

- [ ] **Build to verify**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -10
```

Fix any compile errors from the new file.

- [ ] **Commit**

```bash
git add MacAllYouNeed/Voice/ASR/SenseVoiceModels.swift
git commit -m "feat(voice): add SenseVoiceModels download helper"
```

---

## Task 3: SenseVoiceEngine actor

**Files:**
- Create: `MacAllYouNeed/Voice/ASR/SenseVoiceEngine.swift`

- [ ] **Check the exact MLXAudioSTT API in the mlx-audio-swift package**

```bash
# After xcodegen, the package is in DerivedData or the checkouts folder:
find ~/Library/Developer/Xcode/DerivedData -name "SenseVoiceModel.swift" 2>/dev/null | head -3
find ~/.spm -name "SenseVoiceModel.swift" 2>/dev/null | head -3
# OR look at Package.resolved to find checkout location
grep -r "SenseVoiceModel\|func generate\|fromDirectory" ~/Library/Developer/Xcode/DerivedData/MacAllYouNeed*/SourcePackages 2>/dev/null | head -10
```

Confirm the exact signatures of:
- `SenseVoiceModel.fromDirectory(_ url: URL) throws -> SenseVoiceModel`
- `model.generate(audio: MLXArray, language: String?, useITN: Bool, verbose: Bool) -> <OutputType>`
- The property that holds the transcription text on the output (e.g. `output.text`)

- [ ] **Create SenseVoiceEngine.swift with the confirmed API**

```swift
import Core
import Foundation
import MLXAudioCore
import MLXAudioSTT
import OSLog

private let senseVoiceLog = Logger(
    subsystem: "com.macallyouneed.voice",
    category: "sensevoice"
)

/// Non-autoregressive ASR engine using SenseVoice Small via mlx-audio-swift.
/// Batch-only: no live streaming session. Transcribes full audio in <100ms.
actor SenseVoiceEngine: VoiceTranscriptionEngine {

    private var model: SenseVoiceModel?

    nonisolated var modelIdentifier: String { "sense-voice-small" }

    nonisolated var capabilities: VoiceASRCapabilities {
        .init(supportsStreaming: false, requiresNetwork: false, emitsPartials: false)
    }

    func transcribe(
        samples: [Float],
        sampleRate: Double,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult {
        let loadedModel = try await loadModelIfNeeded()
        let resampled = sampleRate == 16000
            ? samples
            : AudioCaptureService.resample(samples, from: sampleRate, to: 16000)
        senseVoiceLog.info("SenseVoice transcribe: \(resampled.count / 16000, privacy: .public)s audio")
        let output = loadedModel.generate(
            audio: MLXArray(resampled),
            language: nil,   // auto-detect zh/en
            useITN: true,    // normalize numbers/dates
            verbose: false
        )
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return VoiceTranscriptionResult(
            text: text,
            language: .mixed,
            modelIdentifier: modelIdentifier
        )
    }

    /// Pre-load the model into memory so first dictation is instant.
    func warmup() async {
        _ = try? await loadModelIfNeeded()
    }

    // MARK: - Private

    private func loadModelIfNeeded() async throws -> SenseVoiceModel {
        if let existing = model { return existing }
        let dir = SenseVoiceModels.defaultCacheDirectory()
        guard SenseVoiceModels.modelsExist(at: dir) else {
            throw VoiceLocalASREngineError.modelNotInstalled(.senseVoiceSmall)
        }
        senseVoiceLog.info("SenseVoice: loading model from \(dir.path, privacy: .public)")
        let loaded = try SenseVoiceModel.fromDirectory(dir)
        model = loaded
        return loaded
    }
}
```

> **If the `output.text` property name or `generate` signature differs** from what you confirmed in the previous step, adjust accordingly. Do not guess — read the actual API.

- [ ] **Build to verify it compiles**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -10
```

- [ ] **Commit**

```bash
git add MacAllYouNeed/Voice/ASR/SenseVoiceEngine.swift
git commit -m "feat(voice): add SenseVoiceEngine actor (non-autoregressive batch ASR)"
```

---

## Task 4: Add senseVoiceSmall to VoiceASRModelID + VoiceModelRuntime

**Files:**
- Modify: `MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift`
- Modify: `MacAllYouNeed/Voice/VoiceModelCatalog.swift`

- [ ] **Add `case sensevoice` to VoiceModelRuntime in VoiceModelCatalog.swift**

Find `enum VoiceModelRuntime` (line ~5) and add:

```swift
case sensevoice
```

- [ ] **Add `case senseVoiceSmall` to VoiceASRModelID in VoiceASRSettings.swift**

Add after the existing cases:

```swift
case senseVoiceSmall = "sense-voice-small"
```

- [ ] **Add `runtime` for the new case** (still in VoiceASRSettings.swift, find `var runtime: VoiceModelRuntime`):

```swift
case .senseVoiceSmall:
    .sensevoice
```

- [ ] **Add `title` for the new case** (find `var title: String` on VoiceASRModelID):

```swift
case .senseVoiceSmall:
    "SenseVoice Small"
```

- [ ] **Add `subtitle` for the new case**:

```swift
case .senseVoiceSmall:
    "Non-autoregressive · Chinese & English · Fast batch inference"
```

- [ ] **Add `diskLabel` for the new case**:

```swift
case .senseVoiceSmall:
    "~900 MB"
```

- [ ] **Fix all remaining exhaustive switch errors on VoiceASRModelID** — build to find them:

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -20
```

For each "switch must be exhaustive" error on `VoiceASRModelID`, add `case .senseVoiceSmall:` with a sensible value (return `nil` for Qwen3/Parakeet-specific properties like `qwen3Variant`, `parakeetVersion`).

- [ ] **Fix all exhaustive switch errors on VoiceModelRuntime** the same way.

- [ ] **Build clean**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

Expected: `BUILD SUCCEEDED`

- [ ] **Commit**

```bash
git add MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift MacAllYouNeed/Voice/VoiceModelCatalog.swift
git commit -m "feat(voice): add senseVoiceSmall model ID and sensevoice runtime"
```

---

## Task 5: Wire SenseVoice into VoiceModelCatalog (catalog entry + install/download)

**Files:**
- Modify: `MacAllYouNeed/Voice/VoiceModelCatalog.swift`

- [ ] **Add SenseVoice to `localASRModels` array**

In `VoiceModelCatalog.localASRModels`, add after the Parakeet entry:

```swift
VoiceModelDescriptor(
    id: "sensevoice.sense-voice-small",
    category: .localASR,
    runtime: .sensevoice,
    title: "SenseVoice Small",
    subtitle: "Non-autoregressive zh-en model. ~10× faster than Qwen3; pairs well with AI cleanup.",
    diskLabel: "~900 MB",
    requiresOSLabel: "Apple Silicon",
    localASRModelID: .senseVoiceSmall,
    cloudASRModelID: nil,
    groqASRModelID: nil
),
```

- [ ] **Add SenseVoice to `recommendedLocalASROrder`**

```swift
static let recommendedLocalASROrder: [VoiceASRModelID] = [
    .qwen3ASR06BF32,
    .parakeetTDT06BV3,
    .qwen3ASR06BInt8,
    .senseVoiceSmall,   // add
]
```

- [ ] **Add `.sensevoice` case to `isLocalASRModelInstalled`**

```swift
case .sensevoice:
    guard SystemInfo.isAppleSilicon else { return false }
    return SenseVoiceModels.modelsExist(at: localASRCacheDirectory(for: modelID))
```

- [ ] **Add `.sensevoice` case to `localASRCacheDirectory`**

```swift
case .sensevoice:
    return SenseVoiceModels.defaultCacheDirectory()
```

- [ ] **Add `.sensevoice` case to `downloadLocalASRModel`**

```swift
case .sensevoice:
    guard SystemInfo.isAppleSilicon else {
        throw VoiceLocalASREngineError.unsupportedPlatform("SenseVoice requires Apple Silicon.")
    }
    return try await SenseVoiceModels.download(progressHandler: progressHandler)
```

- [ ] **Add `.sensevoice` case to `deleteLocalASRModel`** (the existing `deleteLocalASRModel` uses `localASRCacheDirectory`, so it should already work once the case above is added — verify).

- [ ] **Build and verify**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Commit**

```bash
git add MacAllYouNeed/Voice/VoiceModelCatalog.swift
git commit -m "feat(voice): wire SenseVoice into model catalog, install/download/delete"
```

---

## Task 6: Route SenseVoice through VoiceLocalASREngine

**Files:**
- Modify: `MacAllYouNeed/Voice/ASR/VoiceLocalASREngine.swift`

- [ ] **Add SenseVoiceEngine instance to VoiceLocalASREngine**

Find the `actor VoiceLocalASREngine` body. Add alongside existing engine instances:

```swift
private let senseVoice = SenseVoiceEngine()
```

- [ ] **Add `.sensevoice` routing in the `transcribe` method**

Find the `switch modelID.runtime` inside `transcribe`. Add:

```swift
case .sensevoice:
    return try await senseVoice.transcribe(samples: samples, sampleRate: sampleRate, options: options)
```

- [ ] **Add `.sensevoice` routing in the `warmup` method**

Find `func warmup()`. Add:

```swift
case .sensevoice:
    await senseVoice.warmup()
```

- [ ] **Update the `capabilities` computed property**

Find where `capabilities` is computed (it may check the selected model). Add `.sensevoice` to return `senseVoice.capabilities`:

```swift
case .sensevoice:
    return senseVoice.capabilities
```

- [ ] **Build clean**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

- [ ] **Run tests**

```bash
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test 2>&1 | tail -5
```

Expected: all 755+ tests pass.

- [ ] **Commit**

```bash
git add MacAllYouNeed/Voice/ASR/VoiceLocalASREngine.swift
git commit -m "feat(voice): route SenseVoice through VoiceLocalASREngine"
```

---

## Task 7: Guard Apple Silicon in settings UI

**Files:**
- Modify: `MacAllYouNeed/Voice/VoiceModelCatalog.swift` (or wherever the model picker hides unsupported models)

- [ ] **Find how Parakeet is hidden on non-Apple-Silicon**

```bash
grep -n "isAppleSilicon\|requiresOSLabel\|unsupported\|Apple Silicon" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/App/MainWindow/Destinations/VoiceDestinationView.swift 2>/dev/null | head -10
grep -n "isAppleSilicon\|unsupported" /Users/mingjie.wang/Documents/personal/mac-all-you-need/MacAllYouNeed/Voice/VoiceModelCatalog.swift | head -10
```

- [ ] **Verify SenseVoice is shown as "unsupported" on Intel Macs**

The `requiresOSLabel: "Apple Silicon"` in the descriptor + the guard in `isLocalASRModelInstalled` (`.sensevoice` returns `false` when `!SystemInfo.isAppleSilicon`) should be enough. Confirm by reading how the picker uses `VoiceModelInstallState.unsupported`. If there's a separate check needed, add it.

- [ ] **Build and final check**

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
cd Shared && PKG_CONFIG_PATH="/opt/homebrew/opt/libarchive/lib/pkgconfig" swift test 2>&1 | tail -3
```

- [ ] **Commit**

```bash
git add -A
git commit -m "feat(voice): SenseVoice Small complete - non-autoregressive zh-en local ASR engine"
```

---

## Verification checklist

- [ ] Voice → Models shows "SenseVoice Small" with `~900 MB` and "Apple Silicon" label
- [ ] Download button triggers download; progress updates; model is usable after download
- [ ] Select SenseVoice → dictate 5 seconds of Chinese+English → text appears correctly
- [ ] "三百五十块" → ITN produces "350块"
- [ ] With AI cleanup on: total latency feels faster than Qwen3 for short clips
- [ ] Selecting Qwen3 again works normally (no regression)
- [ ] All existing voice tests pass
