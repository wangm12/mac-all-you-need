import Core
import FeatureCore
import Foundation
import Platform

@main
struct DownloadDaemonMain {
    static func main() throws {
        let locator = try LegacyBundleLocator.make()
        let coordinator = try DownloadCoordinator(binaries: locator)
        NSLog("DownloadDaemon ready, container=\(AppGroup.containerURL().path)")
        Task { @MainActor in
            await coordinator.startDispatchServer()
        }
        RunLoop.main.run()
    }
}
