import SwiftUI

struct DockTopBar: View {
    @Bindable var model: ClipboardDockModel
    let dismissDock: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DockSearchField(
                query: $model.search,
                focusRequestID: model.searchFocusRequestID
            )
                .onChange(of: model.search) { _, _ in
                    model.refreshDebounced()
                }

            DockListTabs(model: model)
                .frame(maxWidth: .infinity)

            DockMoreMenu(dismissDock: dismissDock)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 52)
        // Same opaque panel color as DockRootView + MultiSelectBar so the
        // three strips read as one solid surface. `windowBackgroundColor`
        // carries a vibrancy alpha that let the desktop/terminal bleed
        // through; `controlBackgroundColor` is fully opaque.
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
