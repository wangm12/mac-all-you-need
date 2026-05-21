import AppKit
import Core
import Platform
import SwiftUI

// MARK: - Public SwiftUI entry point

/// Modifier picker that uses the same keyboard popup and CGEventTap
/// infrastructure as `HotkeyRecorder`. Clicking the chip opens the
/// floating keyboard; holding modifier keys highlights them; releasing
/// all modifiers auto-commits — no confirmation press needed.
struct WindowGestureModifierPicker: View {
    @Binding var selection: WindowGestureModifier
    var defaultModifier: WindowGestureModifier = .option
    var width: CGFloat = 112

    var body: some View {
        HStack(spacing: 8) {
            ModifierRecorder(selection: $selection, defaultModifier: defaultModifier, width: width)
                .frame(width: width, height: HotkeyChipPresentation.compactHeight)
                .fixedSize()
            resetButton
        }
    }

    private var resetButton: some View {
        let isDefault = selection == defaultModifier
        return Button {
            selection = defaultModifier
        } label: {
            Text("Reset")
                .font(.callout.weight(isDefault ? .regular : .medium))
                .foregroundStyle(isDefault ? Color.secondary : Color.primary)
                .frame(width: 52, height: HotkeyChipPresentation.compactHeight)
                .background(
                    isDefault ? Color.clear : MAYNTheme.elevated,
                    in: RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                        .stroke(isDefault ? Color.clear : MAYNTheme.strongBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDefault)
        .opacity(isDefault ? 0.62 : 1)
    }
}

// MARK: - NSViewRepresentable bridge

struct ModifierRecorder: NSViewRepresentable {
    @Binding var selection: WindowGestureModifier
    var defaultModifier: WindowGestureModifier = .option
    var width: CGFloat = 112

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> ModifierRecorderNSView {
        let view = ModifierRecorderNSView(width: width)
        view.selection = selection
        view.defaultModifier = defaultModifier
        view.onCommit = { [coordinator = context.coordinator] in coordinator.commit($0) }
        return view
    }

    func updateNSView(_ nsView: ModifierRecorderNSView, context: Context) {
        nsView.defaultModifier = defaultModifier
        guard nsView.selection != selection else { return }
        nsView.selection = selection
    }

    final class Coordinator {
        let selection: Binding<WindowGestureModifier>
        init(selection: Binding<WindowGestureModifier>) { self.selection = selection }
        func commit(_ modifier: WindowGestureModifier) {
            DispatchQueue.main.async { self.selection.wrappedValue = modifier }
        }
    }
}

// MARK: - NSView chip (mirrors HotkeyRecorder.RecorderView closely)

final class ModifierRecorderNSView: NSView {
    var selection: WindowGestureModifier = .none {
        didSet { guard oldValue != selection, !isRecording else { return }; updateChip() }
    }
    var defaultModifier: WindowGestureModifier = .option
    var onCommit: ((WindowGestureModifier) -> Void)?

    // State
    private var isRecording = false
    private var activeFlags: CGEventFlags = []

    // Keyboard monitoring
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let floatingKeyboard = KeyboardShortcutFloatingOverlayController()

    // Chip view
    private let width: CGFloat
    private let chip: NSHostingView<ChipView>

    init(width: CGFloat) {
        self.width = width
        chip = NSHostingView(rootView: ChipView(text: "None", isRecording: false))
        super.init(frame: .zero)
        chip.autoresizingMask = [.width, .height]
        addSubview(chip)
        updateChip()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: HotkeyChipPresentation.compactHeight)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    deinit {
        floatingKeyboard.dismiss(immediate: true)
        stopKeyboardMonitoring()
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        guard !isRecording else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        activeFlags = []
        isRecording = true
        updateChip()
        publishState(.recording())
        startKeyboardMonitoring()
        NotificationCenter.default.post(name: .hotkeyRecorderDidStartRecording, object: self)
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        activeFlags = []
        stopKeyboardMonitoring()
        floatingKeyboard.dismiss()
        publishState(.inactive)
        updateChip()
        NotificationCenter.default.post(name: .hotkeyRecorderDidStopRecording, object: self)
    }

    // MARK: - Modifier tracking

    override func flagsChanged(with event: NSEvent) {
        // First-responder delivery when the settings window is key.
        handleNSModifierFlags(event.modifierFlags)
    }

    private func handleNSModifierFlags(_ flags: NSEvent.ModifierFlags) {
        handleFlagsCGEquivalent(cgEventFlags(from: flags))
    }

    private func handleFlagsCGEquivalent(_ cgFlags: CGEventFlags) {
        guard isRecording else { return }
        let modifier = WindowGestureModifier(cgEventFlags: cgFlags)

        if !modifier.isEmpty {
            activeFlags = cgFlags
            publishState(.recording(cgFlags: cgFlags))
        } else if !WindowGestureModifier(cgEventFlags: activeFlags).isEmpty {
            // All keys released — freeze so Confirm stays visible.
            publishState(.recording(cgFlags: activeFlags))
        }
        updateChip()
    }

    /// Converts `NSEvent.ModifierFlags` to `CGEventFlags` using the
    /// device-independent masks (no left/right distinction — sufficient
    /// for the modifier picker since we only care which modifier, not which side).
    private func cgEventFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.control)  { result.insert(.maskControl) }
        if flags.contains(.option)   { result.insert(.maskAlternate) }
        if flags.contains(.command)  { result.insert(.maskCommand) }
        if flags.contains(.shift)    { result.insert(.maskShift) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }

    // MARK: - Keyboard event monitoring

    private func startKeyboardMonitoring() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            switch event.type {
            case .leftMouseDown:
                if self.floatingKeyboard.owns(window: event.window) { return event }
                if event.window !== self.window
                    || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.stopRecording()
                }
                return event
            case .keyDown where event.keyCode == 53: // Escape
                self.stopRecording()
                return nil
            case .flagsChanged:
                // Use event.modifierFlags — always available, unlike event.cgEvent?.flags.
                self.handleNSModifierFlags(event.modifierFlags)
                return nil
            default:
                return event
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .leftMouseDown]
        ) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.isRecording else { return }
                if event.type == .flagsChanged {
                    self.handleNSModifierFlags(event.modifierFlags)
                } else {
                    self.stopRecording()
                }
            }
        }
    }

    private func stopKeyboardMonitoring() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
    }

    // MARK: - Floating keyboard panel

    private func publishState(_ state: KeyboardShortcutVisualizerState) {
        // Always pass a non-nil placeholder so Confirm / Reset / Cancel are
        // visible from the moment the popup opens. The placeholder value is
        // unused — only its non-nil-ness triggers the button row in
        // KeyboardShortcutRegistrationSummaryView.
        let placeholder = HotkeyDescriptor(keyCode: 0, modifiers: [])

        floatingKeyboard.update(
            state: state,
            candidate: placeholder,
            onReset: { [weak self] in
                guard let self else { return }
                self.onCommit?(self.defaultModifier)
                self.stopRecording()
            },
            onConfirm: { [weak self] in
                guard let self else { return }
                let modifier = WindowGestureModifier(cgEventFlags: self.activeFlags)
                if !modifier.isEmpty { self.onCommit?(modifier) }
                self.stopRecording()
            },
            onCancel: { [weak self] in self?.stopRecording() }
        )
    }

    // MARK: - Chip display

    private func updateChip() {
        let text: String
        if isRecording {
            let live = WindowGestureModifier(cgEventFlags: activeFlags)
            text = live.isEmpty ? "Press modifier…" : live.display
        } else {
            text = selection.isEmpty ? "None" : modifierSymbols(selection)
        }
        chip.rootView = ChipView(text: text, isRecording: isRecording)
    }

    /// Compact symbol glyphs for the idle chip, e.g. "⌃⌥" for Control+Option.
    private func modifierSymbols(_ modifier: WindowGestureModifier) -> String {
        var parts: [String] = []
        if modifier.contains(.fn) { parts.append("fn") }
        if !modifier.intersection([.control, .leftControl, .rightControl]).isEmpty { parts.append("⌃") }
        if !modifier.intersection([.option, .leftOption, .rightOption]).isEmpty { parts.append("⌥") }
        if !modifier.intersection([.command, .leftCommand, .rightCommand]).isEmpty { parts.append("⌘") }
        if !modifier.intersection([.shift, .leftShift, .rightShift]).isEmpty { parts.append("⇧") }
        return parts.isEmpty ? "None" : parts.joined()
    }
}

// MARK: - Chip SwiftUI view

private struct ChipView: View {
    let text: String
    let isRecording: Bool
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(isRecording && text.hasSuffix("…") ? Color.secondary : Color.primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: HotkeyChipPresentation.compactHeight)
            .background(background, in: RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: isRecording ? 1.5 : 1)
            )
            .onHover { isHovering = $0 }
            .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
            .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isRecording)
    }

    private var background: Color {
        isRecording ? Color.accentColor.opacity(0.09)
            : isHovering ? MAYNTheme.elevatedHover
            : MAYNTheme.elevated
    }

    private var borderColor: Color {
        isRecording ? Color.accentColor.opacity(0.45)
            : isHovering ? MAYNTheme.strongBorder
            : MAYNTheme.subtleBorder
    }
}
