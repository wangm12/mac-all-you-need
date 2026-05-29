import Core
@testable import MacAllYouNeed
import XCTest

final class VoiceCleanupCatalogPresentationTests: XCTestCase {
    func testPickerEntriesIncludeAllProviders() {
        let ids = Set(VoiceCleanupCatalogPresentation.pickerEntries().map(\.id))
        XCTAssertEqual(ids, Set(VoiceCleanupProviderKind.allCases))
    }

    func testCloudFilterIncludesOnlyCloudProviders() {
        let entries = VoiceCleanupCatalogPresentation.pickerEntries()
        let cloud = VoiceCleanupProviderKind.allCases.filter { $0.cleanupPickerGroup == .cloud }
        let filtered = entries.filter { VoiceCleanupCatalogPresentation.matchesFilter($0, filter: .cloud) }
        XCTAssertEqual(Set(filtered.map(\.id)), Set(cloud))
        XCTAssertTrue(cloud.contains(.openAICompatible))
    }

    func testLocalFilterIncludesOnlyLocalProviders() {
        let entries = VoiceCleanupCatalogPresentation.pickerEntries()
        let local = VoiceCleanupProviderKind.allCases.filter { $0.cleanupPickerGroup == .local }
        let filtered = entries.filter { VoiceCleanupCatalogPresentation.matchesFilter($0, filter: .local) }
        XCTAssertEqual(Set(filtered.map(\.id)), Set(local))
    }

    func testCustomFilterIsEmptyWhenNoCustomProviders() {
        let entries = VoiceCleanupCatalogPresentation.pickerEntries()
        let filtered = entries.filter { VoiceCleanupCatalogPresentation.matchesFilter($0, filter: .custom) }
        XCTAssertTrue(filtered.isEmpty)
        XCTAssertFalse(VoiceCleanupCatalogPresentation.pickerFilters().contains(.custom))
    }

    func testPickerGroupOrderOmitsEmptyCustomSection() {
        XCTAssertEqual(VoiceCleanupCatalogPresentation.pickerGroupOrder(), [.cloud, .local])
    }

    func testAllFilterIncludesEveryEntry() {
        let entries = VoiceCleanupCatalogPresentation.pickerEntries()
        let filtered = entries.filter { VoiceCleanupCatalogPresentation.matchesFilter($0, filter: .all) }
        XCTAssertEqual(filtered.count, entries.count)
    }

    func testCurrentProviderReadsSettingsProvider() {
        var settings = VoiceCleanupSettings.default
        settings.provider = .groq
        XCTAssertEqual(VoiceCleanupCatalogPresentation.currentProvider(from: settings), .groq)
    }

    func testPickerIconsUseBrandAssetsForCloudProviders() {
        XCTAssertEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .anthropic }?.icon,
            .brandAsset(VoiceProviderIconPresentation.BrandAsset.anthropic)
        )
        XCTAssertEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .groq }?.icon,
            .brandAsset(VoiceProviderIconPresentation.BrandAsset.groq)
        )
        XCTAssertEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .openAICompatible }?.icon,
            .brandAsset(VoiceProviderIconPresentation.BrandAsset.openAI)
        )
        XCTAssertEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .gemini }?.icon,
            .brandAsset(VoiceProviderIconPresentation.BrandAsset.google)
        )
        XCTAssertNotEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .groq }?.icon,
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .openAICompatible }?.icon
        )
        XCTAssertNotEqual(
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .anthropic }?.icon,
            VoiceCleanupCatalogPresentation.pickerEntries().first { $0.id == .gemini }?.icon
        )
    }

    func testRowTitlesUseProviderNamesNotModelNames() {
        XCTAssertEqual(VoiceCleanupCatalogPresentation.rowTitle(for: .anthropic), "Anthropic")
        XCTAssertEqual(VoiceCleanupCatalogPresentation.rowTitle(for: .groq), "Groq")
        XCTAssertEqual(VoiceCleanupCatalogPresentation.rowTitle(for: .gemini), "Google")
        XCTAssertEqual(VoiceCleanupCatalogPresentation.rowTitle(for: .openAICompatible), "OpenAI")
        XCTAssertFalse(
            VoiceCleanupCatalogPresentation.rowTitle(for: .groq).localizedCaseInsensitiveContains("llama")
        )
    }

    // MARK: - Validation expectations (mirrors AppControllerVoice.validateVoiceCleanupSettings)

    func testGroqRequiresAPIKeyWhenCleanupEnabled() {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .groq,
            model: "llama-3.1-8b-instant",
            baseURLString: VoiceCleanupProviderKind.groq.defaultBaseURLString,
            timeoutSeconds: 7,
            latencyPolicy: .balanced2s
        )
        XCTAssertTrue(settings.provider.requiresAPIKey)
        XCTAssertEqual(validateCleanupLikeController(settings, apiKey: ""), "API key is required for Groq.")
    }

    func testGeminiRequiresAPIKeyWhenCleanupEnabled() {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .gemini,
            model: "gemini-2.5-flash",
            baseURLString: VoiceCleanupProviderKind.gemini.defaultBaseURLString,
            timeoutSeconds: 7,
            latencyPolicy: .balanced2s
        )
        XCTAssertTrue(settings.provider.requiresAPIKey)
        XCTAssertEqual(validateCleanupLikeController(settings, apiKey: " "), "API key is required for Google.")
    }

    func testOmlxDoesNotRequireAPIKey() {
        let settings = VoiceCleanupSettings(
            isEnabled: true,
            provider: .omlx,
            model: VoiceCleanupProviderKind.omlx.defaultModel,
            baseURLString: VoiceCleanupProviderKind.omlx.defaultBaseURLString,
            timeoutSeconds: 7,
            latencyPolicy: .balanced2s
        )
        XCTAssertFalse(settings.provider.requiresAPIKey)
        XCTAssertEqual(validateCleanupLikeController(settings, apiKey: ""), "Configuration is usable.")
    }

    private func validateCleanupLikeController(_ settings: VoiceCleanupSettings, apiKey: String) -> String {
        guard settings.isEnabled else {
            return "AI cleanup is disabled; local cleanup is active."
        }
        guard URL(string: settings.effectiveBaseURLString) != nil else {
            return "Base URL is invalid."
        }
        if settings.provider.requiresAPIKey, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "API key is required for \(settings.provider.label)."
        }
        if settings.effectiveModel.isEmpty {
            return "Model is required."
        }
        return "Configuration is usable."
    }
}
