import Core
import Foundation
import Platform

@main
struct ClipboardDaemonMain {
    static func main() throws {
        let container = try DaemonContainer()
        let server = ClipboardXPCServer(container: container)
        // Set the capture callback before potential restart so the worker host can
        // pass it to observer.start(callback:).
        container.workerHost.onPasteboardChange = { change in
            if container.isCaptureSuspended() { return }
            for item in change.historyCaptureItems {
                do {
                    try container.persist(
                        item: item,
                        source: change.frontmostAppBundleID,
                        pasteboardTypes: change.pasteboardTypes
                    )
                } catch {
                    container.log.error("persist failed: \(error.localizedDescription)")
                }
            }
            server.notifyInvalidated()
        }
        // If .clipboard was already enabled during DaemonContainer.init(), the pasteboard
        // observer started without a callback. Restart it now with the callback wired.
        container.workerHost.restartClipboardObserverIfRunning()
        NSLog("ClipboardDaemon ready, container=\(AppGroup.containerURL().path)")
        RunLoop.main.run()
    }
}
