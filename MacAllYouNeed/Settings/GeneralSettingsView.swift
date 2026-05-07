import AppKit
import Core
import SwiftUI

struct GeneralSettingsView: View {
    let controller: AppController
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true
    @AppStorage("showDockDuringDownloads", store: AppGroupSettings.defaults) private var showDock = false
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LoginItemController.setLaunchAtLogin(on)
                }
            Toggle("Show dock icon during downloads", isOn: $showDock)
                .onChange(of: showDock) { _, visible in
                    NSApp.setActivationPolicy(visible ? .regular : .accessory)
                }
        }.padding()
    }
}
