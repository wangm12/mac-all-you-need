import SwiftUI

struct VoiceHUDAppearanceSection: View {
    @State private var appearance = VoiceHUDAppearanceStore.load()

    var body: some View {
        MAYNSection(title: "Floating HUD") {
            MAYNSettingsRow(
                title: "Pill appearance",
                subtitle: "Glass uses native Liquid Glass (`glassEffect(.regular)`) on macOS 26+. Graphite is the legacy solid pill."
            ) {
                MAYNDropdown(
                    selection: $appearance,
                    options: Array(VoiceHUDAppearance.allCases),
                    title: \.title,
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
        }
        .onChange(of: appearance) { _, newValue in
            VoiceHUDAppearanceStore.save(newValue)
        }
        .onAppear {
            appearance = VoiceHUDAppearanceStore.load()
        }
    }
}
