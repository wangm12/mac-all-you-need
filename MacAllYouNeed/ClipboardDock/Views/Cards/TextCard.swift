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

            if let calc = item.calculation {
                calculationRow(calc)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }

    private func calculationRow(_ calc: CalculationResult) -> some View {
        HStack(spacing: 6) {
            Text("= \(calc.value)")
                .font(.callout.weight(.medium))
                .foregroundStyle(MAYNTheme.muted)
                .lineLimit(1)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(calc.value, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy result")
        }
    }
}
