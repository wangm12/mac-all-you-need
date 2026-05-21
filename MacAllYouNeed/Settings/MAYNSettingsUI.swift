import AppKit
import Platform
import QuartzCore
import SwiftUI

enum MAYNTheme {
    static let window = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let elevatedHover = Color.primary.opacity(0.045)
    static let elevatedPressed = Color.primary.opacity(0.075)
    static let divider = Color.secondary.opacity(0.16)
    static let selected = Color.primary.opacity(0.08)
    static let hover = Color.primary.opacity(0.05)
    static let muted = Color.secondary
    static let strongBorder = Color.primary.opacity(0.18)
    static let subtleBorder = Color.primary.opacity(0.10)
    static let focusRing = Color.primary.opacity(0.70)
    static let controlTint = Color.secondary
    static let tabSelectedFill = Color.primary.opacity(0.14)
    static let tabSelectedBorder = Color.primary.opacity(0.20)
    static let tabSelectedShadow = Color.black.opacity(0.06)
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let progress = Color.blue
}

enum MAYNMotionDuration {
    static let press: TimeInterval = 0.12
    static let hover: TimeInterval = 0.16
    static let control: TimeInterval = 0.18
    static let tab: TimeInterval = 0.23
    static let panel: TimeInterval = 0.28
    static let instruction: TimeInterval = 0.32
    static let toastIn: TimeInterval = 0.16
    static let toastOut: TimeInterval = 0.22
}

enum MAYNMotionKind {
    case press
    case hover
    case control
    case tab
    case panel
    case instruction
    case toastIn
    case toastOut

    var duration: TimeInterval {
        switch self {
        case .press: MAYNMotionDuration.press
        case .hover: MAYNMotionDuration.hover
        case .control: MAYNMotionDuration.control
        case .tab: MAYNMotionDuration.tab
        case .panel: MAYNMotionDuration.panel
        case .instruction: MAYNMotionDuration.instruction
        case .toastIn: MAYNMotionDuration.toastIn
        case .toastOut: MAYNMotionDuration.toastOut
        }
    }
}

enum MAYNMotion {
    static let press = Animation.easeOut(duration: MAYNMotionDuration.press)
    static let hover = Animation.easeOut(duration: MAYNMotionDuration.hover)
    static let control = Animation.easeOut(duration: MAYNMotionDuration.control)
    static let tab = Animation.easeOut(duration: MAYNMotionDuration.tab)
    static let panel = Animation.easeOut(duration: MAYNMotionDuration.panel)
    static let instruction = Animation.easeOut(duration: MAYNMotionDuration.instruction)
    static let toastIn = Animation.easeOut(duration: MAYNMotionDuration.toastIn)
    static let toastOut = Animation.easeOut(duration: MAYNMotionDuration.toastOut)

    static let fast = press
    static let normal = control

    static func fastAnimation(reduceMotion: Bool) -> Animation? {
        animation(.press, reduceMotion: reduceMotion)
    }

    static func normalAnimation(reduceMotion: Bool) -> Animation? {
        animation(.control, reduceMotion: reduceMotion)
    }

    static func hoverAnimation(reduceMotion: Bool) -> Animation? {
        animation(.hover, reduceMotion: reduceMotion)
    }

    static func controlAnimation(reduceMotion: Bool) -> Animation? {
        animation(.control, reduceMotion: reduceMotion)
    }

    static func tabAnimation(reduceMotion: Bool) -> Animation? {
        animation(.tab, reduceMotion: reduceMotion)
    }

    static func panelAnimation(reduceMotion: Bool) -> Animation? {
        animation(.panel, reduceMotion: reduceMotion)
    }

    static func instructionAnimation(reduceMotion: Bool) -> Animation? {
        animation(.instruction, reduceMotion: reduceMotion)
    }

    static func animation(_ kind: MAYNMotionKind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeOut(duration: kind.duration)
    }
}

enum MAYNMotionBridge {
    static func effectiveDuration(_ kind: MAYNMotionKind, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : kind.duration
    }

    static func effectiveDuration(_ kind: MAYNMotionKind) -> TimeInterval {
        effectiveDuration(kind, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func translation(_ value: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 0 : value
    }

    static func timingFunction(_ kind: MAYNMotionKind) -> CAMediaTimingFunction {
        switch kind {
        case .toastOut:
            CAMediaTimingFunction(name: .easeIn)
        default:
            CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        }
    }
}

enum MAYNControlMetrics {
    static let controlHeight: CGFloat = 30
    static let inlineTabHeight: CGFloat = controlHeight
    static let dropdownHeight: CGFloat = controlHeight
    static let hotkeyHeight: CGFloat = controlHeight
    static let controlRadius: CGFloat = 7
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 8
    static let rowMinHeight: CGFloat = 46
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 9
    static let rowControlSpacing: CGFloat = 16
    static let trailingLaneMinWidth: CGFloat = 220
    static let pickerWidth: CGFloat = 180
    static let widePickerWidth: CGFloat = 220
    static let textFieldWidth: CGFloat = 260
    static let wideTextFieldWidth: CGFloat = 300
}

enum MAYNNotificationPillPresentation {
    static let hasOuterShadow = false
    static let hasIconBackground = false
    static let hasCapsuleStroke = false
    static let iconSize = 14
    static let titleFontSize = 14
    static let detailFontSize = 12
    static let iconFrameSize = 16
    static let horizontalPadding = 14
    static let verticalPadding = 10
    static let copyPanelHeight: CGFloat = 50
    static let minimumCopyPanelWidth: CGFloat = 116
    static let iconTextSpacing: CGFloat = 10

    static func copyPanelSize(message: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: CGFloat(titleFontSize), weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width = max(
            minimumCopyPanelWidth,
            textWidth + CGFloat(iconFrameSize) + iconTextSpacing + CGFloat(horizontalPadding * 2)
        )
        return CGSize(width: width, height: copyPanelHeight)
    }
}

struct MAYNSettingsShell<Sidebar: View, Detail: View>: View {
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .tint(MAYNTheme.controlTint)
        .accentColor(.gray)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 640)
        .background(SettingsWindowConfig())
        .maynDismissTextFocusOnOutsideClick()
    }
}

enum MAYNTextFocusDismissPolicy {
    static func shouldDismissTextFocus(
        isTextEditingFirstResponder: Bool,
        clickedTargetIsTextInput: Bool
    ) -> Bool {
        isTextEditingFirstResponder && !clickedTargetIsTextInput
    }
}

enum MAYNTextEditingShortcutPolicy {
    private static let nativeCommandEditingKeys: Set<String> = ["a", "c", "v", "x", "y", "z"]

    static func shouldYieldToFocusedTextInput(
        isTextEditingFirstResponder: Bool,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let keyMods = modifiers.intersection(.deviceIndependentFlagsMask)
        return isTextEditingFirstResponder
            && keyMods == .command
            && nativeCommandEditingKeys.contains(keyEquivalent.lowercased())
    }

    static func isTextEditingFirstResponder(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is NSText { return true }
        if responder is NSTextView { return true }
        if responder is NSTextField { return true }
        return false
    }
}

private struct MAYNTextFocusDismissBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var view: NSView?
        private var localMouseMonitor: NSEventMonitorHandle?

        deinit {
            detach()
        }

        func attach(to view: NSView) {
            self.view = view
            guard localMouseMonitor == nil else { return }

            localMouseMonitor = NSEventMonitorHandle(local: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            localMouseMonitor = nil
            view = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent {
            guard let window = view?.window,
                  event.window === window,
                  let contentView = window.contentView
            else {
                return event
            }

            let clickLocation = contentView.convert(event.locationInWindow, from: nil)
            let clickedView = contentView.hitTest(clickLocation)
            let shouldDismiss = MAYNTextFocusDismissPolicy.shouldDismissTextFocus(
                isTextEditingFirstResponder: Self.isTextEditingResponder(window.firstResponder),
                clickedTargetIsTextInput: Self.isTextInputView(clickedView)
            )

            if shouldDismiss {
                window.makeFirstResponder(nil)
            }

            return event
        }

        private static func isTextEditingResponder(_ responder: NSResponder?) -> Bool {
            responder is NSTextView || responder is NSTextField
        }

        private static func isTextInputView(_ view: NSView?) -> Bool {
            var current = view
            while let candidate = current {
                if candidate is NSTextView || candidate is NSTextField || candidate is NSSearchField || candidate is NSComboBox {
                    return true
                }
                current = candidate.superview
            }

            return false
        }
    }
}

extension View {
    func maynDismissTextFocusOnOutsideClick() -> some View {
        background(MAYNTextFocusDismissBridge().frame(width: 0, height: 0))
    }
}

struct MAYNSettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(MAYNTheme.window)
    }
}

struct MAYNSection<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MAYNSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = MAYNControlMetrics.rowMinHeight
    @ViewBuilder let trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .frame(minWidth: MAYNControlMetrics.trailingLaneMinWidth, alignment: .trailing)
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
        .frame(minHeight: minHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? MAYNTheme.hover : Color.clear)
        .animation(MAYNMotion.normalAnimation(reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

enum MAYNButtonRole {
    case primary
    case secondary
    case destructive
}

struct MAYNButton<Label: View>: View {
    let role: MAYNButtonRole
    var height: CGFloat = MAYNControlMetrics.controlHeight
    var action: () -> Void
    @ViewBuilder var label: Label
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            label
                .font(.callout.weight(role == .primary ? .semibold : .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.50)
        .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isPressed)
    }

    private var foreground: Color {
        switch role {
        case .primary:
            Color(nsColor: .controlBackgroundColor)
        case .secondary:
            .primary
        case .destructive:
            MAYNTheme.danger
        }
    }

    private var background: Color {
        guard isEnabled else { return MAYNTheme.elevated }
        switch role {
        case .primary:
            return isPressed ? Color.primary.opacity(0.82) : Color.primary
        case .secondary:
            if isPressed { return MAYNTheme.elevatedPressed }
            if isHovering { return MAYNTheme.elevatedHover }
            return MAYNTheme.elevated
        case .destructive:
            if isPressed { return MAYNTheme.danger.opacity(0.16) }
            if isHovering { return MAYNTheme.danger.opacity(0.10) }
            return MAYNTheme.elevated
        }
    }

    private var border: Color {
        switch role {
        case .primary:
            Color.primary.opacity(0.18)
        case .secondary:
            MAYNTheme.subtleBorder
        case .destructive:
            MAYNTheme.danger.opacity(isHovering || isPressed ? 0.35 : 0.18)
        }
    }
}

extension MAYNButton where Label == Text {
    init(_ title: String, role: MAYNButtonRole = .secondary, height: CGFloat = MAYNControlMetrics.controlHeight, action: @escaping () -> Void) {
        self.role = role
        self.height = height
        self.action = action
        label = Text(title)
    }
}

struct MAYNTextField: View {
    var placeholder = ""
    @Binding var text: String
    var width: CGFloat = MAYNControlMetrics.textFieldWidth
    var alignment: TextAlignment = .leading
    var font: Font = .callout
    var autofocus = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .font(font)
            .padding(.horizontal, 10)
            .frame(width: width, height: MAYNControlMetrics.controlHeight)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(isFocused ? MAYNTheme.focusRing : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder), lineWidth: 1)
            )
            .focused($isFocused)
            .onHover { isHovering = $0 }
            .onAppear {
                guard autofocus else { return }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
            .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isFocused)
    }
}

struct MAYNSecureField: View {
    var placeholder = ""
    @Binding var text: String
    var width: CGFloat = MAYNControlMetrics.textFieldWidth
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(width: width, height: MAYNControlMetrics.controlHeight)
            .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(isFocused ? MAYNTheme.focusRing : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder), lineWidth: 1)
            )
            .focused($isFocused)
            .onHover { isHovering = $0 }
            .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
            .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isFocused)
    }
}

enum MAYNDropdownPresentation {
    static let usesSingleSharedControlChrome = true
    static let usesNativePickerChrome = false
    static let usesBorderlessNativeMenuStyle = false
    static let backgroundMatchesTextField = true
    static let hidesNativeMenuIndicator = true
    static let leadingIndicatorSymbol: String? = nil
    static let trailingIndicatorSymbol = "chevron.up.chevron.down"
}

struct MAYNDropdown<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    var width: CGFloat = MAYNControlMetrics.pickerWidth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 0) {
                Text(title(selection))
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 26)
            .frame(width: width, height: MAYNControlMetrics.dropdownHeight)
            .background(isHovering ? MAYNTheme.elevatedHover : MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
            )
            .overlay(alignment: .trailing) {
                Image(systemName: MAYNDropdownPresentation.trailingIndicatorSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 10)
            }
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }
}

struct MAYNDivider: View {
    var body: some View {
        Rectangle()
            .fill(MAYNTheme.divider)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

enum MAYNNumericInputSupplementaryControl: Equatable {
    case presetsMenu
    case stepperButtons
}

struct MAYNNumericInputCommit: Equatable {
    let value: Int
    let draft: String
}

enum MAYNNumericInputPresentation {
    static func supplementaryControls(presets: [Int]) -> [MAYNNumericInputSupplementaryControl] {
        []
    }

    static func committedValue(
        from draft: String,
        currentValue: Int,
        range: ClosedRange<Int>
    ) -> MAYNNumericInputCommit {
        guard let next = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return MAYNNumericInputCommit(value: currentValue, draft: "\(currentValue)")
        }

        let clamped = min(max(next, range.lowerBound), range.upperBound)
        return MAYNNumericInputCommit(value: clamped, draft: "\(clamped)")
    }
}

struct MAYNNumericStepper: View {
    let text: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var presets: [Int] = []
    var suffix: String?
    var fieldWidth: CGFloat = 78
    @FocusState private var isFocused: Bool
    @State private var draft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .frame(width: fieldWidth, height: MAYNControlMetrics.controlHeight)
                .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                        .stroke(isFocused ? MAYNTheme.focusRing : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder), lineWidth: 1)
                )
                .focused($isFocused)
                .onSubmit(commitDraft)

            if let displaySuffix {
                Text(displaySuffix)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 98, alignment: .trailing)
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isFocused)
        .onAppear { draft = "\(value)" }
        .onChange(of: value) { _, newValue in
            if !isFocused {
                draft = "\(newValue)"
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commitDraft()
            }
        }
    }

    private var displaySuffix: String? {
        if let suffix { return suffix }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let valuePrefix = "\(value)"
        guard trimmed.hasPrefix(valuePrefix) else { return nil }
        let inferred = trimmed.dropFirst(valuePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return inferred.isEmpty ? nil : String(inferred)
    }

    private func commitDraft() {
        let commit = MAYNNumericInputPresentation.committedValue(
            from: draft,
            currentValue: value,
            range: range
        )
        value = commit.value
        draft = commit.draft
    }

}

enum HotkeyChipSegment: Equatable {
    case modifier(Character)
    case key(String)
}

enum HotkeyChipPresentation {
    static let displayHeight: CGFloat = MAYNControlMetrics.hotkeyHeight
    static let compactHeight: CGFloat = 24
    static let cornerRadius: CGFloat = 7

    static func displayText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not set" : text
    }

    static func isModifierGlyph(_ character: Character) -> Bool {
        switch character {
        case "⌘", "⇧", "⌥", "⌃":
            true
        default:
            false
        }
    }

    static func segments(for text: String) -> [HotkeyChipSegment] {
        let display = displayText(text)
        var segments: [HotkeyChipSegment] = []
        var keyStartIndex = display.startIndex

        while keyStartIndex < display.endIndex {
            let character = display[keyStartIndex]
            guard isModifierGlyph(character) else { break }
            segments.append(.modifier(character))
            keyStartIndex = display.index(after: keyStartIndex)
        }

        if keyStartIndex < display.endIndex {
            segments.append(.key(String(display[keyStartIndex...])))
        }

        return segments
    }

    static func swiftUIFont(for character: Character, compact: Bool = false) -> Font {
        if isModifierGlyph(character) {
            return .system(size: compact ? 15 : 17, weight: .semibold)
        }
        return .system(size: compact ? 13 : 15, weight: .semibold, design: .rounded)
    }

    static func swiftUIFont(for segment: HotkeyChipSegment, compact: Bool = false) -> Font {
        switch segment {
        case .modifier(let character):
            swiftUIFont(for: character, compact: compact)
        case .key:
            .system(size: compact ? 13 : 15, weight: .semibold, design: .rounded)
        }
    }

    static func baselineOffset(for character: Character) -> CGFloat {
        0
    }

    static func attributedString(_ text: String, color: NSColor, compact: Bool = true) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for segment in segments(for: text) {
            let font = NSFont.systemFont(
                ofSize: segment.isModifier ? (compact ? 15 : 17) : (compact ? 13 : 15),
                weight: .semibold
            )
            output.append(NSAttributedString(
                string: segment.displayText,
                attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .baselineOffset: segment.baselineOffset
                ]
            ))
        }

        return output
    }
}

private extension HotkeyChipSegment {
    var displayText: String {
        switch self {
        case .modifier(let character):
            String(character)
        case .key(let text):
            text
        }
    }

    var isModifier: Bool {
        if case .modifier = self {
            return true
        }
        return false
    }

    var baselineOffset: CGFloat {
        switch self {
        case .modifier(let character):
            HotkeyChipPresentation.baselineOffset(for: character)
        case .key:
            0
        }
    }
}

struct ShortcutChip: View {
    let text: String
    var height: CGFloat = HotkeyChipPresentation.displayHeight

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.displayText)
                    .font(HotkeyChipPresentation.swiftUIFont(for: segment, compact: height <= HotkeyChipPresentation.compactHeight))
                    .baselineOffset(segment.baselineOffset)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, height <= HotkeyChipPresentation.compactHeight ? 8 : 11)
        .frame(height: height)
        .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HotkeyChipPresentation.cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }

    private var displayText: String {
        HotkeyChipPresentation.displayText(text)
    }

    private var segments: [HotkeyChipSegment] {
        HotkeyChipPresentation.segments(for: text)
    }
}

struct MAYNHotkeyDisplay: View {
    let text: String
    var height: CGFloat = MAYNControlMetrics.hotkeyHeight

    var body: some View {
        ShortcutChip(text: text, height: height)
            .accessibilityLabel("Shortcut \(HotkeyChipPresentation.displayText(text))")
    }
}

struct MAYNToolCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var accent: Color = .secondary
    var fixedHeight: CGFloat?
    var action: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }

                if fixedHeight != nil {
                    Spacer(minLength: 0)
                }

                content
            }
            .padding(14)
            .frame(
                maxWidth: .infinity,
                minHeight: fixedHeight,
                maxHeight: fixedHeight,
                alignment: .topLeading
            )
            .background(cardBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .stroke(isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.992 : 1)
            .contentShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.fastAnimation(reduceMotion: reduceMotion), value: isPressed)
    }

    private var cardBackground: Color {
        if isPressed { return MAYNTheme.elevatedPressed }
        if isHovering { return MAYNTheme.elevatedHover }
        return MAYNTheme.panel
    }
}

struct StatusPill: View {
    enum Kind: Equatable {
        case neutral
        case success
        case warning
        case danger
        case progress
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(kind == .neutral ? .secondary : .primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(kind == .neutral ? 0.08 : 0.14), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(kind == .neutral ? 0.14 : 0.30), lineWidth: 1))
    }

    private var color: Color {
        switch kind {
        case .neutral: Color.secondary
        case .success: MAYNTheme.success
        case .warning: MAYNTheme.warning
        case .danger: MAYNTheme.danger
        case .progress: MAYNTheme.progress
        }
    }
}

extension VoiceASRModelRowPresentation.StatusKind {
    var statusPillKind: StatusPill.Kind {
        switch self {
        case .neutral: .neutral
        case .success: .success
        case .warning: .warning
        case .progress: .progress
        }
    }
}

struct PermissionCard: View {
    enum StateKind {
        case granted
        case needed
        case denied
        case optional
    }

    let title: String
    let reason: String
    let state: StateKind
    let actionTitle: String
    var isHighlighted = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    StatusPill(text: stateText, kind: pillKind)
                }
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            MAYNButton(actionTitle, action: action)
                .disabled(state == .granted)
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(isHighlighted ? MAYNTheme.progress.opacity(0.70) : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .shadow(color: isHighlighted && !reduceMotion ? MAYNTheme.progress.opacity(0.22) : .clear, radius: 12, y: 2)
        .animation(MAYNMotion.instructionAnimation(reduceMotion: reduceMotion), value: isHighlighted)
    }

    private var symbol: String {
        switch state {
        case .granted: "checkmark.circle.fill"
        case .needed: "circle"
        case .denied: "exclamationmark.triangle.fill"
        case .optional: "circle.dashed"
        }
    }

    private var color: Color {
        switch state {
        case .granted: MAYNTheme.success
        case .needed: MAYNTheme.progress
        case .denied: MAYNTheme.warning
        case .optional: Color.secondary
        }
    }

    private var stateText: String {
        switch state {
        case .granted: "Granted"
        case .needed: "Needs setup"
        case .denied: "Blocked"
        case .optional: "Optional"
        }
    }

    private var pillKind: StatusPill.Kind {
        switch state {
        case .granted: .success
        case .needed: .progress
        case .denied: .warning
        case .optional: .neutral
        }
    }

    private var cardBackground: Color {
        isHighlighted ? MAYNTheme.progress.opacity(0.10) : MAYNTheme.panel
    }
}

struct InstructionStrip: View {
    let text: String
    var appName: String = "MacAllYouNeed"
    var symbol: String = "arrow.up"
    var secondaryText: String?
    var dragAppURL: URL?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.callout)
                    Text(secondaryText ?? appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let actionTitle, let action {
                    MAYNButton(actionTitle, action: action)
                }
            }

            if let dragAppURL {
                DraggablePermissionAppTile(appName: appName, appURL: dragAppURL)
            }
        }
        .padding(14)
        .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.strongBorder, lineWidth: 1)
        )
    }
}

struct DraggablePermissionAppTile: View {
    let appName: String
    let appURL: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.callout.weight(.medium))
                Text("Drag this app into the System Settings list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .onDrag {
            let provider = NSItemProvider(object: appURL as NSURL)
            provider.suggestedName = appURL.lastPathComponent
            return provider
        }
        .help("Drag \(appName) into the open permission list")
    }
}

struct MAYNToastContent: View {
    let message: String
    let symbol: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.iconSize), weight: .semibold))
            Text(message)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.titleFontSize), weight: .semibold))
        }
        .foregroundStyle(isDestructive ? .white : Color(nsColor: .controlBackgroundColor))
        .padding(.horizontal, CGFloat(MAYNNotificationPillPresentation.horizontalPadding))
        .padding(.vertical, CGFloat(MAYNNotificationPillPresentation.verticalPadding))
        .background(isDestructive ? Color.red : Color.primary, in: Capsule())
        .overlay {
            if MAYNNotificationPillPresentation.hasCapsuleStroke {
                Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

struct MAYNToast: View {
    let message: String
    var symbol = "checkmark.circle.fill"
    var isDestructive = false

    var body: some View {
        MAYNToastContent(message: message, symbol: symbol, isDestructive: isDestructive)
    }
}
