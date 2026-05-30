import Core
import FeatureCore
import SwiftUI

enum RemindersFeatureDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .voiceReminders,
            displayName: "Voice Reminders",
            icon: "checklist",
            summary: "Speak reminders straight into Apple Reminders.",
            detailDescription: "Press the reminder shortcut (or start a dictation with \u{201C}remind me to\u{2026}\u{201D}) "
                + "and your speech is cleaned up and saved to Apple Reminders instead of being pasted. "
                + "Disabled by default; requires Reminders access.",
            requiredPermissions: [.reminders],
            activator: NoopFeatureActivator()
        )
    }
}
