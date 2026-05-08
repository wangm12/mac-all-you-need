import Core
import SwiftUI

struct DockListTabs: View {
    @Bindable var model: ClipboardDockModel
    @State private var showNew = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tab(label: "Clipboard History", selector: .history, dotColor: nil)
                tab(label: "📌 Pinned", selector: .pinned, dotColor: nil)
                tab(label: "Snippets", selector: .snippets, dotColor: nil)

                ForEach(model.availableLists, id: \.id) { board in
                    tab(label: board.name, selector: .pinboard(board.id), dotColor: board.color)
                        .contextMenu {
                            Button("Rename…") {}
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? model.pinboards.delete(id: board.id)
                                    await model.loadAvailableLists()
                                }
                            }
                        }
                }

                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8)
        }
        .task {
            await model.loadAvailableLists()
        }
        .sheet(isPresented: $showNew) {
            NewListSheet(isPresented: $showNew) { name, color in
                Task {
                    _ = try? model.pinboards.create(name: name, color: color)
                    await model.loadAvailableLists()
                }
            }
        }
    }

    @ViewBuilder
    private func tab(label: String, selector: DockListSelector, dotColor: String?) -> some View {
        let active = model.activeList == selector
        Button {
            Task {
                await model.switchList(selector)
            }
        } label: {
            HStack(spacing: 4) {
                if let dotColor, let color = colorFromHex(dotColor) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.secondary.opacity(0.2) : .clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func colorFromHex(_ hex: String) -> Color? {
        let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
