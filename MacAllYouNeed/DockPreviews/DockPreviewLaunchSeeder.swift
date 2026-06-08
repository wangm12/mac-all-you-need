import AppKit
import Foundation

enum DockPreviewLaunchSeeder {
    /// Cold-start warm-up: CGS thumbnails, then one-shot live frames when live preview is off and disk is empty.
    static func seed(pipeline: DockPreviewWindowCapturePipeline) {
        guard AXIsProcessTrusted() else { return }
        Task { @MainActor in
            pipeline.resetLiveSnapshotSeedBudget()
            await pipeline.warmAllRunningApps()
        }
    }
}
