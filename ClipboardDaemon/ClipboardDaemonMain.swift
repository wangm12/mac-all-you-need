import Core
import Foundation

@main
struct ClipboardDaemonMain {
    static func main() {
        let fallback = AppGroup.isUsingFallbackContainer() ? " (FALLBACK - entitlement missing)" : ""
        NSLog("ClipboardDaemon started, container: \(AppGroup.containerURL().path)\(fallback)")
        RunLoop.main.run()
    }
}
