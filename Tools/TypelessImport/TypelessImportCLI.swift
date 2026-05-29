import AppKit
import Core
import CryptoKit
import Foundation

enum TypelessImportCLIError: Error, CustomStringConvertible {
    case appStillRunning
    case missingTypelessDatabase(URL)
    case missingFFmpeg(URL)
    case fallbackContainer(URL)

    var description: String {
        switch self {
        case .appStillRunning:
            return "Mac All You Need is still running. Quit the app (Cmd+Q) before importing."
        case .missingTypelessDatabase(let url):
            return "Typeless database not found at \(url.path)"
        case .missingFFmpeg(let url):
            return "ffmpeg not found at \(url.path). Run scripts/fetch-binaries.sh first."
        case .fallbackContainer(let url):
            return """
            Import target is not the Mac All You Need App Group container:
              \(url.path)
            Pass --mayn-container pointing at \
            ~/Library/Group Containers/group.com.macallyouneed.shared
            """
        }
    }
}

struct TypelessImportCLIConfiguration {
    var typelessDB: URL
    var recordingsRoot: URL
    var maynContainer: URL
    var ffmpeg: URL
    var dryRun: Bool
    var skipAudio: Bool
    var limit: Int?
}

@main
enum TypelessImportMain {
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
        try ensureAppIsNotRunning()

        guard FileManager.default.fileExists(atPath: config.typelessDB.path) else {
            throw TypelessImportCLIError.missingTypelessDatabase(config.typelessDB)
        }

        let converter: TypelessAudioConverting?
        if config.skipAudio {
            converter = nil
        } else {
            guard FileManager.default.isExecutableFile(atPath: config.ffmpeg.path) else {
                throw TypelessImportCLIError.missingFFmpeg(config.ffmpeg)
            }
            converter = FFmpegTypelessAudioConverter(ffmpegURL: config.ffmpeg)
        }

        AppGroup.containerURLOverride = config.maynContainer
        try validateContainer(config.maynContainer)

        fputs("Writing to App Group container:\n  \(config.maynContainer.path)\n", stderr)

        let key = try KeyManager(keychain: SystemKeychain()).deviceKey()
        let clipboardURL = config.maynContainer
            .appendingPathComponent("databases/clipboard.sqlite")
        let db = try Database(url: clipboardURL, migrations: ClipboardStore.migrations)
        let transcripts = VoiceTranscriptStore(database: db)
        let training = VoiceTrainingExampleStore(
            database: db,
            deviceKey: key,
            audioRoot: config.maynContainer.appendingPathComponent("voice-training-audio", isDirectory: true)
        )

        let importer = TypelessHistoryImporter(
            reader: TypelessHistoryReader(databaseURL: config.typelessDB),
            transcriptStore: transcripts,
            trainingExampleStore: training,
            recordingsRoot: config.recordingsRoot,
            audioConverter: converter,
            log: { message in
                fputs("\(message)\n", stderr)
            }
        )

        fputs("Importing Typeless history (dryRun=\(config.dryRun), skipAudio=\(config.skipAudio))…\n", stderr)
        let report = try importer.importAll(options: .init(
            dryRun: config.dryRun,
            skipAudio: config.skipAudio,
            limit: config.limit
        ))

        printSummary(report, dryRun: config.dryRun)
        if !report.errors.isEmpty {
            exit(2)
        }
    }

    private static func validateContainer(_ container: URL) throws {
        let path = container.path
        let isGroupContainer = path.contains("/Library/Group Containers/group.com.macallyouneed.shared")
        let isFallback = path.contains("/MacAllYouNeed-")
        if isFallback || !isGroupContainer {
            throw TypelessImportCLIError.fallbackContainer(container)
        }
        let dbPath = container.appendingPathComponent("databases/clipboard.sqlite").path
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw TypelessImportCLIError.fallbackContainer(container)
        }
    }

    private static func ensureAppIsNotRunning() throws {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.macallyouneed.app"
        }
        if running { throw TypelessImportCLIError.appStillRunning }
    }

    private static func parseArguments() throws -> TypelessImportCLIConfiguration {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var config = TypelessImportCLIConfiguration(
            typelessDB: home.appendingPathComponent("Library/Application Support/Typeless/typeless.db"),
            recordingsRoot: home.appendingPathComponent("Library/Application Support/Typeless/Recordings"),
            maynContainer: AppGroup.containerURL(),
            ffmpeg: defaultFFmpegURL(),
            dryRun: false,
            skipAudio: false,
            limit: nil
        )

        var args = Array(CommandLine.arguments.dropFirst())
        while let flag = args.first {
            args.removeFirst()
            switch flag {
            case "--typeless-db":
                config.typelessDB = try requiredURL(args: &args, flag: flag)
            case "--typeless-recordings":
                config.recordingsRoot = try requiredURL(args: &args, flag: flag)
            case "--mayn-container":
                config.maynContainer = try requiredURL(args: &args, flag: flag)
            case "--ffmpeg":
                config.ffmpeg = try requiredURL(args: &args, flag: flag)
            case "--dry-run":
                config.dryRun = true
            case "--skip-audio":
                config.skipAudio = true
            case "--limit":
                guard let raw = args.first else { throw ArgumentParseError.missingValue(flag) }
                args.removeFirst()
                guard let value = Int(raw), value > 0 else {
                    throw ArgumentParseError.invalidValue(flag, raw)
                }
                config.limit = value
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                throw ArgumentParseError.unknownFlag(flag)
            }
        }
        return config
    }

    private static func requiredURL(args: inout [String], flag: String) throws -> URL {
        guard let raw = args.first else { throw ArgumentParseError.missingValue(flag) }
        args.removeFirst()
        let expanded = NSString(string: raw).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: false)
    }

    private static func defaultFFmpegURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let root = env["SRCROOT"], !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent("Vendored/binaries/ffmpeg")
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent("Vendored/binaries/ffmpeg")
    }

    private static func printSummary(_ report: TypelessImportReport, dryRun: Bool) {
        print("Typeless import \(dryRun ? "(dry run) " : "")complete")
        print("  scanned:          \(report.scanned)")
        print("  imported:         \(report.imported)")
        print("  skipped existing: \(report.skippedExisting)")
        print("  audio imported:   \(report.audioImported)")
        print("  audio failed:     \(report.audioFailed)")
        if !report.errors.isEmpty {
            print("  errors:           \(report.errors.count)")
            for error in report.errors.prefix(10) {
                print("    - \(error)")
            }
            if report.errors.count > 10 {
                print("    … and \(report.errors.count - 10) more")
            }
        }
    }

    private static func printHelp() {
        print("""
        TypelessImport — import Typeless dictation history into Mac All You Need

        Usage:
          TypelessImport [options]

        Options:
          --typeless-db PATH         Typeless typeless.db (default: ~/Library/Application Support/Typeless/typeless.db)
          --typeless-recordings PATH Typeless Recordings folder
          --mayn-container PATH      Mac All You Need App Group container
          --ffmpeg PATH              ffmpeg binary (default: $SRCROOT/Vendored/binaries/ffmpeg)
          --dry-run                  Count rows without writing
          --skip-audio               Import text only
          --limit N                  Import at most N records (newest first)
          -h, --help                 Show this help

        Quit Mac All You Need before running.
        """)
    }
}

private enum ArgumentParseError: Error, CustomStringConvertible {
    case unknownFlag(String)
    case missingValue(String)
    case invalidValue(String, String)

    var description: String {
        switch self {
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)"
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)"
        }
    }
}
