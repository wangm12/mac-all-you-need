import SwiftUI

struct VoiceDictionarySection: View {
    let entryCount: Int
    let onOpen: () -> Void

    var body: some View {
        MAYNSection(title: "Dictionary") {
            MAYNSettingsRow(
                title: "Voice dictionary",
                subtitle: "\(entryCount) manual entries. Add words individually or import a CSV. Corrections apply before cleanup and paste."
            ) {
                MAYNButton("Open", action: onOpen)
            }
        }
    }
}
