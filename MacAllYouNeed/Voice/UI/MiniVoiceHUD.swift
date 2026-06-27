import AppKit
import Combine
import Core
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
        case inserted
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
    private var obstructionObserver: NSObjectProtocol?

    init() {
        obstructionObserver = NotificationCenter.default.addObserver(
            forName: FloatingBottomObstructionProvider.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionIfVisible()
            }
        }
    }

    deinit {
        if let obstructionObserver {
            NotificationCenter.default.removeObserver(obstructionObserver)
        }
    }

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
        if let panel = panelController?.currentPanel, isVisible {
            return panel.frame.minY
        }
        guard let screen = targetScreen ?? Self.screenContainingMouseCursor() ?? NSScreen.main else { return 0 }
        let frame = screen.visibleFrame
        return MiniVoiceHUDLayout.defaultPillBottomY(
            in: frame,
            screenFrame: screen.frame,
            bottomObstruction: FloatingBottomObstructionProvider.bottomObstruction(for: frame)
        )
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
            if let panel = controller.currentPanel {
                normalizePresentationLayer(panel: panel)
                panel.setContentSize(size)
                firstMouseHosting?.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: size)
                panel.setFrameOrigin(targetOrigin(for: size))
                VoiceHUDWindowLayering.orderFront(panel)
            }
            return
        }

        // New session — lock to the screen the user is currently on.
        targetScreen = Self.screenContainingMouseCursor()

        if panelController == nil {
            let showDuration = MAYNMotionBridge.effectiveDuration(.toastIn)
            let hideDuration = MAYNMotionBridge.effectiveDuration(.toastOut)
            panelController = NonActivatingFloatingPanelController<MiniVoiceHUDView>(
                styleMask: [.borderless, .nonactivatingPanel],
                level: VoiceHUDWindowLayering.windowLevel,
                collectionBehavior: VoiceHUDWindowLayering.collectionBehavior,
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

        // No panel fade — SwiftUI entrance scale/opacity was getting stuck mid-animation.
        panelController?.present(rootView: nextView, size: size, animated: false)

        // Apply HUD-specific panel settings not exposed by the shared controller,
        // and swap in FirstMouseHostingView so buttons respond on the first click
        // without requiring the panel to become key.
        if let panel = panelController?.currentPanel {
            VoiceHUDWindowLayering.configureGlassPanel(panel, acceptsMouseEvents: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            let fmh = FirstMouseHostingView(rootView: nextView)
            fmh.frame = NSRect(origin: .zero, size: size)
            panel.contentView = fmh
            firstMouseHosting = fmh
            normalizePresentationLayer(panel: panel)
            VoiceHUDWindowLayering.orderFront(panel)
        }
    }

    /// Clears any in-flight dismiss scale / panel fade so the pill never sticks small or dim.
    private func normalizePresentationLayer(panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0
            panel.animator().alphaValue = 1
        })
        panel.alphaValue = 1
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.removeAllAnimations()
        panel.contentView?.layer?.setAffineTransform(.identity)
        firstMouseHosting?.wantsLayer = true
        firstMouseHosting?.layer?.removeAllAnimations()
        firstMouseHosting?.layer?.setAffineTransform(.identity)
    }

    private func repositionIfVisible() {
        guard let controller = panelController, controller.isPresented,
              let panel = controller.currentPanel
        else { return }
        let size = panel.frame.size
        normalizePresentationLayer(panel: panel)
        panel.setFrameOrigin(targetOrigin(for: size))
        VoiceHUDWindowLayering.orderFront(panel)
    }

    /// Updates the cleanup wipe without rebuilding the hosting view (stream chunks).
    func updateThinkingProgress(_ progress: Double) {
        guard panelController?.isPresented == true else { return }
        thinkingProgressBridge.applyStreamProgress(progress)
    }

    /// Snap wipe to 100%, show Inserted briefly, then dismiss (success path).
    func dismissAfterSuccessHold() async {
        thinkingProgressBridge.applyStreamProgress(1.0)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        show(.inserted, chrome: chromeOptions, onCancel: nil, onPrimary: nil, onFinish: nil)
        let holdNs = UInt64((reduceMotion ? 0.6 : VoiceHUDCopy.Timing.insertedDuration) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: holdNs)
        dismiss()
    }

    func dismiss() {
        isTranscribingSessionActive = false
        thinkingProgressBridge.cancelBootAndResetDisplay()
        audioLevelBridge.reset()
        guard let controller = panelController, controller.isPresented else { return }
        tearDownHUD(controller: controller)
    }

    private func tearDownHUD(controller: NonActivatingFloatingPanelController<MiniVoiceHUDView>) {
        targetScreen = nil
        firstMouseHosting = nil
        controller.dismiss(animated: false)
    }

    private func targetOrigin(for size: CGSize) -> NSPoint {
        let screen = targetScreen
            ?? Self.screenContainingMouseCursor()
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return .zero }
        let obstruction = FloatingBottomObstructionProvider.bottomObstruction(for: frame)
        return MiniVoiceHUDLayout.pillOrigin(
            in: frame,
            screenFrame: screen?.frame ?? frame,
            size: size,
            bottomObstruction: obstruction
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
  /// V3 fixed capsule geometry — identical in every visible state.
  static let pillWidth: CGFloat = 392
  static let pillHeight: CGFloat = 58
  static let sideSlotWidth: CGFloat = 64
  static let actionButtonSize: CGFloat = 40
  static let waveformBoxWidth: CGFloat = 44
  static let waveformBoxHeight: CGFloat = 28
  static let pillSize = CGSize(width: pillWidth, height: pillHeight)
  /// Legacy aliases — all states share one width now.
  static let recordingWidth: CGFloat = pillWidth
  static let transcribingWidth: CGFloat = pillWidth
  static let slowProcessingWidth: CGFloat = pillWidth
  static let clipboardFallbackWidth: CGFloat = pillWidth
  static let terminalMinWidth: CGFloat = pillWidth
  static let terminalMaxWidth: CGFloat = pillWidth
  static let cancelledWidth: CGFloat = pillWidth
  static let maxPillWidth: CGFloat = pillWidth
  /// Gap above the macOS Dock / bottom screen edge — Typeless-style bottom-center anchor.
  static let bottomInsetAboveDock: CGFloat = 28
  /// When the Dock autohides, `visibleFrame` includes the dock strip until it slides in.
  static let autohideDockReserve: CGFloat = 60

  static func pillOrigin(
    in visibleFrame: NSRect,
    screenFrame: NSRect,
    size: CGSize,
    bottomObstruction: CGFloat = 0
  ) -> NSPoint {
    let dockOccupiedInMetrics = max(0, visibleFrame.minY - screenFrame.minY)
    let autohideReserve = dockOccupiedInMetrics > 1 ? 0 : autohideDockReserve
    return NSPoint(
      x: visibleFrame.midX - size.width / 2,
      y: visibleFrame.minY + bottomInsetAboveDock + autohideReserve + bottomObstruction
    )
  }

  static func defaultPillBottomY(
    in visibleFrame: NSRect,
    screenFrame: NSRect,
    pillHeight: CGFloat = pillHeight,
    bottomObstruction: CGFloat = 0
  ) -> CGFloat {
    pillOrigin(
      in: visibleFrame,
      screenFrame: screenFrame,
      size: CGSize(width: pillWidth, height: pillHeight),
      bottomObstruction: bottomObstruction
    ).y
  }
  static let cornerRadius: CGFloat = pillHeight / 2
  static let iconSize: CGFloat = 14
  static let centerLabelFontSize: CGFloat = 13
  static let labelHorizontalPadding: CGFloat = 0
  static let fontSize: CGFloat = centerLabelFontSize
  static let captionFontSize: CGFloat = 10.5
  static let captionHeight: CGFloat = 16
  static let captionHorizontalPadding: CGFloat = 10
  static let captionVerticalPadding: CGFloat = 4
  static let captionCornerRadius: CGFloat = 8
  static let captionShellHeight: CGFloat = captionHeight + captionVerticalPadding * 2
  static let captionGap: CGFloat = 5
  static let alertGapAboveCaption: CGFloat = 8

  static func captionOrigin(pillBottomY: CGFloat, size: CGSize, centerX: CGFloat) -> NSPoint {
    NSPoint(
      x: centerX - size.width / 2,
      y: pillBottomY + pillHeight + captionGap
    )
  }

  static func alertOrigin(
    pillBottomY: CGFloat,
    captionHeight: CGFloat,
    size: CGSize,
    centerX: CGFloat
  ) -> NSPoint {
    NSPoint(
      x: centerX - size.width / 2,
      y: pillBottomY + pillHeight + captionGap + captionHeight + alertGapAboveCaption
    )
  }

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
    _ = state
    _ = label
    _ = chrome
    return pillWidth
  }
}

enum VoiceHUDAppearance: String, CaseIterable, Codable, Equatable, Hashable, Identifiable, SegmentedTabDestination {
    case glass
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .graphite: "Graphite"
        }
    }

    var label: String {
        switch self {
        case .glass: "Frosted Liquid Glass that adapts to the desktop"
        case .graphite: "Solid near-black pill for maximum contrast"
        }
    }

    var symbolName: String {
        switch self {
        case .glass: "sparkles.rectangle.stack"
        case .graphite: "capsule.fill"
        }
    }
}

enum VoiceHUDAppearanceStore {
    static let storageKey = "voice.hud.appearance.v1"
    static let didChangeNotification = Notification.Name("VoiceHUDAppearanceStore.didChange")

    static func load() -> VoiceHUDAppearance {
        let raw = AppGroupSettings.defaults.string(forKey: storageKey)
        return VoiceHUDAppearance(rawValue: raw ?? VoiceHUDAppearance.glass.rawValue) ?? .glass
    }

    static func save(_ appearance: VoiceHUDAppearance) {
        AppGroupSettings.defaults.set(appearance.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
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

    var dimLeading: Bool {
        contentModel.dimLeading
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
    case retry
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

    /// When true, left-slot waveform renders at reduced opacity (transcribing).
    let dimLeading: Bool

    let label: String
    let labelTransitionSlot: String
    let leading: Leading
    let actionAvailability: VoicePillActionAvailability
    let secondaryAction: VoicePillSecondaryAction

    init(state: MiniVoiceHUD.State, chrome: MiniVoiceHUD.ChromeOptions = .init()) {
        let normalized = state.normalizedForDisplay
        dimLeading = if case .transcribing = normalized { true } else { false }
        switch normalized {
        case .idlePreview:
            label = ""
            labelTransitionSlot = "idlePreview"
            leading = .none
            actionAvailability = .none
            secondaryAction = .none
        case .startingMic:
            label = VoiceHUDCopy.Pill.starting
            labelTransitionSlot = "startingMic"
            leading = .bouncingDots
            actionAvailability = .none
            secondaryAction = .none
        case .recording:
            label = VoiceHUDCopy.Pill.listening
            labelTransitionSlot = "recording"
            leading = .waveformBars
            actionAvailability = .cancel
            secondaryAction = .none
        case let .transcribing(_, isSlow):
            if isSlow {
                label = VoiceHUDCopy.Pill.stillWorking
                labelTransitionSlot = "transcribingSlow"
            } else {
                label = VoiceHUDCopy.Pill.transcribing
                labelTransitionSlot = "transcribing"
            }
            leading = .waveformBars
            actionAvailability = .none
            secondaryAction = .none
        case .inserted:
            label = VoiceHUDCopy.Pill.inserted
            labelTransitionSlot = "inserted"
            leading = .checkInCircle
            actionAvailability = .none
            secondaryAction = .none
        case .cancelled:
            label = VoiceHUDCopy.Pill.cancelled
            labelTransitionSlot = "cancelled"
            leading = .xInCircle
            actionAvailability = .restore
            secondaryAction = .none
        case .noSpeech:
            label = VoiceHUDCopy.Pill.noSpeech
            labelTransitionSlot = "noSpeech"
            leading = .warningTriangle
            actionAvailability = .dismissTerminal
            secondaryAction = .none
        case let .error(message):
            label = VoiceHUDCopy.pillLabel(for: message)
            labelTransitionSlot = "error"
            leading = .warningTriangle
            if VoiceHUDCopy.isTranscribeFailure(message) || message.localizedCaseInsensitiveContains("paste timed out") {
                actionAvailability = .retry
            } else {
                actionAvailability = .dismissTerminal
            }
            secondaryAction = .none
        case .clipboardFallback:
            label = VoiceHUDCopy.Pill.clipboardFallback
            labelTransitionSlot = "clipboardFallback"
            leading = .checkInCircle
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
    @AppStorage(VoiceHUDAppearanceStore.storageKey, store: AppGroupSettings.defaults)
    private var appearanceRaw = VoiceHUDAppearance.glass.rawValue
    @State private var isHovering = false
    @State private var undoRingProgress: CGFloat = 1
    @State private var undoCountdownTask: Task<Void, Never>?

    private var appearance: VoiceHUDAppearance {
        VoiceHUDAppearance(rawValue: appearanceRaw) ?? .glass
    }

    private var usesGraphiteChrome: Bool {
        appearance == .graphite
    }

    private var contentForeground: Color {
        usesGraphiteChrome ? MiniVoiceHUDPalette.pillText : Color.primary
    }

    private var waveformBarColor: Color {
        usesGraphiteChrome ? Color.white.opacity(0.96) : Color.primary.opacity(0.92)
    }

    private var pillWidth: CGFloat {
        MiniVoiceHUDLayout.pillWidth
    }

    var body: some View {
        ZStack {
            if showsTranscribingProgressWipe {
                transcribingWipeOverlay
            }

            HStack(spacing: 0) {
                leftSlot
                    .frame(width: MiniVoiceHUDLayout.sideSlotWidth, height: MiniVoiceHUDLayout.pillHeight)
                centerSlot
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightSlot
                    .frame(width: MiniVoiceHUDLayout.sideSlotWidth, height: MiniVoiceHUDLayout.pillHeight)
            }
        }
        .frame(width: pillWidth, height: MiniVoiceHUDLayout.pillHeight)
        .voiceHubPillChrome(isGraphite: usesGraphiteChrome)
        .compositingGroup()
        .clipShape(Capsule())
        .shadow(
            color: .black.opacity(usesGraphiteChrome ? 0.26 : 0.08),
            radius: usesGraphiteChrome ? 18 : 8,
            x: 0,
            y: usesGraphiteChrome ? 14 : 4
        )
        .contentShape(Capsule())
        .onTapGesture(perform: handleBackgroundTap)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private var leftSlot: some View {
        HStack {
            Spacer(minLength: 0)
            leftSlotContent
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var leftSlotContent: some View {
        switch pill.leading {
        case .bouncingDots:
            PulsingDot(color: contentForeground)
        case .waveformBars:
            let dimmed: Bool = {
                if pill.dimLeading { return true }
                if case .startingMic = state.normalizedForDisplay { return true }
                if case .recording(_, _, let dim) = state.normalizedForDisplay { return dim }
                return false
            }()
            WaveformBars(
                level: recordingLevel,
                dimmed: dimmed,
                barColor: waveformBarColor
            )
            .frame(
                width: MiniVoiceHUDLayout.waveformBoxWidth,
                height: MiniVoiceHUDLayout.waveformBoxHeight
            )
        case .checkInCircle:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(contentForeground.opacity(0.92))
        case .xInCircle:
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(contentForeground.opacity(0.92))
        case .warningTriangle:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(contentForeground.opacity(0.92))
        case .aiSparkle:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(contentForeground.opacity(0.85))
        case .none:
            Color.clear
                .frame(width: MiniVoiceHUDLayout.waveformBoxWidth, height: MiniVoiceHUDLayout.waveformBoxHeight)
        }
    }

    @ViewBuilder
    private var centerSlot: some View {
        if pill.label.isEmpty {
            Color.clear
        } else {
            Text(pill.label)
                .font(.system(size: MiniVoiceHUDLayout.centerLabelFontSize, weight: .semibold))
                .foregroundStyle(contentForeground.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .id(pill.labelTransitionSlot)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var rightSlot: some View {
        HStack {
            Spacer(minLength: 0)
            switch pill.actionAvailability {
            case .cancel:
                voiceActionButton(icon: "stop.fill", accessibilityLabel: "Stop", action: { onCancel?() })
            case .restore:
                undoActionButton
            case .retry:
                voiceActionButton(icon: "arrow.clockwise", accessibilityLabel: "Retry", action: { onPrimary?() })
            case .finish:
                voiceActionButton(icon: "checkmark", accessibilityLabel: "Finish", action: { onFinish?() })
            case .none, .dismissTerminal:
                Color.clear
                    .frame(width: MiniVoiceHUDLayout.actionButtonSize, height: MiniVoiceHUDLayout.actionButtonSize)
            }
            Spacer(minLength: 0)
        }
    }

    private var undoActionButton: some View {
        ZStack {
            VoiceHUDCountdownRing(progress: undoRingProgress, color: contentForeground.opacity(0.35))
                .frame(width: MiniVoiceHUDLayout.actionButtonSize, height: MiniVoiceHUDLayout.actionButtonSize)
            voiceActionButton(
                icon: "arrow.uturn.backward",
                accessibilityLabel: VoiceHUDCopy.Pill.undo,
                action: { onPrimary?() }
            )
        }
        .onAppear { startUndoCountdown() }
    }

    private func startUndoCountdown() {
        undoRingProgress = 1
        undoCountdownTask?.cancel()
        guard !reduceMotion else { return }
        let duration: TimeInterval = 5
        let started = Date()
        undoCountdownTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                undoRingProgress = CGFloat(max(0, 1 - elapsed / duration))
                if elapsed >= duration { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func voiceActionButton(
        icon: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(contentForeground.opacity(0.92))
                .frame(width: MiniVoiceHUDLayout.actionButtonSize, height: MiniVoiceHUDLayout.actionButtonSize)
                .background(
                    Circle()
                        .fill(
                            usesGraphiteChrome
                                ? Color.white.opacity(0.14)
                                : Color.primary.opacity(0.08)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var transcribingWipeOverlay: some View {
        let w = min(1, max(0, thinkingProgress.displayWipe))
        GeometryReader { geo in
            Capsule()
                .fill(
                    usesGraphiteChrome
                        ? MiniVoiceHUDPalette.pillWipeOverlay
                        : Color.primary.opacity(0.12)
                )
                .frame(width: geo.size.width * w, height: geo.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }

    private var showsTranscribingProgressWipe: Bool {
        if case .transcribing = state.normalizedForDisplay { return true }
        return false
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
        case .restore, .retry:
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
    var barColor: Color = Color.white.opacity(0.96)
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
                        .fill(barColor)
                        .frame(width: barWidth, height: height)
                }
            }
        }
        .frame(width: MiniVoiceHUDLayout.waveformBoxWidth, height: MiniVoiceHUDLayout.waveformBoxHeight)
        .accessibilityHidden(true)
    }
}

private struct PulsingDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color.opacity(pulse ? 0.95 : 0.45))
            .frame(width: 8, height: 8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct VoiceHUDCountdownRing: View {
    let progress: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0, min(1, progress)))
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
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

    override func layout() {
        if let container = superview {
            frame = container.bounds
        }
        super.layout()
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
