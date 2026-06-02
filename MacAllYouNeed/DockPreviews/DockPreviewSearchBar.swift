import AppKit
import SwiftUI

struct DockPreviewSearchBar: View {
    @Binding var query: String
    var placeholder: String = "Search windows…"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

struct DockPreviewSearchFieldRepresentable: NSViewRepresentable {
    let textField: NSTextField

    func makeNSView(context: Context) -> NSTextField { textField }
    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

struct DockPreviewSearchFieldChrome: View {
    let searchField: NSTextField
    let appearance: DockPreviewResolvedBackgroundAppearance

    var body: some View {
        ZStack {
            let cornerRadius = DockPreviewCardRadius.base + DockPreviewCardRadius.innerPadding
            DockPreviewBlurView(cornerRadius: cornerRadius, appearance: appearance)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                DockPreviewSearchFieldRepresentable(textField: searchField)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
    }
}
