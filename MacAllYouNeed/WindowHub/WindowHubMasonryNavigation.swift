import Foundation

enum WindowHubMasonryNavigation {
    static func moveSelection(
        selectedTargetID: WindowHubTargetID?,
        in targets: [WindowHubTarget],
        delta: Int
    ) -> WindowHubTargetID? {
        guard !targets.isEmpty else { return nil }
        let currentIndex = selectedTargetID.flatMap { id in
            targets.firstIndex(where: { $0.id == id })
        } ?? -1
        let nextIndex = min(max(0, currentIndex + delta), targets.count - 1)
        return targets[nextIndex].id
    }

    static func moveSelectionHorizontal(
        selectedTargetID: WindowHubTargetID?,
        columnTargets: [[WindowHubTarget]],
        delta: Int
    ) -> WindowHubTargetID? {
        guard columnTargets.count > 1 else {
            return moveSelection(
                selectedTargetID: selectedTargetID,
                in: columnTargets.flatMap { $0 },
                delta: delta
            )
        }
        guard let selectedTargetID else {
            return moveSelection(
                selectedTargetID: nil,
                in: columnTargets.flatMap { $0 },
                delta: delta > 0 ? 1 : -1
            )
        }

        guard let currentColumnIndex = columnTargets.firstIndex(where: { column in
            column.contains { $0.id == selectedTargetID }
        }) else {
            return moveSelection(
                selectedTargetID: selectedTargetID,
                in: columnTargets.flatMap { $0 },
                delta: delta > 0 ? 1 : -1
            )
        }

        let nextColumnIndex = currentColumnIndex + delta
        guard columnTargets.indices.contains(nextColumnIndex) else { return selectedTargetID }

        let currentColumn = columnTargets[currentColumnIndex]
        guard let currentRow = currentColumn.firstIndex(where: { $0.id == selectedTargetID }) else {
            return selectedTargetID
        }

        let neighborColumn = columnTargets[nextColumnIndex]
        guard !neighborColumn.isEmpty else { return selectedTargetID }

        let neighborRow = min(currentRow, neighborColumn.count - 1)
        return neighborColumn[neighborRow].id
    }
}
