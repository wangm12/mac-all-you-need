import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Options for `CGSHWCaptureWindowList` (DockDoor / alt-tab private API).
public struct CGSWindowCaptureOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    public static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    public static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    public static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

public enum WindowImageCaptureQuality: String, Sendable {
    case nominal
    case best
}

/// Protocol seam over private CGS/SkyLight symbols loaded via dlopen.
public protocol WindowServerPrivateAPI: Sendable {
    var isCaptureAvailable: Bool { get }
    var isRaiseAvailable: Bool { get }
    var isSpaceAPIAvailable: Bool { get }
    func captureWindowThumbnail(windowID: CGWindowID, scale: CGFloat, quality: WindowImageCaptureQuality) -> CGImage?
    func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool
    func axWindowID(for element: AXUIElement) -> CGWindowID?
    func axElementWithRemoteToken(_ token: Data) -> AXUIElement?
    func managedDisplaySpaces() -> [[String: AnyObject]]?
    func copySpaces(forWindowIDs windowIDs: [CGWindowID]) -> [CGWindowID: [Int]]?
    func setSymbolicHotKeyEnabled(_ hotKey: UInt32, enabled: Bool) -> Bool
    func moveWindowsToManagedSpace(_ windowIDs: [CGWindowID], spaceID: UInt64) -> Bool
}

/// Live implementation using dlopen + SkyLight for window raising and CGS capture.
public final class SystemWindowServerPrivateAPI: WindowServerPrivateAPI, @unchecked Sendable {
    public typealias CGSConnectionID = UInt32
    typealias CGSHWCaptureWindowListFn = @convention(c) (
        CGSConnectionID,
        UnsafePointer<UInt32>,
        UInt32,
        UInt32
    ) -> Unmanaged<CFArray>?
    typealias CGSMainConnectionIDFn = @convention(c) () -> CGSConnectionID
    typealias CGSCopyManagedDisplaySpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    typealias CGSCopySpacesForWindowsFn = @convention(c) (
        CGSConnectionID,
        UInt64,
        CFArray
    ) -> Unmanaged<CFArray>?
    typealias CGSSetSymbolicHotKeyEnabledFn = @convention(c) (UInt32, Bool) -> Void
    typealias SLPSSetFrontProcessWithOptionsFn = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> OSStatus
    typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    typealias AXUIElementGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> OSStatus
    typealias AXUIElementCreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private var captureWindowList: CGSHWCaptureWindowListFn?
    private var mainConnection: CGSMainConnectionIDFn?
    private var copyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFn?
    private var copySpacesForWindows: CGSCopySpacesForWindowsFn?
    private var setSymbolicHotKeyEnabled: CGSSetSymbolicHotKeyEnabledFn?
    private var setFrontProcess: SLPSSetFrontProcessWithOptionsFn?
    private var getProcessForPID: GetProcessForPIDFn?
    private var axUIElementGetWindow: AXUIElementGetWindowFn?
    private var axUIElementCreateWithRemoteToken: AXUIElementCreateWithRemoteTokenFn?

    public static let shared = SystemWindowServerPrivateAPI()

    public var isCaptureAvailable: Bool { captureWindowList != nil && mainConnection != nil }
    public var isRaiseAvailable: Bool { setFrontProcess != nil && getProcessForPID != nil }
    public var isSpaceAPIAvailable: Bool { copyManagedDisplaySpaces != nil && copySpacesForWindows != nil }

    public init() {
        if let cgHandle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY) {
            if let sym = dlsym(cgHandle, "CGSHWCaptureWindowList") {
                captureWindowList = unsafeBitCast(sym, to: CGSHWCaptureWindowListFn.self)
            }
            if let sym = dlsym(cgHandle, "CGSMainConnectionID") {
                mainConnection = unsafeBitCast(sym, to: CGSMainConnectionIDFn.self)
            }
            if let sym = dlsym(cgHandle, "CGSCopyManagedDisplaySpaces") {
                copyManagedDisplaySpaces = unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFn.self)
            }
            if let sym = dlsym(cgHandle, "CGSCopySpacesForWindows") {
                copySpacesForWindows = unsafeBitCast(sym, to: CGSCopySpacesForWindowsFn.self)
            }
            if let sym = dlsym(cgHandle, "_CGSSetSymbolicHotKeyEnabled") {
                setSymbolicHotKeyEnabled = unsafeBitCast(sym, to: CGSSetSymbolicHotKeyEnabledFn.self)
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
        if let tokenSym = dlsym(dlopen(nil, RTLD_LAZY), "_AXUIElementCreateWithRemoteToken") {
            axUIElementCreateWithRemoteToken = unsafeBitCast(tokenSym, to: AXUIElementCreateWithRemoteTokenFn.self)
        }
    }

    public func axElementWithRemoteToken(_ token: Data) -> AXUIElement? {
        guard let factory = axUIElementCreateWithRemoteToken else { return nil }
        return factory(token as CFData)?.takeRetainedValue()
    }

    public func axWindowID(for element: AXUIElement) -> CGWindowID? {
        guard let getter = axUIElementGetWindow else { return nil }
        var windowID = CGWindowID(0)
        guard getter(element, &windowID) == noErr else { return nil }
        return windowID == 0 ? nil : windowID
    }

    public func captureWindowThumbnail(
        windowID: CGWindowID,
        scale: CGFloat,
        quality: WindowImageCaptureQuality
    ) -> CGImage? {
        guard let connection = mainConnection?(), let capture = captureWindowList else { return nil }
        var wid = UInt32(windowID)
        let qualityOption: CGSWindowCaptureOptions = quality == .best ? .bestResolution : .nominalResolution
        let options: CGSWindowCaptureOptions = [.ignoreGlobalClipShape, qualityOption]
        guard let array = capture(connection, &wid, 1, options.rawValue)?.takeRetainedValue() as? [CGImage],
              let image = array.first
        else { return nil }

        let previewScale = max(1, Int(scale.rounded()))
        guard previewScale > 1 else { return image }
        return downscale(image, divisor: previewScale) ?? image
    }

    public func raiseWindow(windowID: CGWindowID, pid: pid_t) -> Bool {
        _ = windowID
        guard let setFront = setFrontProcess, let resolvePID = getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard resolvePID(pid, &psn) == noErr else { return false }
        return setFront(&psn, 0x0000_0001) == noErr
    }

    public func managedDisplaySpaces() -> [[String: AnyObject]]? {
        guard let connection = mainConnection?(), let copy = copyManagedDisplaySpaces else { return nil }
        return copy(connection)?.takeRetainedValue() as? [[String: AnyObject]]
    }

    public func copySpaces(forWindowIDs windowIDs: [CGWindowID]) -> [CGWindowID: [Int]]? {
        guard let connection = mainConnection?(), let copy = copySpacesForWindows else { return nil }
        let ids = windowIDs.map { UInt32($0) } as CFArray
        guard let raw = copy(connection, 0xFFFF_FFFF_FFFF_FFFF, ids)?.takeRetainedValue() as? [Any] else {
            return nil
        }
        var result: [CGWindowID: [Int]] = [:]
        for (index, wid) in windowIDs.enumerated() where index < raw.count {
            if let spaces = raw[index] as? [Int] {
                result[wid] = spaces
            }
        }
        return result
    }

    public func setSymbolicHotKeyEnabled(_ hotKey: UInt32, enabled: Bool) -> Bool {
        guard let setter = setSymbolicHotKeyEnabled else { return false }
        setter(hotKey, enabled)
        return true
    }

    public func moveWindowsToManagedSpace(_ windowIDs: [CGWindowID], spaceID: UInt64) -> Bool {
        guard !windowIDs.isEmpty else { return false }
        guard let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") else {
            return false
        }
        let initSelector = NSSelectorFromString("initWithWindows:spaceID:")
        let performSelector = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let allocated = (operationClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              allocated.responds(to: initSelector)
        else { return false }

        typealias InitFunction = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject
        let initFunction = unsafeBitCast(allocated.method(for: initSelector), to: InitFunction.self)
        let operation = initFunction(
            allocated,
            initSelector,
            windowIDs.map { NSNumber(value: UInt32($0)) } as NSArray,
            spaceID
        )
        guard operation.responds(to: performSelector) else { return false }
        typealias PerformFunction = @convention(c) (AnyObject, Selector) -> Void
        let performFunction = unsafeBitCast(operation.method(for: performSelector), to: PerformFunction.self)
        performFunction(operation, performSelector)
        return true
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
