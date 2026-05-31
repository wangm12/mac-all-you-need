import AppKit
import Core
import SwiftUI

struct TextCard: View {
    let item: DockItem

    var body: some View {
        let isCode: Bool = {
            if case .code = item.kind { return true }
            return false
        }()

        VStack(alignment: .leading, spacing: 6) {
            Text(item.displayLabel)
                .font(isCode ? .system(.body, design: .monospaced) : .body)
                .lineLimit(8)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}
