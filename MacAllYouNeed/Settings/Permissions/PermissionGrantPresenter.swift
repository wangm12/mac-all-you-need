import AppKit
import AVFoundation
import CoreGraphics
import FeatureCore
import SwiftUI
import UI

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
                primaryText: "Drag \(appName) into Screen Recording.",
                secondaryText: "Dock Previews needs Screen Recording to capture live window thumbnails. If \(appName) already appears in the list, turn on its switch.",
                systemSettingsAnchor: "Privacy_ScreenCapture",
                symbol: "rectangle.on.rectangle.angled",
                supportsAppDrag: true
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

    static func from(_ permission: Permission) -> PermissionInstructionTarget? {
        switch permission {
        case .accessibility: return .accessibility
        case .fullDiskAccess: return .fullDiskAccess
        case .microphone: return .microphone
        case .notifications: return .notifications
        case .screenRecording: return .screenRecording
        case .reminders: return nil
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

struct InlinePermissionInstruction: Equatable {
    let primaryText: String
    let secondaryText: String
    let symbol: String
    let dragAppURL: URL?
}

enum PermissionGrantPresenter {
    static func inlineInstruction(for permission: Permission, appName: String = "Mac All You Need") -> InlinePermissionInstruction {
        if let target = PermissionInstructionTarget.from(permission) {
            let instruction = target.instruction(appName: appName)
            return InlinePermissionInstruction(
                primaryText: instruction.primaryText,
                secondaryText: instruction.secondaryText,
                symbol: instruction.symbol,
                dragAppURL: instruction.supportsAppDrag ? Bundle.main.bundleURL : nil
            )
        }

        switch permission {
        case .reminders:
            return InlinePermissionInstruction(
                primaryText: "Allow Reminders access for \(appName).",
                secondaryText: "Voice Reminders saves spoken tasks to Apple Reminders.",
                symbol: "checklist",
                dragAppURL: nil
            )
        default:
            return InlinePermissionInstruction(
                primaryText: "Open System Settings for \(appName).",
                secondaryText: "",
                symbol: "gearshape",
                dragAppURL: nil
            )
        }
    }

    static func shouldPresentFloatingPanel(for permission: Permission) -> Bool {
        switch permission {
        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            return status != .notDetermined
        default:
            guard let target = PermissionInstructionTarget.from(permission) else { return false }
            return PermissionFloatingInstructionPresentation.shouldFloat(target.instruction(appName: "Mac All You Need"))
        }
    }

    /// Presents the floating drag panel (when applicable) and opens System Settings.
    @MainActor
    static func presentGrant(
        for permission: Permission,
        appName: String = "Mac All You Need",
        sourceWindow: NSWindow?,
        onOpenSettings: @escaping () -> Void
    ) {
        if permission == .microphone,
           AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            return
        }

        if let target = PermissionInstructionTarget.from(permission) {
            presentFloatingInstruction(for: target, appName: appName, sourceWindow: sourceWindow, onOpenSettings: onOpenSettings)
            return
        }

        onOpenSettings()
    }

    @MainActor
    static func presentFloatingInstruction(
        for target: PermissionInstructionTarget,
        appName: String = "Mac All You Need",
        sourceWindow: NSWindow?,
        onOpenSettings: @escaping () -> Void
    ) {
        let instruction = target.instruction(appName: appName)
        guard PermissionFloatingInstructionPresentation.shouldFloat(instruction) else {
            onOpenSettings()
            return
        }

        FloatingPermissionInstructionPanelController.shared.show(
            instruction: instruction,
            appName: appName,
            appURL: Bundle.main.bundleURL,
            sourceWindow: sourceWindow,
            attachToSystemSettings: true,
            openSettings: onOpenSettings
        )
        onOpenSettings()
    }

    @MainActor
    static func dismissFloatingPanel() {
        FloatingPermissionInstructionPanelController.shared.dismiss()
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
