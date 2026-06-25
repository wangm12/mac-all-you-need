import SwiftUI

struct WindowHubTargetRowView: View {
    let target: WindowHubTarget
    let onActivate: () -> Void
    let onAction: (WindowHubDirectAction) -> Void

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

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(target.isActive ? MAYNTheme.progress : .clear)
                .frame(width: 6, height: 6)

            Text(target.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if let domain = target.domain, !domain.isEmpty {
                Text(domain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                        .opacity(isHovering ? 1 : 0)
                }
                .buttonStyle(.plain)
                .help(target.kind == .tab ? "Close tab" : "Close window")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isHovering ? MAYNTheme.hover : Color.clear)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onActivate)
    }
}
