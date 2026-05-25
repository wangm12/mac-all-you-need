import AppKit
import Core
import SwiftUI

@main
enum MacAllYouNeedMain {
    @MainActor private static var appDelegate: MacAllYouNeedApplicationDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = MacAllYouNeedApplicationDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class MacAllYouNeedApplicationDelegate: NSObject, NSApplicationDelegate {
    var handleReopen: (() -> Void)?
    private var controller: AppController?
    #if DEBUG
    private var auditController: UIAuditAppController?
    #endif
    private var statusItemController: AppStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        #if DEBUG
        if UIAuditLaunchMode.isEnabled() {
            do {
                let auditController = try UIAuditAppController.make()
                self.auditController = auditController
                auditController.show()
            } catch {
                presentStartupFailure(error)
                NSApp.terminate(nil)
            }
            return
        }
        #endif

        guard !MAYNIsRunningUnderXCTest() else { return }
        AppChromeVisibilitySettings.applyStoredDockIconVisibility()

        do {
            let controller = try AppController()
            self.controller = controller
            statusItemController = AppStatusItemController(controller: controller)
            statusItemController?.applyVisibilityFromDefaults()
        } catch {
            presentStartupFailure(error)
            NSApp.terminate(nil)
            return
        }

        routeStartupSurface()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        #if DEBUG
        if let auditController {
            auditController.show()
            return true
        }
        #endif
        // Non-activating auxiliary panels may not count toward AppKit's
        // visible-window flag, so check app-owned auxiliary surfaces too.
        guard ApplicationReopenPolicy.shouldRouteStartupSurface(
            hasVisibleWindows: flag,
            hasVisibleAuxiliarySurface: controller?.hasVisibleAuxiliarySurface == true
        ) else { return true }
        routeStartupSurface()
        return true
    }

    private func routeStartupSurface() {
        if let handleReopen {
            handleReopen()
        } else {
            controller?.showStartupSurface()
        }
    }

    func makeMainMenuForTesting() -> NSMenu {
        makeMainMenu()
    }

    private func installMainMenu() {
        NSApp.mainMenu = makeMainMenu()
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: "About Mac All You Need",
            action: #selector(showAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Mac All You Need",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        // File menu — gives Cmd+W a target. LSUIElement=YES keeps the app alive
        // when the main window closes, so Cmd+W just hides the window.
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let closeWindowItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        // target = nil routes through the first responder chain so the active
        // window receives performClose: regardless of which window is key.
        closeWindowItem.target = nil
        fileMenu.addItem(closeWindowItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        addEditMenuItem("Undo", action: Selector(("undo:")), keyEquivalent: "z", to: editMenu)
        addEditMenuItem("Redo", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        addEditMenuItem("Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x", to: editMenu)
        addEditMenuItem("Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c", to: editMenu)
        addEditMenuItem("Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v", to: editMenu)
        addEditMenuItem("Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "", to: editMenu)
        editMenu.addItem(.separator())
        addEditMenuItem("Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a", to: editMenu)

        return mainMenu
    }

    private func addEditMenuItem(
        _ title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = .command,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifiers
        item.target = nil
        menu.addItem(item)
    }

    @objc private func showAboutPanel(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @objc private func showSettings(_ sender: Any?) {
        controller?.showMainWindow(destination: .settings)
    }

    private func presentStartupFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Mac All You Need could not start"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}

enum ApplicationReopenPolicy {
    static func shouldRouteStartupSurface(
        hasVisibleWindows: Bool,
        hasVisibleAuxiliarySurface: Bool
    ) -> Bool {
        !hasVisibleWindows && !hasVisibleAuxiliarySurface
    }
}

enum MainMenuCommandPresentation {
    static let replacesAppSettingsCommand = false
    static let usesSwiftUISettingsScene = false
    static let usesSwiftUIAppLifecycle = false
    static let usesSwiftUIMenuBarExtraScene = false
    static let usesAppKitStatusItem = true
    static let usesManualAppKitDelegateBootstrap = true
}

@MainActor
private final class AppStatusItemController: NSObject, NSPopoverDelegate {
    private let controller: AppController
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var defaultsObserver: NSObjectProtocol?
    private var dismissObserver: NSObjectProtocol?
    private var reanchorObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var popoverWindowObservers: [NSObjectProtocol] = []
    private var reanchorWorkItem: DispatchWorkItem?

    init(controller: AppController) {
        self.controller = controller
        super.init()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyVisibilityFromDefaults() }
        }
        dismissObserver = NotificationCenter.default.addObserver(
            forName: .menuBarPopoverDismissRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        reanchorObserver = NotificationCenter.default.addObserver(
            forName: .menuBarPopoverReanchorRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePopoverReanchor() }
        }
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePopoverReanchor() }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let dismissObserver {
            NotificationCenter.default.removeObserver(dismissObserver)
        }
        if let reanchorObserver {
            NotificationCenter.default.removeObserver(reanchorObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        reanchorWorkItem?.cancel()
    }

    func applyVisibilityFromDefaults() {
        setVisible(AppChromeVisibilitySettings.menuBarIconVisible())
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            ensureStatusItem()
        } else {
            closePopover()
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 24)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Mac All You Need"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        controller.clipboardDock.hide()
        PreviewPanel.dismiss()
        ClipboardSystemQuickLookCoordinator.shared.dismiss()

        let popover = popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        scheduleFollowUpScreenAlignment()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 500, height: 600)
        popover.contentViewController = NSHostingController(rootView: AppMenuBarContent(controller: controller))
        popover.delegate = self
        return popover
    }

    private func closePopover() {
        reanchorWorkItem?.cancel()
        tearDownPopoverWindowObservers()
        popover?.performClose(nil)
    }

    private func tearDownPopoverWindowObservers() {
        for observer in popoverWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        popoverWindowObservers.removeAll()
    }

    private func installPopoverWindowObservers(for window: NSWindow) {
        tearDownPopoverWindowObservers()
        let center = NotificationCenter.default
        let screenChange = center.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.schedulePopoverReanchor() }
        }
        popoverWindowObservers.append(screenChange)
    }

    /// Coalesce tab switches and layout so we re-anchor after SwiftUI settles.
    private func schedulePopoverReanchor() {
        reanchorWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.repositionPopoverIfShown()
        }
        reanchorWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Re-show relative to the status item when the popover window is not
    /// already substantially on the menu-bar screen.
    ///
    /// Calling `NSPopover.show` while already visible during SwiftUI tab churn
    /// (Clipboard / Downloads) can make AppKit re-home the window on the wrong
    /// display; only invoke `show` when overlap with the status item screen is low.
    private func repositionPopoverIfShown() {
        guard let popover, popover.isShown, let button = statusItem?.button else { return }
        if let popWindow = popover.contentViewController?.view.window,
           Self.popoverWindowHasSufficientOverlapWithStatusItemScreen(button: button, popWindow: popWindow) {
            popWindow.makeKey()
            scheduleFollowUpScreenAlignment()
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        scheduleFollowUpScreenAlignment()
    }

    private func scheduleFollowUpScreenAlignment() {
        DispatchQueue.main.async { [weak self] in
            self?.verifyAndCorrectPopoverScreenIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.verifyAndCorrectPopoverScreenIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.verifyAndCorrectPopoverScreenIfNeeded()
        }
    }

    private func verifyAndCorrectPopoverScreenIfNeeded() {
        guard let popover, popover.isShown,
              let button = statusItem?.button as NSButton?,
              let popWindow = popover.contentViewController?.view.window else { return }

        if Self.popoverWindowHasSufficientOverlapWithStatusItemScreen(button: button, popWindow: popWindow) {
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popWindow.makeKey()
    }

    /// Resolve the logical display hosting the status item (menu bar may sit
    /// above `visibleFrame`; use `NSScreen.frame` / `NSMouseInRect`).
    private static func screenForStatusItemButton(_ button: NSButton) -> NSScreen? {
        guard let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectInScreen = window.convertToScreen(rectInWindow)
        let anchor = NSPoint(x: rectInScreen.midX, y: rectInScreen.midY)
        return NSScreen.screens.first { NSMouseInRect(anchor, $0.frame, false) }
    }

    /// Fraction of the popover window area that lies inside `screenFrame`
    /// (global display coordinates).
    private static func overlapFraction(of windowFrame: NSRect, with screenFrame: NSRect) -> CGFloat {
        let inter = windowFrame.intersection(screenFrame)
        guard inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let winArea = windowFrame.width * windowFrame.height
        guard winArea > 0 else { return 0 }
        return interArea / winArea
    }

    /// True when enough of the popover sits on the same logical display as the
    /// status item — avoids mis-detecting during layout when the window center
    /// briefly sits over an adjacent screen while the anchor is still correct.
    private static func popoverWindowHasSufficientOverlapWithStatusItemScreen(
        button: NSButton,
        popWindow: NSWindow,
        minimumFraction: CGFloat = 0.2
    ) -> Bool {
        guard let targetScreen = screenForStatusItemButton(button) else {
            // Cannot resolve menu-bar screen; do not fight AppKit.
            return true
        }
        return overlapFraction(of: popWindow.frame, with: targetScreen.frame) >= minimumFraction
    }

    /// Without `.fullScreenAuxiliary` the popover stays on the desktop Space,
    /// so clicks from a full-screen app appear to do nothing.
    ///
    /// Omit `.canJoinAllSpaces`: it lets AppKit re-home the popover across
    /// displays when content updates (tabs, SwiftUI layout).
    private func applyCommandCenterPopoverSpaceBehavior(to popover: NSPopover) {
        if let window = popover.contentViewController?.view.window {
            window.collectionBehavior.formUnion(.fullScreenAuxiliary)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        applyCommandCenterPopoverSpaceBehavior(to: popover)
    }

    func popoverDidShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else { return }
        applyCommandCenterPopoverSpaceBehavior(to: popover)
        if let window = popover.contentViewController?.view.window {
            installPopoverWindowObservers(for: window)
        }
        scheduleFollowUpScreenAlignment()
    }

    func popoverWillClose(_ notification: Notification) {
        tearDownPopoverWindowObservers()
        reanchorWorkItem?.cancel()
    }
}

private func MAYNIsRunningUnderXCTest() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["XCTestBundlePath"] != nil
        || environment["XCTestConfigurationFilePath"] != nil
        || environment["XCTestSessionIdentifier"] != nil
}

extension Notification.Name {
    static let menuBarPopoverDismissRequested = Notification.Name("menuBarPopoverDismissRequested")
    static let menuBarPopoverReanchorRequested = Notification.Name("menuBarPopoverReanchorRequested")
}
