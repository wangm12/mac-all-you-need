import FeatureCore
import SwiftUI

enum WindowGrabDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .windowGrab,
            displayName: "Window Grab",
            icon: "hand.draw",
            summary: "Modifier-drag windows from anywhere.",
            detailDescription: "Move windows by holding a modifier and dragging from any visible area, with ignored-app rules shared with Window Layouts.",
            requiredPermissions: [.accessibility],
            activator: WindowControlFeatureActivator()
        )
    }
}
