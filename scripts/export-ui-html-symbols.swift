#!/usr/bin/env swift
import AppKit

let symbols: [String] = [
    "square.grid.2x2", "doc.on.clipboard", "mic", "checklist", "arrow.down.circle",
    "sparkles.rectangle.stack", "folder", "folder.badge.gearshape", "rectangle.3.group",
    "hand.draw", "macwindow.on.rectangle", "gearshape", "clock", "text.quote",
    "slider.horizontal.3", "square.stack.3d.down.right", "text.book.closed", "sparkles",
    "command", "circle.grid.cross", "square.split.2x2", "app.badge", "list.bullet.rectangle",
    "stethoscope", "clock.badge.checkmark", "lock.shield", "lock", "arrow.down",
    "checkmark", "sidebar.left", "slash.circle", "plus", "trash", "play.fill", "pause.fill",
    "doc.on.doc", "arrow.clockwise", "mic.badge.plus", "arrow.up.forward.app",
    "rectangle.on.rectangle.angled", "externaldrive.badge.plus", "bell.badge",
    "bolt.fill", "keyboard", "pause.circle", "textformat", "pencil", "link",
    "key", "function", "text.viewfinder", "checklist.checked", "rectangle.on.rectangle",
    "arrow.down.to.line", "waveform", "xmark", "exclamationmark.triangle", "sparkle",
    "stop.fill", "arrow.uturn.backward", "rectangle.and.pencil.and.ellipsis",
    "macwindow", "magnifyingglass", "ellipsis.circle", "pin", "scissors",
    "doc.text", "photo", "chevron.right", "chevron.left", "info.circle",
    "checkmark.shield", "wrench.and.screwdriver", "play.rectangle",
    "arrow.counterclockwise", "globe", "text.bubble", "square.and.pencil",
    "checkmark.seal.fill", "lock.shield", "circle", "checkmark.circle.fill",
    "wand.and.stars", "line.3.horizontal", "line.3.horizontal.decrease.circle",
    "internaldrive", "cloud", "sun.max", "moon", "circle.lefthalf.filled"
]

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

let pointSize: CGFloat = 16
let weight = NSFont.Weight.medium
let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
let scale: CGFloat = 2
let canvas = CGSize(width: pointSize * scale, height: pointSize * scale)

var exported = 0
var missing: [String] = []

for name in symbols {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let image = base.withSymbolConfiguration(config) else {
        missing.append(name)
        continue
    }
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width),
        pixelsHigh: Int(canvas.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: canvas).fill()
    let aspect = image.size
    let fit = min(canvas.width / aspect.width, canvas.height / aspect.height)
    let drawSize = CGSize(width: aspect.width * fit, height: aspect.height * fit)
    let origin = CGPoint(
        x: (canvas.width - drawSize.width) / 2,
        y: (canvas.height - drawSize.height) / 2
    )
    image.draw(
        in: NSRect(origin: origin, size: drawSize),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: nil
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let file = outDir.appendingPathComponent("\(name).png")
    try data.write(to: file)
    exported += 1
}

fputs("exported=\(exported) missing=\(missing.count)\n", stderr)
if !missing.isEmpty {
    fputs("missing: \(missing.joined(separator: ", "))\n", stderr)
}
