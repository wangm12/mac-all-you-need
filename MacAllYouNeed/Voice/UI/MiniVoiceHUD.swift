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

/// Drives Typeless-style cleanup progress wipe on the transcribing pill: optional
/// boot sweep before the first stream chunk, then monotonic progress to `1`
/// (see `MiniVoiceHUDView`).
@MainActor
final class MiniVoiceThinkingProgressBridge: ObservableObject {
    private enum ProgressPolicy {
        static let bootSweepMax = 0.32
        static let bootStepCount = 10
        static let bootStepNanos: UInt64 = 40_000_000
        static let completionSnapThreshold = 0.995
    }
    /// Combined wipe amount 0...1 for the black fill (`max(boot, stream)`).
    @Published private(set) var displayWipe: Double = 0

    private var streamProgress: Double = 0
    private var bootProgress: Double = 0
    private var bootTask: Task<Void, Never>?

    func cancelBootAndResetDisplay() {
        bootTask?.cancel()
        bootTask = nil
        streamProgress = 0
        bootProgress = 0
        displayWipe = 0
    }

    /// Starts a new cleanup-wipe session: reset, then optional ~400ms boot to ~0.32
    /// until stream progress overtakes it.
    func beginThinkingSession(reduceMotion: Bool) {
        cancelBootAndResetDisplay()
        guard !reduceMotion else { return }
        bootTask = Task { @MainActor in
            for i in 1 ... ProgressPolicy.bootStepCount {
                try? await Task.sleep(nanoseconds: ProgressPolicy.bootStepNanos)
                guard !Task.isCancelled else { return }
                bootProgress = ProgressPolicy.bootSweepMax * Double(i) / Double(ProgressPolicy.bootStepCount)
                recombine()
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
        case recording(level: Float)
        case transcribing(TranscribingSubphase)
        case cancelled
        case noSpeech(String)
        case error(String)
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

    func show(
        _ state: State,
        onCancel: (() -> Void)? = nil,
        onPrimary: (() -> Void)? = nil
    ) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if case let .transcribing(sub) = state, case let .cleanup(initial) = sub {
            thinkingProgressBridge.beginThinkingSession(reduceMotion: reduceMotion)
            if initial > 0 {
                thinkingProgressBridge.applyStreamProgress(initial)
            }
        } else {
            thinkingProgressBridge.cancelBootAndResetDisplay()
        }
        let nextView = MiniVoiceHUDView(
            state: state,
            thinkingProgress: thinkingProgressBridge,
            audioLevel: audioLevelBridge,
            onCancel: onCancel,
            onPrimary: onPrimary
        )
        let size = MiniVoiceHUDLayout.size(for: state)

        if let controller = panelController, controller.isPresented {
            // Already visible — update content in-place, no re-animation.
            firstMouseHosting?.rootView = nextView
            firstMouseHosting?.frame = NSRect(origin: .zero, size: size)
            controller.updateSize(size)
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

    func dismiss() {
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
    /// Universal pill size per v8 spec — fixed 144×32 chrome.
    static let pillWidth: CGFloat = 144
    static let pillHeight: CGFloat = 32
    static let pillSize = CGSize(width: pillWidth, height: pillHeight)
    /// Distance from the screen `visibleFrame` bottom (above Dock / inset) to the pill origin.
    static let bottomInsetAboveDock: CGFloat = 28
    static let cornerRadius: CGFloat = 16
    static let iconSize: CGFloat = 14
    /// X-center of the left status slot inside the pill (spec §slot metrics).
    static let leftSlotCenter: CGFloat = 20
    /// X-center of the right stop slot inside the pill.
    static let rightSlotCenter: CGFloat = 124
    /// Label safe-zone insets (34pt from each edge, 76pt centered band at default width).
    static let labelInset: CGFloat = 34
    static let fontSize: CGFloat = 11

    static func size(for _: MiniVoiceHUD.State) -> CGSize {
        pillSize
    }
}

enum MiniVoiceHUDPalette {
    // MiniVoiceHUD is a documented design.md §10 exception for raw RGB so the
    // HUD reads against arbitrary desktop backgrounds. v7 tokens.
    static let pillBlack = Color(red: 0x05 / 255.0, green: 0x05 / 255.0, blue: 0x05 / 255.0)
    /// Cool gray track behind the transcribing cleanup wipe (Typeless-style).
    static let pillThinkingTrack = Color(red: 0x5A / 255.0, green: 0x5A / 255.0, blue: 0x5C / 255.0)
    static let pillBorder = Color(red: 0x36 / 255.0, green: 0x36 / 255.0, blue: 0x36 / 255.0)
    static let pillBorderHover = Color(red: 0x60 / 255.0, green: 0x60 / 255.0, blue: 0x60 / 255.0)
    static let pillText = Color.white
    static let stopActiveOpacity: Double = 1.0
    static let stopDisabledOpacity: Double = 0.68
}

struct MiniVoiceHUDPill: Equatable {
    let state: MiniVoiceHUD.State
    private let contentModel: VoicePillContentModel

    typealias Leading = VoicePillContentModel.Leading

    init(state: MiniVoiceHUD.State) {
        self.state = state
        contentModel = VoicePillContentModel(state: state)
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

    /// True when the user can stop the in-flight task. The right slot shows the
    /// stop button only for these states.
    var isStoppable: Bool {
        actionAvailability == .stop
    }

    /// True when the right slot shows an Undo affordance instead of Stop.
    var isUndoable: Bool {
        actionAvailability == .undo
    }

    var isTerminal: Bool {
        actionAvailability == .dismissTerminal
    }
}

enum VoicePillActionAvailability: Equatable {
    case none
    case stop
    case undo
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

    init(state: MiniVoiceHUD.State) {
        switch state.normalizedForDisplay {
        case .idlePreview:
            label = ""
            labelTransitionSlot = "idlePreview"
            leading = .none
            actionAvailability = .none
        case .recording:
            label = "Listening"
            labelTransitionSlot = "recording"
            leading = .waveformBars
            actionAvailability = .stop
        case let .transcribing(subphase):
            switch subphase {
            case .finalizing:
                label = "Transcribing"
                labelTransitionSlot = "finalizing"
            case .asr:
                label = "Transcribing"
                labelTransitionSlot = "transcribing"
            case .cleanup:
                label = "Transcribing"
                labelTransitionSlot = "cleaning"
            case .pasting:
                label = "Transcribing"
                labelTransitionSlot = "pasting"
            }
            leading = .aiSparkle
            actionAvailability = .stop
        case .cancelled:
            label = "Cancelled"
            labelTransitionSlot = "cancelled"
            leading = .xInCircle
            actionAvailability = .undo
        case .noSpeech:
            label = "No speech"
            labelTransitionSlot = "noSpeech"
            leading = .warningTriangle
            actionAvailability = .dismissTerminal
        case .error:
            label = "Failed"
            labelTransitionSlot = "error"
            leading = .warningTriangle
            actionAvailability = .dismissTerminal
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
    @ObservedObject var thinkingProgress: MiniVoiceThinkingProgressBridge
    @ObservedObject var audioLevel: MiniVoiceAudioLevelBridge
    let onCancel: (() -> Void)?
    let onPrimary: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var hudAsymmetricTransition: AnyTransition {
        let entryOffset = MAYNMotionBridge.translation(-4, reduceMotion: reduceMotion)
        let exitOffset = MAYNMotionBridge.translation(4, reduceMotion: reduceMotion)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: entryOffset)),
            removal: .opacity.combined(with: .offset(y: exitOffset))
        )
    }

    var body: some View {
        EntranceTransform {
            ZStack {
                Group {
                    if showsTranscribingCleanupWipe {
                        thinkingPillBackground(wipe: thinkingProgress.displayWipe)
                    } else {
                        Capsule()
                            .fill(MiniVoiceHUDPalette.pillBlack)
                    }
                }
                .animation(
                    MAYNMotion.animation(.control, reduceMotion: reduceMotion),
                    value: thinkingWipeAnimationValue
                )
                .overlay(
                    Capsule().strokeBorder(
                        isHovering && pill.isStoppable
                            ? MiniVoiceHUDPalette.pillBorderHover
                            : MiniVoiceHUDPalette.pillBorder,
                        lineWidth: 1
                    )
                )

                leadingIcon
                    .id(pill.leading)
                    .transition(hudAsymmetricTransition)
                    .frame(width: MiniVoiceHUDLayout.iconSize,
                           height: MiniVoiceHUDLayout.iconSize)
                    .position(x: MiniVoiceHUDLayout.leftSlotCenter,
                              y: MiniVoiceHUDLayout.pillHeight / 2)

                Text(pill.label)
                    .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                    .foregroundStyle(MiniVoiceHUDPalette.pillText)
                    .lineLimit(1)
                    .id(pill.labelTransitionSlot)
                    .transition(hudAsymmetricTransition)
                    .frame(width: max(0, MiniVoiceHUDLayout.pillWidth - MiniVoiceHUDLayout.labelInset * 2))
                    .position(x: MiniVoiceHUDLayout.pillWidth / 2,
                              y: MiniVoiceHUDLayout.pillHeight / 2)

                if pill.actionAvailability == .stop {
                    StopButton(action: onPrimary ?? onCancel)
                        .position(x: MiniVoiceHUDLayout.rightSlotCenter,
                                  y: MiniVoiceHUDLayout.pillHeight / 2)
                } else if pill.actionAvailability == .undo, let onPrimary {
                    UndoButton(action: onPrimary)
                        .position(x: MiniVoiceHUDLayout.rightSlotCenter,
                                  y: MiniVoiceHUDLayout.pillHeight / 2)
                }
            }
            .frame(width: MiniVoiceHUDLayout.pillWidth,
                   height: MiniVoiceHUDLayout.pillHeight)
            .contentShape(Capsule())
            .onTapGesture(perform: handleBackgroundTap)
            .onHover { isHovering = $0 }
            .animation(MAYNMotion.animation(.control, reduceMotion: reduceMotion), value: pill.leading)
            .animation(MAYNMotion.animation(.control, reduceMotion: reduceMotion), value: pill.labelTransitionSlot)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .frame(width: MiniVoiceHUDLayout.pillWidth,
               height: MiniVoiceHUDLayout.pillHeight)
    }

    private var pill: MiniVoiceHUDPill {
        MiniVoiceHUDPill(state: state)
    }

    private var showsTranscribingCleanupWipe: Bool {
        if case let .transcribing(sub) = state.normalizedForDisplay, case .cleanup = sub { return true }
        return false
    }

    /// Stable animation token for the cleanup wipe; `-1` when the wipe stack is inactive.
    private var thinkingWipeAnimationValue: Double {
        if showsTranscribingCleanupWipe { return thinkingProgress.displayWipe }
        return -1
    }

    @ViewBuilder
    private func thinkingPillBackground(wipe: Double) -> some View {
        let w = min(1, max(0, wipe))
        let fillWidth = MiniVoiceHUDLayout.pillWidth * w
        ZStack(alignment: .leading) {
            Capsule()
                .fill(MiniVoiceHUDPalette.pillThinkingTrack)
            Capsule()
                .fill(MiniVoiceHUDPalette.pillBlack)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: fillWidth)
                }
        }
        .frame(width: MiniVoiceHUDLayout.pillWidth, height: MiniVoiceHUDLayout.pillHeight)
        .clipShape(Capsule())
    }

    private var accessibilityText: String {
        if pill.isUndoable { return "\(pill.label). Undo available." }
        return pill.isStoppable ? "\(pill.label). Stop available." : pill.label
    }

    private func handleBackgroundTap() {
        // Stoppable: tapping the body (not the stop button) cancels.
        // Undoable (cancelled): tapping the body dismisses; the right Undo
        // button reruns the transcription.
        // Terminal: tapping the body dismisses.
        switch pill.actionAvailability {
        case .stop:
            onCancel?()
        case .undo:
            onCancel?()
        case .dismissTerminal:
            onPrimary?()
        case .none:
            break
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        switch pill.leading {
        case .waveformBars:     WaveformBars(level: recordingLevel)
        case .aiSparkle:        AISparkleIcon()
        case .bouncingDots:     HorizontalBouncingDots()
        case .checkInCircle:    CheckInCircle()
        case .xInCircle:        XInCircle()
        case .warningTriangle:  WarningTriangle()
        case .none:             EmptyView()
        }
    }

    private var recordingLevel: Float {
        audioLevel.level
    }
}

private struct WaveformBars: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let barCount = 8
    private let barWidth: CGFloat = 1.45
    private let barSpacing: CGFloat = 1.65
    /// Per-bar amplitude weights (taller center emphasis).
    private let barWeights: [CGFloat] = [0.38, 0.58, 0.78, 0.95, 0.88, 0.72, 0.55, 0.42]
    /// Baseline bar height in pt when the mic is silent (level == 0).
    private let baselineHeight: CGFloat = 2.5
    /// Peak amplitude added on top of baseline when level == 1 and stagger peaks.
    private let amplitudeRange: CGFloat = 12.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let levelClamped = CGFloat(min(max(level, 0), 1))
            let idleBreath = reduceMotion ? 1.0 : 0.92 + 0.08 * CGFloat(sin(now / 0.55))

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let freq = 0.085 + Double(index) * 0.012
                    let stagger: CGFloat = reduceMotion
                        ? 1.0
                        : 0.86 + CGFloat(sin(now / freq + Double(index) * 0.35)) * 0.14
                    let breath = levelClamped < 0.02 ? idleBreath : 1.0
                    let height = baselineHeight
                        + levelClamped * barWeights[index] * stagger * amplitudeRange * breath
                    Capsule()
                        .fill(Color.white)
                        .frame(width: barWidth, height: max(baselineHeight, height))
                }
            }
        }
        .frame(height: MiniVoiceHUDLayout.iconSize)
        .accessibilityHidden(true)
    }
}

private struct AISparkleIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let loopPeriod: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let phase = now.truncatingRemainder(dividingBy: loopPeriod) / loopPeriod
            let sine = (sin(phase * 2 * .pi) + 1) / 2
            let pulse: CGFloat = reduceMotion ? 1 : 0.96 + 0.04 * CGFloat(sine)
            let opacity: Double = reduceMotion ? 0.86 : 0.72 + 0.28 * sine

            ZStack {
                // 4-line sparkle star centered in the icon frame.
                Path { path in
                    path.move(to: CGPoint(x: 7, y: 0.2))
                    path.addLine(to: CGPoint(x: 7, y: 13.8))
                    path.move(to: CGPoint(x: 0.2, y: 7))
                    path.addLine(to: CGPoint(x: 13.8, y: 7))
                    path.move(to: CGPoint(x: 3.4, y: 3.4))
                    path.addLine(to: CGPoint(x: 10.6, y: 10.6))
                    path.move(to: CGPoint(x: 10.6, y: 3.4))
                    path.addLine(to: CGPoint(x: 3.4, y: 10.6))
                }
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: 1.55, lineCap: .round))

                // Two faint accent strokes leading out of the star.
                Path { path in
                    path.move(to: CGPoint(x: 9.8, y: 5.1))
                    path.addLine(to: CGPoint(x: 12.6, y: 3.1))
                    path.move(to: CGPoint(x: 4.2, y: 9.4))
                    path.addLine(to: CGPoint(x: 1.4, y: 11.4))
                }
                .stroke(Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round))

                // Bright top-right sparkle dot.
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.7, height: 2.7)
                    .position(x: 14.2, y: 1.9)

                // Dimmer bottom-left sparkle dot.
                Circle()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: 2.3, height: 2.3)
                    .position(x: -0.2, y: 12.6)
            }
            .frame(width: MiniVoiceHUDLayout.iconSize,
                   height: MiniVoiceHUDLayout.iconSize)
            .scaleEffect(pulse)
            .opacity(opacity)
        }
        .accessibilityHidden(true)
    }
}

private struct HorizontalBouncingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dotCount = 3
    private let dotSize: CGFloat = 2.1
    private let spacing: CGFloat = 3.2
    private let bouncePeriod: TimeInterval = 0.42
    private let stagger: TimeInterval = 0.12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0 ..< dotCount, id: \.self) { index in
                    let phase = now - Double(index) * stagger
                    let t = phase.truncatingRemainder(dividingBy: bouncePeriod) / bouncePeriod
                    let y: CGFloat = reduceMotion ? 0 : -3.2 * CGFloat(abs(sin(t * .pi)))
                    Circle()
                        .fill(Color.white)
                        .frame(width: dotSize, height: dotSize)
                        .offset(y: y)
                }
            }
        }
        .frame(width: MiniVoiceHUDLayout.iconSize,
               height: MiniVoiceHUDLayout.iconSize)
        .accessibilityHidden(true)
    }
}

private struct CheckInCircle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1.55)
            Path { path in
                path.move(to: CGPoint(x: 3.0, y: 7.0))
                path.addLine(to: CGPoint(x: 6.0, y: 10.4))
                path.addLine(to: CGPoint(x: 12.3, y: 2.6))
            }
            .stroke(Color.white,
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))
            .offset(x: -0.5, y: -1)
        }
        .frame(width: MiniVoiceHUDLayout.iconSize,
               height: MiniVoiceHUDLayout.iconSize)
        .accessibilityHidden(true)
    }
}

private struct XInCircle: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1.55)
            Path { path in
                path.move(to: CGPoint(x: 3.6, y: 3.6))
                path.addLine(to: CGPoint(x: 10.4, y: 10.4))
                path.move(to: CGPoint(x: 10.4, y: 3.6))
                path.addLine(to: CGPoint(x: 3.6, y: 10.4))
            }
            .stroke(Color.white,
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round))
        }
        .frame(width: MiniVoiceHUDLayout.iconSize,
               height: MiniVoiceHUDLayout.iconSize)
        .accessibilityHidden(true)
    }
}

private struct WarningTriangle: View {
    var body: some View {
        ZStack {
            // Triangle outline
            Path { path in
                path.move(to: CGPoint(x: 7, y: 0.3))
                path.addLine(to: CGPoint(x: 0.3, y: 13.7))
                path.addLine(to: CGPoint(x: 13.7, y: 13.7))
                path.closeSubpath()
            }
            .stroke(Color.white,
                    style: StrokeStyle(lineWidth: 1.55, lineJoin: .round))

            // Exclamation stem
            Path { path in
                path.move(to: CGPoint(x: 7, y: 5.7))
                path.addLine(to: CGPoint(x: 7, y: 10))
            }
            .stroke(Color.white,
                    style: StrokeStyle(lineWidth: 1.55, lineCap: .round))

            // Exclamation dot
            Circle()
                .fill(Color.white)
                .frame(width: 1.6, height: 1.6)
                .offset(x: 0, y: 4.9 - MiniVoiceHUDLayout.iconSize / 2 + 0.8)
        }
        .frame(width: MiniVoiceHUDLayout.iconSize,
               height: MiniVoiceHUDLayout.iconSize)
        .accessibilityHidden(true)
    }
}

private struct StopButton: View {
    let action: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button {
            action?()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 1.55)
                RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 6.9, height: 6.9)
            }
            .frame(width: MiniVoiceHUDLayout.iconSize,
                   height: MiniVoiceHUDLayout.iconSize)
            .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("Cancel dictation")
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // No-op; press tracking lives in onPressingChanged below.
        } onPressingChanged: { pressing in
            if reduceMotion {
                isPressed = pressing
            } else {
                withAnimation(MAYNMotion.animation(.press, reduceMotion: reduceMotion)) {
                    isPressed = pressing
                }
            }
        }
    }
}

private struct UndoButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: MiniVoiceHUDLayout.iconSize,
                       height: MiniVoiceHUDLayout.iconSize)
                .background(Circle().stroke(Color.white, lineWidth: 1.55))
                .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Undo")
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // No-op; press tracking lives in onPressingChanged below.
        } onPressingChanged: { pressing in
            if reduceMotion {
                isPressed = pressing
            } else {
                withAnimation(MAYNMotion.animation(.press, reduceMotion: reduceMotion)) {
                    isPressed = pressing
                }
            }
        }
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
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
