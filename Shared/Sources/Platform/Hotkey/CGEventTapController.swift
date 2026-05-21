import Foundation
import CoreGraphics

public final class CGEventTapController {

    public enum RunLoopTarget {
        case main
        case current(CFRunLoop)
    }

    public enum InstallError: Error {
        case creationFailed
    }

    // MARK: - Stored init arguments

    private let tap: CGEventTapLocation
    private let place: CGEventTapPlacement
    private let options: CGEventTapOptions
    private let eventsOfInterest: CGEventMask
    private let runLoopTarget: RunLoopTarget
    private let callback: CGEventTapCallBack
    private let userInfo: UnsafeMutableRawPointer?

    // MARK: - Runtime state

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Init

    public init(
        tap: CGEventTapLocation,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        eventsOfInterest: CGEventMask,
        runLoop: RunLoopTarget,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) {
        self.tap = tap
        self.place = place
        self.options = options
        self.eventsOfInterest = eventsOfInterest
        self.runLoopTarget = runLoop
        self.callback = callback
        self.userInfo = userInfo
    }

    deinit {
        uninstall()
    }

    // MARK: - Public inspection properties

    public var installedTapLocation: CGEventTapLocation { tap }
    public var installedTapPlacement: CGEventTapPlacement { place }
    public var installedTapOptions: CGEventTapOptions { options }
    public var installedRunLoopTarget: RunLoopTarget { runLoopTarget }
    public var isInstalled: Bool { machPort != nil }

    // MARK: - Lifecycle

    public func install() throws {
        guard let port = CGEvent.tapCreate(
            tap: tap,
            place: place,
            options: options,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: userInfo
        ) else {
            throw InstallError.creationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let loop = resolvedRunLoop()
        CFRunLoopAddSource(loop, source, .commonModes)

        machPort = port
        runLoopSource = source
    }

    public func enable() {
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    public func disable() {
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: false)
    }

    public func reenableAfterTimeout() {
        guard let port = machPort else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    public func uninstall() {
        if let source = runLoopSource {
            let loop = resolvedRunLoop()
            CFRunLoopRemoveSource(loop, source, .commonModes)
            runLoopSource = nil
        }
        if let port = machPort {
            CFMachPortInvalidate(port)
            machPort = nil
        }
    }

    // MARK: - Private helpers

    private func resolvedRunLoop() -> CFRunLoop {
        switch runLoopTarget {
        case .main:
            return CFRunLoopGetMain()
        case .current(let loop):
            return loop
        }
    }
}

// MARK: - RunLoopTarget Equatable

extension CGEventTapController.RunLoopTarget: Equatable {
    public static func == (
        lhs: CGEventTapController.RunLoopTarget,
        rhs: CGEventTapController.RunLoopTarget
    ) -> Bool {
        switch (lhs, rhs) {
        case (.main, .main):
            return true
        case (.current(let a), .current(let b)):
            return a === b
        default:
            return false
        }
    }
}
