import FeatureCore
import SwiftUI

enum ClipboardSmartTextDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .clipboardSmartText,
            displayName: "Clipboard Smart Text",
            icon: "wand.and.stars",
            summary: "Calculations, link cleaning, type detection, OCR, smart search.",
            detailDescription: "Adds an on-device intelligence layer over the clipboard: inline math results, tracking-parameter removal, email/URL/phone/JWT/color/code detection, background image OCR, sensitive-content filtering, and slash/regex/semantic search.",
            requiredPermissions: [],
            activator: NoopFeatureActivator(),
            settingsTabFactory: { AnyView(ClipboardSmartTextSettingsView()) }
        )
    }
}
