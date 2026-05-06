import Core
import Foundation
import Platform

@main
struct ClipboardDaemonMain {
    static func main() throws {
        let container = try DaemonContainer()
        let server = ClipboardXPCServer(container: container)
        container.observer.start { change in
            for item in change.items {
                do { try container.persist(item: item, source: change.frontmostAppBundleID) }
                catch { container.log.error("persist failed: \(error.localizedDescription)") }
            }
            server.notifyInvalidated()
        }
        NSLog("ClipboardDaemon ready, container=\(AppGroup.containerURL().path)")
        RunLoop.main.run()
    }
}
