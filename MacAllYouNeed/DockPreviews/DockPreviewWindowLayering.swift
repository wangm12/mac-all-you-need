import AppKit

/// Window layering for dock hover previews — below dock context menus, above normal windows.
enum DockPreviewWindowLayering {
  static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
  static let collectionBehavior = FloatingHUDWindowLayering.collectionBehavior

  static func configure(_ panel: NSPanel) {
    panel.level = windowLevel
    panel.collectionBehavior = collectionBehavior
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isFloatingPanel = true
  }

  static func orderFront(_ panel: NSPanel) {
    panel.level = windowLevel
    panel.orderFrontRegardless()
  }
}
