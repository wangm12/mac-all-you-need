import AppKit
import ApplicationServices
import Foundation

/// Options for `CGSHWCaptureWindowList` (matches DockDoor / alt-tab private API).
struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

/// Protocol seam over private CGS/SkyLight symbols loaded via dlopen.
protocol DockPreviewPrivateAPI {
    func captureWindowThumbnail(windowID: CGWindowID, scale: CGFloat) -> CGImage?
    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool
    func axWindowID(for element: AXUIElement) -> CGWindowID?
}

/// Live implementation using dlopen + SkyLight for window raising.
final class SystemDockPreviewPrivateAPI: DockPreviewPrivateAPI {
    typealias CGSConnectionID = UInt32
    typealias CGSHWCaptureWindowListFn = @convention(c) (
        CGSConnectionID,
        UnsafePointer<UInt32>,
        UInt32,
        UInt32
    ) -> Unmanaged<CFArray>?
    typealias CGSMainConnectionIDFn = @convention(c) () -> CGSConnectionID

    typealias SLPSSetFrontProcessWithOptionsFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> OSStatus
    private var captureWindowList: CGSHWCaptureWindowListFn?
    private var mainConnection: CGSMainConnectionIDFn?
    private var setFrontProcess: SLPSSetFrontProcessWithOptionsFn?

    typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private var getProcessForPID: GetProcessForPIDFn?

    typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> OSStatus
    private var axUIElementGetWindow: AXUIElementGetWindowFn?

    init() {
        if let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) {
            if let sym = dlsym(cgHandle, "CGSHWCaptureWindowList") {
                captureWindowList = unsafeBitCast(sym, to: CGSHWCaptureWindowListFn.self)
            }
            if let sym = dlsym(cgHandle, "CGSMainConnectionID") {
                mainConnection = unsafeBitCast(sym, to: CGSMainConnectionIDFn.self)
            }
        }
        if let slHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            if let sym = dlsym(slHandle, "_SLPSSetFrontProcessWithOptions") {
                setFrontProcess = unsafeBitCast(sym, to: SLPSSetFrontProcessWithOptionsFn.self)
            }
        }
        if let sym = dlsym(dlopen(nil, RTLD_LAZY), "GetProcessForPID") {
            getProcessForPID = unsafeBitCast(sym, to: GetProcessForPIDFn.self)
        }
        if let axSym = dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementGetWindow") {
            axUIElementGetWindow = unsafeBitCast(axSym, to: AXUIElementGetWindowFn.self)
        }
    }

    func axWindowID(for element: AXUIElement) -> CGWindowID? {
        guard let getter = axUIElementGetWindow else { return nil }
        var windowID = CGWindowID(0)
        guard getter(element, &windowID) == noErr else { return nil }
        return windowID == 0 ? nil : windowID
    }

    func captureWindowThumbnail(windowID: CGWindowID, scale: CGFloat) -> CGImage? {
        guard let connection = mainConnection?(), let capture = captureWindowList else { return nil }
        var wid = UInt32(windowID)
        var options: CGSWindowCaptureOptions = [.ignoreGlobalClipShape, .bestResolution, .fullSize]
        if scale <= 1 {
            options.insert(.nominalResolution)
        }
        guard let array = capture(connection, &wid, 1, options.rawValue)?.takeRetainedValue() as? [CGImage],
              let image = array.first
        else { return nil }

        let previewScale = max(1, Int(scale.rounded()))
        guard previewScale > 1 else { return image }
        return downscale(image, divisor: previewScale) ?? image
    }

    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let setFront = setFrontProcess, let resolvePID = getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard resolvePID(pid, &psn) == noErr else { return false }
        return setFront(&psn, 0x0000_0001) == noErr
    }

    private func downscale(_ image: CGImage, divisor: Int) -> CGImage? {
        let newWidth = image.width / divisor
        let newHeight = image.height / divisor
        guard newWidth > 0, newHeight > 0 else { return nil }
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
