import Foundation
import Platform

@MainActor
enum CursorPaster {
    struct Result {
        let accessibilityTrusted: Bool
        let didPostPasteEvent: Bool
    }

    static func paste(_ text: String) async -> Result {
        let outcome = await PasteInjector.pasteWithRestore(text, restoreOnManualPasteRequired: false)
        return Result(
            accessibilityTrusted: outcome.result == .injected,
            didPostPasteEvent: outcome.result == .injected
        )
    }
}
