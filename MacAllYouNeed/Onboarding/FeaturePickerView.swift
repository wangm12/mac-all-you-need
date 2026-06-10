import FeatureCore
import SwiftUI

enum FeaturePickerPresets {
    static let essentials: [FeatureID] = [.clipboard]
    static let productivity: [FeatureID] = [.clipboard, .voice, .windowLayouts]
    static let all: [FeatureID] = OnboardingFeaturePickerOrdering.featureIDs

    static func apply(_ preset: [FeatureID], to selectedIDs: inout [FeatureID]) {
        selectedIDs = preset
    }
}

struct FeaturePickerView: View {
    let registry: FeatureRegistry
    @Binding var selectedIDs: [FeatureID]

    private var pickerDescriptors: [FeatureDescriptor] {
        OnboardingFeaturePickerOrdering.descriptors(in: registry)
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your features")
                    .font(.system(size: 22, weight: .semibold))
                Text("Tap to select. Setup guides run on the next steps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                MAYNButton("Essentials") {
                    FeaturePickerPresets.apply(FeaturePickerPresets.essentials, to: &selectedIDs)
                }
                MAYNButton("Productivity") {
                    FeaturePickerPresets.apply(FeaturePickerPresets.productivity, to: &selectedIDs)
                }
                MAYNButton("Select all") {
                    FeaturePickerPresets.apply(FeaturePickerPresets.all, to: &selectedIDs)
                }
                MAYNButton("Clear all") {
                    selectedIDs = []
                }
                Spacer(minLength: 0)
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(pickerDescriptors, id: \.id) { descriptor in
                    FeaturePickerCard(
                        descriptor: descriptor,
                        isSelected: binding(for: descriptor.id)
                    )
                }
            }
        }
    }

    private var selectionSummary: String {
        if selectedIDs.isEmpty {
            return "None selected — you can enable later from the Dashboard"
        }
        return "\(selectedIDs.count) selected"
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
