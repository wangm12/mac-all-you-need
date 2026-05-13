import AppKit
import Core
import SwiftUI

@main
struct MacAllYouNeedApp: App {
    // Static let: created exactly once regardless of how many times
    // SwiftUI recreates the App struct value.
    fileprivate static let controller = try! AppController()
    @NSApplicationDelegateAdaptor(MacAllYouNeedApplicationDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            appMenuContent
        } label: {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .padding(.horizontal, -2)
                .accessibilityLabel("Mac All You Need")
        }
        .menuBarExtraStyle(.window)
        Settings { settingsContent }
    }

    @ViewBuilder
    private var appMenuContent: some View {
        if MAYNIsRunningUnderXCTest() {
            EmptyView()
        } else {
            AppMenuBarContent(controller: Self.controller)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if MAYNIsRunningUnderXCTest() {
            EmptyView()
        } else {
            SettingsRoot(controller: Self.controller)
        }
    }

    init() {
        guard !MAYNIsRunningUnderXCTest() else { return }
        // init() may be called more than once by SwiftUI; showOnboardingIfNeeded()
        // is idempotent so re-scheduling is safe.
        Task { @MainActor in
            await Task.yield()
            Self.controller.showStartupSurface()
        }
    }
}

@MainActor
final class MacAllYouNeedApplicationDelegate: NSObject, NSApplicationDelegate {
    var handleReopen: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !MAYNIsRunningUnderXCTest() else { return }
        routeStartupSurface()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        routeStartupSurface()
        return true
    }

    private func routeStartupSurface() {
        if let handleReopen {
            handleReopen()
        } else {
            MacAllYouNeedApp.controller.showStartupSurface()
        }
    }
}

private func MAYNIsRunningUnderXCTest() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestBundlePath"] != nil
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestSessionIdentifier"] != nil
}
