import Core
import Foundation
import Platform

extension AppController {
    /// Plan 03 — registers the dedicated reminder hotkey (Cmd+Shift+R). When
    /// fired it toggles a recording with the reminder intent so the spoken text
    /// is saved to Apple Reminders instead of pasted. Best-effort: a conflicting
    /// registration is logged via the coordinator and otherwise ignored.
    func registerReminderHotkey() {
        let hotkey = GlobalHotkey(descriptor: .defaultVoiceReminder) { [weak self] in
            Task { @MainActor in await self?.voiceCoordinator.toggleReminderRecording() }
        }
        try? hotkey.register()
        setReminderHotkey(hotkey)
    }

    func applyVoiceActivationSettings(_ settings: VoiceActivationSettings) throws {
        try voiceCoordinator.applyActivationSettings(settings)
        VoiceActivationSettingsStore.save(settings)
    }

    func listVoiceDictionaryEntries() -> [VoiceDictionaryEntry] {
        (try? voiceDictionaryStore.list()) ?? []
    }

    func upsertVoiceDictionaryEntry(phrase: String, replacement: String) throws {
        try voiceDictionaryStore.upsert(phrase: phrase, replacement: replacement)
    }

    func deleteVoiceDictionaryEntry(id: String) throws {
        try voiceDictionaryStore.delete(id: id)
    }

    func importVoiceDictionaryCSV(_ data: Data) throws -> VoiceDictionaryCSVImportSummary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw VoiceDictionaryCSVImportError.unsupportedEncoding
        }
        let rows = try VoiceDictionaryCSVParser.parse(text)
        var imported = 0
        for row in rows {
            try voiceDictionaryStore.upsert(phrase: row.phrase, replacement: row.replacement)
            imported += 1
        }
        return VoiceDictionaryCSVImportSummary(imported: imported)
    }

    func listRecentVoiceTranscripts(limit: Int = 20) -> [VoiceTranscript] {
        (try? voiceTranscriptStore.listRecent(limit: limit)) ?? []
    }

    func deleteVoiceTranscripts(ids: [String]) throws {
        try voiceTranscriptStore.delete(ids: ids)
    }

    func listPersonalizationContexts() -> [VoicePersonalizationContext] {
        (try? voicePersonalizationStore.listContexts()) ?? []
    }

    func upsertPersonalizationContext(_ draft: VoicePersonalizationContextDraft) throws {
        try voicePersonalizationStore.upsertContext(draft)
    }

    func deletePersonalizationContext(id: String) throws {
        try voicePersonalizationStore.deleteContext(id: id)
    }

    func clearPersonalizationData() throws {
        try voicePersonalizationStore.clearAll()
    }

    func voiceTrainingExampleCount() -> Int {
        (try? voiceTrainingExampleStore.count()) ?? 0
    }

    func clearVoiceTrainingExamples() throws {
        try voiceTrainingExampleStore.clearAll()
    }

    func listVoiceTrainingExamples(limit: Int = 200) -> [VoiceTrainingExample] {
        (try? voiceTrainingExampleStore.listRecent(limit: limit)) ?? []
    }

    func deleteVoiceTrainingExample(id: String) throws {
        try voiceTrainingExampleStore.delete(id: id)
    }

    func listPinnedExamples(contextID: String) -> [VoicePinnedExample] {
        (try? voicePersonalizationStore.listPinnedExamples(contextID: contextID)) ?? []
    }

    @discardableResult
    func addPinnedExample(_ draft: VoicePinnedExampleDraft) throws -> VoicePinnedExample {
        try voicePersonalizationStore.addPinnedExample(draft)
    }

    func updatePinnedExample(id: String, before: String, after: String, isStarred: Bool) throws {
        try voicePersonalizationStore.updatePinnedExample(
            id: id,
            before: before,
            after: after,
            isStarred: isStarred
        )
    }

    func deletePinnedExample(id: String) throws {
        try voicePersonalizationStore.deletePinnedExample(id: id)
    }

    func globalPersonalizationContextID() throws -> String {
        let draft = VoicePersonalizationContextDraft(
            bundleID: VoicePersonalizationContext.globalBundleID,
            displayName: VoicePersonalizationContext.globalDisplayName
        )
        return try voicePersonalizationStore.upsertContext(draft).id
    }

    func exportVoiceTrainingData(
        to archiveURL: URL,
        options: VoiceTrainingExportOptions = .default
    ) throws -> VoiceTrainingExportSummary {
        let exporter = VoiceTrainingExporter(store: voiceTrainingExampleStore)
        return try exporter.export(to: archiveURL, options: options)
    }

    func voicePersonalizationSettings() -> VoicePersonalizationSettings {
        VoicePersonalizationSettingsStore.load()
    }

    func applyVoicePersonalizationSettings(_ settings: VoicePersonalizationSettings) {
        VoicePersonalizationSettingsStore.save(settings)
    }

    // MARK: - ASR Settings (delegate to VoiceSettingsService)

    func voiceASRSettings() -> VoiceASRSettings {
        voiceSettings.voiceASRSettings()
    }

    func voiceGroqASRSettings() -> GroqASRSettings {
        voiceSettings.voiceGroqASRSettings()
    }

    func voiceCloudASRSettings() -> VoiceCloudASRSettings {
        voiceSettings.voiceCloudASRSettings()
    }

    func groqASRAPIKey() -> String {
        voiceSettings.groqASRAPIKey()
    }

    func cloudASRAPIKey(for providerKind: VoiceASRProviderKind) -> String {
        voiceSettings.cloudASRAPIKey(for: providerKind)
    }

    func applyVoiceASRSettings(_ settings: VoiceASRSettings) {
        voiceSettings.applyVoiceASRSettings(settings, coordinator: voiceCoordinator)
    }

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        groqSettings: GroqASRSettings,
        groqAPIKey: String
    ) throws {
        try voiceSettings.applyVoiceASRProviderSettings(
            asrSettings: asrSettings,
            groqSettings: groqSettings,
            groqAPIKey: groqAPIKey,
            coordinator: voiceCoordinator
        )
    }

    func applyVoiceASRProviderSettings(
        asrSettings: VoiceASRSettings,
        cloudSettings: VoiceCloudASRSettings,
        cloudAPIKey: String
    ) throws {
        try voiceSettings.applyVoiceASRProviderSettings(
            asrSettings: asrSettings,
            cloudSettings: cloudSettings,
            cloudAPIKey: cloudAPIKey,
            coordinator: voiceCoordinator
        )
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings, apiKey: String) throws {
        try voiceSettings.applyGroqASRSettings(settings, apiKey: apiKey)
    }

    func applyGroqASRSettings(_ settings: GroqASRSettings) {
        voiceSettings.applyGroqASRSettings(settings)
    }

    func applyCloudASRSettings(_ settings: VoiceCloudASRSettings, apiKey: String) throws {
        try voiceSettings.applyCloudASRSettings(settings, apiKey: apiKey)
    }

    func applyCloudASRSettings(_ settings: VoiceCloudASRSettings) {
        voiceSettings.applyCloudASRSettings(settings)
    }

    func testGroqASRSettings(_ settings: GroqASRSettings, apiKey: String) async -> String {
        await voiceSettings.testGroqASRSettings(settings, apiKey: apiKey)
    }

    func testCloudASRSettings(
        _ settings: VoiceCloudASRSettings,
        providerKind: VoiceASRProviderKind,
        apiKey: String
    ) async -> String {
        await voiceSettings.testCloudASRSettings(settings, providerKind: providerKind, apiKey: apiKey)
    }

    // MARK: - Cleanup Settings (delegate to VoiceSettingsService)

    func voiceCleanupSettings() -> VoiceCleanupSettings {
        voiceSettings.voiceCleanupSettings()
    }

    func voiceCleanupAPIKey(for provider: VoiceCleanupProviderKind) -> String {
        voiceSettings.voiceCleanupAPIKey(for: provider)
    }

    func applyVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) throws {
        try voiceSettings.applyVoiceCleanupSettings(settings, apiKey: apiKey, coordinator: voiceCoordinator)
    }

    func disableVoiceCleanup() {
        voiceSettings.disableVoiceCleanup(coordinator: voiceCoordinator)
    }

    func validateVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) -> String {
        voiceSettings.validateVoiceCleanupSettings(settings, apiKey: apiKey)
    }

    func testVoiceCleanupSettings(_ settings: VoiceCleanupSettings, apiKey: String) async -> String {
        await voiceSettings.testVoiceCleanupSettings(settings, apiKey: apiKey)
    }

    func listOllamaCleanupModels(settings: VoiceCleanupSettings) async throws -> [OllamaModel] {
        try await voiceSettings.listOllamaCleanupModels(settings: settings)
    }

    func pullOllamaCleanupModel(settings: VoiceCleanupSettings, model: String) async throws {
        try await voiceSettings.pullOllamaCleanupModel(settings: settings, model: model)
    }

    func deleteOllamaCleanupModel(settings: VoiceCleanupSettings, model: String) async throws {
        try await voiceSettings.deleteOllamaCleanupModel(settings: settings, model: model)
    }

    func testOllamaCleanupService(settings: VoiceCleanupSettings) async -> String {
        await voiceSettings.testOllamaCleanupService(settings: settings)
    }

    // MARK: - History

    func loadVoiceHistorySettings() -> VoiceHistorySettings {
        VoiceHistorySettings.load(from: AppGroupSettings.defaults)
    }

    func saveVoiceHistorySettings(_ settings: VoiceHistorySettings) {
        settings.save(to: AppGroupSettings.defaults)
        voiceRetentionRunner.sweepNow()
    }

    func retryVoiceTranscript(id: String) async throws -> VoiceTranscript {
        try await voiceCoordinator.retryTranscript(id: id)
    }

    func downloadVoiceAudio(transcript: VoiceTranscript, to url: URL) throws {
        guard let path = transcript.audioPath else {
            throw VoiceRetryError.audioMissing
        }
        let wav = try voiceTrainingExampleStore.loadEncryptedAudio(path: path)
        try wav.write(to: url, options: .atomic)
    }

    /// Deletes the transcript row immediately and defers audio-file deletion by 5 seconds.
    /// Returns a token whose `undo()` re-saves the row and cancels the deferred delete.
    func deleteVoiceTranscriptWithUndo(_ transcript: VoiceTranscript) -> VoiceHistoryUndoToken {
        try? voiceTranscriptStore.delete(ids: [transcript.id])

        let id = transcript.id
        let audioPath = transcript.audioPath
        let store = voiceTranscriptStore
        let trainingStore = voiceTrainingExampleStore

        // Defer audio cleanup so undo can restore the row before the file is gone.
        let cleanupTask = Task.detached {
            try? await Task.sleep(for: .seconds(5))
            guard let audioPath else { return }
            // Don't delete if training example store still references the file.
            if let paths = try? trainingStore.allAudioPaths(), paths.contains(audioPath) { return }
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        let undo: () -> Void = { [transcript, store] in
            cleanupTask.cancel()
            _ = try? store.save(
                VoiceTranscriptDraft(
                    startedAt: transcript.startedAt,
                    endedAt: transcript.endedAt,
                    rawText: transcript.rawText,
                    cleanedText: transcript.cleanedText,
                    appBundleID: transcript.appBundleID,
                    language: transcript.language,
                    modelIdentifier: transcript.modelIdentifier,
                    audioPath: transcript.audioPath,
                    status: transcript.status,
                    failedStage: transcript.failedStage,
                    failureReason: transcript.failureReason,
                    retrySourceTranscriptID: transcript.retrySourceTranscriptID
                ),
                existingID: id
            )
        }

        return VoiceHistoryUndoToken(
            message: "Transcript deleted",
            undo: undo,
            expiresAt: Date().addingTimeInterval(5)
        )
    }
}
