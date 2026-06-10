import SwiftUI

struct OnboardingShortcutSection: View {
    let title: String
    let subtitle: String
    let shortcutDisplay: String

    var body: some View {
        OnboardingGroupedSection(title: title, subtitle: subtitle) {
            OnboardingPanel {
                HStack(spacing: 10) {
                    ShortcutChip(text: shortcutDisplay, height: HotkeyChipPresentation.compactHeight)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
