import AppKit
import Core
import CryptoKit
import Foundation

enum VoiceTrainingExportCLIError: Error, CustomStringConvertible {
    case appStillRunning
    case fallbackContainer(URL)
    case exportFailed(String)

    var description: String {
        switch self {
        case .appStillRunning:
            "Mac All You Need is still running. Quit the app (Cmd+Q) before exporting to avoid database locks."
        case .fallbackContainer(let url):
            "Not using App Group container: \(url.path). Pass --mayn-container explicitly."
        case .exportFailed(let message):
            message
        }
    }
}

struct VoiceTrainingExportCLIConfiguration {
    var maynContainer: URL
    var output: URL
    var quality: VoiceTrainingExampleQuality
    var anyQuality: Bool
    var statsOnly: Bool
}

@main
enum VoiceTrainingExportMain {
    static func main() {
        do {
            try run()
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let config = try parseArguments()
        if ProcessInfo.processInfo.environment["MAYN_ALLOW_RUNNING_APP"] != "1" {
            if MAYNToolHarness.isMAYNRunning() {
                throw VoiceTrainingExportCLIError.appStillRunning
            }
        }

        AppGroup.containerURLOverride = config.maynContainer
        do {
            try MAYNToolHarness.validateMAYNContainer(config.maynContainer)
        } catch {
            throw VoiceTrainingExportCLIError.fallbackContainer(config.maynContainer)
        }

        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let clipboardURL = config.maynContainer.appendingPathComponent("databases/clipboard.sqlite")
        let db = try Database(url: clipboardURL, migrations: ClipboardStore.migrations)
        let store = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: config.maynContainer.appendingPathComponent("voice-training-audio", isDirectory: true)
        )

        let examples = try store.listRecent(limit: 20_000)
        let withAudio = examples.filter { $0.audioPath != nil }
        let high = examples.filter { $0.quality == .high }
        let medium = examples.filter { $0.quality == .medium }
        let highWithAudio = high.filter { $0.audioPath != nil }

        fputs(
            """
            Voice training corpus
              container: \(config.maynContainer.path)
              training rows: \(examples.count)
              with audio: \(withAudio.count)
              quality high: \(high.count) (with audio: \(highWithAudio.count))
              quality medium: \(medium.count)
              transcripts (table): \(try transcriptCount(db: db))

            """,
            stderr
        )

        if config.statsOnly {
            return
        }

        let exportOptions = VoiceTrainingExportOptions(
            quality: config.quality,
            anyQuality: config.anyQuality,
            requiresAudio: true,
            minDurationMs: 1_000,
            maxDurationMs: 30_000
        )

        do {
            let summary = try VoiceTrainingExporter(store: store).export(to: config.output, options: exportOptions)
            print("Exported \(summary.exportedCount) examples to \(summary.archiveURL.path) (skipped \(summary.skippedCount))")
        } catch VoiceTrainingExporterError.noEligibleExamples {
            if config.quality == .high, highWithAudio.isEmpty, !withAudio.isEmpty {
                throw VoiceTrainingExportCLIError.exportFailed(
                    "No high-quality rows with valid audio. Try: --quality medium or enable post-edit verification, or --include-medium."
                )
            }
            throw VoiceTrainingExportCLIError.exportFailed("No rows matched export filter (quality=\(exportOptions.quality), audio, 1–30s).")
        }
    }

    private static func transcriptCount(db: Database) throws -> Int {
        try db.queue.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM voice_transcripts") ?? 0
        }
    }

    private static func parseArguments() throws -> VoiceTrainingExportCLIConfiguration {
        var maynContainer = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Group Containers/group.com.macallyouneed.shared", isDirectory: true)
        var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mayn-voice-training-export.tar.gz")
        var quality: VoiceTrainingExampleQuality = .high
        var anyQuality = false
        var statsOnly = false

        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--mayn-container":
                guard let path = iterator.next() else { throw VoiceTrainingExportCLIError.exportFailed("Missing value for --mayn-container") }
                maynContainer = MAYNToolHarness.expandPath(path, isDirectory: true)
            case "--output", "-o":
                guard let path = iterator.next() else { throw VoiceTrainingExportCLIError.exportFailed("Missing value for --output") }
                output = MAYNToolHarness.expandPath(path)
            case "--quality":
                guard let raw = iterator.next() else { throw VoiceTrainingExportCLIError.exportFailed("Missing value for --quality") }
                guard let q = VoiceTrainingExampleQuality(rawValue: raw) else {
                    throw VoiceTrainingExportCLIError.exportFailed("Unknown quality: \(raw)")
                }
                quality = q
            case "--any-quality":
                anyQuality = true
            case "--stats-only":
                statsOnly = true
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                throw VoiceTrainingExportCLIError.exportFailed("Unknown argument: \(arg)")
            }
        }

        return VoiceTrainingExportCLIConfiguration(
            maynContainer: maynContainer,
            output: output,
            quality: quality,
            anyQuality: anyQuality,
            statsOnly: statsOnly
        )
    }

    private static func printHelp() {
        print("""
        Usage: VoiceTrainingExport [--stats-only] [--quality high|medium] [--output path.tar.gz]

          --mayn-container   App Group path (default: ~/Library/Group Containers/.../shared)
          --stats-only       Print corpus counts without exporting
          --quality          Export filter (default: high)
          --any-quality      Export all quality tiers (pilot / small corpora)
          --output           Output .tar.gz path
        """)
    }
}
