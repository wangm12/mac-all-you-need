import AppKit
import SwiftUI
import UI

@MainActor
final class MiniVoiceHUD {
    enum State: Equatable {
        case idlePreview
        case recording(level: Float)
        case transcribing
        case thinking
        case pasted
        case copied
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
        let nextView = MiniVoiceHUDView(
            state: state,
            onCancel: onCancel,
            onPrimary: onPrimary
        )
        let size = MiniVoiceHUDLayout.pillSize

        if let controller = panelController, controller.isPresented {
            // Already visible — update content in-place, no re-animation.
            firstMouseHosting?.rootView = nextView
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
            panel.contentView = fmh
            firstMouseHosting = fmh
        }
    }

    func dismiss() {
        guard let controller = panelController, controller.isPresented else { return }
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
            y: frame.minY + 96
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
    /// Universal pill size per v7 spec. Every state uses the same 144x32pt
    /// chrome — no morph, no resize.
    static let pillWidth: CGFloat = 144
    static let pillHeight: CGFloat = 32
    static let pillSize = CGSize(width: pillWidth, height: pillHeight)
    static let cornerRadius: CGFloat = 16
    static let iconSize: CGFloat = 14
    /// X-center of the left status slot inside the pill (spec §slot metrics).
    static let leftSlotCenter: CGFloat = 20
    /// X-center of the right stop slot inside the pill.
    static let rightSlotCenter: CGFloat = 124
    /// Label safe-zone insets (34pt from each edge, 76pt centered band).
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
    static let pillBorder = Color(red: 0x36 / 255.0, green: 0x36 / 255.0, blue: 0x36 / 255.0)
    static let pillBorderHover = Color(red: 0x60 / 255.0, green: 0x60 / 255.0, blue: 0x60 / 255.0)
    static let pillText = Color.white
    static let stopActiveOpacity: Double = 1.0
    static let stopDisabledOpacity: Double = 0.68
}

struct MiniVoiceHUDPill: Equatable {
    enum Leading {
        case waveformBars
        case aiSparkle
        case dotSpinner
        case checkInCircle
        case xInCircle
        case warningTriangle
        case none
    }

    let state: MiniVoiceHUD.State

    init(state: MiniVoiceHUD.State) {
        self.state = state
    }

    var label: String {
        switch state.normalizedForDisplay {
        case .idlePreview: ""
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        case .thinking: "Thinking"
        case .pasted: "Applied"
        case .copied: "Copied"
        case .cancelled: "Cancelled"
        case .noSpeech: "No speech"
        case .error: "Failed"
        }
    }

    var leading: Leading {
        switch state.normalizedForDisplay {
        case .idlePreview: .none
        case .recording: .waveformBars
        case .transcribing: .aiSparkle
        case .thinking: .dotSpinner
        case .pasted, .copied: .checkInCircle
        case .cancelled: .xInCircle
        case .noSpeech, .error: .warningTriangle
        }
    }

    /// True when the user can stop the in-flight task. The right slot shows the
    /// stop button only for these states.
    var isStoppable: Bool {
        switch state.normalizedForDisplay {
        case .recording, .transcribing, .thinking: true
        default: false
        }
    }

    /// True when the right slot shows an Undo affordance instead of Stop.
    var isUndoable: Bool {
        if case .cancelled = state.normalizedForDisplay { return true }
        return false
    }

    var isTerminal: Bool {
        switch state.normalizedForDisplay {
        case .pasted, .copied, .noSpeech, .error: true
        default: false
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
    let onCancel: (() -> Void)?
    let onPrimary: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        EntranceTransform {
            ZStack {
                Capsule()
                    .fill(MiniVoiceHUDPalette.pillBlack)
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
                    .transition(.opacity)
                    .frame(width: MiniVoiceHUDLayout.iconSize,
                           height: MiniVoiceHUDLayout.iconSize)
                    .position(x: MiniVoiceHUDLayout.leftSlotCenter,
                              y: MiniVoiceHUDLayout.pillHeight / 2)

                Text(pill.label)
                    .font(.system(size: MiniVoiceHUDLayout.fontSize, weight: .semibold))
                    .foregroundStyle(MiniVoiceHUDPalette.pillText)
                    .lineLimit(1)
                    .id(pill.label)
                    .transition(.opacity)
                    .frame(width: MiniVoiceHUDLayout.pillWidth - MiniVoiceHUDLayout.labelInset * 2)
                    .position(x: MiniVoiceHUDLayout.pillWidth / 2,
                              y: MiniVoiceHUDLayout.pillHeight / 2)

                if pill.isStoppable {
                    StopButton(action: onPrimary ?? onCancel)
                        .position(x: MiniVoiceHUDLayout.rightSlotCenter,
                                  y: MiniVoiceHUDLayout.pillHeight / 2)
                } else if pill.isUndoable, let onPrimary {
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
            .animation(MAYNMotion.animation(.press, reduceMotion: reduceMotion), value: pill.leading)
            .animation(MAYNMotion.animation(.press, reduceMotion: reduceMotion), value: pill.label)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .frame(width: MiniVoiceHUDLayout.pillWidth,
               height: MiniVoiceHUDLayout.pillHeight)
    }

    private var pill: MiniVoiceHUDPill {
        MiniVoiceHUDPill(state: state)
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
        if pill.isStoppable {
            onCancel?()
        } else if pill.isUndoable {
            onCancel?()
        } else if pill.isTerminal {
            onPrimary?()
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        switch pill.leading {
        case .waveformBars:     WaveformBars(level: recordingLevel)
        case .aiSparkle:        AISparkleIcon()
        case .dotSpinner:       DotSpinner()
        case .checkInCircle:    CheckInCircle()
        case .xInCircle:        XInCircle()
        case .warningTriangle:  WarningTriangle()
        case .none:             EmptyView()
        }
    }

    private var recordingLevel: Float {
        if case let .recording(level) = state { return level }
        return 0
    }
}

private struct WaveformBars: View {
    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let barCount = 6
    private let barWidth: CGFloat = 1.8
    private let barSpacing: CGFloat = 2.3
    /// Per-bar amplitude weights (v8 spec). Matches the static SVG bar heights
    /// but is now multiplied by the live mic level so the wave reacts to voice.
    private let barWeights: [CGFloat] = [0.35, 0.62, 0.92, 0.70, 0.82, 0.48]
    /// Baseline bar height in pt when the mic is silent (level == 0).
    private let baselineHeight: CGFloat = 2.4
    /// Peak amplitude added on top of baseline when level == 1 and stagger peaks.
    private let amplitudeRange: CGFloat = 11

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let levelClamped = CGFloat(min(max(level, 0), 1))

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    let stagger: CGFloat = reduceMotion
                        ? 1.0
                        : 0.86 + CGFloat(sin(now / 0.09 + Double(index))) * 0.14
                    let height = baselineHeight
                        + levelClamped * barWeights[index] * stagger * amplitudeRange
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

private struct DotSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dotCount = 8
    private let loopPeriod: TimeInterval = 1.1
    private let radius: CGFloat = 5
    private let dotSize: CGFloat = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let phase = now.truncatingRemainder(dividingBy: loopPeriod) / loopPeriod
            let leadIndex = reduceMotion ? 0 : Int(phase * Double(dotCount)) % dotCount

            ZStack {
                ForEach(0 ..< dotCount, id: \.self) { index in
                    let offset = (index - leadIndex + dotCount) % dotCount
                    let opacity = 1.0 - (Double(offset) / Double(dotCount)) * 0.78
                    let angle = Angle(degrees: Double(index) * (360.0 / Double(dotCount)) - 90)
                    Circle()
                        .fill(Color.white.opacity(opacity))
                        .frame(width: dotSize, height: dotSize)
                        .offset(x: cos(angle.radians) * radius,
                                y: sin(angle.radians) * radius)
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
        .accessibilityLabel("Stop and transcribe")
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // No-op; press tracking lives in onPressingChanged below.
        } onPressingChanged: { pressing in
            if reduceMotion {
                isPressed = pressing
            } else {
                withAnimation(MAYNMotion.animation(.press, reduceMotion: false)) {
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
                withAnimation(MAYNMotion.animation(.press, reduceMotion: false)) {
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
            .scaleEffect(inflated ? 1 : (reduceMotion ? 1 : 0.98))
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
