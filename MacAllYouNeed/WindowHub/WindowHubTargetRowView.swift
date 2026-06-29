import SwiftUI

struct WindowHubTargetRowView: View {
    let target: WindowHubTarget
    var isSelected: Bool = false
    var showsDomain: Bool = false
    let onActivate: () -> Void
    let onSelect: () -> Void
    let onAction: (WindowHubDirectAction) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var canClose: Bool {
        switch target.kind {
        case .tab:
            return target.capabilities.contains(.close)
        case .window:
            return true
        case .app:
            return false
        }
    }

    private var closeAction: WindowHubDirectAction {
        target.kind == .tab ? .closeTab : .closeWindow
    }

    private var shouldShowDomain: Bool {
        showsDomain
            && target.kind == .tab
            && target.capabilities.contains(.readDomain)
            && !(target.domain?.isEmpty ?? true)
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(target.isActive ? MAYNTheme.progress : .clear)
                .frame(width: 6, height: 6)

            Text(target.displayTitle)
                .font(.system(size: 12.5, weight: MAYNSelectionLabelStyle.weight(isSelected: isSelected)))
                .foregroundStyle(
                    MAYNSelectionLabelStyle.foreground(isSelected: isSelected, scheme: colorScheme)
                )
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if shouldShowDomain, let domain = target.domain {
                Text(domain)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        MAYNSelectionLabelStyle.subtitle(isSelected: isSelected, scheme: colorScheme)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .trailing)
            }

            if canClose {
                Button {
                    onAction(closeAction)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(MAYNTheme.hover, in: Circle())
                        .opacity(isHovering || isSelected ? 1 : 0)
                }
                .buttonStyle(.plain)
                .help(target.kind == .tab ? "Close tab" : "Close window")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 29)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .maynSelectionBackground(
            isSelected: isSelected,
            isHovering: isHovering && !isSelected,
            shape: .rounded(8)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                onSelect()
            }
        }
        .onTapGesture(perform: onActivate)
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isSelected)
        .animation(MAYNMotion.hoverAnimation(reduceMotion: reduceMotion), value: isHovering)
    }
}
