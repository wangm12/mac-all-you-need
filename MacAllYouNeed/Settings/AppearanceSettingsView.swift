import Core
import SwiftUI
import CoreFoundation

struct AppearanceSettingsView: View {
    let controller: AppController

    @State private var menuSymbol: String = AppGroupSettings.defaults.string(forKey: "appearance.menuSymbol") ?? "tray.full"
    @State private var dockHeight: Double = {
        let value = AppGroupSettings.defaults.double(forKey: "dock.height")
        return value == 0 ? 360 : value
    }()
    @State private var captureSound: Bool = AppGroupSettings.defaults.object(forKey: "capture.sound") as? Bool ?? false
    @State private var pasteBehavior: String = AppGroupSettings.defaults.string(forKey: "autoPaste.behavior") ?? "pasteIntoFocused"
    @State private var pasteDelay: Int = {
        let value = AppGroupSettings.defaults.integer(forKey: "autoPaste.delayMs")
        return value == 0 ? 150 : value
    }()

    private let symbols = ["tray.full", "doc.on.clipboard", "clipboard", "square.on.square", "tray"]

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Icon", selection: $menuSymbol) {
                    ForEach(symbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
            }

            Section("Dock") {
                Slider(value: $dockHeight, in: 300...500, step: 10) {
                    Text("Height")
                } minimumValueLabel: {
                    Text("300")
                } maximumValueLabel: {
                    Text("500")
                }
                Text("Height: \(Int(dockHeight))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                Toggle("Play sound on capture", isOn: $captureSound)
            }

            Section("Auto-paste") {
                Picker("On pick", selection: $pasteBehavior) {
                    Text("Paste into focused app").tag("pasteIntoFocused")
                    Text("Just copy").tag("copyOnly")
                    Text("Copy, then paste").tag("copyThenPaste")
                }

                if pasteBehavior == "copyThenPaste" {
                    Stepper(value: $pasteDelay, in: 50...2000, step: 50) {
                        Text("Delay: \(pasteDelay) ms")
                    }
                }
            }
        }
        .padding()
        .onChange(of: menuSymbol) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "appearance.menuSymbol")
            postSettingsChangedDarwin()
        }
        .onChange(of: dockHeight) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "dock.height")
            controller.clipboardDock.dockHeight = CGFloat(value)
            postSettingsChangedDarwin()
        }
        .onChange(of: captureSound) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "capture.sound")
            postSettingsChangedDarwin()
        }
        .onChange(of: pasteBehavior) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "autoPaste.behavior")
            postSettingsChangedDarwin()
        }
        .onChange(of: pasteDelay) { _, value in
            AppGroupSettings.defaults.set(value, forKey: "autoPaste.delayMs")
            postSettingsChangedDarwin()
        }
    }

    private func postSettingsChangedDarwin() {
        let name = "com.macallyouneed.settings-changed" as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
    }
}
