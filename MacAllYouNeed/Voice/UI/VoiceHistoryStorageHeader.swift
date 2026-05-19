import Core
import SwiftUI

struct VoiceHistoryStorageHeader: View {
    @Binding var settings: VoiceHistorySettings

    var body: some View {
        MAYNSection(title: "Storage") {
            MAYNSettingsRow(
                title: "Keep history",
                subtitle: "How long to keep voice transcripts on this device."
            ) {
                MAYNDropdown(
                    selection: $settings.retention,
                    options: VoiceHistoryRetention.allCases,
                    title: { $0.displayTitle },
                    width: MAYNControlMetrics.widePickerWidth
                )
            }
            MAYNDivider()
            MAYNSettingsRow(
                title: "Save audio recordings",
                subtitle: "Required for Download audio and Retry. Recordings are encrypted locally."
            ) {
                Toggle("", isOn: $settings.saveAudio)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }
}
