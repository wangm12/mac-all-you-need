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
    private var startingStreams = Set<CGWindowID>()
    private var streamConfig: DockPreviewLiveCaptureConfiguration?
    private var keepAliveTask: Task<Void, Never>?
    private var cachedShareableContent: SCShareableContent?
    private var cachedShareableContentAt = Date.distantPast
    private let maxStreams = 4
    private let shareableContentCacheTTL: TimeInterval = 2

    func setActiveWindowIDs(
        _ ids: [CGWindowID],
        hub: DockHubSettings,
        context: DockPreviewLiveCaptureContext,
        enabled: Bool
    ) {
        keepAliveTask?.cancel()
        keepAliveTask = nil

        guard enabled, DockPreviewPermissionGate.screenRecordingGranted() else {
            stopAll()
            return
        }

        let config = DockPreviewLiveCaptureConfiguration.resolve(hub: hub, context: context)
        let configChanged = streamConfig != config
        streamConfig = config

        let limited = Array(ids.prefix(maxStreams))
        let keep = Set(limited)
        for id in streams.keys where !keep.contains(id) {
            stopStream(id)
        }
        for id in limited {
            if streams[id] == nil || configChanged {
                if streams[id] != nil {
                    stopStream(id)
                }
                Task { await startStream(windowID: id, config: config) }
            }
        }
    }

    func scheduleStopAfterKeepAlive(hub: DockHubSettings) {
        keepAliveTask?.cancel()
        let seconds = hub.advanced.livePreviewStreamKeepAlive > 0
            ? hub.advanced.livePreviewStreamKeepAlive
            : hub.previews.liveStreamKeepAliveSec
        guard seconds > 0 else {
            stopAll()
            return
        }
        keepAliveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stopAll()
        }
    }

    func stopAll() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        for id in streams.keys {
            stopStream(id)
        }
    }

    private var panelOpenCount = 0

    func panelOpened() {
        panelOpenCount += 1
    }

    func panelClosed() {
        panelOpenCount = max(0, panelOpenCount - 1)
        if panelOpenCount == 0 {
            scheduleStopAfterKeepAlive(hub: DockHubSettingsStore.load())
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

    private func shareableContent() async -> SCShareableContent? {
        let now = Date()
        if let cachedShareableContent,
           now.timeIntervalSince(cachedShareableContentAt) < shareableContentCacheTTL
        {
            return cachedShareableContent
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else {
            return nil
        }
        cachedShareableContent = content
        cachedShareableContentAt = now
        return content
    }

    private func startStream(windowID: CGWindowID, config: DockPreviewLiveCaptureConfiguration) async {
        guard streams[windowID] == nil, startingStreams.insert(windowID).inserted else { return }
        defer { startingStreams.remove(windowID) }
        guard let content = await shareableContent(),
              let scWindow = content.windows.first(where: { $0.windowID == windowID })
        else { return }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.streamWidth
        streamConfig.height = config.streamHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.frameRate))
        streamConfig.queueDepth = 2

        let minPublishInterval = 1.0 / Double(max(config.frameRate, 1))
        let handler = StreamOutputHandler(
            windowID: windowID,
            minPublishInterval: minPublishInterval
        ) { [weak self] id, image in
            Task { @MainActor in self?.frames[id] = image }
        }
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
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
    let minPublishInterval: TimeInterval
    let onFrame: (CGWindowID, CGImage) -> Void
    private var lastPublish = Date.distantPast
    private let publishLock = NSLock()

    init(
        windowID: CGWindowID,
        minPublishInterval: TimeInterval,
        onFrame: @escaping (CGWindowID, CGImage) -> Void
    ) {
        self.windowID = windowID
        self.minPublishInterval = minPublishInterval
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
        publishLock.lock()
        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= minPublishInterval else {
            publishLock.unlock()
            return
        }
        lastPublish = now
        publishLock.unlock()

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        guard let cgImage else { return }
        onFrame(windowID, cgImage)
    }
}
