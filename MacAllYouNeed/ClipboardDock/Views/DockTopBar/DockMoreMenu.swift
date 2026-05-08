import Core
import SwiftUI

struct DockMoreMenu: View {
    let openSettings: () -> Void

    var body: some View {
        Menu {
            Menu("Privacy") {
                Button("Open Privacy Settings…") {
                    AppGroupSettings.defaults.set("privacy", forKey: "settings.selectedTab")
                    openSettings()
                }
                Button("Pause capture for 60s") {
                    NotificationCenter.default.post(name: .pauseCaptureRequested, object: nil)
                }
            }

            Menu("Clear Older Than") {
                Button("1 day") {
                    NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 1)
                }
                Button("7 days") {
                    NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 7)
                }
                Button("30 days") {
                    NotificationCenter.default.post(name: .clearClipboardOlderThanRequested, object: 30)
                }
            }

            Divider()

            Button("Open Settings…") {
                AppGroupSettings.defaults.set("general", forKey: "settings.selectedTab")
                openSettings()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28, height: 28)
    }
}
