import AppKit
import ApplicationServices
import SwiftUI
import UserNotifications

struct WelcomeStep: View {
    let next: () -> Void
    var body: some View {
        SetupTaskPage(
            symbol: "sparkles",
            title: "Welcome to Mac All You Need",
            subtitle: "Set up the permissions that make clipboard pasteback, folder previews, and downloads work smoothly."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                setupItem("Universal clipboard with search and snippets", "doc.on.clipboard")
                setupItem("Quick Look folders and archives", "folder")
                setupItem("Video downloads with queue and progress", "arrow.down.circle")
            }
        }
    }

    private func setupItem(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.primary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
    }
}

struct AccessibilityStep: View {
    let next: () -> Void
    var permissionChanged: (Bool) -> Void = { _ in }
    @State private var granted = AXIsProcessTrusted()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        SetupTaskPage(
            symbol: "accessibility",
            title: "Allow Accessibility",
            subtitle: "Required for pasteback from the clipboard popup and snippet expansion into the active app."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionCard(
                    title: "Accessibility",
                    reason: "Mac All You Need needs this to paste selected clipboard items and expand `;trigger` snippets.",
                    state: granted ? .granted : .needed,
                    actionTitle: "Open System Settings"
                ) {
                    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                }
                InstructionStrip(
                    text: "Enable Accessibility for Mac All You Need, then return here.",
                    symbol: "switch.2"
                )
                Text("This step advances automatically once macOS reports the permission as granted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { permissionChanged(granted) }
        .onReceive(timer) { _ in
            granted = AXIsProcessTrusted()
            permissionChanged(granted)
            if granted { next() }
        }
    }
}

struct FullDiskAccessStep: View {
    let next: () -> Void
    var body: some View {
        SetupTaskPage(
            symbol: "externaldrive",
            title: "Full Disk Access",
            subtitle: "Recommended for browser cookie import so authenticated video downloads can reuse signed-in sessions."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionCard(
                    title: "Full Disk Access",
                    reason: "Basic downloads still work without it, but cookie import from Chrome or Safari needs this permission.",
                    state: .optional,
                    actionTitle: "Open System Settings"
                ) {
                    openFullDiskAccessSettings()
                }
                InstructionStrip(
                    text: "Turn on Full Disk Access for Mac All You Need if you want browser cookie import.",
                    symbol: "lock.open"
                )
                StatusPill(text: "You can continue without this", kind: .neutral)
            }
        }
    }

    private func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

struct NotificationsStep: View {
    let next: () -> Void
    var body: some View {
        SetupTaskPage(
            symbol: "bell",
            title: "Notifications",
            subtitle: "Optional alerts for completed downloads and long-running background work."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PermissionCard(
                    title: "Notifications",
                    reason: "Used only for download completion alerts. You can change this later in System Settings.",
                    state: .optional,
                    actionTitle: "Allow"
                ) {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                        DispatchQueue.main.async { next() }
                    }
                }
                InstructionStrip(
                    text: "Choose Allow in the macOS notification prompt.",
                    symbol: "bell.badge"
                )
            }
        }
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
        SetupTaskPage(
            symbol: "arrow.triangle.2.circlepath",
            title: "Sync setup",
            subtitle: "Choose how this Mac should store setup data. Sync is planned, so local-only is the practical default today."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $choice) {
                    Text("Set up sync now").tag("now")
                    Text("Local only").tag("local")
                    Text("Decide later").tag("later")
                }
                .pickerStyle(.radioGroup)
                if choice == "now" {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(path.isEmpty ? "Pick a folder..." : path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Browse...") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                if panel.runModal() == .OK, let picked = panel.url { path = picked.path }
                            }
                        }
                        SecureField("Passphrase", text: $passphrase)
                        Text("Sync requires Plan 2 and is not active yet. These fields are retained for the future sync setup flow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                    )
                } else {
                    StatusPill(text: choice == "local" ? "Local only" : "Decide later", kind: .neutral)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.primary).font(.caption)
                }
            }
        }
    }
}

struct ReadyStep: View {
    let close: () -> Void
    var body: some View {
        SetupTaskPage(
            symbol: "checkmark",
            title: "You're ready",
            subtitle: "The app is configured. Use the shortcuts below to open the two fastest workflows."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ShortcutChip(text: "⌘⇧V")
                Text("Open clipboard search from anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ShortcutChip(text: "Space")
                Text("Preview folders and archives from Finder with Quick Look.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
            )
        }
    }
}
