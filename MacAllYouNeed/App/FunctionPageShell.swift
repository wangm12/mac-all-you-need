import SwiftUI

enum FunctionPageShellPresentation {
    static func showsTabStrip(tabCount: Int) -> Bool {
        tabCount > 1
    }
}

struct FunctionPageShell<Tab: FunctionTabDestination, Toolbar: View, Content: View>: View {
    let title: String
    let subtitle: String
    let tabs: [Tab]
    @Binding var selection: Tab
    @ViewBuilder let toolbar: Toolbar
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flowDirection: FunctionTabFlowDirection = .forward

    init(
        title: String,
        subtitle: String,
        tabs: [Tab] = Array(Tab.allCases),
        selection: Binding<Tab>,
        @ViewBuilder toolbar: () -> Toolbar,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tabs = tabs
        _selection = selection
        self.toolbar = toolbar()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                toolbar
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 14)

            if FunctionPageShellPresentation.showsTabStrip(tabCount: tabs.count) {
                FunctionSegmentedTabStrip(tabs: tabs, selection: selection) { tab in
                    selectTab(tab)
                }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 14)
            }

            Divider()
                .overlay(MAYNTheme.divider)

            ZStack(alignment: .topLeading) {
                content
                    .id(selection.rawValue)
                    .transition(contentTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: selection.rawValue)
        }
        .background(MAYNTheme.window)
        .onChange(of: selection.rawValue) { oldValue, newValue in
            guard let oldSelection = tabs.first(where: { $0.rawValue == oldValue }),
                  let newSelection = tabs.first(where: { $0.rawValue == newValue }),
                  let direction = FunctionTabFlow.direction(from: oldSelection, to: newSelection, in: tabs)
            else {
                return
            }

            flowDirection = direction
        }
    }

    private var contentTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .modifier(
                active: FunctionTabContentTransitionModifier(
                    opacity: 0,
                    xOffset: FunctionTabFlow.contentInsertionOffset(for: flowDirection)
                ),
                identity: FunctionTabContentTransitionModifier(opacity: 1, xOffset: 0)
            ),
            removal: .opacity
        )
    }

    private func selectTab(_ tab: Tab) {
        guard selection.rawValue != tab.rawValue else { return }

        if let direction = FunctionTabFlow.direction(from: selection, to: tab, in: tabs) {
            flowDirection = direction
        }
        selection = tab
    }
}

private struct FunctionTabContentTransitionModifier: ViewModifier {
    let opacity: Double
    let xOffset: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: xOffset)
    }
}

extension FunctionPageShell where Toolbar == EmptyView {
    init(
        title: String,
        subtitle: String,
        tabs: [Tab] = Array(Tab.allCases),
        selection: Binding<Tab>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            tabs: tabs,
            selection: selection,
            toolbar: { EmptyView() },
            content: content
        )
    }
}

struct FunctionPageScrollContent<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
                .padding(.horizontal, 32)
                .padding(.vertical, 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollIndicators(.never)
        }
    }
}

struct FunctionSegmentedTabStrip<Tab: SegmentedTabDestination>: View {
    enum Size {
        case header
        case control

        var outerHeight: CGFloat {
            switch self {
            case .header: 38
            case .control: 30
            }
        }

        var innerHeight: CGFloat {
            switch self {
            case .header: 30
            case .control: 24
            }
        }

        var outerPadding: CGFloat {
            switch self {
            case .header: 4
            case .control: 3
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .header: 14
            case .control: 10
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .header: 11
            case .control: 10
            }
        }

        var font: Font {
            switch self {
            case .header:
                .callout.weight(.medium)
            case .control:
                .caption.weight(.medium)
            }
        }
    }

    let tabs: [Tab]
    let selection: Tab
    let fillsAvailableWidth: Bool
    let equalSegmentWidths: Bool
    let size: Size
    let onSelect: (Tab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace

    init(
        tabs: [Tab] = Array(Tab.allCases),
        selection: Tab,
        fillsAvailableWidth: Bool = true,
        equalSegmentWidths: Bool = false,
        size: Size = .header,
        onSelect: @escaping (Tab) -> Void
    ) {
        self.tabs = tabs
        self.selection = selection
        self.fillsAvailableWidth = fillsAvailableWidth
        self.equalSegmentWidths = equalSegmentWidths
        self.size = size
        self.onSelect = onSelect
    }

    var body: some View {
        strip
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
            .frame(width: intrinsicEqualWidthStripWidth)
            .fixedSize(horizontal: !fillsAvailableWidth && !equalSegmentWidths, vertical: false)
            .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: selection.rawValue)
    }

    /// Fixed width when segments share space equally but the strip does not fill the row.
    private var intrinsicEqualWidthStripWidth: CGFloat? {
        guard equalSegmentWidths, !fillsAvailableWidth else { return nil }
        let segmentWidth: CGFloat = size == .header ? 88 : 100
        let spacing = CGFloat(max(0, tabs.count - 1)) * 4
        return CGFloat(tabs.count) * segmentWidth + spacing + size.outerPadding * 2
    }

    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                FunctionSegmentedTabButton(
                    tab: tab,
                    isSelected: selection.rawValue == tab.rawValue,
                    size: size,
                    expandsToFillSegment: equalSegmentWidths || fillsAvailableWidth,
                    namespace: selectionNamespace
                ) {
                    onSelect(tab)
                }
            }
        }
        .padding(size.outerPadding)
        .frame(height: size.outerHeight)
        .background(MAYNTheme.panel, in: Capsule())
        .overlay(Capsule().stroke(MAYNTheme.strongBorder, lineWidth: 1))
    }
}

private struct FunctionSegmentedTabButton<Tab: SegmentedTabDestination>: View {
    let tab: Tab
    let isSelected: Bool
    let size: FunctionSegmentedTabStrip<Tab>.Size
    let expandsToFillSegment: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: size.iconSize, weight: .semibold))
                Text(tab.title)
                    .font(size.font)
                    .lineLimit(1)
            }
            .frame(maxWidth: expandsToFillSegment ? .infinity : nil)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.innerHeight)
            .background(tabBackground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: expandsToFillSegment ? .infinity : nil)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(MAYNMotion.tabAnimation(reduceMotion: reduceMotion), value: isSelected)
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            Capsule()
                .fill(MAYNTheme.tabSelectedFill)
                .overlay(Capsule().stroke(MAYNTheme.tabSelectedBorder, lineWidth: 1))
                .shadow(color: MAYNTheme.tabSelectedShadow, radius: 2, x: 0, y: 1)
                .matchedGeometryEffect(id: "function-tab-selection", in: namespace)
        } else if isHovering {
            Capsule()
                .fill(MAYNTheme.hover)
        }
    }
}
