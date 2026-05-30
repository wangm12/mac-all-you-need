import Core
import FeatureCore
import SwiftUI

enum FileOrganizerDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .aiFileOrganizer,
            displayName: "AI File Organizer",
            icon: "folder.badge.gearshape",
            summary: "Rename and re-file messy folders with on-device content extraction and LLM naming.",
            detailDescription: "Scan a folder (or your Downloads) and the organizer reads each file's content "
                + "on-device (OCR, PDF text, plain text), asks your configured LLM for a clean name and "
                + "category, then shows a preview/approve diff before any change. Every batch is recorded "
                + "as a reversible manifest you can undo. Disabled by default.",
            requiredPermissions: [.fullDiskAccess],
            activator: NoopFeatureActivator()
        )
    }
}
