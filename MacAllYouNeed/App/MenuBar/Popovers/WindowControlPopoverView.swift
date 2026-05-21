import SwiftUI

/// Placeholder for the Window Control tab popover.
/// The Window Control tab is not yet present in `AppMenuBarContent.Tab`;
/// this file reserves the type name for when it is added.
struct WindowControlPopoverView: View {
    let controller: AppController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Window Control")
                .font(.callout.weight(.semibold))
            Text("Coming soon.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
