import AppKit
import Foundation

/// Protocol seam over private CGS/SkyLight symbols loaded via dlopen.
/// The live `SystemDockPreviewPrivateAPI` calls the real private API;
/// tests use a fake/stub.
protocol DockPreviewPrivateAPI {
    func captureWindowThumbnail(windowID: CGWindowID, scale: CGFloat) -> CGImage?
    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool
}

/// Live implementation using dlopen + SkyLight for window raising.
final class SystemDockPreviewPrivateAPI: DockPreviewPrivateAPI {
    // MARK: - CGS thumbnail capture

    typealias CGSConnectionID = UInt32
    typealias CGSHWCaptureWindowListFn = @convention(c) (CGSConnectionID, UnsafePointer<CGWindowID>, Int32, CGFloat, Int32) -> CGImage?
    typealias CGSDefaultConnectionForThreadFn = @convention(c) () -> CGSConnectionID

    private var captureWindowList: CGSHWCaptureWindowListFn?
    private var defaultConnection: CGSDefaultConnectionForThreadFn?

    // MARK: - SkyLight raise

    typealias SLPSSetFrontProcessWithOptionsFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> OSStatus
    private var setFrontProcess: SLPSSetFrontProcessWithOptionsFn?

    // GetProcessForPID is unavailable to Swift directly (deprecated headers), so
    // resolve it dynamically from ApplicationServices.
    typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private var getProcessForPID: GetProcessForPIDFn?

    init() {
        // Load CoreGraphics for CGS
        if let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) {
            if let sym = dlsym(cgHandle, "CGSHWCaptureWindowList") {
                captureWindowList = unsafeBitCast(sym, to: CGSHWCaptureWindowListFn.self)
            }
            if let sym = dlsym(cgHandle, "CGSDefaultConnectionForThread") {
                defaultConnection = unsafeBitCast(sym, to: CGSDefaultConnectionForThreadFn.self)
            }
        }
        // Load SkyLight for window raising
        if let slHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            if let sym = dlsym(slHandle, "_SLPSSetFrontProcessWithOptions") {
                setFrontProcess = unsafeBitCast(sym, to: SLPSSetFrontProcessWithOptionsFn.self)
            }
        }
        // Resolve the deprecated-but-present Process Manager symbol dynamically.
        if let sym = dlsym(dlopen(nil, RTLD_LAZY), "GetProcessForPID") {
            getProcessForPID = unsafeBitCast(sym, to: GetProcessForPIDFn.self)
        }
    }

    func captureWindowThumbnail(windowID: CGWindowID, scale: CGFloat) -> CGImage? {
        guard let conn = defaultConnection?(), let capture = captureWindowList else { return nil }
        var wid = windowID
        return capture(conn, &wid, 1, scale, 0)
    }

    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        // Bring the owning process to front via SkyLight.
        guard let setFront = setFrontProcess, let resolvePID = getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard resolvePID(pid, &psn) == noErr else { return false }
        return setFront(&psn, 0x0000_0001) == noErr
    }
}
