import SwiftUI

struct SettingsDestinationView: View {
    let controller: AppController

    var body: some View {
        EmbeddedSettingsView(controller: controller)
    }
}
