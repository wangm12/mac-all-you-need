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
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        if let dismissObserver {
            NotificationCenter.default.removeObserver(dismissObserver)
        }
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
        popover?.performClose(nil)
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
}
