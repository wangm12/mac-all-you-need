import FeatureCore
import SwiftUI

struct FeaturePickerView: View {
    let registry: FeatureRegistry
    @Binding var selectedIDs: [FeatureID]
    let onContinue: () -> Void
    let onSkip: () -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        SetupTaskPage(
            symbol: "square.grid.2x2",
            title: "Choose your features",
            subtitle: "Pick what you want now. Everything is opt-in — you can install or remove features any time from Settings → Features."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(registry.descriptors, id: \.id) { descriptor in
                        FeaturePickerCard(
                            descriptor: descriptor,
                            isSelected: binding(for: descriptor.id)
                        )
                    }
                }
                Text("\(selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for id: FeatureID) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected, !selectedIDs.contains(id) {
                    selectedIDs.append(id)
                } else if !isSelected {
                    selectedIDs.removeAll { $0 == id }
                }
            }
        )
    }
}
