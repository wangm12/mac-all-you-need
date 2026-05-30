import Core
import Foundation

/// Monitors a folder using FSEvents and triggers proposals after a debounce delay.
@MainActor
final class WatchDaemon {
    private var eventStream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let debounceDelay: TimeInterval
    private let onNewFiles: ([URL]) async -> Void
    private var watchedURL: URL?

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
        debounceTask?.cancel()
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        eventStream = nil
        watchedURL = nil
    }

    private func handleFSEvent() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.debounceDelay))
            guard !Task.isCancelled, let url = self.watchedURL else { return }
            let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let newFiles = files.filter { !$0.hasDirectoryPath }
            if !newFiles.isEmpty { await self.onNewFiles(newFiles) }
        }
    }
}
