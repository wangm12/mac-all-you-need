import SwiftUI

/// Tighter numeric row: title on the left, stepper on the right — no redundant subtitle line.
struct DockSettingsCompactNumericRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String?

    var body: some View {
        MAYNSettingsRow(title: title, minHeight: 44) {
            MAYNNumericStepper(
                text: title,
                value: $value,
                range: range,
                step: step,
                suffix: suffix,
                fieldWidth: 72
            )
        }
    }
}
