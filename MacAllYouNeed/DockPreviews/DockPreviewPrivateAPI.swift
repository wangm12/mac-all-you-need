import AppKit
import ApplicationServices
import Foundation
import Platform

typealias CGSWindowCaptureOptions = Platform.CGSWindowCaptureOptions

/// Protocol seam over private CGS/SkyLight symbols loaded via dlopen.
protocol DockPreviewPrivateAPI {
    func captureWindowThumbnail(
        windowID: CGWindowID,
        scale: CGFloat,
        quality: DockWindowImageCaptureQuality
    ) -> CGImage?
    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool
    func axWindowID(for element: AXUIElement) -> CGWindowID?
    func axElementWithRemoteToken(_ token: Data) -> AXUIElement?
}

/// Live implementation delegating to shared `WindowServerPrivateAPI`.
final class SystemDockPreviewPrivateAPI: DockPreviewPrivateAPI {
    private let api: any WindowServerPrivateAPI

    init(api: any WindowServerPrivateAPI = SystemWindowServerPrivateAPI.shared) {
        self.api = api
    }

    func axElementWithRemoteToken(_ token: Data) -> AXUIElement? {
        api.axElementWithRemoteToken(token)
    }

    func axWindowID(for element: AXUIElement) -> CGWindowID? {
        api.axWindowID(for: element)
    }

    func captureWindowThumbnail(
        windowID: CGWindowID,
        scale: CGFloat,
        quality: DockWindowImageCaptureQuality
    ) -> CGImage? {
        let mapped: WindowImageCaptureQuality = quality == .best ? .best : .nominal
        return api.captureWindowThumbnail(windowID: windowID, scale: scale, quality: mapped)
    }

    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        api.raiseWindow(windowID: windowID, pid: pid)
    }
}
