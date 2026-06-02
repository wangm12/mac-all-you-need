import AppKit
import SwiftUI

enum DockPinnableViewType: String, CaseIterable {
    case media
    case calendar

    var displayName: String {
        switch self {
        case .media: "Media Controls"
        case .calendar: "Calendar"
        }
    }
}

struct DockPinnedWindowInfo {
    let appName: String
    let bundleIdentifier: String
    var type: DockPinnableViewType
    var isEmbedded: Bool
}

/// Standalone pinned widget panels (DockDoor `PinnedWindowDelegate` subset).
@MainActor
final class DockPinnedWindowController: NSObject {
    static let shared = DockPinnedWindowController()

    private var pinnedWindows: [String: (window: NSPanel, info: DockPinnedWindowInfo)] = [:]

    func isPinned(bundleIdentifier: String, type: DockPinnableViewType) -> Bool {
        pinnedWindows[key(bundleIdentifier, type)] != nil
    }

    func createPinnedWindow(
        appName: String,
        bundleIdentifier: String,
        type: DockPinnableViewType,
        isEmbedded: Bool,
        preservePosition: CGPoint? = nil
    ) {
        let windowKey = key(bundleIdentifier, type)
        guard pinnedWindows[windowKey] == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none

        let root = pinnedRootView(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            type: type,
            isEmbedded: isEmbedded,
            windowKey: windowKey
        )
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = preservePosition ?? CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.makeKeyAndOrderFront(nil)

        let info = DockPinnedWindowInfo(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            type: type,
            isEmbedded: isEmbedded
        )
        pinnedWindows[windowKey] = (panel, info)
    }

    func toggleMode(key: String) {
        guard let entry = pinnedWindows[key] else { return }
        let origin = entry.window.frame.origin
        let info = entry.info
        close(key: key)
        createPinnedWindow(
            appName: info.appName,
            bundleIdentifier: info.bundleIdentifier,
            type: info.type,
            isEmbedded: !info.isEmbedded,
            preservePosition: origin
        )
    }

    func close(key: String) {
        pinnedWindows[key]?.window.close()
        pinnedWindows.removeValue(forKey: key)
    }

    func closeAll() {
        for entry in pinnedWindows.values {
            entry.window.close()
        }
        pinnedWindows.removeAll()
    }

    private func key(_ bundleID: String, _ type: DockPinnableViewType) -> String {
        "\(bundleID)-\(type.rawValue)"
    }

    @ViewBuilder
    private func pinnedRootView(
        appName: String,
        bundleIdentifier: String,
        type: DockPinnableViewType,
        isEmbedded: Bool,
        windowKey: String
    ) -> some View {
        Group {
            switch type {
            case .media:
                DockMediaWidgetView(compact: isEmbedded)
            case .calendar:
                DockCalendarWidgetView()
            }
        }
        .dockPreviewPinnableDisabled(
            windowKey: windowKey,
            type: type,
            isEmbedded: isEmbedded
        )
        .padding(8)
    }
}
