import AppKit
import Combine
import SwiftUI
import UI

/// Holds the live microphone peak level so `WaveformBars` can observe it
/// directly without requiring a full hosting-view rootView swap every tick.
@MainActor
final class MiniVoiceAudioLevelBridge: ObservableObject {
    @Published private(set) var level: Float = 0

    func update(_ newLevel: Float) {
        level = newLevel
    }

    func reset() {
        level = 0
    }
}

/// Drives processing progress wipe on the transcribing pill: boot curve from
/// release through ASR/cleanup/pasting, then monotonic stream progress to `1`.
@MainActor
final class MiniVoiceThinkingProgressBridge: ObservableObject {
    private enum ProgressPolicy {
        static let bootCap = 0.63
        static let bootTickNanos: UInt64 = 50_000_000
        static let completionSnapThreshold = 0.995
        /// Typeless-style keyframes: fast early motion, asymptotic cap at ~63% @10s.
        static let bootKeyframes: [(time: Double, progress: Double)] = [
            (0, 0),
            (0.4, 0.30),
            (1.0, 0.50),
            (2.0, 0.57),
            (10.0, 0.63),
        ]
    }
    /// Combined wipe amount 0...1 for the black fill (`max(boot, stream)`).
    @Published private(set) var displayWipe: Double = 0

    private var streamProgress: Double = 0
    private var bootProgress: Double = 0
    private var bootTask: Task<Void, Never>?
    private var bootStartedAt: Date?

    static func bootProgress(at elapsed: TimeInterval) -> Double {
        let keyframes = ProgressPolicy.bootKeyframes
        guard elapsed > 0 else { return 0 }
        if elapsed >= keyframes.last!.time { return keyframes.last!.progress }
        for index in 1 ..< keyframes.count {
            let previous = keyframes[index - 1]
            let next = keyframes[index]
            if elapsed <= next.time {
                let span = next.time - previous.time
                guard span > 0 else { return next.progress }
                let t = (elapsed - previous.time) / span
                return previous.progress + t * (next.progress - previous.progress)
            }
        }
        return keyframes.last!.progress
    }

    func cancelBootAndResetDisplay() {
        bootTask?.cancel()
        bootTask = nil
        bootStartedAt = nil
        streamProgress = 0
        bootProgress = 0
        displayWipe = 0
    }

    /// Starts a new processing-wipe session from release through paste.
    func beginThinkingSession(reduceMotion: Bool) {
        cancelBootAndResetDisplay()
        bootStartedAt = Date()
        if reduceMotion {
            bootProgress = Self.bootProgress(at: 0.4)
            recombine()
        }
        bootTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let started = bootStartedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                bootProgress = Self.bootProgress(at: elapsed)
                recombine()
                if elapsed >= ProgressPolicy.bootKeyframes.last!.time { return }
                let tick = reduceMotion
                    ? ProgressPolicy.bootTickNanos * 2
                    : ProgressPolicy.bootTickNanos
                try? await Task.sleep(nanoseconds: tick)
            }
        }
    }

    func applyStreamProgress(_ progress: Double) {
        let clamped = min(1, max(0, progress))
        streamProgress = max(streamProgress, clamped)
        if streamProgress > bootProgress, bootTask != nil {
            bootTask?.cancel()
            bootTask = nil
            bootProgress = 0
        }
        recombine()
    }

    private func recombine() {
        var next = min(1, max(bootProgress, streamProgress))
        if next >= ProgressPolicy.completionSnapThreshold {
            next = 1
        }
        if abs(next - displayWipe) > 1e-12 {
            displayWipe = next
        }
    }
}

@MainActor
final class MiniVoiceHUD {
    /// Post-commit transcription: cloud/local ASR, then optional LLM cleanup. The
    /// HUD always reads **Transcribing**; cleanup adds the gray-track + black wipe.
    enum TranscribingSubphase: Equatable {
        case finalizing
        case asr
        /// `progress` is 0...1 on first `show`; live wipe uses `MiniVoiceThinkingProgressBridge`.
        case cleanup(progress: Double)
        case pasting
    }

    enum State: Equatable {
        case idlePreview
        case startingMic
        /// `liveText`: stable partial for the center label (nil = waveform only).
        /// `dimWaveform`: lower motion while the mic is still warming up.
        case recording(level: Float, liveText: String? = nil, dimWaveform: Bool = false)
        case transcribing(TranscribingSubphase, isSlow: Bool = false)
        case cancelled
        case noSpeech(String)
        case error(String)
        /// Text landed in the clipboard but couldn't be auto-pasted. Brief notice before dismiss.
        case clipboardFallback
        /// Reminder intent finished — brief confirmation before dismiss.
        case reminderAdded
    }

    struct ChromeOptions: Equatable {
        var activationMode: VoiceActivationMode = .toggle
    }

    private var panelController: NonActivatingFloatingPanelController<MiniVoiceHUDView>?
    /// Tracks the first-mouse hosting view that replaces the controller's
    /// default NSHostingView so SwiftUI buttons respond on the first click.
    private var firstMouseHosting: FirstMouseHostingView<MiniVoiceHUDView>?
    /// Locked at session start (first show from hidden) and cleared on dismiss
    /// so the HUD stays on one screen for an entire recording → transcribing →
    /// pasting cycle instead of jumping to whichever screen has the active key
    /// window during state transitions.
    private var targetScreen: NSScreen?
    private var chromeOptions = ChromeOptions()
    private var isTranscribingSessionActive = false
    private let thinkingProgressBridge = MiniVoiceThinkingProgressBridge()
    /// Carries live microphone peak level to `WaveformBars` without forcing a
    /// full rootView swap on every audio tick. Created once and shared with each
    /// `MiniVoiceHUDView` instance so the waveform observes it directly.
    let audioLevelBridge = MiniVoiceAudioLevelBridge()

    #if DEBUG
    var testingContentView: NSView? {
        panelController?.currentPanel?.contentView
    }
    #endif

    /// True when the floating pill panel is currently on screen. Used by
    /// VoiceCoordinator to decide whether an Esc keystroke should dismiss the
    /// HUD or be ignored (so we don't fight with other apps' Esc handlers).
    var isVisible: Bool {
        panelController?.isPresented ?? false
    }

    var currentTargetScreen: NSScreen? { targetScreen }

    var currentPillBottomY: CGFloat {
        guard let screen = targetScreen ?? Self.screenContainingMouseCursor() ?? NSScreen.main else { return 0 }
        return screen.visibleFrame.minY + MiniVoiceHUDLayout.bottomInsetAboveDock
    }

    var currentPillCenterX: CGFloat {
        if let panel = panelController?.currentPanel, isVisible {
            return panel.frame.midX
        }
        guard let screen = targetScreen
            ?? Self.screenContainingMouseCursor()
            ?? NSScreen.main
        else {
            return 0
        }
        return screen.visibleFrame.midX
    }

    func show(
        _ state: State,
        chrome: ChromeOptions = ChromeOptions(),
        onCancel: (() -> Void)? = nil,
        onPrimary: (() -> Void)? = nil,
        onFinish: (() -> Void)? = nil
    ) {
        chromeOptions = chrome
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch state {
        case .transcribing:
            if !isTranscribingSessionActive {
                thinkingProgressBridge.beginThinkingSession(reduceMotion: reduceMotion)
                isTranscribingSessionActive = true
            }
            if case let .transcribing(.cleanup(initial), _) = state, initial > 0 {
                thinkingProgressBridge.applyStreamProgress(initial)
            }
        case .startingMic, .recording:
            isTranscribingSessionActive = false
            thinkingProgressBridge.cancelBootAndResetDisplay()
        default:
            isTranscribingSessionActive = false
            thinkingProgressBridge.cancelBootAndResetDisplay()
        }
        let pill = MiniVoiceHUDPill(state: state, chrome: chrome)
        let nextView = MiniVoiceHUDView(
            state: state,
            chrome: chrome,
            pill: pill,
            thinkingProgress: thinkingProgressBridge,
            audioLevel: audioLevelBridge,
            onCancel: onCancel,
            onPrimary: onPrimary,
            onFinish: onFinish
        )
        let size = MiniVoiceHUDLayout.size(for: state, label: pill.label, chrome: chrome)

        if let controller = panelController, controller.isPresented {
            // Already visible — update content in-place, no re-animation.
            firstMouseHosting?.rootView = nextView
            firstMouseHosting?.frame = NSRect(origin: .zero, size: size)
            controller.updateSize(size)
            controller.currentPanel?.setFrameOrigin(targetOrigin(for: size))
            return
        }

        // New session — lock to the screen the user is currently on.
        targetScreen = Self.screenContainingMouseCursor()

        if panelController == nil {
            let showDuration = MAYNMotionBridge.effectiveDuration(.toastIn)
            let hideDuration = MAYNMotionBridge.effectiveDuration(.toastOut)
            panelController = NonActivatingFloatingPanelController<MiniVoiceHUDView>(
                styleMask: [.borderless, .nonactivatingPanel],
                level: FloatingHUDWindowLayering.windowLevel,
                collectionBehavior: FloatingHUDWindowLayering.collectionBehavior,
                hasShadow: false,
                backgroundColor: .clear,
                showAnimationDuration: showDuration,
                hideAnimationDuration: hideDuration,
                positioner: { [weak self] panel, size in
                    guard let self else { return }
                    let origin = self.targetOrigin(for: size)
                    panel.setFrameOrigin(origin)
                }
            )
        }

        // present() creates the panel and starts the fade-in animation.
        panelController?.present(rootView: nextView, size: size, animated: true)

        // Apply HUD-specific panel settings not exposed by the shared controller,
        // and swap in FirstMouseHostingView so buttons respond on the first click
        // without requiring the panel to become key.
        if let panel = panelController?.currentPanel {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            let fmh = FirstMouseHostingView(rootView: nextView)
            fmh.frame = NSRect(origin: .zero, size: size)
            fmh.layer?.setAffineTransform(CGAffineTransform.identity)
            panel.contentView = fmh
            firstMouseHosting = fmh
        }
    }

    /// Updates the cleanup wipe without rebuilding the hosting view (stream chunks).
    func updateThinkingProgress(_ progress: Double) {
        guard panelController?.isPresented == true else { return }
        thinkingProgressBridge.applyStreamProgress(progress)
    }

    /// Snap wipe to 100%, hold briefly, then dismiss (success path).
    func dismissAfterSuccessHold() async {
        thinkingProgressBridge.applyStreamProgress(1.0)
        let holdMs = UInt64(MAYNMotionBridge.effectiveDuration(.press) * 1000) + 200
        try? await Task.sleep(nanoseconds: holdMs * 1_000_000)
        dismiss()
    }

    func dismiss() {
        isTranscribingSessionActive = false
        thinkingProgressBridge.cancelBootAndResetDisplay()
        audioLevelBridge.reset()
        guard let controller = panelController, controller.isPresented else { return }
        if let fmh = firstMouseHosting, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == false {
            fmh.wantsLayer = true
            if let layer = fmh.layer {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = MAYNMotionBridge.effectiveDuration(.press)
                    context.timingFunction = MAYNMotionBridge.timingFunction(.press)
                    layer.setAffineTransform(CGAffineTransform(scaleX: 0.88, y: 0.88))
                }, completionHandler: { [weak self] in
                    layer.setAffineTransform(CGAffineTransform.identity)
                    self?.tearDownHUD(controller: controller)
                })
                return
            }
        }
        tearDownHUD(controller: controller)
    }

    private func tearDownHUD(controller: NonActivatingFloatingPanelController<MiniVoiceHUDView>) {
        targetScreen = nil
        firstMouseHosting = nil
        controller.dismiss(animated: true)
    }

    private func targetOrigin(for size: CGSize) -> NSPoint {
        let screen = targetScreen
            ?? Self.screenContainingMouseCursor()
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return .zero }
        return NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + MiniVoiceHUDLayout.bottomInsetAboveDock
        )
    }

    private static func screenContainingMouseCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

enum MiniVoiceHUDLayout {
  static let recordingWidth: CGFloat = 144
  static let transcribingWidth: CGFloat = 164
  static let slowProcessingWidth: CGFloat = 172
  static let clipboardFallbackWidth: CGFloat = 144
  static let terminalMinWidth: CGFloat = 160
  static let terminalMaxWidth: CGFloat = 180
  static let cancelledWidth: CGFloat = 184
  /// Legacy alias used by tests.
  static let pillWidth: CGFloat = recordingWidth
  static let maxPillWidth: CGFloat = terminalMaxWidth
  static let pillHeight: CGFloat = 32
  static let pillSize = CGSize(width: pillWidth, height: pillHeight)
  static let bottomInsetAboveDock: CGFloat = 28
  static let cornerRadius: CGFloat = 16
  static let iconSize: CGFloat = 14
  static let labelHorizontalPadding: CGFloat = 16
  static let fontSize: CGFloat = 11
  static let captionFontSize: CGFloat = 10.5
  static let captionHeight: CGFloat = 16
  static let captionHorizontalPadding: CGFloat = 10
  static let captionVerticalPadding: CGFloat = 4
  static let captionCornerRadius: CGFloat = 8
  static let captionShellHeight: CGFloat = captionHeight + captionVerticalPadding * 2
  static let captionGap: CGFloat = 5

  static func size(
    for state: MiniVoiceHUD.State,
    label: String = "",
    chrome: MiniVoiceHUD.ChromeOptions = .init()
  ) -> CGSize {
    CGSize(width: computedWidth(for: state, label: label, chrome: chrome), height: pillHeight)
  }

  static func computedWidth(
    for state: MiniVoiceHUD.State,
    label: String,
    chrome: MiniVoiceHUD.ChromeOptions
  ) -> CGFloat {
    _ = chrome
    switch state.normalizedForDisplay {
    case .startingMic, .recording:
      return recordingWidth
    case let .transcribing(_, isSlow):
      return isSlow ? slowProcessingWidth : transcribingWidth
    case .clipboardFallback:
      return clipboardFallbackWidth
    case .reminderAdded:
      let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
      let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
      return min(terminalMaxWidth, max(recordingWidth, textWidth + labelHorizontalPadding * 2 + iconSize + 6))
    case .cancelled:
      return cancelledWidth
    case .noSpeech:
      return terminalMinWidth
    case .error:
      let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
      let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
      return min(terminalMaxWidth, max(terminalMinWidth, textWidth + labelHorizontalPadding * 2))
    case .idlePreview:
      return recordingWidth
    }
  }
}

enum MiniVoiceHUDPalette {
  // Graphite HUD identity — same across light/dark (design.md §10 exception).
  static let pillGraphite = Color(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0)
  static let pillWipeOverlay = Color.white.opacity(0.145)
  static let pillBorder = Color.clear
  static let pillBorderHover = Color.clear
  static let pillText = Color.white.opacity(0.96)
  /// Legacy aliases for tests / gradual migration.
  static let pillBlack = pillGraphite
  static let pillThinkingTrack = pillGraphite
}

struct MiniVoiceHUDPill: Equatable {
    let state: MiniVoiceHUD.State
    private let contentModel: VoicePillContentModel

    typealias Leading = VoicePillContentModel.Leading

    init(state: MiniVoiceHUD.State, chrome: MiniVoiceHUD.ChromeOptions = .init()) {
        self.state = state
        contentModel = VoicePillContentModel(state: state, chrome: chrome)
    }

    var label: String {
        contentModel.label
    }

    var labelTransitionSlot: String {
        contentModel.labelTransitionSlot
    }

    var leading: Leading {
        contentModel.leading
    }

    var actionAvailability: VoicePillActionAvailability {
        contentModel.actionAvailability
    }

    var secondaryAction: VoicePillSecondaryAction {
        contentModel.secondaryAction
    }

    /// True when the user can cancel the in-flight task.
    var isCancellable: Bool {
        actionAvailability == .cancel || secondaryAction == .cancel
    }

    /// True when the right slot shows Restore instead of Cancel.
    var isRestorable: Bool {
        actionAvailability == .restore
    }

    var isTerminal: Bool {
        actionAvailability == .dismissTerminal
    }
}

enum VoicePillSecondaryAction: Equatable {
    case none
    case cancel
    case finish
}

enum VoicePillActionAvailability: Equatable {
    case none
    case cancel
    case finish
    case restore
    case dismissTerminal
}

struct VoicePillContentModel: Equatable {
    enum Leading: Equatable {
        case waveformBars
        case aiSparkle
        case bouncingDots
        case checkInCircle
        case xInCircle
        case warningTriangle
        case none
    }

    let label: String
    let labelTransitionSlot: String
    let leading: Leading
    let actionAvailability: VoicePillActionAvailability
    let secondaryAction: VoicePillSecondaryAction

    init(state: MiniVoiceHUD.State, chrome: MiniVoiceHUD.ChromeOptions = .init()) {
        switch state.normalizedForDisplay {
        case .idlePreview:
            label = ""
            labelTransitionSlot = "idlePreview"
            leading = .none
            actionAvailability = .none
            secondaryAction = .none
        case .startingMic:
            label = ""
            labelTransitionSlot = "startingMic"
            leading = .waveformBars
            actionAvailability = .none
            secondaryAction = .none
        case .recording:
            label = ""
            labelTransitionSlot = "recording"
            leading = .waveformBars
            actionAvailability = .none
            secondaryAction = .none
        case let .transcribing(_, isSlow):
            if isSlow {
                label = VoiceHUDCopy.Pill.stillWorking
                labelTransitionSlot = "transcribingSlow"
            } else {
                label = VoiceHUDCopy.Pill.transcribing
                labelTransitionSlot = "transcribing"
            }
            leading = .none
            actionAvailability = .none
            secondaryAction = .none
        case .cancelled:
            label = VoiceHUDCopy.Pill.cancelled
            labelTransitionSlot = "cancelled"
            leading = .none
            actionAvailability = .restore
            secondaryAction = .none
        case .noSpeech:
            label = VoiceHUDCopy.Pill.noSpeech
            labelTransitionSlot = "noSpeech"
            leading = .none
            actionAvailability = .dismissTerminal
            secondaryAction = .none
        case let .error(message):
            label = VoiceHUDCopy.pillLabel(for: message)
            labelTransitionSlot = "error"
            leading = .none
            actionAvailability = .dismissTerminal
            secondaryAction = .none
        case .clipboardFallback:
            label = VoiceHUDCopy.Pill.clipboardFallback
            labelTransitionSlot = "clipboardFallback"
            leading = .none
            actionAvailability = .none
            secondaryAction = .none
        case .reminderAdded:
            label = VoiceHUDCopy.Pill.reminderAdded
            labelTransitionSlot = "reminderAdded"
            leading = .checkInCircle
            actionAvailability = .none
            secondaryAction = .none
        }
    }
}

extension MiniVoiceHUD.State {
    /// Demotes "no usable audio" / "transcript was empty" error messages —
    /// emitted by VoiceCoordinator.fail() — to the calmer .noSpeech presentation
    /// so the user doesn't see a hard-error pill for a user-input condition.
    var normalizedForDisplay: MiniVoiceHUD.State {
        if case let .error(message) = self,
           message.localizedCaseInsensitiveContains("no usable audio")
           || message.localizedCaseInsensitiveContains("transcript was empty")
        {
            return .noSpeech(message)
        }
        return self
    }
}

struct MiniVoiceHUDView: View {
    let state: MiniVoiceHUD.State
    let chrome: MiniVoiceHUD.ChromeOptions
    let pill: MiniVoiceHUDPill
    @ObservedObject var thinkingProgress: MiniVoiceThinkingProgressBridge
    @ObservedObject var audioLevel: MiniVoiceAudioLevelBridge
    let onCancel: (() -> Void)?
    let onPrimary: (() -> Void)?
    let onFinish: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var pillWidth: CGFloat {
        MiniVoiceHUDLayout.computedWidth(for: state, label: pill.label, chrome: chrome)
    }

    var body: some View {
        EntranceTransform {
            ZStack {
                pillBackground

                centeredContent
                    .padding(.horizontal, MiniVoiceHUDLayout.labelHorizontalPadding)
            }
            .frame(width: pillWidth, height: MiniVoiceHUDLayout.pillHeight)
            .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 14)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .contentShape(Capsule())
            .onTapGesture(perform: handleBackgroundTap)
            .onHover { isHovering = $0 }
            .animation(MAYNMotion.animation(.control, reduceMotion: reduceMotion), value: pill.labelTransitionSlot)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .frame(width: pillWidth, height: MiniVoiceHUDLayout.pillHeight)
        .animation(MAYNMotion.animation(.control, reduceMotion: reduceMotion), value: pillWidth)
    }

    @ViewBuilder
    private var pillBackground: some View {
        Group {
            if showsTranscribingProgressWipe {
                thinkingPillBackground(wipe: thinkingProgress.displayWipe)
            } else {
                Capsule()
                    .fill(MiniVoiceHUDPalette.pillGraphite)
            }
        }
        .clipShape(Capsule())
        .animation(
            MAYNMotion.animation(.control, reduceMotion: reduceMotion),
            value: thinkingWipeAnimationValue
        )
    }

    @ViewBuilder
    private var centeredContent: some View {
        Group {
            if case .cancelled = state.normalizedForDisplay {
                cancelledContent
            } else if case .reminderAdded = state.normalizedForDisplay {
                reminderAddedContent
            } else {
                switch pill.leading {
                case .waveformBars:
                    let dimmed = if case .startingMic = state { true }
                    else if case .recording(_, _, let dim) = state { dim }
                    else { false }
                    WaveformBars(level: recordingLevel, dimmed: dimmed)
                case .none where !pill.label.isEmpty:
                    Text(pill.label)
                        .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                        .foregroundStyle(MiniVoiceHUDPalette.pillText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .id(pill.labelTransitionSlot)
                        .transition(hudAsymmetricTransition)
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var cancelledContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MiniVoiceHUDPalette.pillText.opacity(0.92))
                .accessibilityHidden(true)

            Text(pill.label)
                .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                .foregroundStyle(MiniVoiceHUDPalette.pillText)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: { onPrimary?() }) {
                Text(VoiceHUDCopy.Pill.undo)
                    .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                    .foregroundStyle(MiniVoiceHUDPalette.pillText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo")
        }
    }

    private var reminderAddedContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: MiniVoiceHUDLayout.iconSize, weight: .semibold))
                .foregroundStyle(MiniVoiceHUDPalette.pillText.opacity(0.92))
                .accessibilityHidden(true)

            Text(pill.label)
                .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                .foregroundStyle(MiniVoiceHUDPalette.pillText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .id(pill.labelTransitionSlot)
                .transition(hudAsymmetricTransition)
        }
    }

    private var hudAsymmetricTransition: AnyTransition {
        let entryOffset = MAYNMotionBridge.translation(-4, reduceMotion: reduceMotion)
        let exitOffset = MAYNMotionBridge.translation(4, reduceMotion: reduceMotion)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: entryOffset)),
            removal: .opacity.combined(with: .offset(y: exitOffset))
        )
    }

    private var showsTranscribingProgressWipe: Bool {
        if case .transcribing = state.normalizedForDisplay { return true }
        return false
    }

    /// Stable animation token for the processing wipe; `-1` when the wipe stack is inactive.
    private var thinkingWipeAnimationValue: Double {
        if showsTranscribingProgressWipe { return thinkingProgress.displayWipe }
        return -1
    }

    @ViewBuilder
    private func thinkingPillBackground(wipe: Double) -> some View {
        let w = min(1, max(0, wipe))
        let fillWidth = pillWidth * w
        ZStack(alignment: .leading) {
            Capsule()
                .fill(MiniVoiceHUDPalette.pillGraphite)
            Capsule()
                .fill(MiniVoiceHUDPalette.pillWipeOverlay)
                .frame(width: fillWidth)
        }
        .frame(width: pillWidth, height: MiniVoiceHUDLayout.pillHeight)
        .clipShape(Capsule())
    }

    private var accessibilityText: String {
        let spoken = recordingAccessibilityStatus ?? pill.label
        if pill.isRestorable { return "\(spoken). Restore available." }
        return pill.isCancellable ? "\(spoken). Cancel available." : spoken
    }

    private var recordingAccessibilityStatus: String? {
        if case .startingMic = state.normalizedForDisplay {
            return "Starting microphone"
        }
        if case .recording = state.normalizedForDisplay {
            return "Recording started"
        }
        return nil
    }

    private func handleBackgroundTap() {
        switch pill.actionAvailability {
        case .restore:
            onPrimary?()
        case .dismissTerminal:
            onPrimary?()
        case .cancel, .finish:
            onCancel?()
        case .none:
            break
        }
    }

    private var recordingLevel: Float {
        audioLevel.level
    }
}

private struct WaveformBars: View {
    let level: Float
    var dimmed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Matches `mayn_voice_pill_centered_final.html` drawWave at 1× (canvas native is 2×).
    private let barCount = 8
    private let barWidth: CGFloat = 2.4
    private let barSpacing: CGFloat = 2.2
    private let barWeights: [CGFloat] = [
        0.42, 0.62, 0.82, 0.96, 0.96, 0.82, 0.62, 0.42,
    ]
    private let minBarHeight: CGFloat = 3.0
    private let maxBarHeight: CGFloat = 25.0
    private let amplitudeScale: CGFloat = 23.0
    private let dimWaveLevel: CGFloat = 0.28

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let nowMs = context.date.timeIntervalSinceReferenceDate * 1000
            let waveLevel: CGFloat = dimmed
                ? dimWaveLevel
                : CGFloat(min(max(level, 0), 1))

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let phase = nowMs / (115 + Double(index) * 8) + Double(index) * 0.55
                    let pulse: CGFloat = reduceMotion
                        ? 1.0
                        : 0.72 + CGFloat(sin(phase)) * 0.28
                    let target = minBarHeight
                        + barWeights[index] * waveLevel * pulse * amplitudeScale
                    let height = min(maxBarHeight, max(minBarHeight, target))
                    Capsule()
                        .fill(Color.white.opacity(0.96))
                        .frame(width: barWidth, height: height)
                }
            }
        }
        .frame(width: 108, height: 26)
        .accessibilityHidden(true)
    }
}

private struct EntranceTransform<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var inflated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .opacity(inflated ? 1 : 0)
            .offset(y: inflated ? 0 : MAYNMotionBridge.translation(4, reduceMotion: reduceMotion))
            .scaleEffect(inflated ? 1 : (reduceMotion ? 1 : 0.82))
            .onAppear {
                withAnimation(MAYNMotion.animation(.control, reduceMotion: reduceMotion)) {
                    inflated = true
                }
            }
    }
}

/// NSHostingView subclass that reports acceptsFirstMouse = true so SwiftUI
/// buttons in the floating HUD respond on the first click without requiring
/// the panel to become key first.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
