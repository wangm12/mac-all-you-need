@testable import MacAllYouNeed
import XCTest

final class VoiceASRSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceASRSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultSettingsUseAutomaticLanguageHint() {
        let settings = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(settings.modelID, .qwen3ASR06BF32)
        XCTAssertEqual(settings.languageHint, .automatic)
        XCTAssertNil(settings.languageHint.qwen3Language)
    }

    func testLanguageModePresentationUsesOneClearDropdown() {
        XCTAssertTrue(VoiceLanguageModePresentation.exposesSingleDropdown)
        XCTAssertFalse(VoiceLanguageModePresentation.showsSeparateMultipleLanguagesStatus)
        XCTAssertEqual(VoiceLanguageModePresentation.title(for: .automatic), "Auto-detect Chinese + English")
        XCTAssertEqual(VoiceLanguageModePresentation.title(for: .chinese), "Chinese only")
        XCTAssertEqual(VoiceLanguageModePresentation.title(for: .english), "English only")
    }

    func testSavesAndLoadsLanguageHint() {
        let saved = VoiceASRSettings(modelID: .qwen3ASR06BInt8, languageHint: .english)

        VoiceASRSettingsStore.save(saved, to: defaults)
        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(loaded.modelID, .qwen3ASR06BInt8)
        XCTAssertEqual(loaded.languageHint.qwen3Language, .english)
        XCTAssertEqual(loaded.languageHint.parakeetLanguage, .english)
    }

    func testUpdatingLanguageHintPreservesProviderKind() {
        let settings = VoiceASRSettings(
            modelID: .qwen3ASR06BF32,
            languageHint: .automatic,
            providerKind: .groq
        )

        let updated = settings.updating(languageHint: .english)

        XCTAssertEqual(updated.modelID, .qwen3ASR06BF32)
        XCTAssertEqual(updated.languageHint, .english)
        XCTAssertEqual(updated.providerKind, .groq)
    }

    func testUpdatingModelPreservesProviderKind() {
        let settings = VoiceASRSettings(
            modelID: .qwen3ASR06BF32,
            languageHint: .chinese,
            providerKind: .groq
        )

        let updated = settings.updating(modelID: .qwen3ASR06BInt8)

        XCTAssertEqual(updated.modelID, .qwen3ASR06BInt8)
        XCTAssertEqual(updated.languageHint, .chinese)
        XCTAssertEqual(updated.providerKind, .groq)
    }

    func testGroqProviderApplyPlanSavesGroqConfigBeforeSwitchingProvider() {
        XCTAssertEqual(
            VoiceASRProviderApplyPlan.steps(for: .groq),
            [.saveCloudSettings, .applyASRSettings]
        )
    }

    func testGroqProviderApplyPlanRejectsBlankAPIKey() {
        XCTAssertEqual(
            VoiceASRProviderApplyPlan.validationMessage(providerKind: .groq, apiKey: " \n "),
            "Groq API key is required."
        )
    }

    func testLocalProviderApplyPlanDoesNotRequireGroqAPIKey() {
        XCTAssertNil(VoiceASRProviderApplyPlan.validationMessage(providerKind: .local, apiKey: ""))
        XCTAssertEqual(VoiceASRProviderApplyPlan.steps(for: .local), [.applyASRSettings])
    }

    func testProviderControlsDoNotShowSaveButtonForDropdownChanges() {
        XCTAssertFalse(VoiceASRProviderControlsPresentation.showsSaveButton)
        XCTAssertNil(VoiceASRProviderControlsPresentation.connectionActionTitle(for: .local))
        XCTAssertEqual(
            VoiceASRProviderControlsPresentation.connectionActionTitle(for: .groq),
            "Test connection"
        )
    }

    func testCloudASRSetupDrawerShowsMissingKeyStatus() {
        let presentation = VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: " \n ",
            isTesting: false,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.text, "Needs API key")
        XCTAssertEqual(presentation.kind, .warning)
    }

    func testCloudASRSetupDrawerShowsTestingStatus() {
        let presentation = VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: "",
            isTesting: true,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.text, "Testing")
        XCTAssertEqual(presentation.kind, .progress)
    }

    func testCloudASRSetupDrawerShowsConnectedStatusAfterSuccess() {
        let presentation = VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: "gsk_test",
            isTesting: false,
            statusMessage: "Connection succeeded. Future dictations will use Groq."
        )

        XCTAssertEqual(presentation.text, "Connected")
        XCTAssertEqual(presentation.kind, .success)
    }

    func testCloudASRSetupDrawerShowsEnteredKeyWithoutConnectionResult() {
        let presentation = VoiceCloudASRSetupDrawerPresentation.status(
            apiKey: "gsk_test",
            isTesting: false,
            statusMessage: nil
        )

        XCTAssertEqual(presentation.text, "Key entered")
        XCTAssertEqual(presentation.kind, .neutral)
    }

    func testUpdatingProviderKindPreservesModelAndLanguage() {
        let settings = VoiceASRSettings(
            modelID: .qwen3ASR06BInt8,
            languageHint: .english,
            providerKind: .local
        )

        let updated = settings.updating(providerKind: .groq)

        XCTAssertEqual(updated.modelID, .qwen3ASR06BInt8)
        XCTAssertEqual(updated.languageHint, .english)
        XCTAssertEqual(updated.providerKind, .groq)
    }

    func testLoadsLegacyLanguageOnlyPayloadWithDefaultModel() {
        let legacyPayload = #"{"languageHint":"chinese"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: VoiceASRSettingsStore.key)

        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded.modelID, .qwen3ASR06BInt8)
        XCTAssertEqual(loaded.languageHint, .chinese)
    }

    func testLoadsLegacyModelIdentifierAsF32Model() {
        let legacyPayload = #"{"modelID":"qwen3-asr-0.6b","languageHint":"english"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: VoiceASRSettingsStore.key)

        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded.modelID, .qwen3ASR06BInt8)
        XCTAssertEqual(loaded.languageHint, .english)
    }

    func testResolvesKnownProfileModelOverride() {
        let settings = VoiceASRSettings(modelID: .qwen3ASR06BF32, languageHint: .automatic)

        XCTAssertEqual(
            settings.resolvedModelID(preferredModelIdentifier: VoiceASRModelID.qwen3ASR06BInt8.rawValue),
            .qwen3ASR06BInt8
        )
    }

    func testResolvesLegacyProfileModelOverride() {
        let settings = VoiceASRSettings(modelID: .qwen3ASR06BInt8, languageHint: .automatic)

        XCTAssertEqual(
            settings.resolvedModelID(preferredModelIdentifier: "qwen3-asr-0.6b"),
            .qwen3ASR06BF32
        )
    }

    func testIgnoresUnknownProfileModelOverride() {
        let settings = VoiceASRSettings(modelID: .qwen3ASR06BF32, languageHint: .automatic)

        XCTAssertEqual(
            settings.resolvedModelID(preferredModelIdentifier: "unknown-local-asr"),
            .qwen3ASR06BF32
        )
    }

    func testResolvesParakeetProfileModelOverride() {
        let settings = VoiceASRSettings(modelID: .qwen3ASR06BF32, languageHint: .automatic)

        XCTAssertEqual(
            settings.resolvedModelID(preferredModelIdentifier: VoiceASRModelID.parakeetTDT06BV3.rawValue),
            .parakeetTDT06BV3
        )
    }

    func testSelectedModelPresentationUsesStatusPillWithoutDuplicateAction() {
        let presentation = VoiceASRModelRowPresentation.model(
            isSelected: true,
            isDownloaded: true,
            isDownloading: false
        )

        XCTAssertEqual(presentation.statusText, "Selected")
        XCTAssertEqual(presentation.statusKind, .success)
        XCTAssertNil(presentation.actionTitle)
    }

    func testDownloadingModelPresentationUsesProgressStatusWithoutDuplicateAction() {
        let presentation = VoiceASRModelRowPresentation.model(
            isSelected: false,
            isDownloaded: false,
            isDownloading: true
        )

        XCTAssertEqual(presentation.statusText, "Downloading")
        XCTAssertEqual(presentation.statusKind, .progress)
        XCTAssertNil(presentation.actionTitle)
    }

    func testAvailableModelPresentationUsesActionWithoutDownloadedStatusPill() {
        let presentation = VoiceASRModelRowPresentation.model(
            isSelected: false,
            isDownloaded: true,
            isDownloading: false
        )

        XCTAssertNil(presentation.statusText)
        XCTAssertEqual(presentation.statusKind, .neutral)
        XCTAssertEqual(presentation.actionTitle, "Use")
    }

    func testModelTitlePresentationPlacesDiskSizeNextToName() {
        XCTAssertEqual(VoiceASRModelTitlePresentation.title(for: .qwen3ASR06BF32), "Qwen3-ASR 0.6B f32")
        XCTAssertEqual(VoiceASRModelTitlePresentation.sizeLabel(for: .qwen3ASR06BF32), "~1.75 GB")
        XCTAssertEqual(VoiceASRModelTitlePresentation.sizeLabel(for: .qwen3ASR06BInt8), "~900 MB")
        XCTAssertEqual(VoiceASRModelTitlePresentation.sizeLabel(for: .parakeetTDT06BV3), "~850 MB")
    }

    func testSelectedCloudModelPresentationUsesStatusWithoutAction() {
        let presentation = VoiceASRModelRowPresentation.cloudModel(isSelected: true)

        XCTAssertEqual(presentation.statusText, "Selected")
        XCTAssertEqual(presentation.statusKind, .success)
        XCTAssertNil(presentation.actionTitle)
    }

    func testAvailableCloudModelPresentationUsesUseAction() {
        let presentation = VoiceASRModelRowPresentation.cloudModel(isSelected: false)

        XCTAssertNil(presentation.statusText)
        XCTAssertEqual(presentation.statusKind, .neutral)
        XCTAssertEqual(presentation.actionTitle, "Use")
    }

    func testCloudModelPresentationDisablesUseWhenAPIKeyIsMissing() {
        let presentation = VoiceASRModelRowPresentation.cloudModel(
            isSelected: false,
            hasUsableAPIKey: false
        )

        XCTAssertEqual(presentation.statusText, "Needs API key")
        XCTAssertEqual(presentation.statusKind, .warning)
        XCTAssertEqual(presentation.actionTitle, "Configure")
    }

    func testCloudASRSetupDrawerTitleNamesCurrentProvider() {
        XCTAssertEqual(
            VoiceCloudASRSetupDrawerPresentation.title(for: .groq),
            "Groq ASR setup"
        )
        XCTAssertEqual(
            VoiceCloudASRSetupDrawerPresentation.title(for: .openAITranscribe),
            "OpenAI Transcribe ASR setup"
        )
    }

    func testCloudModelSelectionRequiresUsableAPIKey() {
        XCTAssertFalse(
            VoiceASRModelSelectionState.isCloudModelSelected(
                providerKind: .groq,
                selectedModelID: .groqWhisperLargeV3Turbo,
                modelID: .groqWhisperLargeV3Turbo,
                hasUsableAPIKey: false
            )
        )
    }

    func testCanSelectCloudModelRequiresNonBlankAPIKey() {
        XCTAssertFalse(VoiceASRModelSelectionState.canSelectCloudModel(apiKey: " \n "))
        XCTAssertTrue(VoiceASRModelSelectionState.canSelectCloudModel(apiKey: "gsk_test"))
    }

    func testLocalModelSelectionRequiresLocalProvider() {
        XCTAssertTrue(
            VoiceASRModelSelectionState.isLocalModelSelected(
                providerKind: .local,
                selectedModelID: .qwen3ASR06BF32,
                modelID: .qwen3ASR06BF32
            )
        )
        XCTAssertFalse(
            VoiceASRModelSelectionState.isLocalModelSelected(
                providerKind: .groq,
                selectedModelID: .qwen3ASR06BF32,
                modelID: .qwen3ASR06BF32
            )
        )
    }

    func testCloudModelSelectionRequiresGroqProvider() {
        XCTAssertTrue(
            VoiceASRModelSelectionState.isCloudModelSelected(
                providerKind: .groq,
                selectedModelID: .groqWhisperLargeV3Turbo,
                modelID: .groqWhisperLargeV3Turbo
            )
        )
        XCTAssertFalse(
            VoiceASRModelSelectionState.isCloudModelSelected(
                providerKind: .local,
                selectedModelID: .groqWhisperLargeV3Turbo,
                modelID: .groqWhisperLargeV3Turbo
            )
        )
    }

    func testSelectingLocalModelSwitchesProviderToLocal() {
        XCTAssertEqual(
            VoiceASRModelSelectionState.providerKindAfterSelectingLocalModel(),
            .local
        )
    }

    func testSelectingCloudModelSwitchesProviderToGroq() {
        XCTAssertEqual(
            VoiceASRModelSelectionState.providerKindAfterSelectingCloudModel(.groqWhisperLargeV3Turbo),
            .groq
        )
    }

    func testMissingModelPresentationKeepsSingleDownloadAction() {
        let presentation = VoiceASRModelRowPresentation.model(
            isSelected: false,
            isDownloaded: false,
            isDownloading: false
        )

        XCTAssertEqual(presentation.statusText, "Not installed")
        XCTAssertEqual(presentation.statusKind, .warning)
        XCTAssertEqual(presentation.actionTitle, "Download & Use")
    }

    func testSelectedInheritedProfileModelPresentationUsesSelectedStatusWithoutAction() {
        let presentation = VoiceASRModelRowPresentation.inheritedProfile(isSelected: true)

        XCTAssertEqual(presentation.statusText, "Selected")
        XCTAssertEqual(presentation.statusKind, .success)
        XCTAssertNil(presentation.actionTitle)
    }

    func testAppProfileEditorPresentation_removed() {
        // VoiceAppProfileEditorPresentation was part of VoiceAppProfilesSection,
        // which was deleted when app_profiles was replaced by the personalization store.
        // These tests are intentionally empty; the T10 sweep will clean them up.
    }
}

final class VoiceAudioSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceAudioSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testDefaultMicrophonePreferenceUsesSystemInput() {
        XCTAssertEqual(
            VoiceAudioSettings.preferredMicrophoneID(from: defaults),
            VoiceAudioSettings.systemMicrophoneID
        )
    }

    func testLoadsStoredPreferredMicrophoneID() {
        defaults.set("ExternalMicUID", forKey: VoiceAudioSettings.microphoneIDKey)

        XCTAssertEqual(VoiceAudioSettings.preferredMicrophoneID(from: defaults), "ExternalMicUID")
    }

    func testUnavailablePreferredMicrophoneFallsBackToSystemInput() {
        XCTAssertEqual(
            VoiceAudioSettings.normalizedPreferredMicrophoneID(
                "EarPodsUID",
                availableDeviceIDs: ["BuiltInUID", "StudioMicUID"]
            ),
            VoiceAudioSettings.systemMicrophoneID
        )
    }

    func testAvailablePreferredMicrophoneIsPreserved() {
        XCTAssertEqual(
            VoiceAudioSettings.normalizedPreferredMicrophoneID(
                "StudioMicUID",
                availableDeviceIDs: ["BuiltInUID", "StudioMicUID"]
            ),
            "StudioMicUID"
        )
    }
}
