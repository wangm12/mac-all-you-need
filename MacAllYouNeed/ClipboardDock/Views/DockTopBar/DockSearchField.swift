import SwiftUI

struct DockSearchField: View {
    @Binding var query: String
    let focusRequestID: Int
    @FocusState private var focused: Bool
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .onTapGesture {
                    focusSearchField()
                }

            if expanded || !query.isEmpty {
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .font(.callout)
                    .frame(width: 280)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, query.isEmpty {
                            expanded = false
                        }
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
        .onChange(of: focusRequestID) { _, _ in
            focusSearchField()
        }
        .animation(MAYNMotion.controlAnimation(reduceMotion: reduceMotion), value: expanded)
    }

    private func focusSearchField() {
        expanded = true
        DispatchQueue.main.async {
            focused = true
        }
    }
}
