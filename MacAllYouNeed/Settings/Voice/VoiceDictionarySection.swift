import SwiftUI

struct VoiceDictionarySection: View {
    let entryCount: Int
    let onOpen: () -> Void

    var body: some View {
        MAYNSection(title: "Dictionary") {
            MAYNSettingsRow(
                title: "Voice dictionary",
                subtitle: "\(entryCount) manual entries. Correct names, product terms, and recurring ASR mistakes before cleanup and paste."
            ) {
                MAYNButton("Open", action: onOpen)
            }
        }
    }
}
