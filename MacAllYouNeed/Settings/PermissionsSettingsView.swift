import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI
import UserNotifications

enum PermissionDisplayState: Equatable {
    case notRequested
    case needsAction
    case granted
    case denied
    case optional

    var cardState: PermissionCard.StateKind {
        switch self {
        case .granted:
            .granted
        case .denied:
            .denied
        case .optional:
            .optional
        case .notRequested, .needsAction:
            .needed
        }
    }
}

enum PermissionStatusProvider {
    static func microphoneStatus(_ status: AVAuthorizationStatus) -> PermissionDisplayState {
        switch status {
        case .authorized:
            .granted
        case .notDetermined:
            .notRequested
        case .denied, .restricted:
            .denied
        @unknown default:
            .needsAction
        }
    }

    static func requiredPermission(isGranted: Bool) -> PermissionDisplayState {
        isGranted ? .granted : .needsAction
    }

    static func optionalPermission(isGranted: Bool) -> PermissionDisplayState {
        isGranted ? .granted : .optional
    }

    static func fullDiskAccessStatus(hasCheckedAccess: Bool?) -> PermissionDisplayState {
        guard let hasCheckedAccess else { return .optional }
        return optionalPermission(isGranted: hasCheckedAccess)
    }
}

struct PermissionsSettingsView: View {
    @State private var accessibilityStatus = PermissionStatusProvider.requiredPermission(isGranted: AXIsProcessTrusted())
    @State private var fullDiskAccessStatus = PermissionStatusProvider.fullDiskAccessStatus(hasCheckedAccess: nil)
    @State private var microphoneStatus = PermissionStatusProvider.microphoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    @State private var notificationsStatus = PermissionDisplayState.optional

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        MAYNSettingsPage(
            title: "Permissions",
            subtitle: "macOS access required for paste, voice, cookies, and alerts."
        ) {
            MAYNSection(
                title: "Required Access",
                subtitle: "These permissions unlock core workflows. The app stays local-first either way."
            ) {
                PermissionCard(
                    title: "Accessibility",
                    reason: "Allows global shortcuts, paste injection, and snippet expansion in the active app.",
                    state: accessibilityStatus.cardState,
                    actionTitle: accessibilityStatus == .granted ? "Granted" : "Open"
                ) {
                    requestAccessibility()
                }

                MAYNDivider()

                PermissionCard(
                    title: "Microphone",
                    reason: "Allows voice dictation and the voice setup test to capture local audio.",
                    state: microphoneStatus.cardState,
                    actionTitle: microphoneActionTitle
                ) {
                    requestMicrophone()
                }

            }

            MAYNSection(
                title: "Optional Access",
                subtitle: "Useful for cookie import and status feedback, but not required for local capture or downloads."
            ) {
                PermissionCard(
                    title: "Full Disk Access",
                    reason: "Allows browser cookie import for authenticated video downloads.",
                    state: fullDiskAccessStatus.cardState,
                    actionTitle: "Open"
                ) {
                    requestFullDiskAccess()
                }

                MAYNDivider()

                PermissionCard(
                    title: "Notifications",
                    reason: "Shows download completion and failure alerts.",
                    state: notificationsStatus.cardState,
                    actionTitle: notificationsStatus == .granted ? "Granted" : "Request"
                ) {
                    requestNotifications()
                }
            }

            InstructionStrip(
                text: "If System Settings opens, enable Mac All You Need, then return here.",
                appName: "Mac All You Need",
                symbol: "arrow.up.forward.app"
            )
        }
        .onAppear {
            refresh()
            loadNotificationStatus()
        }
        .onReceive(timer) { _ in
            refresh()
        }
    }

    private var microphoneActionTitle: String {
        switch microphoneStatus {
        case .granted:
            "Granted"
        case .denied:
            "Open"
        default:
            "Request"
        }
    }

    private func refresh() {
        accessibilityStatus = PermissionStatusProvider.requiredPermission(isGranted: AXIsProcessTrusted())
        microphoneStatus = PermissionStatusProvider.microphoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    private func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openPrivacyPane("Privacy_Accessibility")
    }

    private func requestFullDiskAccess() {
        openPrivacyPane("Privacy_AllFiles")
    }

    private func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    refresh()
                }
            }
        default:
            openPrivacyPane("Privacy_Microphone")
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                loadNotificationStatus()
            }
        }
    }

    private func loadNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                notificationsStatus = PermissionStatusProvider.optionalPermission(isGranted: granted)
            }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
