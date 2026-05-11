import AppKit
import Core

public enum CaptureSound {
    public static func playIfEnabled() {
        guard AppGroupSettings.defaults.bool(forKey: "capture.sound") else { return }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}
