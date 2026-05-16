import FeatureCore
import SwiftUI

enum ClipboardDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .clipboard,
            displayName: "Clipboard Manager",
            icon: "doc.on.clipboard",
            summary: "Copy history, snippets, ⌘⇧V popup.",
            detailDescription: "Captures everything you copy and lets you paste any past clip with ⌘⇧V. Includes snippet expansion (type `;email` to expand a saved snippet).",
            requiredPermissions: [.accessibility],
            hotkeys: [HotkeyDescriptor(identifier: "clipboard.popup", displayName: "Show clipboard popup")],
            activator: ClipboardFeatureActivator(),
            settingsTabFactory: { AnyView(ClipboardSettingsView()) }
        )
    }
}
