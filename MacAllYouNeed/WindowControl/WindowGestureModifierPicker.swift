import Core
import SwiftUI

struct WindowGestureModifierPicker: View {
    @Binding var selection: WindowGestureModifier
    var width: CGFloat = MAYNControlMetrics.widePickerWidth

    var body: some View {
        MAYNDropdown(
            selection: $selection,
            options: Self.options,
            title: { $0.display },
            width: width
        )
    }

    static let options: [WindowGestureModifier] = [
        .none,
        .fn,
        .option,
        .leftOption,
        .rightOption,
        .control,
        .leftControl,
        .rightControl,
        .command,
        .leftCommand,
        .rightCommand,
        .shift,
        .leftShift,
        .rightShift,
        WindowGestureModifier([.control, .option]),
        WindowGestureModifier([.leftControl, .leftOption]),
        WindowGestureModifier([.rightControl, .rightOption]),
        WindowGestureModifier([.command, .option]),
        WindowGestureModifier([.leftCommand, .leftOption]),
        WindowGestureModifier([.rightCommand, .rightOption]),
        WindowGestureModifier([.control, .command])
    ]
}
