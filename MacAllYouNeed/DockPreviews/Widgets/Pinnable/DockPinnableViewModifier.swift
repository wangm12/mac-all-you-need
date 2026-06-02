import SwiftUI

struct DockPinnableViewModifier: ViewModifier {
    let appName: String
    let bundleIdentifier: String
    let type: DockPinnableViewType
    let enablePinning: Bool
    let onPin: () -> Void

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if enablePinning {
                    let pinned = DockPinnedWindowController.shared.isPinned(
                        bundleIdentifier: bundleIdentifier,
                        type: type
                    )
                    if pinned {
                        Button("Unpin from Screen") {
                            let key = "\(bundleIdentifier)-\(type.rawValue)"
                            DockPinnedWindowController.shared.close(key: key)
                        }
                    } else {
                        Section("Pin to Screen") {
                            Button {
                                DockPinnedWindowController.shared.createPinnedWindow(
                                    appName: appName,
                                    bundleIdentifier: bundleIdentifier,
                                    type: type,
                                    isEmbedded: false
                                )
                                onPin()
                            } label: {
                                Label("Full Mode", systemImage: "rectangle.expand.vertical")
                            }
                            Button {
                                DockPinnedWindowController.shared.createPinnedWindow(
                                    appName: appName,
                                    bundleIdentifier: bundleIdentifier,
                                    type: type,
                                    isEmbedded: true
                                )
                                onPin()
                            } label: {
                                Label("Compact Mode", systemImage: "rectangle.compress.vertical")
                            }
                        }
                    }
                }
            }
    }
}

struct DockPinnableDisabledModifier: ViewModifier {
    let windowKey: String
    let type: DockPinnableViewType
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                DockPinnedWindowController.shared.toggleMode(key: windowKey)
            } label: {
                Label(
                    isEmbedded ? "Switch to Full" : "Switch to Compact",
                    systemImage: isEmbedded ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
                )
            }
            Divider()
            Button(role: .destructive) {
                DockPinnedWindowController.shared.close(key: windowKey)
            } label: {
                Label("Close", systemImage: "xmark.circle")
            }
        }
    }
}

extension View {
    func dockPreviewPinnable(
        appName: String,
        bundleIdentifier: String,
        type: DockPinnableViewType,
        enablePinning: Bool,
        onPin: @escaping () -> Void = {}
    ) -> some View {
        modifier(DockPinnableViewModifier(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            type: type,
            enablePinning: enablePinning,
            onPin: onPin
        ))
    }

    func dockPreviewPinnableDisabled(
        windowKey: String,
        type: DockPinnableViewType,
        isEmbedded: Bool
    ) -> some View {
        modifier(DockPinnableDisabledModifier(windowKey: windowKey, type: type, isEmbedded: isEmbedded))
    }
}
