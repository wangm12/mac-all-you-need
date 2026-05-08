import SwiftUI

struct TextCard: View {
    let item: DockItem

    var body: some View {
        let isCode: Bool = {
            if case .code = item.kind { return true }
            return false
        }()

        Text(item.preview)
            .font(isCode ? .system(.body, design: .monospaced) : .body)
            .lineLimit(8)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
    }
}
