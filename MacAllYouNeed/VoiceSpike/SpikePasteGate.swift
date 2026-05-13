import AppKit
import ApplicationServices
import Foundation

/// Gate 4: pasteboard + Cmd+V injection + pasteboard restore.
enum SpikePasteGate {
    struct PasteTiming {
        let setMicros: Double
        let postMicros: Double
        let restoreMicros: Double
    }

    static func runWithUserSwitch(
        text: String = "Hello from Voice spike - paste injection test"
    ) async -> String {
        var lines: [String] = []

        let trusted = AXIsProcessTrusted()
        lines.append("AXIsProcessTrusted: \(trusted)")
        if !trusted {
            lines.append("WARN: Accessibility is not granted; CGEvent paste may silently fail.")
        }

        let originalSnapshot = snapshotPasteboard()
        lines.append("Original pasteboard had \(originalSnapshot.count) item(s)")
        lines.append("Waiting 5s. Focus a target text field now.")
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        let timing = unattendedCore(text: text)
        lines.append("Pasteboard set: \(String(format: "%.0f", timing.setMicros)) us")
        lines.append("CGEvent post: \(String(format: "%.0f", timing.postMicros)) us")
        lines.append("Cmd+V posted via CGEvent.")

        try? await Task.sleep(nanoseconds: 450_000_000)
        let restoreMicros = restorePasteboard(originalSnapshot)
        lines.append("Pasteboard restore: \(String(format: "%.0f", restoreMicros)) us")
        lines.append("Manual check required: verify target app received text and previous clipboard was restored.")

        return lines.joined(separator: "\n")
    }

    @discardableResult
    static func runUnattended(text: String) -> PasteTiming {
        let snapshot = snapshotPasteboard()
        let timing = unattendedCore(text: text)
        let restoreMicros = restorePasteboard(snapshot)
        return PasteTiming(setMicros: timing.setMicros, postMicros: timing.postMicros, restoreMicros: restoreMicros)
    }

    private struct PasteboardSnapshot {
        let items: [[(NSPasteboard.PasteboardType, Data)]]
        var count: Int {
            items.count
        }
    }

    private static func snapshotPasteboard() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = pasteboard.pasteboardItems?.map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    private static func restorePasteboard(_ snapshot: PasteboardSnapshot) -> Double {
        let start = DispatchTime.now()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for itemTypes in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in itemTypes {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1000.0
    }

    private static func unattendedCore(text: String) -> (setMicros: Double, postMicros: Double) {
        let pasteboard = NSPasteboard.general

        let setStart = DispatchTime.now()
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let setMicros = Double(DispatchTime.now().uptimeNanoseconds - setStart.uptimeNanoseconds) / 1000.0

        let source = CGEventSource(stateID: .privateState)
        let postStart = DispatchTime.now()
        if let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
        let postMicros = Double(DispatchTime.now().uptimeNanoseconds - postStart.uptimeNanoseconds) / 1000.0

        return (setMicros, postMicros)
    }
}
