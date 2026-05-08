import AppKit
import SwiftUI
import UI

struct ColorCard: View {
    let item: DockItem

    var body: some View {
        let nsColor: NSColor = {
            if case let .color(color) = PreviewDetection.detect(item.preview) { return color }
            return .gray
        }()
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor))
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
            Text(item.preview)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(10)
    }
}
