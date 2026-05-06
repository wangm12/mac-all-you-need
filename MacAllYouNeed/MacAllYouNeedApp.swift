import SwiftUI
import Core

@main
struct MacAllYouNeedApp: App {
    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            let fallback = AppGroup.isUsingFallbackContainer() ? " (FALLBACK - entitlement missing)" : ""
            Text("Container: \(AppGroup.containerURL().path)\(fallback)")
                .padding()
                .frame(width: 480)
        }
        .menuBarExtraStyle(.window)
    }
}
