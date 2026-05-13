import AppKit
import Core
import SwiftUI

struct GeneralSettingsView: View {
    let controller: AppController
    @AppStorage("launchAtLogin", store: AppGroupSettings.defaults) private var launchAtLogin = true
    @AppStorage("hudDurationMs", store: AppGroupSettings.defaults) private var hudDurationMs = 2000
    @State private var dockHeight: Double = {
        let value = AppGroupSettings.defaults.double(forKey: "dock.height")
        return value == 0 ? 360 : value
    }()

    var body: some View {
        MAYNSettingsPage(
            title: "General",
            subtitle: "Control how Mac All You Need launches, appears, and reports quick feedback."
        ) {
            MAYNSection(title: "App behavior") {
                MAYNSettingsRow(
                    title: "Launch at login",
                    subtitle: "Start the helper app automatically when macOS signs in."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Dock icon",
                    subtitle: "Mac All You Need now appears as a regular macOS app with a persistent Dock icon."
                ) {
                    StatusPill(text: "Always visible", kind: .success)
                }
            }

            MAYNSection(title: "Menu bar and feedback") {
                MAYNSettingsRow(
                    title: "Menu bar icon",
                    subtitle: "The menu bar icon matches the black-and-white infinity app icon."
                ) {
                    StatusPill(text: "Synced", kind: .neutral)
                }
                MAYNDivider()
                MAYNSettingsRow(
                    title: "Notification duration",
                    subtitle: "How long copy, download, and voice status chips stay visible."
                ) {
                    Picker("", selection: $hudDurationMs) {
                        Text("1 second").tag(1000)
                        Text("2 seconds").tag(2000)
                        Text("3 seconds").tag(3000)
                        Text("5 seconds").tag(5000)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }

            MAYNSection(title: "Clipboard dock") {
                MAYNSettingsRow(
                    title: "Dock height",
                    subtitle: "The bottom clipboard surface stays dense while leaving room for the active app."
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $dockHeight, in: 300...500, step: 10)
                            .frame(width: 160)
                        Text("\(Int(dockHeight))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
        .onChange(of: launchAtLogin) { _, on in
            LoginItemController.setLaunchAtLogin(on)
        }
        .onChange(of: dockHeight) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "dock.height")
            controller.clipboardDock.dockHeight = CGFloat(value)
        }
    }
}
