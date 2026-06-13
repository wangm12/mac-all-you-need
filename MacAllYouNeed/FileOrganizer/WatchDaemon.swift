import Core
import Foundation

/// Monitors a folder using FSEvents and triggers proposals after a debounce delay.
@MainActor
final class WatchDaemon {
    private var eventStream: FSEventStreamRef?
    private let debounceDelay: TimeInterval
    private let onNewFiles: ([URL]) async -> Void
    private var watchedURL: URL?
    private var knownPaths: Set<String> = []

    init(debounceDelay: TimeInterval = 2.0, onNewFiles: @escaping ([URL]) async -> Void) {
        self.debounceDelay = debounceDelay
        self.onNewFiles = onNewFiles
    }

    func start(watching url: URL) {
        stop()
        watchedURL = url
        var context = FSEventStreamContext()
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let daemon = Unmanaged<WatchDaemon>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in daemon.handleFSEvent() }
        }
        context.info = Unmanaged.passUnretained(self).toOpaque()
        eventStream = FSEventStreamCreate(
            nil, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceDelay,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        if let stream = eventStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        eventStream = nil
        watchedURL = nil
        knownPaths = []
    }

    private func handleFSEvent() {
        // FSEvents stream latency (debounceDelay) already coalesces rapid events;
        // no additional sleep is needed here.
        guard let url = watchedURL else { return }
        let all = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let currentPaths = Set(all.filter { !$0.hasDirectoryPath }.map(\.path))
        let addedPaths = currentPaths.subtracting(knownPaths)
        knownPaths = currentPaths
        guard !addedPaths.isEmpty else { return }
        let newFiles = addedPaths.map { URL(fileURLWithPath: $0) }
        Task { @MainActor [weak self] in
            await self?.onNewFiles(newFiles)
        }
    }
}
