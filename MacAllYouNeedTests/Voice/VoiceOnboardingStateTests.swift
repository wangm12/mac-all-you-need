@testable import MacAllYouNeed
import XCTest

final class VoiceOnboardingStateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "VoiceOnboardingStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testStepOrderMatchesVoiceOnboardingSpec() {
        XCTAssertEqual(VoiceOnboardingStep.orderedCases, [
            .welcome,
            .asr,
            .llm,
            .hotkey,
            .languages,
            .tryIt,
            .done
        ])
    }

    func testLegacyMicrophoneStepMigratesToASR() {
        defaults.set("microphone", forKey: "voiceOnboardingCurrentStep")
        XCTAssertEqual(VoiceOnboardingProgressStore.load(from: defaults).currentStep, .asr)
    }

    func testProgressDefaultsToWelcomeAndIncomplete() {
        let progress = VoiceOnboardingProgressStore.load(from: defaults)

        XCTAssertEqual(progress.currentStep, .welcome)
        XCTAssertFalse(progress.isCompleted)
    }

    func testProgressPersistsCurrentStepAndCompletion() {
        VoiceOnboardingProgressStore.saveStep(.languages, to: defaults)
        XCTAssertEqual(VoiceOnboardingProgressStore.load(from: defaults).currentStep, .languages)

        VoiceOnboardingProgressStore.markCompleted(to: defaults)
        let completed = VoiceOnboardingProgressStore.load(from: defaults)

        XCTAssertEqual(completed.currentStep, .done)
        XCTAssertTrue(completed.isCompleted)
    }

    func testResetClearsProgress() {
        VoiceOnboardingProgressStore.saveStep(.hotkey, to: defaults)
        VoiceOnboardingProgressStore.markCompleted(to: defaults)

        VoiceOnboardingProgressStore.reset(in: defaults)

        XCTAssertEqual(VoiceOnboardingProgressStore.load(from: defaults), .default)
    }

    func testLanguageSelectionPersistsSelectedLanguages() {
        let selection = VoiceOnboardingLanguageSelection(selectedLanguages: [.simplifiedChinese, .english])

        VoiceOnboardingProgressStore.saveLanguageSelection(selection, to: defaults)

        XCTAssertEqual(VoiceOnboardingProgressStore.loadLanguageSelection(from: defaults), selection)
        XCTAssertEqual(selection.asrLanguageHint, .automatic)
    }

    func testAutoDetectEverythingIsAnExplicitLanguageMode() {
        let selection = VoiceOnboardingLanguageSelection(
            selectedLanguages: [],
            autoDetectEverything: true
        )

        VoiceOnboardingProgressStore.saveLanguageSelection(selection, to: defaults)

        XCTAssertEqual(VoiceOnboardingProgressStore.loadLanguageSelection(from: defaults), selection)
        XCTAssertEqual(selection.asrLanguageHint, .automatic)
    }

    func testSingleLanguageSelectionBiasesASR() {
        XCTAssertEqual(
            VoiceOnboardingLanguageSelection(selectedLanguages: [.english]).asrLanguageHint,
            .english
        )
        XCTAssertEqual(
            VoiceOnboardingLanguageSelection(selectedLanguages: [.simplifiedChinese]).asrLanguageHint,
            .chinese
        )
    }
}
