import Foundation

@MainActor
extension WindowHubCoordinator {
    var isAIOrganizePresented: Bool { aiPlan != nil }

    func requestAIOrganize() async {
        isAIOrganizing = true
        defer { isAIOrganizing = false }

        guard let llmGenerate else {
            aiPlan = WindowHubAIPlan(summary: "AI provider is not configured.", steps: [])
            pendingPlan = WindowHubActionPlan(
                title: "AI Organize",
                steps: [],
                requiresConfirmation: true,
                canUndo: false
            )
            return
        }
        do {
            let plan = try await WindowHubTabOrganizerLLMService.organize(
                snapshot: snapshot,
                settings: settings,
                generate: llmGenerate
            )
            aiPlan = plan
            pendingPlan = WindowHubTabOrganizerExecutor.executableSteps(from: plan, snapshot: snapshot)
        } catch {
            aiPlan = WindowHubAIPlan(summary: "AI organize failed: \(error.localizedDescription)", steps: [])
            pendingPlan = WindowHubActionPlan(
                title: "AI Organize",
                steps: [],
                requiresConfirmation: true,
                canUndo: false
            )
        }
    }

    func confirmAIOrganize(selectedStepIDs: Set<String>) async {
        guard let plan = pendingPlan else { return }
        let steps = plan.steps.filter { selectedStepIDs.contains($0.id) && $0.executable }
        guard !steps.isEmpty else { return }
        let filtered = WindowHubActionPlan(
            title: plan.title,
            steps: steps,
            requiresConfirmation: plan.requiresConfirmation,
            canUndo: plan.canUndo
        )
        executionState = await actionExecutor.execute(plan: filtered, snapshot: snapshot)
        dismissAIOrganize()
        refreshIndex()
    }

    func dismissAIOrganize() {
        aiPlan = nil
        pendingPlan = nil
    }
}
