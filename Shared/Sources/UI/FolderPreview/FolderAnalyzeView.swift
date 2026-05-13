import Charts
import Platform
import SwiftUI

struct FolderAnalyzeView: View {
    let inventory: FolderInventory
    var data: [(FolderEntryKind, Int)] {
        inventory.breakdown.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        Group {
            if inventory.entries.isEmpty {
                FolderPreviewStateView(
                    symbol: "chart.bar",
                    title: "Nothing to analyze",
                    message: nil
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("File types")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FolderPreviewUI.secondary)
                        Chart(data, id: \.0.rawValue) { kind, count in
                            BarMark(x: .value("Kind", kind.rawValue), y: .value("Count", count))
                                .foregroundStyle(FolderPreviewUI.secondary)
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                                AxisValueLabel()
                                    .foregroundStyle(FolderPreviewUI.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine()
                                    .foregroundStyle(FolderPreviewUI.border)
                                AxisValueLabel()
                                    .foregroundStyle(FolderPreviewUI.secondary)
                            }
                        }
                        .frame(height: 190)
                    }
                    .padding(12)
                    .background(FolderPreviewUI.panel)

                    Divider()

                    Text("Largest files")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FolderPreviewUI.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    if inventory.largest.isEmpty {
                        FolderPreviewStateView(
                            symbol: "doc",
                            title: "No files found",
                            message: nil
                        )
                    } else {
                        List(inventory.largest) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: "doc")
                                    .foregroundStyle(FolderPreviewUI.secondary)
                                    .frame(width: 18)
                                Text(entry.name)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(FolderPreviewUI.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(FolderPreviewUI.background)
                    }
                }
            }
        }
    }
}
