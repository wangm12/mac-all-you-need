import AppKit
import CoreMedia
import Foundation
import ScreenCaptureKit
import VideoToolbox

@MainActor
final class DockPreviewLiveCaptureManager: ObservableObject {
    static let shared = DockPreviewLiveCaptureManager()

    @Published private(set) var frames: [CGWindowID: CGImage] = [:]
    private var outputs: [CGWindowID: StreamOutputHandler] = [:]
    private var streams: [CGWindowID: SCStream] = [:]
    private let maxStreams = 4

    func setActiveWindowIDs(_ ids: [CGWindowID], settings: DockPreviewSettings) {
        guard settings.enableLivePreview, DockPreviewPermissionGate.screenRecordingGranted() else {
            stopAll()
            return
        }
        let limited = Array(ids.prefix(maxStreams))
        let keep = Set(limited)
        for id in streams.keys where !keep.contains(id) {
            stopStream(id)
        }
        for id in limited where streams[id] == nil {
            Task { await startStream(windowID: id, settings: settings) }
        }
    }

    func stopAll() {
        for id in streams.keys {
            stopStream(id)
        }
    }

    private func stopStream(_ windowID: CGWindowID) {
        if let stream = streams[windowID] {
            Task { try? await stream.stopCapture() }
        }
        streams[windowID] = nil
        outputs[windowID] = nil
        frames[windowID] = nil
    }

    private func startStream(windowID: CGWindowID, settings: DockPreviewSettings) async {
        guard streams[windowID] == nil else { return }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let scWindow = content.windows.first(where: { $0.windowID == windowID })
        else { return }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = settings.livePreviewQuality == .low ? 240 : 360
        config.height = settings.livePreviewQuality == .low ? 150 : 225
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.livePreviewFrameRate.rawValue))
        config.queueDepth = 2

        let handler = StreamOutputHandler(windowID: windowID) { [weak self] id, image in
            Task { @MainActor in self?.frames[id] = image }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        do {
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            try await stream.startCapture()
            streams[windowID] = stream
            outputs[windowID] = handler
        } catch {
            try? await stream.stopCapture()
        }
    }
}

private final class StreamOutputHandler: NSObject, SCStreamOutput {
    let windowID: CGWindowID
    let onFrame: (CGWindowID, CGImage) -> Void

    init(windowID: CGWindowID, onFrame: @escaping (CGWindowID, CGImage) -> Void) {
        self.windowID = windowID
        self.onFrame = onFrame
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
        guard let cgImage else { return }
        onFrame(windowID, cgImage)
    }
}
