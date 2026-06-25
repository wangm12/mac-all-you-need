import AppKit
import Foundation
import Platform

@MainActor
final class VoiceActivationMonitor {
    private var globalHotkey: GlobalHotkey?
    private var globalMonitor: NSEventMonitorHandle?
    private var localMonitor: NSEventMonitorHandle?
    private var settings: VoiceActivationSettings?
    private var isDown = false
    private var staleTask: Task<Void, Never>?
    private var lastTogglePressAt: Date?
    private let toggleDebounceSeconds: TimeInterval = 0.15

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// True while a hold-to-talk shortcut is currently pressed.
    var isHeld: Bool { isDown }

    func start(settings: VoiceActivationSettings) throws {
        stop()
        self.settings = settings

        switch settings.mode {
        case .toggle:
            let hotkey = GlobalHotkey(descriptor: settings.shortcut) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.shouldAcceptTogglePress() else { return }
                    self.onPress?()
                }
            }
            try hotkey.register()
            globalHotkey = hotkey

        case .hold:
            globalMonitor = NSEventMonitorHandle(global: [.keyDown, .keyUp]) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
            localMonitor = NSEventMonitorHandle(local: [.keyDown, .keyUp]) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
                return event
            }
        }
    }

    func stop() {
        globalHotkey?.unregister()
        globalHotkey = nil

        globalMonitor = nil
        localMonitor = nil
        settings = nil

        staleTask?.cancel()
        staleTask = nil
        lastTogglePressAt = nil
        releaseIfNeeded()
    }

    private func handle(_ event: NSEvent) {
        guard let settings else { return }
        switch event.type {
        case .keyDown:
            guard !isDown,
                  VoiceShortcutMatcher.matches(
                      keyCode: event.keyCode,
                      modifierFlags: event.modifierFlags,
                      descriptor: settings.shortcut
                  )
            else { return }
            isDown = true
            onPress?()
            scheduleStaleRelease()

        case .keyUp:
            guard isDown, UInt32(event.keyCode) == settings.shortcut.keyCode else { return }
            releaseIfNeeded()

        default:
            break
        }
    }

    private func releaseIfNeeded() {
        guard isDown else { return }
        isDown = false
        staleTask?.cancel()
        staleTask = nil
        onRelease?()
    }

    private func scheduleStaleRelease() {
        staleTask?.cancel()
        staleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            releaseIfNeeded()
        }
    }

    private func shouldAcceptTogglePress(now: Date = Date()) -> Bool {
        if let last = lastTogglePressAt,
           now.timeIntervalSince(last) < toggleDebounceSeconds
        {
            return false
        }
        lastTogglePressAt = now
        return true
    }
}
