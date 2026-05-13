import Carbon.HIToolbox
import Core
import CoreGraphics
import Foundation

struct VoiceAutoSubmitEvent: Equatable {
    let keyCode: CGKeyCode
    let isKeyDown: Bool
    let flags: CGEventFlags
}

final class VoiceAutoSubmitService {
    private let postEvent: (VoiceAutoSubmitEvent) -> Void

    init(postEvent: @escaping (VoiceAutoSubmitEvent) -> Void = VoiceAutoSubmitService.postToSystem) {
        self.postEvent = postEvent
    }

    func submit(_ key: VoiceAutoSubmitKey) {
        switch key {
        case .none:
            return
        case .returnKey:
            postReturn(flags: [])
        case .commandReturn:
            postReturn(flags: .maskCommand)
        }
    }

    private func postReturn(flags: CGEventFlags) {
        let keyCode = CGKeyCode(kVK_Return)
        postEvent(VoiceAutoSubmitEvent(keyCode: keyCode, isKeyDown: true, flags: flags))
        postEvent(VoiceAutoSubmitEvent(keyCode: keyCode, isKeyDown: false, flags: flags))
    }

    private static func postToSystem(_ event: VoiceAutoSubmitEvent) {
        guard let cgEvent = CGEvent(
            keyboardEventSource: nil,
            virtualKey: event.keyCode,
            keyDown: event.isKeyDown
        ) else {
            return
        }
        cgEvent.flags = event.flags
        cgEvent.post(tap: .cghidEventTap)
    }
}
