import Foundation

public struct VoiceTrainingExportOptions: Equatable, Sendable {
    public var quality: VoiceTrainingExampleQuality
    /// When true, export every quality tier (still applies audio + duration filters).
    public var anyQuality: Bool
    public var requiresAudio: Bool
    public var minDurationMs: Int
    public var maxDurationMs: Int

    public static let `default` = VoiceTrainingExportOptions(
        quality: .high,
        anyQuality: false,
        requiresAudio: true,
        minDurationMs: 1_000,
        maxDurationMs: 30_000
    )

    public init(
        quality: VoiceTrainingExampleQuality,
        anyQuality: Bool = false,
        requiresAudio: Bool,
        minDurationMs: Int,
        maxDurationMs: Int
    ) {
        self.quality = quality
        self.anyQuality = anyQuality
        self.requiresAudio = requiresAudio
        self.minDurationMs = minDurationMs
        self.maxDurationMs = maxDurationMs
    }
}

public struct VoiceTrainingExportSummary: Equatable, Sendable {
    public let exportedCount: Int
    public let skippedCount: Int
    public let archiveURL: URL

    public init(exportedCount: Int, skippedCount: Int, archiveURL: URL) {
        self.exportedCount = exportedCount
        self.skippedCount = skippedCount
        self.archiveURL = archiveURL
    }
}

public enum VoiceTrainingExporterError: Error, Equatable {
    case noEligibleExamples
    case stagingFailed
    case archiveFailed
    case audioDecryptFailed(exampleID: String)
}

public final class VoiceTrainingExporter {
    private let store: VoiceTrainingExampleStore

    public init(store: VoiceTrainingExampleStore) {
        self.store = store
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public func export(
        to archiveURL: URL,
        options: VoiceTrainingExportOptions = .default
    ) throws -> VoiceTrainingExportSummary {
        let examples = try store.listRecent(limit: 10_000)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("mayn-voice-export-\(UUID().uuidString)", isDirectory: true)
        let audioDir = staging.appendingPathComponent("audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        let jsonlURL = staging.appendingPathComponent("data.jsonl")
        FileManager.default.createFile(atPath: jsonlURL.path, contents: nil)

        guard let jsonlHandle = FileHandle(forWritingAtPath: jsonlURL.path) else {
            throw VoiceTrainingExporterError.stagingFailed
        }

        var exported = 0
        var skipped = 0

        for example in examples {
            if !options.anyQuality, example.quality != options.quality {
                skipped += 1
                continue
            }
            guard !options.requiresAudio || example.audioPath != nil else {
                skipped += 1
                continue
            }

            let wavData: Data?
            if let audioPath = example.audioPath {
                do {
                    wavData = try store.loadEncryptedAudio(path: audioPath)
                } catch {
                    throw VoiceTrainingExporterError.audioDecryptFailed(exampleID: example.id)
                }
            } else {
                wavData = nil
            }

            if let wavData {
                let durationMs = VoiceWAVDuration.milliseconds(for: wavData) ?? 0
                guard durationMs >= options.minDurationMs, durationMs <= options.maxDurationMs else {
                    skipped += 1
                    continue
                }

                let relativeAudio = "audio/\(example.id).wav"
                let wavURL = staging.appendingPathComponent(relativeAudio)
                try wavData.write(to: wavURL, options: .atomic)

                let line = try exportLine(
                    for: example,
                    audioPath: relativeAudio,
                    durationMs: durationMs
                )
                try jsonlHandle.write(contentsOf: line)
                exported += 1
            } else {
                skipped += 1
            }
        }

        guard exported > 0 else {
            throw VoiceTrainingExporterError.noEligibleExamples
        }

        try jsonlHandle.close()
        try createTarGz(sourceDirectory: staging, destination: archiveURL)
        try? FileManager.default.removeItem(at: staging)

        return VoiceTrainingExportSummary(
            exportedCount: exported,
            skippedCount: skipped,
            archiveURL: archiveURL
        )
    }

    private func exportLine(
        for example: VoiceTrainingExample,
        audioPath: String,
        durationMs: Int
    ) throws -> Data {
        let payload: [String: Any] = [
            "id": example.id,
            "transcript_id": example.transcriptID,
            "audio_path": audioPath,
            "raw_text": example.rawText,
            "cleaned_text": example.cleanedText,
            "user_edited_text": example.finalText,
            "was_edited": example.wasEdited,
            "language": example.language.rawValue,
            "asr_model_id": example.modelIdentifier,
            "source_app": example.appBundleID as Any,
            "quality": example.quality.rawValue,
            "quality_reason": example.qualityReason as Any,
            "duration_ms": durationMs,
            "created_at": Self.isoFormatter.string(from: example.createdAt)
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var line = data
        line.append(Data([0x0A]))
        return line
    }

    private func createTarGz(sourceDirectory: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", destination.path, "-C", sourceDirectory.path, "data.jsonl", "audio"]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VoiceTrainingExporterError.archiveFailed
        }
    }
}

enum VoiceWAVDuration {
    static func milliseconds(for data: Data) -> Int? {
        guard data.count >= 44 else { return nil }
        guard let riff = String(data: data[0 ..< 4], encoding: .ascii), riff == "RIFF" else { return nil }
        let byteRate = data.withUnsafeBytes { raw -> UInt32 in
            raw.load(fromByteOffset: 28, as: UInt32.self)
        }
        guard byteRate > 0 else { return nil }
        let dataSize = data.withUnsafeBytes { raw -> UInt32 in
            raw.load(fromByteOffset: 40, as: UInt32.self)
        }
        let seconds = Double(dataSize) / Double(byteRate)
        return Int((seconds * 1000).rounded())
    }
}
