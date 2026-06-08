import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

/// One-shot ScreenCaptureKit frame for seeding disk thumbnails when live preview is off.
enum DockPreviewLiveSnapshotCapturer {
    fileprivate static let snapshotFrameRate = 5

    static func capture(
        windowID: CGWindowID,
        hub: DockHubSettings,
        timeout: TimeInterval = 2.5
    ) async -> CGImage? {
        guard DockPreviewPermissionGate.screenRecordingGranted() else { return nil }
        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: .dockHover)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ),
            let scWindow = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }

        return await withTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                await SingleWindowLiveSnapshotSession().capture(window: scWindow, config: config)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let image = await group.next() ?? nil
            group.cancelAll()
            return image
        }
    }
}

private final class SingleWindowLiveSnapshotSession: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var finished = false
    private let finishLock = NSLock()

    func capture(window: SCWindow, config: DockPreviewLiveCaptureConfiguration) async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let streamConfig = SCStreamConfiguration()
            streamConfig.width = config.streamWidth
            streamConfig.height = config.streamHeight
            streamConfig.minimumFrameInterval = CMTime(
                value: 1,
                timescale: 5
            )
            streamConfig.queueDepth = 1
            let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
            self.stream = stream
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))
                Task {
                    do {
                        try await stream.startCapture()
                    } catch {
                        self.finish(with: nil)
                    }
                }
            } catch {
                self.finish(with: nil)
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        finish(with: cgImage)
    }

    private func finish(with image: CGImage?) {
        finishLock.lock()
        defer { finishLock.unlock() }
        guard !finished else { return }
        finished = true
        let stream = self.stream
        self.stream = nil
        let continuation = self.continuation
        self.continuation = nil
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        continuation?.resume(returning: image)
    }
}
