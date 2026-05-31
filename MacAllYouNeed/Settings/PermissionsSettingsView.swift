import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
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

struct PermissionInstruction: Equatable {
    let primaryText: String
    let secondaryText: String
    let systemSettingsAnchor: String
    let symbol: String
    let supportsAppDrag: Bool
}

enum PermissionInstructionTarget: String, Equatable, Identifiable {
    case accessibility
    case microphone
    case screenRecording
    case fullDiskAccess
    case notifications

    var id: String { rawValue }

    static func defaultTarget(
        accessibilityStatus: PermissionDisplayState,
        microphoneStatus: PermissionDisplayState,
        screenRecordingStatus: PermissionDisplayState,
        fullDiskAccessStatus: PermissionDisplayState,
        notificationsStatus: PermissionDisplayState
    ) -> PermissionInstructionTarget {
        let required: [(PermissionInstructionTarget, PermissionDisplayState)] = [
            (.accessibility, accessibilityStatus),
            (.microphone, microphoneStatus)
        ]
        if let target = required.first(where: { $0.1 != .granted })?.0 {
            return target
        }

        let optional: [(PermissionInstructionTarget, PermissionDisplayState)] = [
            (.screenRecording, screenRecordingStatus),
            (.fullDiskAccess, fullDiskAccessStatus),
            (.notifications, notificationsStatus)
        ]
        if let target = optional.first(where: { $0.1 != .granted })?.0 {
            return target
        }

        return .accessibility
    }

    func instruction(appName: String) -> PermissionInstruction {
        switch self {
        case .accessibility:
            PermissionInstruction(
                primaryText: "Drag \(appName) into Accessibility.",
                secondaryText: "Window Layouts, Window Grab, paste injection, and snippets need this. If \(appName) already appears in the list, turn on its switch.",
                systemSettingsAnchor: "Privacy_Accessibility",
                symbol: "arrow.up.forward.app",
                supportsAppDrag: true
            )
        case .microphone:
            PermissionInstruction(
                primaryText: "Drag \(appName) into Microphone access.",
                secondaryText: "If \(appName) already appears in the list, turn on its switch.",
                systemSettingsAnchor: "Privacy_Microphone",
                symbol: "mic.badge.plus",
                supportsAppDrag: true
            )
        case .screenRecording:
            PermissionInstruction(
                primaryText: "Allow Screen Recording for \(appName).",
                secondaryText: "Dock Previews needs Screen Recording to capture live window thumbnails. Without it, the panel shows window titles only.",
                systemSettingsAnchor: "Privacy_ScreenCapture",
                symbol: "rectangle.on.rectangle.angled",
                supportsAppDrag: false
            )
        case .fullDiskAccess:
            PermissionInstruction(
                primaryText: "Drag \(appName) into Full Disk Access.",
                secondaryText: "If \(appName) already appears in the list, turn on its switch.",
                systemSettingsAnchor: "Privacy_AllFiles",
                symbol: "externaldrive.badge.plus",
                supportsAppDrag: true
            )
        case .notifications:
            PermissionInstruction(
                primaryText: "Allow notifications for \(appName).",
                secondaryText: "If notifications were denied before, enable them in macOS Notifications settings.",
                systemSettingsAnchor: "Notifications",
                symbol: "bell.badge",
                supportsAppDrag: false
            )
        }
    }
}

enum PermissionInstructionPresentation {
    static func actionTitle(for instruction: PermissionInstruction) -> String {
        "Open Settings"
    }

    static func visibleTarget(
        requestedTarget: PermissionInstructionTarget?,
        accessibilityStatus: PermissionDisplayState,
        microphoneStatus: PermissionDisplayState,
        screenRecordingStatus: PermissionDisplayState,
        fullDiskAccessStatus: PermissionDisplayState,
        notificationsStatus: PermissionDisplayState
    ) -> PermissionInstructionTarget? {
        guard let requestedTarget else { return nil }

        let requestedStatus: PermissionDisplayState
        switch requestedTarget {
        case .accessibility:
            requestedStatus = accessibilityStatus
        case .microphone:
            requestedStatus = microphoneStatus
        case .screenRecording:
            requestedStatus = screenRecordingStatus
        case .fullDiskAccess:
            requestedStatus = fullDiskAccessStatus
        case .notifications:
            requestedStatus = notificationsStatus
        }

        return requestedStatus == .granted ? nil : requestedTarget
    }
}

enum PermissionFloatingInstructionPresentation {
    static let arrowSymbol = "arrow.down.forward"
    static let panelSize = CGSize(width: 720, height: 176)
    static let windowLevel = NSWindow.Level.statusBar
    private static let screenMargin: CGFloat = 24
    private static let sourceWindowGap: CGFloat = 12

    static func shouldFloat(_ instruction: PermissionInstruction) -> Bool {
        instruction.supportsAppDrag
    }

    static func frame(on screen: NSScreen, preferredWindowFrame: NSRect? = nil) -> NSRect {
        frame(in: screen.visibleFrame, preferredWindowFrame: preferredWindowFrame)
    }

    static func frame(in visibleFrame: NSRect, preferredWindowFrame: NSRect? = nil) -> NSRect {
        let visible = visibleFrame
        let size = panelSize
        let preferredMidX = preferredWindowFrame?.midX ?? visible.midX
        let proposedX = preferredMidX - size.width / 2
        let minX = visible.minX + screenMargin
        let maxX = visible.maxX - size.width - screenMargin
        let proposedY: CGFloat
        if let preferredWindowFrame {
            proposedY = preferredWindowFrame.minY - size.height - sourceWindowGap
        } else {
            proposedY = visible.maxY - size.height - screenMargin
        }
        let minY = visible.minY + screenMargin
        let maxY = visible.maxY - size.height - screenMargin

        return NSRect(
            x: min(max(proposedX, minX), maxX),
            y: min(max(proposedY, minY), maxY),
            width: size.width,
            height: size.height
        )
    }

    static func appKitFrame(fromQuartzBounds bounds: CGRect, mainScreenFrame: NSRect) -> NSRect {
        NSRect(
            x: bounds.minX,
            y: mainScreenFrame.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    static func frame(
        belowQuartzBounds bounds: CGRect,
        mainScreenFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        frame(
            in: visibleFrame,
            preferredWindowFrame: appKitFrame(
                fromQuartzBounds: bounds,
                mainScreenFrame: mainScreenFrame
            )
        )
    }
}

@MainActor
final class FloatingPermissionInstructionPanelController {
    static let shared = FloatingPermissionInstructionPanelController()

    private var panelController: NonActivatingFloatingPanelController<FloatingPermissionInstructionPanelView>?
    private weak var sourceWindow: NSWindow?
    private var followTimer: Timer?
    private var isFollowingSystemSettings = false

    func show(
        instruction: PermissionInstruction,
        appName: String,
        appURL: URL,
        sourceWindow preferredSourceWindow: NSWindow?,
        attachToSystemSettings: Bool = false,
        openSettings: @escaping () -> Void
    ) {
        guard PermissionFloatingInstructionPresentation.shouldFloat(instruction) else { return }

        let sourceWindow = preferredSourceWindow ?? NSApp.keyWindow ?? NSApp.mainWindow

        // Tear down any existing panel before showing a new one.
        if let existing = panelController {
            existing.currentPanel.map { self.sourceWindow?.removeChildWindow($0) }
            existing.dismiss(animated: false)
            panelController = nil
        }
        followTimer?.invalidate()
        followTimer = nil
        isFollowingSystemSettings = attachToSystemSettings
        self.sourceWindow = attachToSystemSettings ? nil : sourceWindow

        let content = FloatingPermissionInstructionPanelView(
            instruction: instruction,
            appName: appName,
            appURL: appURL,
            openSettings: openSettings,
            close: { [weak self] in self?.dismiss() }
        )

        let initialFrame = computeInitialFrame(
            attachToSystemSettings: attachToSystemSettings,
            sourceWindow: sourceWindow
        )

        let controller = NonActivatingFloatingPanelController<FloatingPermissionInstructionPanelView>(
            styleMask: [.borderless, .nonactivatingPanel],
            level: PermissionFloatingInstructionPresentation.windowLevel,
            collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary],
            hasShadow: true,
            backgroundColor: .clear,
            showAnimationDuration: 0,
            hideAnimationDuration: 0,
            positioner: { panel, _ in
                panel.setFrameOrigin(initialFrame.origin)
            }
        )
        panelController = controller
        controller.present(rootView: content, size: PermissionFloatingInstructionPresentation.panelSize, animated: false)

        guard let panel = controller.currentPanel else { return }
        panel.isOpaque = false

        if let sourceWindow, !attachToSystemSettings {
            sourceWindow.addChildWindow(panel, ordered: .above)
        }

        panel.alphaValue = attachToSystemSettings && systemSettingsPanelFrame() == nil ? 0 : 1

        if attachToSystemSettings {
            startFollowingSystemSettings()
        }
    }

    func dismiss() {
        followTimer?.invalidate()
        followTimer = nil
        isFollowingSystemSettings = false
        if let panel = panelController?.currentPanel {
            sourceWindow?.removeChildWindow(panel)
        }
        panelController?.dismiss(animated: false)
        panelController = nil
        sourceWindow = nil
    }

    private func computeInitialFrame(attachToSystemSettings: Bool, sourceWindow: NSWindow?) -> NSRect {
        if attachToSystemSettings, let frame = systemSettingsPanelFrame() {
            return frame
        }

        guard let screen = sourceWindow?.screen ?? NSScreen.main else {
            return NSRect(origin: .zero, size: PermissionFloatingInstructionPresentation.panelSize)
        }

        return PermissionFloatingInstructionPresentation.frame(
            on: screen,
            preferredWindowFrame: attachToSystemSettings ? nil : sourceWindow?.frame
        )
    }

    private func startFollowingSystemSettings() {
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncSystemSettingsPosition()
            }
        }
        followTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        syncSystemSettingsPosition()
    }

    private func syncSystemSettingsPosition() {
        guard isFollowingSystemSettings, let panel = panelController?.currentPanel else { return }
        guard let frame = systemSettingsPanelFrame() else {
            panel.alphaValue = 0
            return
        }

        panel.setFrame(frame, display: true, animate: false)
        if panel.alphaValue == 0 {
            panel.alphaValue = 1
        }
        panel.orderFrontRegardless()
    }

    private func systemSettingsPanelFrame() -> NSRect? {
        guard
            let bounds = SystemSettingsWindowLocator.frontmostWindowBounds(),
            let primaryScreenFrame = NSScreen.screens.first?.frame
        else {
            return nil
        }

        let sourceFrame = PermissionFloatingInstructionPresentation.appKitFrame(
            fromQuartzBounds: bounds,
            mainScreenFrame: primaryScreenFrame
        )
        let screen = screen(containing: sourceFrame) ?? NSScreen.main
        guard let screen else { return nil }

        return PermissionFloatingInstructionPresentation.frame(
            in: screen.visibleFrame,
            preferredWindowFrame: sourceFrame
        )
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, frame) < intersectionArea(rhs.frame, frame)
        }
    }

    private func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

private enum SystemSettingsWindowLocator {
    private static let ownerNames = Set(["System Settings", "System Preferences"])

    static func frontmostWindowBounds() -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: [.optionOnScreenOnly, .excludeDesktopElements])
        guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard
                let ownerName = window[kCGWindowOwnerName as String] as? String,
                ownerNames.contains(ownerName),
                intValue(window[kCGWindowLayer as String]) == 0,
                let bounds = windowBounds(window[kCGWindowBounds as String])
            else {
                continue
            }

            if bounds.width > 120, bounds.height > 120 {
                return bounds
            }
        }

        return nil
    }

    private static func windowBounds(_ rawBounds: Any?) -> CGRect? {
        guard
            let dict = rawBounds as? [String: Any],
            let x = cgFloatValue(dict["X"]),
            let y = cgFloatValue(dict["Y"]),
            let width = cgFloatValue(dict["Width"]),
            let height = cgFloatValue(dict["Height"])
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func cgFloatValue(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }
}

private struct FloatingPermissionInstructionPanelView: View {
    let instruction: PermissionInstruction
    let appName: String
    let appURL: URL
    let openSettings: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: PermissionFloatingInstructionPresentation.arrowSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: MAYNControlMetrics.controlRadius, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(instruction.primaryText)
                        .font(.system(size: 14, weight: .semibold))
                    Text(instruction.secondaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MAYNButton("Open Settings", action: openSettings)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            DraggablePermissionAppTile(appName: appName, appURL: appURL)
        }
        .padding(14)
        .frame(
            width: PermissionFloatingInstructionPresentation.panelSize.width,
            height: PermissionFloatingInstructionPresentation.panelSize.height,
            alignment: .topLeading
        )
        .background(
            MAYNTheme.panel,
            in: RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MAYNControlMetrics.panelRadius, style: .continuous)
                .stroke(MAYNTheme.strongBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

struct PermissionsSettingsView: View {
    @State private var accessibilityStatus = PermissionStatusProvider.requiredPermission(isGranted: AXIsProcessTrusted())
    @State private var fullDiskAccessStatus = PermissionStatusProvider.currentFullDiskAccessStatus()
    @State private var microphoneStatus = PermissionStatusProvider.currentMicrophoneStatus()
    @State private var screenRecordingStatus = PermissionStatusProvider.currentScreenRecordingStatus()
    @State private var notificationsStatus = PermissionDisplayState.optional
    @State private var requestedInstructionTarget: PermissionInstructionTarget?
    @State private var highlightedPermission: PermissionInstructionTarget?
    @State private var hostWindow: NSWindow?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let appName = "Mac All You Need"

    var body: some View {
        MAYNSettingsPage(
            title: "Permissions",
            subtitle: "macOS access required for paste, voice, cookies, and alerts."
        ) {
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

            // Inline instruction strip only for permissions that don't support
            // the floating drag panel (currently just Notifications). Anything
            // with supportsAppDrag = true (Accessibility, Microphone, FDA)
            // gets the same floating drag-into-Settings panel.
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
        .onDisappear {
            FloatingPermissionInstructionPanelController.shared.dismiss()
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
        fullDiskAccessStatus = PermissionStatusProvider.currentFullDiskAccessStatus()
        screenRecordingStatus = PermissionStatusProvider.currentScreenRecordingStatus()
        advanceInstructionIfCurrentTargetIsGranted()
    }

    private func requestScreenRecording() {
        focusInstruction(.screenRecording)
        CGRequestScreenCaptureAccess()
        openPrivacyPane("Privacy_ScreenCapture")
    }

    private func requestAccessibility() {
        focusInstruction(.accessibility)
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        presentFloatingInstructionAndOpenSettings(for: .accessibility)
    }

    private func requestFullDiskAccess() {
        focusInstruction(.fullDiskAccess)
        presentFloatingInstructionAndOpenSettings(for: .fullDiskAccess)
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
            presentFloatingInstructionAndOpenSettings(for: .microphone)
        }
    }

    /// Single shared path for every permission that uses the drag-into-Settings
    /// floating panel. Mirrors what `requestFullDiskAccess` was doing inline
    /// and keeps the three call sites identical so they can never drift.
    private func presentFloatingInstructionAndOpenSettings(for target: PermissionInstructionTarget) {
        let instruction = target.instruction(appName: appName)
        FloatingPermissionInstructionPanelController.shared.show(
            instruction: instruction,
            appName: appName,
            appURL: Bundle.main.bundleURL,
            sourceWindow: hostWindow,
            attachToSystemSettings: true
        ) {
            openPrivacyPane(instruction.systemSettingsAnchor)
        }
        openPrivacyPane(instruction.systemSettingsAnchor)
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
