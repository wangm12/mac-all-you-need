import AppKit
import SwiftUI

/// Sets the SwiftUI Settings NSWindow's collection behavior so it appears
/// over the active full-screen Space instead of triggering a Space-switch
/// to the main desktop.
///
/// The `Settings` scene gives no API for this. We embed a zero-size
/// NSViewRepresentable inside `SettingsRoot.body`; the first time the view
/// is added to a window we walk up to that NSWindow and add
/// `.canJoinAllSpaces, .fullScreenAuxiliary`. Singleton window — no need
/// to reverse the change.
struct SettingsWindowConfig: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply if the window was rehydrated (closed + reopened).
        DispatchQueue.main.async {
            nsView.window?.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        }
    }
}
