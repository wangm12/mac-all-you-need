@testable import MacAllYouNeed
import XCTest

final class VoiceModelCatalogTests: XCTestCase {
    func testLocalASRCatalogContainsQwenModelsWithStableRuntimeIDs() {
        let descriptors = VoiceModelCatalog.localASRModels

        XCTAssertEqual(
            descriptors.map(\.id),
            [
                "qwenCoreML.qwen3-asr-0.6b-f32",
                "qwenCoreML.qwen3-asr-0.6b-int8",
                "parakeetCoreML.parakeet-tdt-0.6b-v3",
                "whisperKit.whisper-large-v3-turbo",
                "mlxExperimental.qwen3-asr-1.7b"
            ]
        )
        XCTAssertEqual(
            descriptors.map(\.runtime),
            [.qwenCoreML, .qwenCoreML, .parakeetCoreML, .whisperKit, .mlxExperimental]
        )
        XCTAssertEqual(
            descriptors.compactMap(\.localASRModelID),
            [.qwen3ASR06BF32, .qwen3ASR06BInt8, .parakeetTDT06BV3]
        )
    }

    func testFutureLocalASRRuntimeDescriptorsAreUnsupportedUntilAdaptersExist() {
        let futureDescriptors = VoiceModelCatalog.localASRModels.filter { $0.localASRModelID == nil }

        XCTAssertEqual(futureDescriptors.map(\.runtime), [.whisperKit, .mlxExperimental])
        for descriptor in futureDescriptors {
            let state = VoiceModelManager.localASRInstallState(
                descriptor: descriptor,
                selectedModelID: .qwen3ASR06BF32,
                providerKind: .local,
                installedModelIDs: [.qwen3ASR06BF32],
                downloadingModelID: nil,
                failureReason: nil
            )

            XCTAssertEqual(state, .unsupported)
        }
    }

    func testCloudASRCatalogContainsBYOKAdaptersWithStableRuntimeIDs() {
        let descriptors = VoiceModelCatalog.cloudASRModels

        XCTAssertEqual(
            descriptors.map(\.id),
            [
                "groq.whisper-large-v3-turbo",
                "groq.whisper-large-v3",
                "elevenLabs.scribe_v2",
                "openAITranscribe.gpt-4o-transcribe",
                "deepgram.nova-3"
            ]
        )
        XCTAssertEqual(
            descriptors.map(\.runtime),
            [.groq, .groq, .elevenLabs, .openAITranscribe, .deepgram]
        )
        XCTAssertEqual(
            descriptors.compactMap(\.cloudASRModelID),
            [
                .groqWhisperLargeV3Turbo,
                .groqWhisperLargeV3,
                .elevenLabsScribeV2,
                .openAIGPT4oTranscribe,
                .deepgramNova3
            ]
        )
    }

    func testInstallStateMarksSelectedInstalledAndMissingModels() {
        let state = VoiceModelManager.localASRInstallState(
            modelID: .qwen3ASR06BF32,
            selectedModelID: .qwen3ASR06BF32,
            providerKind: .local,
            installedModelIDs: [.qwen3ASR06BF32],
            downloadingModelID: nil,
            failureReason: nil
        )

        XCTAssertEqual(state, .selected)

        let missing = VoiceModelManager.localASRInstallState(
            modelID: .qwen3ASR06BInt8,
            selectedModelID: .qwen3ASR06BF32,
            providerKind: .local,
            installedModelIDs: [.qwen3ASR06BF32],
            downloadingModelID: nil,
            failureReason: nil
        )

        XCTAssertEqual(missing, .notInstalled)
    }

    func testParakeetRuntimeIsSelectableWhenInstalled() {
        let state = VoiceModelManager.localASRInstallState(
            modelID: .parakeetTDT06BV3,
            selectedModelID: .parakeetTDT06BV3,
            providerKind: .local,
            installedModelIDs: [.parakeetTDT06BV3],
            downloadingModelID: nil,
            failureReason: nil
        )

        XCTAssertEqual(state, .selected)
        XCTAssertEqual(VoiceASRModelID.parakeetTDT06BV3.runtime, .parakeetCoreML)
        if case .v3? = VoiceASRModelID.parakeetTDT06BV3.parakeetVersion {
        } else {
            XCTFail("Parakeet local model should use FluidAudio v3.")
        }
        XCTAssertNil(VoiceASRModelID.parakeetTDT06BV3.qwen3Variant)
    }

    func testDeletingSelectedModelFallsBackToFirstInstalledRecommendation() {
        let fallback = VoiceModelManager.fallbackLocalASRModel(
            afterDeleting: .qwen3ASR06BF32,
            selectedModelID: .qwen3ASR06BF32,
            installedModelIDsAfterDelete: [.qwen3ASR06BInt8]
        )

        XCTAssertEqual(fallback, .qwen3ASR06BInt8)
    }
}
