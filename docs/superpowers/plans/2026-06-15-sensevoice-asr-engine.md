# SenseVoice Small ASR Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SenseVoice Small as a fourth local ASR option in the Voice → Models picker — non-autoregressive, batch, ~900 MB, zh-en, downloadable on demand.

**Architecture:** `SenseVoiceEngine` actor uses `MLXAudioSTT.SenseVoiceModel.fromDirectory(url)` for model loading and `model.generate(audio:language:useITN:verbose:)` for inference. Model files are downloaded from HuggingFace `mlx-community/SenseVoiceSmall` via a new `SenseVoiceModels` helper that mirrors the `Qwen3AsrModels`/`AsrModels` pattern. Routing goes through the existing `VoiceLocalASREngine` switch on `VoiceASRModelID.runtime`.

**Tech Stack:** Swift, mlx-audio-swift (revision `a1c7b11`, `hehehai/mlx-audio-swift`), MLXAudioCore, MLXAudioSTT, existing DownloadUtils, existing VoiceModelCatalog pattern.

---

## File Map

| Action | File | What changes |
|---|---|---|
| **Add dep** | `project.yml` → `MacAllYouNeed.xcodeproj/project.pbxproj` (via xcodegen) | mlx-audio-swift package (`MLXAudioCore` + `MLXAudioSTT`) **plus the `MLX` product from mlx-swift** (the engine does `import MLX` for `MLXArray`) |
| **Create** | `MacAllYouNeed/Voice/ASR/SenseVoiceEngine.swift` | Actor: load model, transcribe, warmup |
| **Create** | `MacAllYouNeed/Voice/ASR/SenseVoiceModels.swift` | Download (4 verified files), cache dir, install check |
| **Modify** | `MacAllYouNeed/Voice/ASR/VoiceASRSettings.swift` | Add `senseVoiceSmall` case to `VoiceASRModelID`; fill **every** exhaustive switch: `runtime`, `title`, `subtitle`, `strengths`, `tradeoffs`, `diskLabel`, `requiresOSLabel`, `qwen3Variant` (nil), `parakeetVersion` (nil) |
| **Modify** | `MacAllYouNeed/Voice/VoiceModelCatalog.swift` | Add `sensevoice` to `VoiceModelRuntime`; add descriptor to `VoiceModelCatalog.localASRModels`; update `VoiceModelManager.{recommendedLocalASROrder, isLocalASRModelInstalled, localASRCacheDirectory, downloadLocalASRModel}` (note: these live in `enum VoiceModelManager`, not `VoiceModelCatalog`) |
| **Modify** | `MacAllYouNeed/Voice/ASR/VoiceLocalASREngine.swift` | Add `SenseVoiceEngine` instance; route `.sensevoice` in transcribe/warmup/capabilities |
| **Modify** | All exhaustive switches on `VoiceASRModelID` / `VoiceModelRuntime` | Compiler flags each one — add `.senseVoiceSmall` / `.sensevoice` |

---

## Task 1: Add mlx-audio-swift SPM dependency

**Files:**
- Modify: `project.yml` (xcodegen source)

> **Dependency-weight risk (read before starting).** `MLXAudioCore` pulls in a
> full MLX stack transitively: `mlx-swift`, `mlx-swift-lm`, `swift-transformers`,
> and `swift-huggingface`. Today this app's local ASR (Qwen3 / Parakeet) runs on
> FluidAudio's **CoreML** path; this adds a second, independent ML runtime
> (hundreds of MB of frameworks, longer clean builds, larger app, possible MLX
> version pins). Confirm this trade-off is acceptable before proceeding — it is
> the single biggest cost of this feature.

- [ ] **Check the project.yml for how existing SPM packages are declared**

```bash
grep -A5 "FluidAudio\|packages:" /Users/mingjie.wang/Documents/personal/mac-all-you-need/project.yml | head -30
```

- [ ] **Add the packages to project.yml**

The engine does `import MLX` (for `MLXArray`), so the `MLX` product must be a
**direct** dependency of the target — relying on it being transitively visible
through `MLXAudioCore` is fragile in SPM/Xcode. Declare `mlx-swift` explicitly.

In `project.yml`, under the `MacAllYouNeed` target `dependencies:` add:

```yaml
- package: mlx-audio-swift
  product: MLXAudioCore
- package: mlx-audio-swift
  product: MLXAudioSTT
- package: mlx-swift
  product: MLX
```

And in the top-level `packages:` section add:

```yaml
mlx-audio-swift:
  url: https://github.com/hehehai/mlx-audio-swift
  revision: a1c7b11b68b16f1591bb0ff586372dde9b265135
mlx-swift:
  url: https://github.com/ml-explore/mlx-swift
  # Pin to whatever version mlx-audio-swift@a1c7b11 resolves to (read its
  # Package.resolved after the first `xcodegen generate` + resolve, then pin
  # the exact version here to keep builds reproducible).
```

> If, after building, `import MLX` resolves cleanly via the transitive
> `MLXAudioCore` dependency on your toolchain, the explicit `mlx-swift` entry can
> be dropped. Keep it if you see "No such module 'MLX'".

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
# The resolved file for the app-target packages lives inside the xcodeproj,
# not Shared/. Add whatever xcodegen + the resolve actually touched:
git add project.yml MacAllYouNeed.xcodeproj
git add MacAllYouNeed.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null || true
git commit -m "feat(voice): add mlx-audio-swift dependency for SenseVoice"
```

---

## Task 2: SenseVoiceModels helper (download + install check)

**Files:**
- Create: `MacAllYouNeed/Voice/ASR/SenseVoiceModels.swift`

This mirrors the role of FluidAudio's `Qwen3AsrModels` / `AsrModels` (which live in
the FluidAudio package, not in this repo). It knows:
1. Where to store model files on disk
2. Which files must be present for "installed" to return true
3. How to download from HuggingFace

> **VERIFIED against the real repo (`mlx-community/SenseVoiceSmall`).** The repo
> contains exactly four content files: `config.json`, `model.safetensors`,
> `am.mvn`, `chn_jpn_yue_eng_ko_spectok.bpe.model`. There is **no** `tokenizer.json`
> / `tokenizer_config.json` / `special_tokens_map.json`. `SenseVoiceModel.fromDirectory`
> reads `am.mvn` (CMVN normalization) and the `.bpe.model` tokenizer from the
> directory, so all four files are mandatory.

> **VERIFIED:** FluidAudio's `DownloadUtils` has **no** `downloadFile(from:to:)`
> method. Its public surface is `downloadRepo` / `downloadSubdirectory` /
> `fetchHuggingFaceFile`, all coupled to FluidAudio's own `Repo` registry, so we
> cannot reuse it for an arbitrary HF repo. We therefore stream the four files
> ourselves with `URLSession`, while still emitting the shared
> `DownloadUtils.ProgressHandler` / `DownloadUtils.DownloadProgress` type so the
> catalog and UI progress plumbing is unchanged.

- [ ] **Create SenseVoiceModels.swift**

```swift
import FluidAudio
import Foundation

/// Manages the on-disk lifecycle of the SenseVoice Small MLX model.
/// Model source: https://huggingface.co/mlx-community/SenseVoiceSmall
enum SenseVoiceModels {
    static let huggingFaceRepo = "mlx-community/SenseVoiceSmall"

    /// Files that must all be present for the model to be usable.
    /// Verified against the actual HuggingFace repo contents.
    static let requiredFiles = [
        "config.json",
        "model.safetensors",
        "am.mvn",
        "chn_jpn_yue_eng_ko_spectok.bpe.model",
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
        let total = requiredFiles.count
        for (index, file) in requiredFiles.enumerated() {
            let destination = directory.appendingPathComponent(file)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                continue
            }
            let fileURL = baseURL
                .appendingPathComponent(huggingFaceRepo)
                .appendingPathComponent("resolve/main")
                .appendingPathComponent(file)

            // Download to a temp URL, then move into place so a partial
            // download never satisfies modelsExist(at:).
            let (tempURL, response) = try await URLSession.shared.download(from: fileURL)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode)
            {
                throw URLError(.badServerResponse)
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            progressHandler?(
                DownloadUtils.DownloadProgress(
                    fractionCompleted: Double(index + 1) / Double(total),
                    phase: .downloading(completedFiles: index + 1, totalFiles: total)
                )
            )
        }
        return directory
    }
}
```

> Per-file fraction (not byte-level) progress is intentional — it keeps the
> helper dependency-free and is enough for a four-file download. If byte-level
> progress is later wanted, swap `URLSession.shared.download` for a
> `URLSessionDownloadDelegate`.

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

- [ ] **(Optional) Re-confirm the MLXAudioSTT API at the pinned revision**

The signatures below are **verified** against `hehehai/mlx-audio-swift` at revision
`a1c7b11` (`Sources/MLXAudioSTT/Models/SenseVoice/SenseVoiceModel.swift`). If you
bump the revision, re-check them:

```bash
grep -rn "func generate\|static func fromDirectory\|struct STTOutput\|var text\|var language" \
  ~/Library/Developer/Xcode/DerivedData/MacAllYouNeed*/SourcePackages/checkouts/mlx-audio-swift/Sources/MLXAudioSTT/Models/SenseVoice 2>/dev/null | head -20
```

Confirmed facts (do not change unless the revision changes):
- `public static func fromDirectory(_ modelDirectory: URL) throws -> SenseVoiceModel`
- `public func generate(audio: MLXArray, language: String = "auto", useITN: Bool = false, verbose: Bool = false) -> STTOutput`
  — **`language` is a non-optional `String` (default `"auto"`); passing `nil` does not compile.**
- `STTOutput.text: String` and `STTOutput.language: String?`
- `generate` takes an `MLXArray`, which lives in the `MLX` module → **`import MLX` is required.**

- [ ] **Create SenseVoiceEngine.swift with the confirmed API**

```swift
import Core
import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import OSLog

private let senseVoiceLog = Logger(
    subsystem: "com.macallyouneed.voice",
    category: "sensevoice"
)

/// Non-autoregressive CTC ASR engine using SenseVoice Small via mlx-audio-swift.
/// Batch-only: no live streaming session.
actor SenseVoiceEngine: VoiceTranscriptionEngine {

    private var model: SenseVoiceModel?

    nonisolated var modelIdentifier: String { "sense-voice-small" }

    nonisolated var capabilities: VoiceASRCapabilities { .batchOnly }

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
            language: "auto",  // auto-detect language
            useITN: true,      // normalize numbers/dates
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

> `capabilities` uses `.batchOnly` to match `ParakeetEngine` (SenseVoice has no
> live streaming path). `VoiceLocalASREngine.makeLiveSession` already throws
> `unsupportedEngine` for any non-Qwen runtime via its `default:` branch, so no
> change is needed there for batch-only SenseVoice.

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
    "Non-autoregressive CTC model for Chinese & English. Fast batch transcription; no live streaming."
```

- [ ] **Add `strengths` for the new case** (non-optional `String`):

```swift
case .senseVoiceSmall:
    "Single-pass CTC decoding (no beam search / repetition), small resident footprint, strong mixed zh/en."
```

- [ ] **Add `tradeoffs` for the new case** (non-optional `String`):

```swift
case .senseVoiceSmall:
    "Batch only — no live partials. Requires Apple Silicon (MLX). Different ML runtime from the CoreML models."
```

- [ ] **Add `diskLabel` for the new case**:

```swift
case .senseVoiceSmall:
    "~900 MB"
```

- [ ] **Add `requiresOSLabel` for the new case** (non-optional `String`):

```swift
case .senseVoiceSmall:
    "Apple Silicon"
```

- [ ] **Fix all remaining exhaustive switch errors on VoiceASRModelID** — build to find them:

```bash
xcodebuild build -project MacAllYouNeed.xcodeproj -scheme MacAllYouNeed -destination 'platform=macOS,arch=arm64' 2>&1 | grep "error:" | head -20
```

`VoiceASRModelID` has these exhaustive switches: `title`, `subtitle`, `strengths`,
`tradeoffs`, `diskLabel`, `runtime`, `qwen3Variant`, `parakeetVersion`,
`requiresOSLabel`. The only ones that may return `nil` are the **optional**
`qwen3Variant: Qwen3AsrVariant?` and `parakeetVersion: AsrModelVersion?`. The
`strengths` / `tradeoffs` / `requiresOSLabel` properties are **non-optional
`String`** and must have real copy (added above) — `nil` will not compile.

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

> This file contains **two** enums. The descriptor list lives in
> `enum VoiceModelCatalog`; everything else below (`recommendedLocalASROrder`,
> `isLocalASRModelInstalled`, `localASRCacheDirectory`, `downloadLocalASRModel`)
> lives in `enum VoiceModelManager`. `deleteLocalASRModel` is generic (uses
> `localASRCacheDirectory`) and needs no SenseVoice-specific change.

- [ ] **Add SenseVoice to `VoiceModelCatalog.localASRModels` array**

Add after the Parakeet entry:

```swift
VoiceModelDescriptor(
    id: "sensevoice.sense-voice-small",
    category: .localASR,
    runtime: .sensevoice,
    title: "SenseVoice Small",
    subtitle: "Non-autoregressive CTC zh/en model. Fast single-pass batch transcription; pairs well with AI cleanup.",
    diskLabel: "~900 MB",
    requiresOSLabel: "Apple Silicon",
    localASRModelID: .senseVoiceSmall,
    cloudASRModelID: nil,
    groqASRModelID: nil
),
```

- [ ] **Add SenseVoice to `VoiceModelManager.recommendedLocalASROrder`**

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
