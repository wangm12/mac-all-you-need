import AppKit
import SwiftUI
import UI

struct ColorCard: View {
    let item: DockItem
    @Environment(ClipboardDockModel.self) private var model

    @State private var picker = ColorPickerCoordinator()
    @State private var formatIndex = 0

    private let formats = ["hex", "rgb", "hsl"]

    private var nsColor: NSColor {
        if case let .color(color) = PreviewDetection.detect(item.preview) {
            return color
        }
        return .gray
    }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor))
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            Text(formattedColor())
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .onTapGesture {
                    formatIndex = (formatIndex + 1) % formats.count
                }
        }
        .padding(10)
        .contextMenu {
            Button("Open in Color Picker") {
                picker.onCommit = { color in
                    let hex = color.hexString
                    Task {
                        _ = await model.xpc.pasteText(text: hex, plainText: true, saveAsNew: true)
                    }
                }
                picker.present(initial: nsColor)
            }
        }
    }

    private func formattedColor() -> String {
        let color = nsColor.usingColorSpace(.sRGB) ?? nsColor

        switch formats[formatIndex] {
        case "rgb":
            return String(
                format: "rgb(%d, %d, %d)",
                Int(color.redComponent * 255),
                Int(color.greenComponent * 255),
                Int(color.blueComponent * 255)
            )
        case "hsl":
            return String(
                format: "hsl(%.0f, %.0f%%, %.0f%%)",
                color.hueComponent * 360,
                color.saturationComponent * 100,
                color.brightnessComponent * 100
            )
        default:
            return color.hexString
        }
    }
}

private extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(c.redComponent * 255),
            Int(c.greenComponent * 255),
            Int(c.blueComponent * 255)
        )
    }
}
