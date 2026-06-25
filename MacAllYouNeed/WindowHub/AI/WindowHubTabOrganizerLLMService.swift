import Foundation

enum WindowHubTabOrganizerPrompt {
    static let system = """
    You are a macOS window and tab organization assistant.
    Respond with JSON only using this schema:
    {
      "summary": "short human summary",
      "steps": [
        {
          "id": "unique-id",
          "kind": "focus|close|move|create|group",
          "targetID": "optional target id",
          "title": "human readable step",
          "executable": true,
          "reason": "optional when executable is false"
        }
      ]
    }
    Rules:
    - Prefer closing duplicate tabs and grouping related tabs.
    - Never invent target IDs; only use IDs from the payload.
    - Mark unsupported steps executable=false.
    """

    static func userPayload(
        snapshot: WindowHubSnapshot,
        settings: WindowHubSettings
    ) -> String {
        let lines = snapshot.flatTargets.prefix(200).map { target in
            var parts = ["id=\(target.id.raw)", "kind=\(target.kind.rawValue)", "title=\(target.displayTitle)"]
            if settings.aiSendFullURLs, let domain = target.domain {
                parts.append("domain=\(domain)")
            } else if let domain = target.domain {
                parts.append("domain=\(domain)")
            }
            return parts.joined(separator: " | ")
        }
        return lines.joined(separator: "\n")
    }
}

enum WindowHubTabOrganizerLLMService {
    static func organize(
        snapshot: WindowHubSnapshot,
        settings: WindowHubSettings,
        generate: (String, String) async throws -> String
    ) async throws -> WindowHubAIPlan {
        let raw = try await generate(
            WindowHubTabOrganizerPrompt.system,
            WindowHubTabOrganizerPrompt.userPayload(snapshot: snapshot, settings: settings)
        )
        return try parse(raw)
    }

    private static func parse(_ raw: String) throws -> WindowHubAIPlan {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonStart = trimmed.firstIndex(of: "{")
        let jsonEnd = trimmed.lastIndex(of: "}")
        guard let jsonStart, let jsonEnd, jsonEnd > jsonStart else {
            throw CocoaError(.coderReadCorrupt)
        }
        let json = String(trimmed[jsonStart ... jsonEnd])
        let data = Data(json.utf8)
        return try JSONDecoder().decode(WindowHubAIPlan.self, from: data)
    }
}

enum WindowHubTabOrganizerExecutor {
    static func executableSteps(from plan: WindowHubAIPlan, snapshot: WindowHubSnapshot) -> WindowHubActionPlan {
        let steps = plan.steps.map { step in
            let targetID = step.targetID.flatMap { WindowHubTargetID(raw: $0) }
            let executable = step.executable && targetID != nil
            return WindowHubActionStep(
                id: step.id,
                title: step.title,
                action: mapKind(step.kind),
                targetID: targetID ?? WindowHubTargetID(raw: "missing"),
                executable: executable,
                reason: step.reason
            )
        }
        return WindowHubActionPlan(
            title: plan.summary,
            steps: steps,
            requiresConfirmation: true,
            canUndo: false
        )
    }

    private static func mapKind(_ kind: String) -> WindowHubDirectAction? {
        switch kind.lowercased() {
        case "close": return .closeTab
        case "quit": return .quitApp
        default: return nil
        }
    }
}
