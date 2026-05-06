import AppKit
import Carbon.HIToolbox

public final class GlobalHotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyID: UInt32?
    private let descriptor: HotkeyDescriptor
    private let callback: () -> Void
    private static let stateLock = NSLock()
    private static var dispatcher: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    public enum Error: Swift.Error, Equatable {
        case registrationFailed(OSStatus)
    }

    public init(descriptor: HotkeyDescriptor, callback: @escaping () -> Void) {
        self.descriptor = descriptor
        self.callback = callback
    }

    public func register() throws {
        Self.installHandlerIfNeeded()
        let id = Self.allocateID(callback: callback)
        var hkID = EventHotKeyID(signature: OSType(0x4D41_594E), id: id) // 'MAYN'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            descriptor.keyCode, descriptor.modifiers.rawValue,
            hkID, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr, let ref else {
            Self.removeCallback(id: id)
            throw Error.registrationFailed(status)
        }
        hotKeyRef = ref
        hotKeyID = id
    }

    public func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let id = hotKeyID { Self.removeCallback(id: id) }
        hotKeyRef = nil
        hotKeyID = nil
    }

    private static func allocateID(callback: @escaping () -> Void) -> UInt32 {
        stateLock.lock(); defer { stateLock.unlock() }
        let id = nextID
        nextID += 1
        dispatcher[id] = callback
        return id
    }

    private static func removeCallback(id: UInt32) {
        stateLock.lock(); defer { stateLock.unlock() }
        dispatcher.removeValue(forKey: id)
    }

    private static func callback(for id: UInt32) -> (() -> Void)? {
        stateLock.lock(); defer { stateLock.unlock() }
        return dispatcher[id]
    }

    private static func installHandlerIfNeeded() {
        stateLock.lock()
        guard !handlerInstalled else { stateLock.unlock(); return }
        handlerInstalled = true
        stateLock.unlock()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(
                eventRef, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &hkID
            )
            if let cb = GlobalHotkey.callback(for: hkID.id) {
                DispatchQueue.main.async(execute: cb)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
