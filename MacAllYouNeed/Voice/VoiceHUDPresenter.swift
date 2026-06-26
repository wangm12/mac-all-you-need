import AppKit
import Core
import Foundation
import OSLog

/// Owns the voice session chrome (pill + captions + alerts), EscKeyMonitor, and level sampling.
@MainActor
final class VoiceHUDPresenter {
    let chrome = VoiceSessionChrome()
    let escKeyMonitor = EscKeyMonitor()

    private var levelTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var slowProcessingTask: Task<Void, Never>?
    private var warmupCaptionTask: Task<Void, Never>?
    private var chromeOptions = MiniVoiceHUD.ChromeOptions()
    private var transcribingSubphase: MiniVoiceHUD.TranscribingSubphase = .finalizing
    private var lastMicDeviceName: String?
    private var slowCaptionShown = false
    private var lastPendingCaptionAt: Date?
    private var isRecordingSession = false

    let log: Logger

    var hud: MiniVoiceHUD { chrome.pill }

    // MARK: - Action callbacks (set by VoiceCoordinator after init)

    var onCancel: (() -> Void)?
    var onDismissUndo: (() -> Void)?
    var onUndo: (() async -> Void)?
    var onFinish: (() async -> Void)?
    var hasPendingUndo: (() -> Bool)?
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

    func applyChrome(activationMode: VoiceActivationMode) {
        chromeOptions.activationMode = activationMode
    }

    // MARK: - HUD display

    func showStartingMic() {
        cancelWarmupCaptionTask()
        isRecordingSession = true
        present(.startingMic)
        scheduleWarmupCaptionIfNeeded()
    }

    func showRecording(level: Float) {
        cancelWarmupCaptionTask()
        chrome.captions.dismiss()
        present(.recording(level: level, liveText: nil, dimWaveform: false))
        showEducationCaptionIfNeeded()
    }

    func showLivePartial(_: String) {
        // Centered-native HUD: recording stays waveform-only; partials are suppressed.
    }

    func showTranscribingPhase(_ phase: MiniVoiceHUD.TranscribingSubphase, isSlow: Bool = false) {
        isRecordingSession = false
        cancelWarmupCaptionTask()
        chrome.captions.dismiss()
        transcribingSubphase = phase
        log.info("voice.stage — \(String(describing: phase), privacy: .public)")
        if !isSlow {
            startSlowProcessingWatch()
        }
        present(.transcribing(phase, isSlow: isSlow))
    }

    func showCancelled() {
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        chrome.captions.dismiss()
        chrome.syncAlertAnchor()
        chrome.pill.show(
            .cancelled,
            chrome: chromeOptions,
            onCancel: makeDismissUndoAction(),
            onPrimary: makeUndoAction(),
            onFinish: nil
        )
        chrome.syncAlertAnchor()
    }

    func showError(_ message: String, onDismiss: @escaping () -> Void) {
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        presentFailure(message, onPrimary: onDismiss)
    }

    func showClipboardFallbackNotice() {
        cancelSlowProcessingWatch()
        showCaption(
            VoiceHUDCopy.Caption.textCopied,
            priority: .terminal,
            duration: VoiceHUDCopy.Timing.clipboardFallbackDuration
        )
        present(.clipboardFallback)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.clipboardFallbackDuration))
            chrome.dismissAll()
        }
    }

    func showReminderAddedNotice() {
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        chrome.captions.dismiss()
        chrome.pill.updateThinkingProgress(1.0)
        present(.reminderAdded)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.reminderAddedDuration))
            self.dismiss()
        }
    }

    func showFirstUseInsertionAnchorIfNeeded() {
        let key = "voice.insertionAnchor.shown"
        guard !AppGroupSettings.defaults.bool(forKey: key) else { return }
        AppGroupSettings.defaults.set(true, forKey: key)
        chrome.insertionAnchor.showNearMouse()
    }

    func showMicDeviceToastIfNeeded(deviceName: String) {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmed.isEmpty
            ? VoiceHUDCopy.Caption.usingSelectedMic
            : VoiceHUDCopy.Caption.usingMic(trimmed)
        guard trimmed.isEmpty || lastMicDeviceName != trimmed else { return }
        lastMicDeviceName = trimmed.isEmpty ? lastMicDeviceName : trimmed
        showCaption(message, priority: .sessionInfo, duration: VoiceHUDCopy.Timing.usingMicDuration)
    }

    func showPendingRecordingAlert() {
        let now = Date()
        if let last = lastPendingCaptionAt,
           now.timeIntervalSince(last) < VoiceHUDCopy.Timing.previousPendingThrottle
        {
            return
        }
        lastPendingCaptionAt = now
        showCaption(
            VoiceHUDCopy.Caption.previousPending,
            priority: .activeRisk,
            duration: 4
        )
    }

    func showSlowProcessingCaptionIfNeeded() {
        guard !slowCaptionShown else { return }
        slowCaptionShown = true
        showCaption(
            VoiceHUDCopy.Caption.takingLonger,
            priority: .activeRisk,
            duration: 5
        )
    }

    func showPasteTargetToast(appName: String) {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        showCaption(
            VoiceHUDCopy.Caption.toApp(trimmed),
            priority: .sessionInfo,
            duration: VoiceHUDCopy.Timing.targetAppDuration
        )
    }

    func showLongRecordingCaption(minutes: Int, seconds: Int) {
        showCaption(
            VoiceHUDCopy.Caption.recordingDuration(minutes: minutes, seconds: seconds),
            priority: .sessionInfo,
            duration: 3
        )
    }

    func showRecordingLimitCaption(remainingSeconds: Int) {
        showCaption(
            VoiceHUDCopy.Caption.recordingWillStop(in: remainingSeconds),
            priority: .activeRisk,
            duration: 3
        )
    }

    func showCaption(
        _ message: String,
        priority: VoiceHUDCopy.Priority,
        duration: TimeInterval?
    ) {
        chrome.syncAlertAnchor()
        chrome.captions.show(message, priority: priority, duration: duration)
    }

    func updateThinkingProgress(_ progress: Double) {
        guard chrome.pill.isVisible else { return }
        chrome.pill.updateThinkingProgress(progress)
    }

    func dismiss() {
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        chrome.dismissAll()
        slowCaptionShown = false
        isRecordingSession = false
    }

    func dismissAfterSuccessHold() async {
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        chrome.syncAlertAnchor()
        await chrome.pill.dismissAfterSuccessHold()
        chrome.captions.dismiss()
        chrome.alerts.dismiss()
        slowCaptionShown = false
        isRecordingSession = false
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

    func showFailure(
        _ message: String,
        onStateReset: @escaping @MainActor () -> Void
    ) {
        cancelErrorDismissTask()
        cancelSlowProcessingWatch()
        cancelWarmupCaptionTask()
        stopLevelUpdates()
        presentFailure(message, onPrimary: makeDismissAction(onStateReset: onStateReset))
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.terminalAutoDismiss))
            guard let self else { return }
            onStateReset()
            self.chrome.dismissAll()
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
            log.info("esc — dismissing restore offer")
            onDismissUndo?()
        } else if chrome.pill.isVisible {
            log.info("esc — dismissing visible HUD")
            dismiss()
        }
    }

    private func handleEnterKey() {
        guard hasPendingUndo?() == true else { return }
        log.info("enter — triggering restore")
        let action = onUndo
        Task { @MainActor in await action?() }
    }

    // MARK: - Private

    private func presentFailure(_ message: String, onPrimary: (() -> Void)?) {
        chrome.alerts.dismiss()
        present(.error(message), onPrimary: onPrimary)
        if let caption = VoiceHUDCopy.captionMessage(forFailure: message) {
            showCaption(caption, priority: .terminal, duration: nil)
        } else {
            showBlockingAlertIfNeeded(for: message)
        }
        chrome.syncAlertAnchor()
    }

    private func present(
        _ state: MiniVoiceHUD.State,
        onPrimary: (() -> Void)? = nil
    ) {
        chrome.syncAlertAnchor()
        chrome.pill.show(
            state,
            chrome: chromeOptions,
            onCancel: makeCancelAction(),
            onPrimary: onPrimary ?? makeCancelAction(),
            onFinish: makeFinishAction()
        )
        chrome.syncAlertAnchor()
    }

    private func scheduleWarmupCaptionIfNeeded() {
        warmupCaptionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.micWarmupCaptionThreshold))
            guard !Task.isCancelled, let self, self.isRecordingSession else { return }
            self.showCaption(
                VoiceHUDCopy.Caption.startingMic,
                priority: .activeRisk,
                duration: nil
            )
        }
    }

    private func cancelWarmupCaptionTask() {
        warmupCaptionTask?.cancel()
        warmupCaptionTask = nil
    }

    private func showEducationCaptionIfNeeded() {
        switch chromeOptions.activationMode {
        case .hold:
            let key = "voice.education.releaseToFinish"
            let count = AppGroupSettings.defaults.integer(forKey: key)
            guard count < 3 else { return }
            AppGroupSettings.defaults.set(count + 1, forKey: key)
            showCaption(
                VoiceHUDCopy.Caption.releaseToFinish,
                priority: .education,
                duration: VoiceHUDCopy.Timing.educationDuration
            )
        case .toggle:
            let key = "voice.education.pressAgain"
            let count = AppGroupSettings.defaults.integer(forKey: key)
            guard count < 3 else { return }
            AppGroupSettings.defaults.set(count + 1, forKey: key)
            showCaption(
                VoiceHUDCopy.Caption.pressAgainToFinish,
                priority: .education,
                duration: VoiceHUDCopy.Timing.educationDuration
            )
        }
    }

    private func showBlockingAlertIfNeeded(for message: String) {
        guard let presentation = VoicePillErrorLabels.blockingPresentation(for: message) else { return }
        let lower = message.lowercased()
        if lower.contains("permission") {
            chrome.alerts.onPrimaryAction = {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                )
            }
        } else {
            chrome.alerts.onPrimaryAction = { [weak self] in
                self?.chrome.alerts.dismiss()
            }
        }
        chrome.alerts.onSecondaryAction = { [weak self] in
            self?.chrome.alerts.dismiss()
        }
        chrome.syncAlertAnchor()
        chrome.alerts.show(presentation)
    }

    private func startSlowProcessingWatch() {
        slowProcessingTask?.cancel()
        slowCaptionShown = false
        slowProcessingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.slowPillThreshold))
            guard !Task.isCancelled, let self else { return }
            self.showTranscribingPhase(self.transcribingSubphase, isSlow: true)
            try? await Task.sleep(for: .seconds(VoiceHUDCopy.Timing.slowCaptionThreshold - VoiceHUDCopy.Timing.slowPillThreshold))
            guard !Task.isCancelled else { return }
            self.showSlowProcessingCaptionIfNeeded()
        }
    }

    private func cancelSlowProcessingWatch() {
        slowProcessingTask?.cancel()
        slowProcessingTask = nil
    }

    private func makeCancelAction() -> () -> Void {
        { [weak self] in self?.onCancel?() }
    }

    private func makeFinishAction() -> () -> Void {
        { [weak self] in
            let action = self?.onFinish
            Task { @MainActor in await action?() }
        }
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
            self?.dismiss()
        }
    }
}
