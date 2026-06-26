import SwiftUI

struct WindowHubAIOrganizeSheetView: View {
    @Bindable var coordinator: WindowHubCoordinator
    @State private var selectedStepIDs: Set<String> = []
    @State private var expandedGroups: Set<String> = []

    private var plan: WindowHubActionPlan? { coordinator.pendingPlan }
    private var summary: String { coordinator.aiPlan?.summary ?? "AI suggestions" }

    private var groupedSteps: [(key: String, title: String, steps: [WindowHubActionStep])] {
        guard let plan else { return [] }
        let order = ["close", "window", "other"]
        var buckets: [String: [WindowHubActionStep]] = [:]
        for step in plan.steps {
            let key = groupKey(for: step)
            buckets[key, default: []].append(step)
        }
        return order.compactMap { key in
            guard let steps = buckets[key], !steps.isEmpty else { return nil }
            return (key, groupTitle(for: key, count: steps.count), steps)
        }
    }

    private var executableSelectedCount: Int {
        guard let plan else { return 0 }
        return plan.steps.filter { selectedStepIDs.contains($0.id) && $0.executable }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(MAYNTheme.subtleBorder)

            if groupedSteps.isEmpty {
                emptyState
            } else {
                suggestionList
            }

            Divider().overlay(MAYNTheme.subtleBorder)
            footer
        }
        .frame(width: 500, height: min(560, sheetHeight))
        .background(MAYNTheme.elevated)
        .onAppear(perform: seedExpandedGroups)
    }

    private var sheetHeight: CGFloat {
        let base: CGFloat = 220
        let rowHeight: CGFloat = 34
        let groupHeader: CGFloat = 36
        let stepCount = CGFloat(plan?.steps.count ?? 0)
        let groupCount = CGFloat(groupedSteps.count)
        return base + groupCount * groupHeader + min(stepCount, 12) * rowHeight
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Organize")
                .font(.title3.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(privacyLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private var privacyLine: String {
        coordinator.settings.aiSendFullURLs
            ? "Sending tab titles and domains to your configured AI provider."
            : "Sending tab titles and domains only. Full URLs stay on device."
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No suggestions",
            systemImage: "sparkles",
            description: Text(summary)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groupedSteps, id: \.key) { group in
                    groupSection(group)
                }
            }
            .padding(12)
        }
    }

    private func groupSection(_ group: (key: String, title: String, steps: [WindowHubActionStep])) -> some View {
        let isExpanded = expandedGroups.contains(group.key)
        let selectable = group.steps.filter(\.executable)
        let selectedInGroup = selectable.filter { selectedStepIDs.contains($0.id) }.count
        let allSelected = !selectable.isEmpty && selectable.allSatisfy { selectedStepIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(MAYNMotion.fast) {
                        if isExpanded { expandedGroups.remove(group.key) }
                        else { expandedGroups.insert(group.key) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("\(selectedInGroup)/\(selectable.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: groupToggleBinding(selectable: selectable, allSelected: allSelected)) {
                    EmptyView()
                }
                .labelsHidden()
                .maynSwitchToggleStyle()
                .disabled(selectable.isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.steps) { step in
                        stepRow(step)
                    }
                }
                .background(MAYNTheme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MAYNTheme.subtleBorder, lineWidth: 1)
                )
            }
        }
    }

    private func groupToggleBinding(
        selectable: [WindowHubActionStep],
        allSelected: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { allSelected },
            set: { isOn in
                if isOn {
                    selectable.forEach { selectedStepIDs.insert($0.id) }
                } else {
                    selectable.forEach { selectedStepIDs.remove($0.id) }
                }
            }
        )
    }

    private func stepRow(_ step: WindowHubActionStep) -> some View {
        let label = stepLabel(for: step)
        return HStack(spacing: 8) {
            Toggle(isOn: binding(for: step)) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!step.executable)

            VStack(alignment: .leading, spacing: 1) {
                Text(label.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = label.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            actionPill(for: step)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .opacity(step.executable ? 1 : 0.55)
    }

    private func binding(for step: WindowHubActionStep) -> Binding<Bool> {
        Binding(
            get: { selectedStepIDs.contains(step.id) },
            set: { isOn in
                if isOn { selectedStepIDs.insert(step.id) }
                else { selectedStepIDs.remove(step.id) }
            }
        )
    }

    private func actionPill(for step: WindowHubActionStep) -> some View {
        let text: String
        let kind: StatusPill.Kind
        if !step.executable {
            text = step.reason ?? "Unavailable"
            kind = .warning
        } else {
            switch step.action {
            case .closeTab: text = "Close tab"; kind = .danger
            case .closeWindow: text = "Close window"; kind = .danger
            case .closeAllTabsInWindow: text = "Close all"; kind = .danger
            case .quitApp: text = "Quit"; kind = .danger
            case .none: text = "Suggest"; kind = .neutral
            }
        }
        return StatusPill(text: text, kind: kind)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel") { coordinator.dismissAIOrganize() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("\(executableSelectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Apply selected") {
                Task { await coordinator.confirmAIOrganize(selectedStepIDs: selectedStepIDs) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(MAYNTheme.danger)
            .disabled(executableSelectedCount == 0)
        }
        .padding(16)
    }

    private func seedExpandedGroups() {
        expandedGroups = Set(
            groupedSteps
                .filter { $0.steps.count <= 5 }
                .map(\.key)
        )
        selectedStepIDs = []
    }

    private func groupKey(for step: WindowHubActionStep) -> String {
        switch step.action {
        case .closeTab: return "close"
        case .closeWindow, .closeAllTabsInWindow: return "window"
        default: return "other"
        }
    }

    private func groupTitle(for key: String, count: Int) -> String {
        switch key {
        case "close": return "Close tabs (\(count))"
        case "window": return "Close windows (\(count))"
        default: return "Other suggestions (\(count))"
        }
    }

    private func stepLabel(for step: WindowHubActionStep) -> (title: String, subtitle: String?) {
        if let target = coordinator.snapshot.flatTargets.first(where: { $0.id == step.targetID }) {
            return (target.displayTitle, target.appName)
        }
        return (step.title, nil)
    }
}

struct WindowHubActionConfirmationView: View {
    let plan: WindowHubActionPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(plan.title)
                .font(.title3.weight(.semibold))
            Text(plan.canUndo ? "You can undo some changes." : "This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.steps) { step in
                        Text(step.title)
                            .font(.system(size: 12))
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxHeight: 240)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Confirm", role: .destructive, action: onConfirm)
            }
        }
        .padding()
        .frame(width: 420)
    }
}
