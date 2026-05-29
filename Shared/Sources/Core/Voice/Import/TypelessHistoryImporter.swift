import Foundation

public struct TypelessHistoryImporter: Sendable {
    public let reader: TypelessHistoryReader
    public let transcriptStore: VoiceTranscriptStore
    public let trainingExampleStore: VoiceTrainingExampleStore
    public let recordingsRoot: URL
    public let audioConverter: TypelessAudioConverting?
    public let log: (@Sendable (String) -> Void)?

    public init(
        reader: TypelessHistoryReader,
        transcriptStore: VoiceTranscriptStore,
        trainingExampleStore: VoiceTrainingExampleStore,
        recordingsRoot: URL,
        audioConverter: TypelessAudioConverting?,
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.reader = reader
        self.transcriptStore = transcriptStore
        self.trainingExampleStore = trainingExampleStore
        self.recordingsRoot = recordingsRoot
        self.audioConverter = audioConverter
        self.log = log
    }

    public func importAll(options: TypelessImportOptions = .init()) throws -> TypelessImportReport {
        var report = TypelessImportReport()
        var records = try reader.loadRecords()
        if let limit = options.limit, limit > 0 {
            records = Array(records.prefix(limit))
        }
        report.scanned = records.count

        for (index, record) in records.enumerated() {
            if (index + 1).isMultiple(of: options.progressInterval) {
                self.log?("Progress: \(index + 1)/\(records.count)")
            }

            if try transcriptStore.fetch(id: record.id) != nil {
                report.skippedExisting += 1
                continue
            }

            if options.dryRun {
                report.imported += 1
                continue
            }

            let language = TypelessLanguageMapper.map(
                detectedLanguage: record.detectedLanguage,
                languagesJSON: record.languagesJSON
            )

            var audioPath: String?
            if !options.skipAudio, let converter = audioConverter, let oggURL = record.resolvedAudioURL(recordingsRoot: recordingsRoot) {
                do {
                    let wavData = try converter.convertOGGToWAV(oggURL: oggURL)
                    audioPath = try trainingExampleStore.saveEncryptedAudio(wavData, id: record.id)
                    report.audioImported += 1
                } catch {
                    report.audioFailed += 1
                    report.errors.append("audio \(record.id): \(error)")
                }
            }

            let draft = VoiceTranscriptDraft(
                startedAt: record.createdAt,
                endedAt: record.endedAt,
                rawText: record.refinedText,
                cleanedText: record.refinedText,
                appBundleID: normalizedBundleID(record.appBundleID),
                language: language,
                modelIdentifier: TypelessLanguageMapper.typelessImportModelIdentifier,
                audioPath: audioPath
            )

            do {
                _ = try transcriptStore.save(draft, existingID: record.id)
                try trainingExampleStore.save(.init(
                    transcriptID: record.id,
                    rawText: record.refinedText,
                    cleanedText: record.refinedText,
                    finalText: record.finalText,
                    appBundleID: draft.appBundleID,
                    language: language,
                    modelIdentifier: TypelessLanguageMapper.typelessImportModelIdentifier,
                    audioPath: audioPath,
                    quality: .medium,
                    qualityReason: "typeless_import"
                ))
                report.imported += 1
            } catch {
                report.errors.append("save \(record.id): \(error)")
                if let audioPath {
                    try? FileManager.default.removeItem(atPath: audioPath)
                }
            }
        }

        return report
    }

    private func normalizedBundleID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
