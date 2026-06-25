import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import EventKit
import SwiftUI
import UI
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

    static func microphoneStatus(
        captureStatus: AVAuthorizationStatus,
        recordPermission: AVAudioApplication.recordPermission
    ) -> PermissionDisplayState {
        if captureStatus == .authorized || recordPermission == .granted {
            return .granted
        }
        if captureStatus == .denied || captureStatus == .restricted || recordPermission == .denied {
            return .denied
        }
        if captureStatus == .notDetermined || recordPermission == .undetermined {
            return .notRequested
        }

        return .needsAction
    }

    static func currentMicrophoneStatus() -> PermissionDisplayState {
        microphoneStatus(
            captureStatus: AVCaptureDevice.authorizationStatus(for: .audio),
            recordPermission: AVAudioApplication.shared.recordPermission
        )
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

    /// Probes the live OS state. Returns `.granted` only if the app can
    /// actually read an FDA-protected system file right now.
    static func currentFullDiskAccessStatus() -> PermissionDisplayState {
        optionalPermission(isGranted: FullDiskAccessProbe.isGranted())
    }

    static func currentScreenRecordingStatus() -> PermissionDisplayState {
        optionalPermission(isGranted: CGPreflightScreenCaptureAccess())
    }

    static func notificationStatus(_ status: UNAuthorizationStatus) -> PermissionDisplayState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .granted
        case .denied:
            .denied
        case .notDetermined:
            .optional
        @unknown default:
            .needsAction
        }
    }

    static func remindersStatus(_ status: EKAuthorizationStatus) -> PermissionDisplayState {
        switch status {
        case .fullAccess, .authorized:
            .granted
        case .notDetermined:
            .notRequested
        case .denied, .restricted:
            .denied
        case .writeOnly:
            .needsAction
        @unknown default:
            .needsAction
        }
    }

    static func currentRemindersStatus() -> PermissionDisplayState {
        remindersStatus(EKEventStore.authorizationStatus(for: .reminder))
    }
}

enum PermissionActionPresentation {
    static func notificationActionTitle(for status: PermissionDisplayState) -> String {
        switch status {
        case .granted:
            "Granted"
        case .denied:
            "Open"
        case .notRequested, .needsAction, .optional:
            "Request"
        }
    }
}

struct PermissionsSettingsView: View {
    let remindersService: RemindersService

    var body: some View {
        MAYNSettingsPage(
            title: "Permissions",
            subtitle: "macOS access required for paste, voice, reminders, cookies, and alerts."
        ) {
            PermissionsSettingsSection(remindersService: remindersService)
        }
    }
}

struct PermissionsSettingsSection: View {
    let remindersService: RemindersService
    @State private var accessibilityStatus = PermissionStatusProvider.requiredPermission(isGranted: AXIsProcessTrusted())
    @State private var fullDiskAccessStatus = PermissionStatusProvider.currentFullDiskAccessStatus()
    @State private var microphoneStatus = PermissionStatusProvider.currentMicrophoneStatus()
    @State private var screenRecordingStatus = PermissionStatusProvider.currentScreenRecordingStatus()
    @State private var notificationsStatus = PermissionDisplayState.optional
    @State private var remindersStatus = PermissionStatusProvider.currentRemindersStatus()
    @State private var requestedInstructionTarget: PermissionInstructionTarget?
    @State private var highlightedPermission: PermissionInstructionTarget?
    @State private var hostWindow: NSWindow?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let appName = "Mac All You Need"

    var body: some View {
        Group {
            MAYNSection(
                title: "Required Access",
                subtitle: "These permissions unlock core workflows. The app stays local-first either way."
            ) {
                AccessibilityPermissionRow(
                    status: accessibilityStatus,
                    isHighlighted: highlightedPermission == .accessibility,
                    onAction: requestAccessibility
                )

                MAYNDivider()

                MicrophonePermissionRow(
                    status: microphoneStatus,
                    isHighlighted: highlightedPermission == .microphone,
                    onAction: requestMicrophone
                )

                MAYNDivider()

                RemindersPermissionRow(
                    status: remindersStatus,
                    isHighlighted: false,
                    onAction: requestReminders
                )
            }

            MAYNSection(
                title: "Optional Access",
                subtitle: "Useful for cookie import and status feedback, but not required for local capture or downloads."
            ) {
                ScreenRecordingPermissionRow(
                    status: screenRecordingStatus,
                    isHighlighted: highlightedPermission == .screenRecording,
                    onAction: requestScreenRecording
                )

                MAYNDivider()

                FullDiskAccessPermissionRow(
                    status: fullDiskAccessStatus,
                    isHighlighted: highlightedPermission == .fullDiskAccess,
                    onAction: requestFullDiskAccess
                )

                MAYNDivider()

                NotificationsPermissionRow(
                    status: notificationsStatus,
                    isHighlighted: highlightedPermission == .notifications,
                    onAction: requestNotifications
                )
            }

            if let visibleInstructionTarget,
               !PermissionFloatingInstructionPresentation.shouldFloat(
                   visibleInstructionTarget.instruction(appName: appName)
               ) {
                permissionInstructionStrip(for: visibleInstructionTarget)
            }
        }
        .onAppear {
            refresh()
            loadNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remindersStatus = PermissionStatusProvider.currentRemindersStatus()
        }
        .onDisappear {
            PermissionGrantPresenter.dismissFloatingPanel()
        }
        .onReceive(timer) { _ in
            refresh()
        }
        .background(PermissionSettingsWindowReader { hostWindow = $0 })
    }

    private var visibleInstructionTarget: PermissionInstructionTarget? {
        PermissionInstructionPresentation.visibleTarget(
            requestedTarget: requestedInstructionTarget,
            accessibilityStatus: accessibilityStatus,
            microphoneStatus: microphoneStatus,
            screenRecordingStatus: screenRecordingStatus,
            fullDiskAccessStatus: fullDiskAccessStatus,
            notificationsStatus: notificationsStatus
        )
    }

    private func permissionInstructionStrip(for target: PermissionInstructionTarget) -> some View {
        let instruction = target.instruction(appName: appName)
        return InstructionStrip(
            text: instruction.primaryText,
            appName: appName,
            symbol: instruction.symbol,
            secondaryText: instruction.secondaryText,
            dragAppURL: instruction.supportsAppDrag ? Bundle.main.bundleURL : nil,
            actionTitle: PermissionInstructionPresentation.actionTitle(for: instruction)
        ) {
            openInstructionSettings(instruction)
        }
        .id(target.rawValue)
        .transition(.opacity)
    }

    private func refresh() {
        accessibilityStatus = PermissionStatusProvider.requiredPermission(isGranted: AXIsProcessTrusted())
        microphoneStatus = PermissionStatusProvider.currentMicrophoneStatus()
        remindersStatus = PermissionStatusProvider.currentRemindersStatus()
        fullDiskAccessStatus = PermissionStatusProvider.currentFullDiskAccessStatus()
        screenRecordingStatus = PermissionStatusProvider.currentScreenRecordingStatus()
        advanceInstructionIfCurrentTargetIsGranted()
    }

    private func requestReminders() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            switch EKEventStore.authorizationStatus(for: .reminder) {
            case .notDetermined:
                _ = try? await remindersService.requestAccess()
            default:
                PermissionGateProbe.openSettings(for: .reminders)
            }
            remindersStatus = PermissionStatusProvider.currentRemindersStatus()
            if remindersStatus == .denied || remindersStatus == .needsAction {
                PermissionGateProbe.openSettings(for: .reminders)
            }
        }
    }

    private func requestScreenRecording() {
        focusInstruction(.screenRecording)
        CGRequestScreenCaptureAccess()
        refresh()
        guard !CGPreflightScreenCaptureAccess() else { return }
        PermissionGrantPresenter.presentFloatingInstruction(
            for: .screenRecording,
            appName: appName,
            sourceWindow: hostWindow
        ) {
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    private func requestAccessibility() {
        focusInstruction(.accessibility)
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        PermissionGrantPresenter.presentFloatingInstruction(
            for: .accessibility,
            appName: appName,
            sourceWindow: hostWindow
        ) {
            openPrivacyPane("Privacy_Accessibility")
        }
    }

    private func requestFullDiskAccess() {
        focusInstruction(.fullDiskAccess)
        PermissionGrantPresenter.presentFloatingInstruction(
            for: .fullDiskAccess,
            appName: appName,
            sourceWindow: hostWindow
        ) {
            openPrivacyPane("Privacy_AllFiles")
        }
    }

    private func requestMicrophone() {
        focusInstruction(.microphone)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async {
                    refresh()
                }
            }
        default:
            PermissionGrantPresenter.presentFloatingInstruction(
                for: .microphone,
                appName: appName,
                sourceWindow: hostWindow
            ) {
                openPrivacyPane("Privacy_Microphone")
            }
        }
    }

    private func requestNotifications() {
        focusInstruction(.notifications)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async {
                        loadNotificationStatus()
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    openNotificationsSettings()
                    loadNotificationStatus()
                }
            default:
                DispatchQueue.main.async {
                    loadNotificationStatus()
                }
            }
        }
    }

    private func focusInstruction(_ target: PermissionInstructionTarget) {
        requestedInstructionTarget = target
        highlightedPermission = target

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            if highlightedPermission == target {
                highlightedPermission = nil
            }
        }
    }

    private func status(for target: PermissionInstructionTarget) -> PermissionDisplayState {
        switch target {
        case .accessibility:
            accessibilityStatus
        case .microphone:
            microphoneStatus
        case .screenRecording:
            screenRecordingStatus
        case .fullDiskAccess:
            fullDiskAccessStatus
        case .notifications:
            notificationsStatus
        }
    }

    private func openInstructionSettings(_ instruction: PermissionInstruction) {
        if instruction.systemSettingsAnchor == "Notifications" {
            openNotificationsSettings()
        } else {
            openPrivacyPane(instruction.systemSettingsAnchor)
        }
    }

    private func loadNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsStatus = PermissionStatusProvider.notificationStatus(settings.authorizationStatus)
                advanceInstructionIfCurrentTargetIsGranted()
            }
        }
    }

    private func advanceInstructionIfCurrentTargetIsGranted() {
        guard let requestedInstructionTarget else { return }
        if status(for: requestedInstructionTarget) == .granted {
            self.requestedInstructionTarget = nil
            PermissionGrantPresenter.dismissFloatingPanel()
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openNotificationsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

private struct PermissionSettingsWindowReader: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onWindowChange(nsView.window)
        }
    }
}
