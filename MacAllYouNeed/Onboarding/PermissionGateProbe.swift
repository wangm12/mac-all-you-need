import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import FeatureCore
import Foundation
import UserNotifications

/// Read-only probe + UI-driving helper for each `Permission` declared on a
/// `FeatureDescriptor`. Owns the mapping from FeatureCore's abstract Permission
/// to AppKit/AVFoundation/UN APIs and the `x-apple.systempreferences:` URL.
@MainActor
enum PermissionGateProbe {
    private(set) static var cachedNotificationGranted = false

    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted()
        case .fullDiskAccess:
            // No first-party API. Probe by attempting to read a known protected path.
            let probe = ("~/Library/Safari/Bookmarks.plist" as NSString).expandingTildeInPath
            return FileManager.default.isReadableFile(atPath: probe)
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .notifications:
            return cachedNotificationGranted
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .reminders:
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .fullAccess, .authorized:
                return true
            default:
                return false
            }
        }
    }

    static func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        cachedNotificationGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    static func openSettings(for permission: Permission) {
        let raw: String
        switch permission {
        case .accessibility:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .fullDiskAccess:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .microphone:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .notifications:
            raw = "x-apple.systempreferences:com.apple.preference.notifications"
        case .screenRecording:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .reminders:
            raw = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        }
        if let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Issues the system permission request where applicable.
    /// Calls `completion` with `true` once granted (or immediately if not requestable).
    static func request(_ permission: Permission, completion: @escaping (Bool) -> Void) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            completion(AXIsProcessTrusted())
        case .fullDiskAccess:
            // No programmatic request — UI directs the user to System Settings.
            completion(isGranted(.fullDiskAccess))
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            completion(granted)
        case .reminders:
            EKEventStore().requestFullAccessToReminders { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    static func displayName(for permission: Permission) -> String {
        switch permission {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .microphone: return "Microphone"
        case .notifications: return "Notifications"
        case .screenRecording: return "Screen Recording"
        case .reminders: return "Reminders"
        }
    }

    static func reason(for permission: Permission, descriptor: FeatureDescriptor) -> String {
        switch (descriptor.id, permission) {
        case (.clipboard, .accessibility):
            return "Lets the clipboard popup paste into the active app and `;trigger` snippets expand."
        case (.downloader, .fullDiskAccess):
            return "Optional. Browser cookie import (Chrome/Safari) needs this for authenticated downloads."
        case (.downloader, .notifications):
            return "Optional. Used only for download completion alerts."
        case (.voice, .accessibility):
            return "Lets dictation paste recognized text into the active app."
        case (.voice, .microphone):
            return "Required for voice capture."
        default:
            return "Required for \(descriptor.displayName)."
        }
    }
}
