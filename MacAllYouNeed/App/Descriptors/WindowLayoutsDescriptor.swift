import FeatureCore
import SwiftUI

enum WindowLayoutsDescriptor {
    static func descriptor() -> FeatureDescriptor {
        FeatureDescriptor(
            id: .windowLayouts,
            displayName: "Window Layouts",
            icon: "rectangle.3.group",
            summary: "Keyboard layouts, edge snap, and restore.",
            detailDescription: "Arrange, snap, maximize, center, and restore the focused window with global shortcuts or edge gestures.",
            requiredPermissions: [.accessibility],
            hotkeys: [
                HotkeyDescriptor(identifier: "windowLayouts.leftHalf", displayName: "Left half"),
                HotkeyDescriptor(identifier: "windowLayouts.rightHalf", displayName: "Right half"),
                HotkeyDescriptor(identifier: "windowLayouts.topHalf", displayName: "Top half"),
                HotkeyDescriptor(identifier: "windowLayouts.bottomHalf", displayName: "Bottom half"),
                HotkeyDescriptor(identifier: "windowLayouts.maximize", displayName: "Maximize"),
                HotkeyDescriptor(identifier: "windowLayouts.center", displayName: "Center"),
                HotkeyDescriptor(identifier: "windowLayouts.restore", displayName: "Restore"),
            ],
            activator: WindowControlFeatureActivator()
        )
    }
}
