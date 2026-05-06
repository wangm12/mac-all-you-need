import Foundation
import Core

@main
struct ClipboardDaemonMain {
    static func main() {
        NSLog("ClipboardDaemon started, Core \(CoreVersion.value)")
        RunLoop.main.run()
    }
}
