import Charts
import Platform
import SwiftUI

struct FolderAnalyzeView: View {
    let inventory: FolderInventory
    var data: [(FolderEntryKind, Int)] {
        inventory.breakdown.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Chart(data, id: \.0.rawValue) { kind, count in
                BarMark(x: .value("Kind", kind.rawValue), y: .value("Count", count))
            }
            .frame(height: 200).padding(.horizontal, 12)
            Divider()
            Text("Largest files").font(.headline).padding(.horizontal, 12)
            List(inventory.largest) { entry in
                HStack {
                    Text(entry.name)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                }
            }
        }
    }
}
