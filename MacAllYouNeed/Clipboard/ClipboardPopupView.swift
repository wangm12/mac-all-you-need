import AppKit
import Core
import SwiftUI

struct ClipboardPopupView: View {
    @Bindable var deps: AppDependencies
    let dismiss: () -> Void
    @State private var search = ""
    @State private var selected: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(deps.recentItems.enumerated()), id: \.element.id) { idx, item in
                        ClipboardItemRow(item: item, isSelected: idx == selected)
                            .onTapGesture { paste(index: idx) }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 200)
        }
        .frame(width: 720, height: 280)
        .background(.ultraThinMaterial)
        .onAppear {
            search = ""
            selected = 0
        }
        .onChange(of: search) { _, newValue in
            Task { @MainActor in
                await deps.refresh(query: newValue, rememberQuery: true)
                selected = 0
            }
        }
        .onKeyPress(.return) { paste(index: selected); return .handled }
        .onKeyPress(.leftArrow) { selected = max(0, selected - 1); return .handled }
        .onKeyPress(.rightArrow) { selected = min(deps.recentItems.count - 1, selected + 1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func paste(index: Int) {
        guard deps.recentItems.indices.contains(index) else { return }
        let id = deps.recentItems[index].id
        let plainText = NSEvent.modifierFlags.contains(.option)
        dismiss()
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let proxy = deps.xpc.connection.remoteObjectProxyWithErrorHandler { _ in
                    cont.resume()
                } as? ClipboardXPCProtocol
                guard let proxy else { cont.resume(); return }
                proxy.paste(itemID: id, plainText: plainText) { _ in cont.resume() }
            }
        }
    }
}
