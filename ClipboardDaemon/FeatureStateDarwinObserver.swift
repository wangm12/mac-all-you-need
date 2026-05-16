import Core
import CoreFoundation
import FeatureCore
import Foundation

/// Registers a Darwin notification observer for `DarwinNotification.featureStateDidChange`,
/// diffs per-`FeatureID` `ActivationState` against a snapshot, and calls `onChange` with
/// the diff on each change.
///
/// Intended to be held for the lifetime of the daemon. The observer is removed in `deinit`.
/// The caller MUST keep a strong reference for as long as Darwin notifications should be received.
final class FeatureStateDarwinObserver {
    /// Called when one or more features change activation state.
    /// The dictionary contains only the features whose state changed.
    var onChange: (([FeatureID: ActivationState]) -> Void)?

    private var previous: [FeatureID: ActivationState] = [:]

    func start(defaults: UserDefaults) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = DarwinNotification.featureStateDidChange as CFString
        // `passUnretained` — the caller (DaemonContainer) owns this object and keeps it alive
        // for the daemon lifetime, matching the pattern used in installSettingsReloader().
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let ptr = observer else { return }
                let me = Unmanaged<FeatureStateDarwinObserver>.fromOpaque(ptr)
                    .takeUnretainedValue()
                me.reload(defaults: AppGroupSettings.defaults)
            },
            name,
            nil,
            .deliverImmediately
        )
        // Perform an initial read so `previous` is populated and workers are started
        // based on the current persisted state without waiting for the next notification.
        reload(defaults: defaults)
    }

    func reload(defaults: UserDefaults) {
        var current: [FeatureID: ActivationState] = [:]
        for id in FeatureID.allCases {
            current[id] = FeatureStateReader.read(for: id, defaults: defaults).activationState
        }
        let diff = current.filter { previous[$0.key] != $0.value }
        previous = current
        if !diff.isEmpty {
            onChange?(diff)
        }
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil
        )
    }
}
