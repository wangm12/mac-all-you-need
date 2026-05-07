import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Welcome to Mac All You Need").font(.largeTitle).bold()
            VStack(alignment: .leading, spacing: 8) {
                Label("Universal clipboard with search and snippets", systemImage: "doc.on.clipboard")
                Label("Quick Look folders and archives", systemImage: "folder")
                Label("Download videos from any site", systemImage: "arrow.down.circle")
            }
            Button("Get started", action: next).keyboardShortcut(.return)
        }.padding()
    }
}

struct AccessibilityStep: View {
    let next: () -> Void
    @State private var granted = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            Text("Accessibility permission").font(.title2).bold()
            Text("Required so the clipboard popup can paste back into your app, and so snippet `;trigger` expansion works.")
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            if granted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack { Spacer(); Button("Continue", action: next).disabled(!granted) }
        }
        .padding()
        .onReceive(timer) { _ in
            granted = AXIsProcessTrusted()
            if granted { next() }
        }
    }
}

struct FullDiskAccessStep: View {
    let next: () -> Void
    @State private var granted = FullDiskAccessProbe.hasUsefulAccess()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 12) {
            Text("Full Disk Access").font(.title2).bold()
            Text("Required for browser cookie import so authenticated downloads work. Without it, basic downloads still work.")
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            if granted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            HStack { Spacer(); Button("Continue", action: next) }
        }
        .padding()
        .onReceive(timer) { _ in
            let nowGranted = FullDiskAccessProbe.hasUsefulAccess()
            if nowGranted && !granted { next() }
            granted = nowGranted
        }
    }
}

enum FullDiskAccessProbe {
    static func hasUsefulAccess() -> Bool {
        let chromeCookies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")
        let safariCookies = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        return FileManager.default.isReadableFile(atPath: chromeCookies.path)
            || FileManager.default.isReadableFile(atPath: safariCookies.path)
    }
}

struct NotificationsStep: View {
    let next: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("Notifications").font(.title2).bold()
            Text("Optional. Used for download completion alerts. You can change this anytime in System Settings.")
                .multilineTextAlignment(.center)
            Button("Allow") {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async { next() }
                }
            }
            HStack { Spacer(); Button("Skip", action: next) }
        }.padding()
    }
}

struct SyncSetupStep: View {
    let controller: AppController
    let next: () -> Void
    @State private var choice = "later"
    @State private var path: String = ""
    @State private var passphrase: String = ""
    @State private var errorMessage: String?
    var body: some View {
        VStack(spacing: 12) {
            Text("Sync setup").font(.title2).bold()
            Picker("Mode", selection: $choice) {
                Text("Set up sync now").tag("now")
                Text("Local only").tag("local")
                Text("Decide later").tag("later")
            }.pickerStyle(.radioGroup)
            if choice == "now" {
                HStack {
                    Text(path.isEmpty ? "Pick a folder…" : path).foregroundStyle(.secondary)
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let u = panel.url { path = u.path }
                    }
                }
                SecureField("Passphrase", text: $passphrase)
                Text("Sync requires Plan 2 — coming soon. Saved for when it ships.").font(.caption).foregroundStyle(.tertiary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Continue", action: next)
            }
        }.padding()
    }
}

struct ReadyStep: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("You're ready!").font(.largeTitle).bold()
            Text("Press ⌘⇧V to open your clipboard. Press Space on a folder in Finder to preview it.")
                .multilineTextAlignment(.center)
            Button("Done", action: close).keyboardShortcut(.return)
        }.padding()
    }
}
