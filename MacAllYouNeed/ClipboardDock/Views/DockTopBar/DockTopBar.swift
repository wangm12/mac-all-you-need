import SwiftUI

struct DockTopBar: View {
    @Bindable var model: ClipboardDockModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DockSearchField(query: $model.search)
                .onChange(of: model.search) { _, _ in
                    model.refreshDebounced()
                }

            DockListTabs(model: model)
                .frame(maxWidth: .infinity)

            DockMoreMenu(openSettings: openSettings)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 52)
        .background(.thinMaterial)
    }
}
