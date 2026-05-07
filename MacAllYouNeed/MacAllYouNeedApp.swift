import AppKit
import Core
import SwiftUI

@main
struct MacAllYouNeedApp: App {
    @State private var controller: AppController

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            AppMenuBarContent(controller: controller)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsRoot(controller: controller) }
    }

    init() {
        let c = try! AppController()
        _controller = State(initialValue: c)
        Task { @MainActor in
            await Task.yield()
            c.showOnboardingIfNeeded()
        }
    }
}
