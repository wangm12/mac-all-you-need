import Core
import Foundation

@MainActor
final class DockPasteCoordinator {
    private let xpc: any ClipboardXPCInteracting

    init(xpc: any ClipboardXPCInteracting) {
        self.xpc = xpc
    }

    func paste(itemID: String, plainText: Bool, dismissWindow: @MainActor () -> Void) async {
        dismissWindow()
        try? await Task.sleep(nanoseconds: 80_000_000)
        _ = await xpc.paste(itemID: itemID, plainText: plainText)
    }
}
