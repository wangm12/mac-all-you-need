import AppKit
import ApplicationServices
import Foundation

@MainActor
final class WindowControlAccessibilityTrustMonitor {
    private let accessibilityTrust: () -> Bool
    private let onTrustChanged: (Bool) -> Void
    private let shouldPoll: () -> Bool
    private let notificationCenter: NotificationCenter
    private let pollIntervalNanoseconds: UInt64

    private var didBecomeActiveObserver: NSObjectProtocol?
    private var pollingTask: Task<Void, Never>?
    private var lastTrusted: Bool?

    init(
        accessibilityTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
        onTrustChanged: @escaping (Bool) -> Void,
        shouldPoll: @escaping () -> Bool,
        notificationCenter: NotificationCenter = .default,
        pollInterval: TimeInterval = 2
    ) {
        self.accessibilityTrust = accessibilityTrust
        self.onTrustChanged = onTrustChanged
        self.shouldPoll = shouldPoll
        self.notificationCenter = notificationCenter
        pollIntervalNanoseconds = UInt64(max(0.1, pollInterval) * 1_000_000_000)
    }

    func start() {
        if didBecomeActiveObserver == nil {
            didBecomeActiveObserver = notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshNow() }
            }
        }

        refreshNow()
    }

    func stop() {
        if let didBecomeActiveObserver {
            notificationCenter.removeObserver(didBecomeActiveObserver)
        }
        didBecomeActiveObserver = nil
        stopPolling()
        lastTrusted = nil
    }

    func refreshNow() {
        let trusted = accessibilityTrust()
        if trusted != lastTrusted {
            lastTrusted = trusted
            onTrustChanged(trusted)
        }
        reconcilePolling()
    }

    static func shouldPoll(
        runtimeEnabled: Bool,
        coordinatorState: WindowControlCoordinator.State
    ) -> Bool {
        guard runtimeEnabled else { return false }
        switch coordinatorState {
        case .needsAccessibility, .active:
            return true
        case .off, .suspended, .error:
            return false
        }
    }

    private func reconcilePolling() {
        guard shouldPoll() else {
            stopPolling()
            return
        }
        guard pollingTask == nil else { return }

        pollingTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.pollIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                self.refreshNow()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
