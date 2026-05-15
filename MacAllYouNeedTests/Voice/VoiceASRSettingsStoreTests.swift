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
    }

    func testLoadsLegacyLanguageOnlyPayloadWithDefaultModel() throws {
        let legacyPayload = #"{"languageHint":"chinese"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: VoiceASRSettingsStore.key)

        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded.modelID, .qwen3ASR06BF32)
        XCTAssertEqual(loaded.languageHint, .chinese)
    }

    func testLoadsLegacyModelIdentifierAsF32Model() throws {
        let legacyPayload = #"{"modelID":"qwen3-asr-0.6b","languageHint":"english"}"#.data(using: .utf8)!
        defaults.set(legacyPayload, forKey: VoiceASRSettingsStore.key)

        let loaded = VoiceASRSettingsStore.load(from: defaults)

        XCTAssertEqual(loaded.modelID, .qwen3ASR06BF32)
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
            settings.resolvedModelID(preferredModelIdentifier: "parakeet-tdt-v3"),
            .qwen3ASR06BF32
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

    func testAppProfileEditorExplainsAppSpecificOverrides() {
        XCTAssertEqual(
            VoiceAppProfileEditorPresentation.sectionSubtitle,
            "Use app-specific overrides only when an app needs different voice behavior."
        )
        XCTAssertEqual(
            VoiceAppProfileEditorPresentation.modelSubtitle,
            "Usually Inherit. Override only when this app needs a different accuracy or memory tradeoff."
        )
    }

    func testAppProfileModelPickerUsesCompactInheritAndKnownModelOptions() {
        XCTAssertEqual(
            VoiceAppProfileEditorPresentation.modelOptions,
            [
                "inherit",
                VoiceASRModelID.qwen3ASR06BF32.rawValue,
                VoiceASRModelID.qwen3ASR06BInt8.rawValue
            ]
        )
        XCTAssertEqual(VoiceAppProfileEditorPresentation.modelTitle("inherit"), "Inherit global model")
        XCTAssertEqual(
            VoiceAppProfileEditorPresentation.modelTitle(VoiceASRModelID.qwen3ASR06BF32.rawValue),
            "Qwen3-ASR 0.6B f32"
        )
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
