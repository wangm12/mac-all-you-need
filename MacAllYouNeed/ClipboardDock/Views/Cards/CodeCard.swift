import SwiftUI

struct CodeCard: View {
    let item: DockItem

    var body: some View {
        let language: String = {
            if case let .code(language) = item.kind { return language }
            return "text"
        }()
        VStack(alignment: .leading, spacing: 6) {
            Text(language.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MAYNTheme.elevated)
                .clipShape(Capsule())
            Text(item.displayLabel)
                .font(.system(.body, design: .monospaced))
                .lineLimit(8)
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}
