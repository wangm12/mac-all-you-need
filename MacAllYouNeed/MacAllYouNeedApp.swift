import SwiftUI
import Core
import UI
import Platform

@main
struct MacAllYouNeedApp: App {
    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            Text("Core \(CoreVersion.value), UI \(UIVersion.value), Platform \(PlatformVersion.value)")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
