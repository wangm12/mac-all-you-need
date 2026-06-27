import SwiftUI

struct DockSearchField: View {
    @Binding var query: String
    let focusRequestID: Int
    @FocusState private var focused: Bool
    @State private var explicitExpand = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expandedFieldWidth: CGFloat = 280

    private var isActive: Bool {
        explicitExpand || !query.isEmpty
    }

    var body: some View {
        HStack(spacing: isActive ? 6 : 0) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .onTapGesture {
                    activateSearchField()
                }

            TextField("Search…", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .font(.callout)
                .frame(width: isActive ? Self.expandedFieldWidth : 0, alignment: .leading)
                .opacity(isActive ? 1 : 0)
                .clipped()
                .allowsHitTesting(isActive)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused, query.isEmpty {
                        explicitExpand = false
                    }
                }
        }
        .padding(.horizontal, 8)
        .frame(height: MAYNControlMetrics.controlHeight)
        .background(MAYNTheme.elevated, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(focused ? MAYNTheme.focusRing : MAYNTheme.subtleBorder, lineWidth: 1)
        )
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: isActive)
        .onChange(of: focusRequestID) { _, _ in
            activateSearchField()
        }
        .onChange(of: query) { _, newValue in
            guard !newValue.isEmpty else { return }
            DispatchQueue.main.async {
                focused = true
            }
        }
    }

    private func activateSearchField() {
        explicitExpand = true
        DispatchQueue.main.async {
            focused = true
        }
    }
}
