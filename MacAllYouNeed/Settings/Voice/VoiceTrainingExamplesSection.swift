import Core
import SwiftUI

struct VoiceTrainingExamplesSection: View {
    let controller: AppController
    @State private var examples: [VoiceTrainingExample] = []
    @State private var qualityFilter: TrainingQualityFilter = .all
    @State private var errorMessage: String?

    var body: some View {
        MAYNSection(
            title: "Training examples",
            subtitle: "Local audio and labels for optional offline ASR fine-tuning. Export from Advanced settings."
        ) {
            if examples.isEmpty {
                MAYNSettingsRow(
                    title: "No saved examples",
                    subtitle: "Turn on “Save training examples” in the Personalization tab, then dictate and edit text."
                ) {
                    EmptyView()
                }
            } else {
                MAYNSettingsRow(
                    title: "Filter",
                    subtitle: "\(filteredExamples.count) of \(examples.count) shown"
                ) {
                    Picker("", selection: $qualityFilter) {
                        ForEach(TrainingQualityFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                }
                MAYNDivider()
                ForEach(Array(filteredExamples.prefix(25).enumerated()), id: \.element.id) { index, example in
                    trainingRow(example)
                    if index < min(filteredExamples.count, 25) - 1 {
                        MAYNDivider()
                    }
                }
                if filteredExamples.count > 25 {
                    MAYNDivider()
                    Text("Showing the 25 most recent matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
                        .padding(.vertical, 8)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
            }
        }
        .onAppear { reload() }
    }

    private var filteredExamples: [VoiceTrainingExample] {
        switch qualityFilter {
        case .all:
            examples
        case .high:
            examples.filter { $0.quality == .high }
        case .medium:
            examples.filter { $0.quality == .medium }
        }
    }

    private func trainingRow(_ example: VoiceTrainingExample) -> some View {
        HStack(alignment: .top, spacing: MAYNControlMetrics.rowControlSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(example.finalText.prefix(80) + (example.finalText.count > 80 ? "…" : ""))
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    StatusPill(text: example.quality.rawValue, kind: example.quality == .high ? .success : .neutral)
                    if let reason = example.qualityReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if example.audioPath != nil {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MAYNButton("Delete", role: .destructive, height: 24) {
                deleteExample(example)
            }
        }
        .padding(.horizontal, MAYNControlMetrics.rowHorizontalPadding)
        .padding(.vertical, MAYNControlMetrics.rowVerticalPadding)
    }

    private func reload() {
        examples = controller.listVoiceTrainingExamples()
        errorMessage = nil
    }

    private func deleteExample(_ example: VoiceTrainingExample) {
        do {
            try controller.deleteVoiceTrainingExample(id: example.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TrainingQualityFilter: String, CaseIterable, Identifiable {
    case all
    case high
    case medium

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .high: "High"
        case .medium: "Medium"
        }
    }
}
