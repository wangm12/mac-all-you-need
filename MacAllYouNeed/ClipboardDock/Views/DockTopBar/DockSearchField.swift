import SwiftUI

struct DockSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .onTapGesture {
                    expanded = true
                    focused = true
                }

            if expanded || !query.isEmpty {
                TextField("Search…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .frame(width: 280)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused, query.isEmpty {
                            expanded = false
                        }
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.18), value: expanded)
    }
}
