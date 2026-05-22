@testable import MacAllYouNeed
import AppKit
import XCTest

final class MacAllYouNeedApplicationDelegateTests: XCTestCase {
    func testAppDoesNotOverrideNativeSettingsMenuCommand() {
        XCTAssertFalse(MainMenuCommandPresentation.replacesAppSettingsCommand)
        XCTAssertFalse(MainMenuCommandPresentation.usesSwiftUISettingsScene)
        XCTAssertFalse(MainMenuCommandPresentation.usesSwiftUIAppLifecycle)
        XCTAssertFalse(MainMenuCommandPresentation.usesSwiftUIMenuBarExtraScene)
        XCTAssertTrue(MainMenuCommandPresentation.usesAppKitStatusItem)
        XCTAssertTrue(MainMenuCommandPresentation.usesManualAppKitDelegateBootstrap)
    }

    @MainActor
    func testMainMenuInstallsStandardEditCommandsForTextFieldEditing() {
        let delegate = MacAllYouNeedApplicationDelegate()
        let menu = delegate.makeMainMenuForTesting()
        let editMenu = menu.item(withTitle: "Edit")?.submenu

        XCTAssertNotNil(editMenu)
        XCTAssertEqual(editMenu?.item(withTitle: "Cut")?.action, #selector(NSText.cut(_:)))
        XCTAssertEqual(editMenu?.item(withTitle: "Copy")?.action, #selector(NSText.copy(_:)))
        XCTAssertEqual(editMenu?.item(withTitle: "Paste")?.action, #selector(NSText.paste(_:)))
        XCTAssertEqual(editMenu?.item(withTitle: "Select All")?.action, #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(editMenu?.item(withTitle: "Select All")?.keyEquivalent, "a")
        XCTAssertNil(editMenu?.item(withTitle: "Select All")?.target)
    }

    @MainActor
    func testReopenInvokesStartupSurfaceHandlerAndLetsSystemContinue() {
        let delegate = MacAllYouNeedApplicationDelegate()
        var didHandleReopen = false
        delegate.handleReopen = { didHandleReopen = true }

        let shouldContinue = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(didHandleReopen)
        XCTAssertTrue(shouldContinue)
    }

    func testReopenDoesNotInvokeStartupSurfaceHandlerWhenAuxiliaryPanelIsVisible() {
        XCTAssertFalse(ApplicationReopenPolicy.shouldRouteStartupSurface(
            hasVisibleWindows: false,
            hasVisibleAuxiliarySurface: true
        ))
    }
}
