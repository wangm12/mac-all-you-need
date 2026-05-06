import SwiftUI

@main
struct MacAllYouNeedApp: App {
    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            Text("Mac All You Need — scaffold")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
