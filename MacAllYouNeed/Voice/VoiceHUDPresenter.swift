import AppKit
import Core
import Foundation
import OSLog

/// Owns the MiniVoiceHUD panel, the EscKeyMonitor, and level sampling.
/// VoiceCoordinator holds this as a stored property and wires the action
/// callbacks once both objects exist.
///
/// Responsibilities:
///   - show/update/dismiss HUD states
///   - drive the audio-level sampling loop
///   - dispatch Esc and Return key events to coordinator actions
@MainActor
final class VoiceHUDPresenter {
    let hud = MiniVoiceHUD()
    let escKeyMonitor = EscKeyMonitor()

    private var levelTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?

    let log: Logger

    // MARK: - Action callbacks (set by VoiceCoordinator after init)

    /// Called when the user taps the cancel/stop button in the HUD.
    var onCancel: (() -> Void)?
    /// Called when the user taps Dismiss on the Undo pill (or Esc while undo is showing).
    var onDismissUndo: (() -> Void)?
    /// Called when the user taps Undo or presses Return while the cancelled pill is up.
    var onUndo: (() async -> Void)?
    /// Returns true when there is a pending undo context (Cancelled pill up).
    var hasPendingUndo: (() -> Bool)?
    /// Returns true when the coordinator is in recording or transcribing state.
    var isStoppable: (() -> Bool)?

    init(log: Logger) {
        self.log = log
    }

    // MARK: - Install / uninstall

    func installEscMonitor() {
        escKeyMonitor.onEsc = { [weak self] in self?.handleEscKey() }
        escKeyMonitor.onReturn = { [weak self] in self?.handleEnterKey() }
        escKeyMonitor.install()
    }

    // MARK: - HUD display

    func showRecording(level: Float) {
        hud.show(.recording(level: level, liveText: nil), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
    }

    /// Update the recording HUD with live partial transcript text.
    func showLivePartial(_ text: String) {
        hud.show(.recording(level: hud.audioLevelBridge.level, liveText: text), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
    }

    func showTranscribingPhase(_ phase: MiniVoiceHUD.TranscribingSubphase) {
        log.info("voice.stage — \(String(describing: phase), privacy: .public)")
        hud.show(.transcribing(phase), onCancel: makeCancelAction(), onPrimary: makeCancelAction())
    }

    func showCancelled() {
        hud.show(.cancelled,
                 onCancel: makeDismissUndoAction(),
                 onPrimary: makeUndoAction())
    }

    func showError(_ message: String, onDismiss: @escaping () -> Void) {
        hud.show(.error(message), onPrimary: onDismiss)
    }

    /// Show a brief "⌘V to paste" notice when auto-paste couldn't inject the text.
    /// Dismisses automatically after 2 seconds — calmer than the error state.
    func showClipboardFallbackNotice() {
        hud.show(.clipboardFallback)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            hud.dismiss()
        }
    }

    func updateThinkingProgress(_ progress: Double) {
        hud.updateThinkingProgress(progress)
    }

    func dismiss() {
        hud.dismiss()
    }

    // MARK: - Level sampling

    func startLevelUpdates(peakLevelProvider: @escaping @MainActor () -> Float) {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                hud.audioLevelBridge.update(peakLevelProvider())
                try? await Task.sleep(for: .milliseconds(VoiceLevelSampling.intervalMilliseconds))
            }
        }
    }

    func stopLevelUpdates() {
        levelTask?.cancel()
        levelTask = nil
    }

    // MARK: - Error auto-dismiss

    /// Shows an error state in the HUD and schedules auto-dismiss after 2 s.
    /// `onStateReset` is called when the 2 s timer fires so the coordinator can
    /// reset its own state to idle.
    func showFailure(
        _ message: String,
        onStateReset: @escaping @MainActor () -> Void
    ) {
        cancelErrorDismissTask()
        stopLevelUpdates()
        hud.show(.error(message), onPrimary: makeDismissAction(onStateReset: onStateReset))
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            onStateReset()
            self.hud.dismiss()
            self.errorDismissTask = nil
        }
    }

    func cancelErrorDismissTask() {
        errorDismissTask?.cancel()
        errorDismissTask = nil
    }

    // MARK: - Key handlers

    private func handleEscKey() {
        if isStoppable?() == true {
            log.info("esc — cancelling current operation")
            onCancel?()
        } else if hasPendingUndo?() == true {
            log.info("esc — dismissing undo offer")
            onDismissUndo?()
        } else if hud.isVisible {
            log.info("esc — dismissing visible HUD")
            hud.dismiss()
        }
        // else: no HUD up and nothing to cancel — ignore Esc
    }

    private func handleEnterKey() {
        guard hasPendingUndo?() == true else { return }
        log.info("enter — triggering undo")
        let action = onUndo
        Task { @MainActor in await action?() }
    }

    // MARK: - Action builders

    private func makeCancelAction() -> () -> Void {
        { [weak self] in self?.onCancel?() }
    }

    private func makeUndoAction() -> () -> Void {
        { [weak self] in
            let action = self?.onUndo
            Task { @MainActor in await action?() }
        }
    }

    private func makeDismissUndoAction() -> () -> Void {
        { [weak self] in self?.onDismissUndo?() }
    }

    private func makeDismissAction(onStateReset: @escaping @MainActor () -> Void) -> () -> Void {
        { @MainActor [weak self] in
            self?.cancelErrorDismissTask()
            onStateReset()
            self?.hud.dismiss()
        }
    }
}
