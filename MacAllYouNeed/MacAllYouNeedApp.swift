import AppKit
import Core
import SwiftUI

@main
struct MacAllYouNeedApp: App {
    // Static let: created exactly once regardless of how many times
    // SwiftUI recreates the App struct value.
    private static let controller = try! AppController()

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            AppMenuBarContent(controller: Self.controller)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsRoot(controller: Self.controller) }
    }

    init() {
        // init() may be called more than once by SwiftUI; showOnboardingIfNeeded()
        // is idempotent so re-scheduling is safe.
        Task { @MainActor in
            await Task.yield()
            Self.controller.showOnboardingIfNeeded()
        }
    }
}
