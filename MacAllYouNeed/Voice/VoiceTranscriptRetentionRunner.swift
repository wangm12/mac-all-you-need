import Core
import Foundation
import OSLog

final class VoiceTranscriptRetentionRunner {
    private let transcriptStore: VoiceTranscriptStore
    private let trainingExampleStore: VoiceTrainingExampleStore?
    private let audioRoot: URL
    private let historySettings: () -> VoiceHistorySettings
    private let now: () -> Date
    private var timer: Timer?
    private var notificationToken: NSObjectProtocol?
    private let log = Logger(subsystem: "com.macallyouneed.voice", category: "retention")

    init(
        transcriptStore: VoiceTranscriptStore,
        trainingExampleStore: VoiceTrainingExampleStore?,
        audioRoot: URL,
        historySettings: @escaping () -> VoiceHistorySettings,
        now: @escaping () -> Date = Date.init
    ) {
        self.transcriptStore = transcriptStore
        self.trainingExampleStore = trainingExampleStore
        self.audioRoot = audioRoot
        self.historySettings = historySettings
        self.now = now
    }

    func start() {
        sweepNow()
        timer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak self] _ in
            self?.sweepNow()
        }
        notificationToken = NotificationCenter.default.addObserver(
            forName: .voiceTranscriptAppended, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sweepNow()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
            notificationToken = nil
        }
    }

    func sweepNow() {
        let settings = historySettings()
        if let maxAge = settings.retention.maxAgeSeconds {
            do {
                let expired = try transcriptStore.expireByAge(maxAge: maxAge, now: now())
                for transcript in expired {
                    guard let path = transcript.audioPath else { continue }
                    guard !isReferencedByTrainingExample(path: path) else { continue }
                    try? FileManager.default.removeItem(atPath: path)
                }
            } catch {
                log.error("retention sweep failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        sweepOrphanAudio()
    }

    private func sweepOrphanAudio() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: audioRoot.path) else { return }
        let liveIDs = buildLiveAudioIDs()
        for entry in entries where entry.hasSuffix(".aesgcm") {
            let id = audioIDFromFilename(entry)
            guard !liveIDs.contains(id) else { continue }
            try? fm.removeItem(at: audioRoot.appendingPathComponent(entry))
        }
    }

    private func buildLiveAudioIDs() -> Set<String> {
        var ids: Set<String> = []
        if let recent = try? transcriptStore.listRecent(limit: 100_000) {
            for transcript in recent {
                if let path = transcript.audioPath {
                    ids.insert(audioIDFromFilename(URL(fileURLWithPath: path).lastPathComponent))
                }
            }
        }
        if let store = trainingExampleStore,
           let paths = try? store.allAudioPaths() {
            for path in paths {
                ids.insert(audioIDFromFilename(URL(fileURLWithPath: path).lastPathComponent))
            }
        }
        return ids
    }

    private func isReferencedByTrainingExample(path: String) -> Bool {
        guard let store = trainingExampleStore,
              let paths = try? store.allAudioPaths() else { return false }
        return paths.contains(path)
    }

    private func audioIDFromFilename(_ name: String) -> String {
        var stem = name
        if stem.hasSuffix(".aesgcm") { stem = String(stem.dropLast(".aesgcm".count)) }
        if stem.hasSuffix(".wav") { stem = String(stem.dropLast(".wav".count)) }
        return stem
    }
}
