import AppKit
import Platform
import SwiftUI

// MARK: - Settings Shell

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

// MARK: - Text Focus Dismiss

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

    /// True while a CJK IME still holds marked (pre-edit) text in the key
    /// window's field editor. Return must reach the IME to commit candidates.
    static func isIMEComposing(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let client = responder as? NSTextInputClient, client.hasMarkedText() {
            return true
        }
        if let textField = responder as? NSTextField,
           let editor = textField.currentEditor() as? NSTextInputClient,
           editor.hasMarkedText()
        {
            return true
        }
        return false
    }

    /// App shortcuts bound to Return (e.g. dock paste) must not run while an
    /// IME composition is active — Enter belongs to the input method first.
    static func shouldConsumeReturnForAppShortcut(isIMEComposing: Bool) -> Bool {
        !isIMEComposing
    }

    /// Space is used by CJK IMEs to pick candidates and by text fields for
    /// literal spaces. Preview shortcuts must not steal it in either case.
    static func shouldConsumeSpaceForAppShortcut(
        isIMEComposing: Bool,
        isTextEditingFirstResponder: Bool
    ) -> Bool {
        !isIMEComposing && !isTextEditingFirstResponder
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

// MARK: - Page + Section + Row

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
        .scrollIndicators(.hidden)
        .background(MAYNTheme.window)
    }
}

struct MAYNSection<Content: View>: View {
    enum ContentLayout {
        /// Settings rows supply their own horizontal padding.
        case rows
        /// Callout / prose blocks (e.g. Quick Start).
        case prose
    }

    enum SurfaceStyle {
        /// Opaque content panel (default for lists and settings).
        case opaque
        /// Opaque dense list panel (`contentListPanel`).
        case listPanel
        /// Liquid Glass — floating panels only.
        case glass
    }

    let title: String
    var subtitle: String?
    var contentLayout: ContentLayout = .rows
    var surfaceStyle: SurfaceStyle = .opaque
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String? = nil,
        contentLayout: ContentLayout = .rows,
        surfaceStyle: SurfaceStyle = .opaque,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.contentLayout = contentLayout
        self.surfaceStyle = surfaceStyle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsHeader ? 10 : 0) {
            if showsHeader {
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
            }

            styledSectionBody(
                VStack(spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(contentInsets)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func styledSectionBody<Inner: View>(_ inner: Inner) -> some View {
        let shape = RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
        switch surfaceStyle {
        case .opaque:
            inner
                .background(MAYNTheme.contentPanel(colorScheme), in: shape)
                .overlay { shape.strokeBorder(MAYNTheme.hairline, lineWidth: 1) }
        case .listPanel:
            inner
                .background(MAYNTheme.contentListPanel(colorScheme), in: shape)
                .overlay { shape.strokeBorder(MAYNTheme.hairline, lineWidth: 1) }
        case .glass:
            inner.maynGlassSurface(.panel, cornerRadius: MAYNControlMetrics.panelRadius)
        }
    }

    private var contentInsets: EdgeInsets {
        switch contentLayout {
        case .rows:
            EdgeInsets()
        case .prose:
            EdgeInsets(
                top: MAYNSpacing.sm,
                leading: MAYNControlMetrics.rowHorizontalPadding,
                bottom: MAYNSpacing.sm,
                trailing: MAYNControlMetrics.rowHorizontalPadding
            )
        }
    }

    private var showsHeader: Bool {
        !title.isEmpty || subtitle != nil
    }
}

struct MAYNSettingsRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = MAYNControlMetrics.rowMinHeight
    private let belowSubtitle: (() -> AnyView)?
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    init(
        title: String,
        subtitle: String? = nil,
        minHeight: CGFloat = MAYNControlMetrics.rowMinHeight,
        belowSubtitle: (() -> AnyView)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) where Leading == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.minHeight = minHeight
        self.belowSubtitle = belowSubtitle
        self.leading = EmptyView()
        self.trailing = trailing()
    }

    init(
        title: String,
        subtitle: String? = nil,
        minHeight: CGFloat = MAYNControlMetrics.rowMinHeight,
        belowSubtitle: (() -> AnyView)? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minHeight = minHeight
        self.belowSubtitle = belowSubtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: MAYNControlMetrics.rowControlSpacing) {
            HStack(alignment: .center, spacing: 10) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let belowSubtitle {
                        belowSubtitle()
                            .padding(.top, 4)
                    }
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

// MARK: - MAYNButton

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
        if !isEnabled {
            switch role {
            case .primary, .secondary:
                return Color.primary.opacity(0.42)
            case .destructive:
                return MAYNTheme.danger.opacity(0.42)
            }
        }
        switch role {
        case .primary:
            return Color(nsColor: .controlBackgroundColor)
        case .secondary:
            return Color.primary
        case .destructive:
            return MAYNTheme.danger
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

// MARK: - MAYNTextField + MAYNSecureField

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
    var allowsReveal = true
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.leading, 10)
            .padding(.trailing, allowsReveal ? 4 : 10)
            .focused($isFocused)

            if allowsReveal {
                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: MAYNControlMetrics.controlHeight - 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .accessibilityLabel(isRevealed ? "Hide value" : "Show value")
            }
        }
        .frame(width: width, height: MAYNControlMetrics.controlHeight)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                .stroke(isFocused ? MAYNTheme.focusRing : (isHovering ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isFocused)
    }
}

// MARK: - MAYNDropdown

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

// MARK: - MAYNDivider

struct MAYNDivider: View {
    var body: some View {
        Rectangle()
            .fill(MAYNTheme.divider)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

// MARK: - MAYNNumericStepper

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

// MARK: - ShortcutChip + MAYNHotkeyDisplay

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
        .background(MAYNTheme.panelSubtle, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.keycapRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.keycapRadius, style: .continuous)
                .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
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

// MARK: - MAYNToolCard

// MARK: - Dashboard card primitives (Metric / Action / List)

struct MAYNMetricStrip<Content: View>: View {
    var height: CGFloat = 76
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: height)
        .background(MAYNTheme.contentPanel(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MAYNTheme.hairline, lineWidth: 1)
        }
    }
}

struct MAYNMetricCell: View {
    let title: String
    let value: String
    let detail: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MAYNTheme.textTertiary(colorScheme))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct MAYNActionCard: View {
    let title: String
    let subtitle: String
    var buttonTitle: String = "Open"
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MAYNTheme.textPrimary(colorScheme))
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(MAYNTheme.textSecondary(colorScheme))
            }
            Spacer(minLength: 8)
            MAYNButton(buttonTitle, role: .secondary, action: action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MAYNTheme.contentPanelElevated(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(MAYNTheme.hairline, lineWidth: 1)
        }
    }
}

struct MAYNListPanel<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        MAYNSection(title: title, subtitle: subtitle, surfaceStyle: .listPanel) {
            content
        }
    }
}

// MARK: - MAYNToolCard

struct MAYNToolCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var accent: Color = .secondary
    var fixedHeight: CGFloat?
    var action: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
            .background(MAYNTheme.contentPanel(colorScheme), in: RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                    .fill(hoverOverlay)
            )
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

    private var hoverOverlay: Color {
        if isPressed { return MAYNTheme.elevatedPressed }
        if isHovering { return MAYNTheme.hover }
        return .clear
    }
}

// MARK: - StatusPill

struct StatusPill: View {
    enum Kind: Equatable {
        case neutral
        case success
        case warning
        case danger
        case progress
        case ready
        case active
        case idle
        case needsPermission
        case failed
        case processing
        case paused
        case completed
    }

    let text: String
    var kind: Kind = .neutral
    var showsIcon = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsePhase = false

    private var palette: MAYNStatusTagPalette.Colors {
        MAYNStatusTagPalette.colors(for: kind)
    }

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                leadingIcon
            }
            Text(text)
                .font(.system(size: MAYNControlMetrics.statusTagFontSize, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(palette.foreground)
        .padding(.horizontal, MAYNControlMetrics.statusPillHorizontalPadding)
        .frame(height: MAYNControlMetrics.statusPillHeight)
        .background(palette.background, in: Capsule())
        .overlay(Capsule().stroke(palette.border, lineWidth: 0.75))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(accessibilityValue)
        .onAppear {
            guard kind == .active, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch kind {
        case .needsPermission:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 8, weight: .semibold))
        case .failed, .danger:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 8, weight: .semibold))
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: 7, weight: .semibold))
        case .success, .ready, .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
        case .active, .processing:
            Circle()
                .fill(palette.foreground)
                .frame(width: 5, height: 5)
                .scaleEffect(pulsePhase ? 1 : 0.75)
                .opacity(pulsePhase ? 1 : 0.45)
        case .progress:
            Circle()
                .fill(palette.foreground)
                .frame(width: 5, height: 5)
        default:
            Circle()
                .fill(palette.foreground.opacity(0.70))
                .frame(width: 5, height: 5)
        }
    }

    private var accessibilityValue: String {
        switch kind {
        case .neutral: "Status"
        case .success, .ready, .completed: "Ready"
        case .warning, .paused: "Paused"
        case .danger, .failed: "Failed"
        case .progress, .processing, .active: "In progress"
        case .idle: "Idle"
        case .needsPermission: "Needs permission"
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

// MARK: - Switch toggle

private enum MAYNSwitchMetrics {
    static let trackWidth: CGFloat = 36
    static let trackHeight: CGFloat = 20
    static let thumbSize: CGFloat = 16
    static let thumbPadding: CGFloat = 2
}

private struct MAYNSwitchControl: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                track
                thumb
            }
            .frame(width: MAYNSwitchMetrics.trackWidth, height: MAYNSwitchMetrics.trackHeight)
        }
        .buttonStyle(.plain)
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isOn)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var track: some View {
        if usesOpaqueChrome {
            Capsule()
                .fill(isOn ? MAYNTheme.activeFill : MAYNTheme.statusMutedFill)
                .overlay(trackBorder)
        } else if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: Capsule())
                .overlay {
                    if isOn {
                        Capsule()
                            .fill(MAYNTheme.activeFill.opacity(0.9))
                    }
                }
                .overlay(trackBorder)
        }
    }

    @ViewBuilder
    private var thumb: some View {
        Group {
            if usesOpaqueChrome {
                Circle()
                    .fill(MAYNTheme.activeText)
            } else if #available(macOS 26.0, *) {
                if isOn {
                    Circle()
                        .fill(MAYNTheme.activeText)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .glassEffect(.regular, in: Circle())
                        .overlay {
                            Circle()
                                .fill(Color.primary.opacity(0.18))
                        }
                }
            }
        }
        .frame(width: MAYNSwitchMetrics.thumbSize, height: MAYNSwitchMetrics.thumbSize)
        .padding(MAYNSwitchMetrics.thumbPadding)
    }

    private var trackBorder: some View {
        Capsule()
            .stroke(MAYNTheme.hairline, lineWidth: 1)
    }

    private var usesOpaqueChrome: Bool {
        if reduceTransparency { return true }
        if #available(macOS 26.0, *) { return false }
        return true
    }
}

private struct MAYNMonochromeSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 0)
            MAYNSwitchControl(isOn: configuration.isOn) {
                configuration.isOn.toggle()
            }
        }
    }
}

extension View {
    /// Monochrome switch styling for settings and dashboard feature cards.
    /// macOS 26+: Liquid Glass track and thumb; opaque fallback on earlier releases and Reduce Transparency.
    func maynSwitchToggleStyle() -> some View {
        toggleStyle(MAYNMonochromeSwitchToggleStyle())
    }
}

// MARK: - PermissionCard

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
    var hidesActionWhenGranted = true
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

            if !(hidesActionWhenGranted && state == .granted) {
                MAYNButton(actionTitle, action: action)
            }
        }
        .padding(14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.cardRadius, style: .continuous)
                .stroke(isHighlighted ? MAYNTheme.strongBorder : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .shadow(color: isHighlighted && !reduceMotion ? Color.black.opacity(0.08) : .clear, radius: 12, y: 2)
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
        case .granted: MAYNTheme.activeFill
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
        case .granted: .ready
        case .needed: .needsPermission
        case .denied: .failed
        case .optional: .idle
        }
    }

    private var cardBackground: Color {
        isHighlighted ? MAYNTheme.selected : MAYNTheme.panel
    }
}

// MARK: - InstructionStrip + DraggablePermissionAppTile

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

// MARK: - MAYNToast

struct MAYNToastContent: View {
    let message: String
    let symbol: String
    var isDestructive = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: CGFloat(MAYNNotificationPillPresentation.iconSize), weight: .semibold))
            Text(message)
                .font(MAYNTypography.body(strong: true))
        }
        .foregroundStyle(MAYNTheme.hudForeground)
        .padding(.horizontal, CGFloat(MAYNNotificationPillPresentation.horizontalPadding))
        .frame(minHeight: MAYNControlMetrics.toastHeight)
        .background(MAYNTheme.hudBackground, in: Capsule())
        .overlay {
            if MAYNNotificationPillPresentation.hasCapsuleStroke {
                Capsule().stroke(MAYNTheme.hairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityValue(isDestructive ? "Destructive notification" : "Notification")
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

// MARK: - MAYNCommandPaletteShell

enum MAYNCommandPaletteMetrics {
    static let cornerRadius: CGFloat = 28
    static let shellPadding: CGFloat = 8
}

struct MAYNCommandPaletteShell<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    var body: some View {
        let radius = MAYNCommandPaletteMetrics.cornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency {
                shellBody(shape: shape, radius: radius)
                    .background { shape.fill(MAYNTheme.contentPanelElevated(colorScheme)) }
            } else if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    shellBody(shape: shape, radius: radius)
                        .glassEffect(.regular, in: .rect(cornerRadius: radius))
                }
            } else {
                shellBody(shape: shape, radius: radius)
                    .background { shape.fill(.regularMaterial) }
            }
        }
        .overlay { innerHighlightStroke(shape: shape) }
        .overlay { shape.strokeBorder(MAYNTheme.commandPaletteBorder(colorScheme), lineWidth: 1) }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.68 : 0.28), radius: colorScheme == .dark ? 45 : 40, x: 0, y: colorScheme == .dark ? 30 : 28)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.6 : 0.08), radius: 2, x: 0, y: 1)
    }

    private func shellBody(shape: RoundedRectangle, radius: CGFloat) -> some View {
        content
            .padding(MAYNCommandPaletteMetrics.shellPadding)
            .background {
                shape.fill(MAYNTheme.commandPaletteGradient(colorScheme))
            }
    }

    private func innerHighlightStroke(shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [
                    MAYNTheme.commandPaletteInnerHighlightTop(colorScheme),
                    MAYNTheme.commandPaletteInnerShadowBottom(colorScheme),
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }
}

// MARK: - MAYNKeycap

/// DESIGN.md §7.4 keycap — thin wrapper over `ShortcutChip`.
struct MAYNKeycap: View {
    let text: String
    var height: CGFloat = MAYNControlMetrics.hotkeyHeight

    var body: some View {
        ShortcutChip(text: text, height: height)
    }
}

// MARK: - MAYNHUDContainer

struct MAYNHUDContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var padding: CGFloat = MAYNSpacing.md

    var body: some View {
        content
            .padding(padding)
            .background(MAYNTheme.hudBackground, in: RoundedRectangle(cornerRadius: MAYNControlMetrics.hudRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MAYNControlMetrics.hudRadius, style: .continuous)
                    .stroke(MAYNTheme.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 24, y: 12)
            .foregroundStyle(MAYNTheme.hudForeground)
    }
}

extension View {
    func maynHUDContainer(padding: CGFloat = MAYNSpacing.md) -> some View {
        MAYNHUDContainer(padding: padding) { self }
    }

    func maynFocusRing(isFocused: Bool) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    .stroke(MAYNTheme.focusRing, lineWidth: 2)
            }
        }
    }
}
