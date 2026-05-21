import Combine
import Foundation

/// Typed AppEvent enum — one case per notification AppController used to
/// observe inline. Promoting them from string-typed NotificationCenter
/// payloads to a closed Swift enum lets the controller's dispatch switch
/// exhaustively match each kind, and lets tests assert which event a
/// notification produced without inspecting NotificationCenter directly.
enum AppEvent: Equatable {
    case browseFolder(URL)
    case clipboardDownloadRequested(URL)
    case pauseCaptureRequested
    case clearClipboardOlderThan(days: Int)
    case clearAllClipboardHistory
    case mainWindowSettings(route: String?)
    case featureRuntimeStateChanged
    case hotkeyRecordingStarted
    case hotkeyRecordingStopped
}

/// Typed-publisher adapter for the 9 NotificationCenter observers
/// AppController used to wire inline. Registers all observers in its
/// initializer, translates each notification into an `AppEvent`, and
/// publishes them on a `PassthroughSubject`. AppController subscribes once
/// and dispatches each event to its existing handler.
///
/// Why `PassthroughSubject`: the original observers were callback-shaped,
/// so a Combine publisher is a natural lift — subscribers receive events
/// synchronously on the same run-loop queue NC delivers them on. An
/// AsyncStream would force an iteration loop on the consumer and complicate
/// the AppController shutdown path.
///
/// The adapter uses an injectable `NotificationCenter` so tests can post
/// against an isolated center and avoid contention with the app's default.
///
/// Thread model: observers register on the main queue via
/// `addObserver(forName:object:queue:.main)`. `PassthroughSubject.send` is
/// thread-safe, so we publish directly from the NC callback without an
/// actor hop — keeping delivery synchronous with the post.
final class AppNotificationObservers {
    /// Publisher of typed app events. AppController subscribes here once.
    let events = PassthroughSubject<AppEvent, Never>()

    private let center: NotificationCenter
    private let queue: OperationQueue?
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default, queue: OperationQueue? = .main) {
        self.center = center
        self.queue = queue
        registerAll()
    }

    deinit {
        for token in tokens {
            center.removeObserver(token)
        }
    }

    private func registerAll() {
        observe(.browseFolderRequested) { [events] note in
            guard let url = note.object as? URL else { return }
            events.send(.browseFolder(url))
        }
        observe(.clipboardDownloadRequested) { [events] note in
            guard let url = note.object as? URL else { return }
            events.send(.clipboardDownloadRequested(url))
        }
        observe(.pauseCaptureRequested) { [events] _ in
            events.send(.pauseCaptureRequested)
        }
        observe(.clearClipboardOlderThanRequested) { [events] note in
            // Mirror AppController's pre-extraction parsing: prefer NSNumber,
            // then Int, defaulting to 0 (which the handler treats as no-op).
            let days = (note.object as? NSNumber)?.intValue ?? (note.object as? Int) ?? 0
            events.send(.clearClipboardOlderThan(days: days))
        }
        observe(.clearAllClipboardHistoryRequested) { [events] _ in
            events.send(.clearAllClipboardHistory)
        }
        observe(.mainWindowSettingsRequested) { [events] note in
            events.send(.mainWindowSettings(route: note.object as? String))
        }
        observe(.featureRuntimeStateChanged) { [events] _ in
            events.send(.featureRuntimeStateChanged)
        }
        observe(.hotkeyRecorderDidStartRecording) { [events] _ in
            events.send(.hotkeyRecordingStarted)
        }
        observe(.hotkeyRecorderDidStopRecording) { [events] _ in
            events.send(.hotkeyRecordingStopped)
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @Sendable (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: queue, using: handler)
        tokens.append(token)
    }
}
