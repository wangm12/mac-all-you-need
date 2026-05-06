import AppKit
import Core
import ServiceManagement
import SwiftUI

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let deps = AppDependencies()
    private var popup: ClipboardPopupController?
    private var hotkey: HotkeyController?

    func applicationDidFinishLaunching(_: Notification) {
        registerDaemon()
        requestAccessibilityIfNeeded()
        registerHotkey()
    }

    @MainActor
    private func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
    }

    @MainActor
    private func registerDaemon() {
        let service = SMAppService.loginItem(identifier: "com.macallyouneed.app.daemon")
        guard service.status == .notRegistered || service.status == .notFound else { return }
        do {
            try service.register()
        } catch {
            Logging.logger(for: "app", category: "daemon").error("Daemon register failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func registerHotkey() {
        let p = ClipboardPopupController(deps: deps)
        let h = HotkeyController(popup: p)
        do {
            try h.registerHotkeyThrowing()
            NSLog("HotkeyController: ⌘⇧V registered")
        } catch {
            NSLog("HotkeyController: FAILED — \(error)")
        }
        popup = p
        hotkey = h
    }
}

// MARK: - App Entry Point

@main
struct MacAllYouNeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Mac All You Need", systemImage: "tray.full") {
            ClipboardMenuBarContent(deps: appDelegate.deps)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Content

struct ClipboardMenuBarContent: View {
    let deps: AppDependencies
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent clipboard").font(.caption).foregroundStyle(.secondary)
            ForEach(deps.recentItems, id: \.id) { item in
                HStack {
                    Text(item.preview).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if deps.recentItems.isEmpty {
                Text("No items yet").foregroundStyle(.tertiary).font(.callout)
            }
        }
        .padding(12)
        .frame(width: 480)
        .task { await deps.refresh() }
    }
}
