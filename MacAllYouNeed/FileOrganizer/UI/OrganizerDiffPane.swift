import Core
import SwiftUI

/// Mandatory preview/approve sheet. No filesystem changes happen until the user
/// taps Apply here.
struct OrganizerDiffPane: View {
    @Binding var proposal: OrganizationProposal
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            MAYNDivider()
            operationsList
            MAYNDivider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(MAYNTheme.window)
    }

    private var header: some View {
        HStack {
            Text("Review Changes").font(.headline)
            Spacer()
            Text("\(proposal.approvedOperations.count)/\(proposal.operations.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var operationsList: some View {
        List($proposal.operations, id: \.id) { $op in
            HStack(spacing: 10) {
                Toggle("", isOn: $op.isApproved).labelsHidden()
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(op.sourceURL.lastPathComponent)
                            .strikethrough(true, color: .secondary)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(op.proposedFilename).fontWeight(.medium)
                    }
                    if let sub = op.proposedSubfolder {
                        Text("→ \(sub)/")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if op.confidence < 0.7 {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(MAYNTheme.warning)
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var footer: some View {
        HStack {
            MAYNButton(role: .secondary, action: onCancel) { Text("Cancel") }
            Spacer()
            MAYNButton(role: .secondary) {
                for i in proposal.operations.indices { proposal.operations[i].isApproved = true }
            } label: {
                Text("Select All")
            }
            MAYNButton(role: .primary, action: onApprove) {
                Text("Apply \(proposal.approvedOperations.count) Changes")
            }
            .disabled(proposal.approvedOperations.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
