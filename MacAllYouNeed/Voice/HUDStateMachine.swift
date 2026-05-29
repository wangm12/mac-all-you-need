import Foundation

/// Pure (no AppKit) state machine for the voice HUD.
///
/// Owns the canonical voice operation state and validates legal transitions.
/// `VoiceCoordinator` reflects these transitions into `MiniVoiceHUD` UI updates;
/// this type does not touch AppKit or SwiftUI directly.
///
/// Invariants enforced here:
///  - `.stop` from `.recording` or `.transcribing` always transitions to
///    `.cancelled` — never advances to a downstream phase. This encodes the
///    "Stop button always cancels" rule from the v8 HUD spec.
///  - `.dismiss` always lands on `.idle`.
struct HUDStateMachine: Equatable {
    /// Mirrors the publicly exposed `VoiceCoordinator.State` plus a
    /// `.cancelled` terminal phase that drives the 5s Undo pill. ASR and LLM
    /// cleanup are both represented as `.transcribing` on this machine (the
    /// HUD still shows a single **Transcribing** pill for both).
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case pasting
        case applied
        case cancelled
        case error(String)
    }

    enum Event: Equatable {
        case beginRecording
        case beginTranscribing
        case beginThinking
        case beginPasting
        case completedPaste
        case stop // stop button / hotkey cancel
        case dismiss
        case fail(String)
    }

    /// Legal phases from which `.stop` produces `.cancelled`. Outside this set
    /// `.stop` is a no-op (we never reach `.cancelled` from `.idle` or terminal).
    static func isStoppable(_ phase: Phase) -> Bool {
        switch phase {
        case .recording, .transcribing: true
        default: false
        }
    }

    private(set) var phase: Phase

    init(phase: Phase = .idle) {
        self.phase = phase
    }

    /// True when the user can cancel the currently in-flight task.
    var isStoppable: Bool {
        Self.isStoppable(phase)
    }

    /// Apply `event` and return whether the transition was accepted. Rejected
    /// transitions leave `phase` unchanged so callers can fall back without
    /// having to inspect state first.
    @discardableResult
    mutating func apply(_ event: Event) -> Bool {
        switch (phase, event) {
        case (.idle, .beginRecording):
            phase = .recording; return true
        case (.recording, .beginTranscribing):
            phase = .transcribing; return true
        case (.recording, .beginThinking),
             (.transcribing, .beginThinking):
            phase = .transcribing; return true
        case (.transcribing, .beginPasting):
            phase = .pasting; return true
        case (.pasting, .completedPaste):
            phase = .applied; return true
        case (_, .stop):
            // Stop ALWAYS cancels — never advances. Only meaningful from a
            // stoppable phase; otherwise reject so callers can decide.
            guard Self.isStoppable(phase) else { return false }
            phase = .cancelled; return true
        case (_, .dismiss):
            phase = .idle; return true
        case let (_, .fail(message)):
            phase = .error(message); return true
        default:
            return false
        }
    }
}
