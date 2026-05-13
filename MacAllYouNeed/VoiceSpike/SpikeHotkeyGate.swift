import AppKit
import Foundation

/// Gate 2: prove whether Fn / Globe emits press and release transitions.
@MainActor
final class SpikeHotkeyGate: ObservableObject {
    @Published private(set) var transcript: String = ""

    private var monitor: Any?
    private var fnDown = false
    private var startedAt: Date?

    func run() async -> String {
        transcript = ""
        fnDown = false
        startedAt = Date()
        log("Listening for Fn/Globe flagsChanged events for 10s.")
        log("Press and release Fn at least three times.")

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
            return event
        }

        try? await Task.sleep(nanoseconds: 10_000_000_000)

        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        NSEvent.removeMonitor(localMonitor)
        monitor = nil

        if !fnDown, transcript.contains("DOWN"), transcript.contains("UP") {
            return transcript + "\nOK: Fn press and release were both observed."
        }
        if transcript.isEmpty {
            return transcript
                + "\nFAIL: no Fn events captured. Check Accessibility permission or Globe key remapping."
        }
        return transcript
            + "\nWARN: only partial Fn transition data observed. Choose a fallback hotkey before Plan 8a."
    }

    private func handle(event: NSEvent) {
        let isFn = event.modifierFlags.contains(.function)
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if isFn, !fnDown {
            fnDown = true
            log(String(format: "[%.2fs] Fn DOWN (keyCode=%d)", elapsed, event.keyCode))
        } else if !isFn, fnDown {
            fnDown = false
            log(String(format: "[%.2fs] Fn UP", elapsed))
        }
    }

    private func log(_ line: String) {
        transcript += line + "\n"
    }
}
