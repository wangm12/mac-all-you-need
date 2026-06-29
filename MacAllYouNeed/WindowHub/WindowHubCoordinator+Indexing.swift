import AppKit
import Foundation

@MainActor
extension WindowHubCoordinator {
    func mergeStreamedSection(_ section: WindowHubAppSection, streamPhase: WindowHubIndexingPhase) {
        refreshEnumeratedPIDs.insert(section.pid)

        var sections = snapshot.sections
        if streamPhase != .shell, !droppedStaleSections {
            sections = sections.filter { refreshEnumeratedPIDs.contains($0.pid) }
            droppedStaleSections = true
        }
        WindowHubSectionMerger.upsert(section, into: &sections)
        sections = WindowHubSectionMerger.sorted(sections, frontPID: frontPID)
        let flatTargets = WindowHubSectionMerger.flatTargets(from: sections)
        if streamPhase != .shell {
            loadingPIDs.remove(section.pid)
        }

        let snapshotPhase: WindowHubIndexingPhase = switch streamPhase {
        case .shell: .shell
        case .complete: .complete
        default: .incremental
        }

        replaceSnapshot(WindowHubSnapshot(
            capturedAt: Date(),
            phase: snapshotPhase,
            currentTargetID: snapshot.currentTargetID,
            sections: sections,
            flatTargets: flatTargets,
            timedOutProviders: snapshot.timedOutProviders
        ))
    }

    func applyBuiltSnapshot(_ built: WindowHubSnapshot, settings: WindowHubSettings) {
        replaceSnapshot(canonicalSnapshot(from: built))
        loadingPIDs = loadingPIDs.filter { pid in
            NSRunningApplication(processIdentifier: pid) != nil
        }
        loadingPIDs = loadingPIDs.intersection(refreshEnumeratedPIDs)
        reconcileLoadingAfterFullPass(settings: settings)
        syncSelectionToNavigableTargets()
    }

    func canonicalSnapshot(from built: WindowHubSnapshot) -> WindowHubSnapshot {
        WindowHubSnapshot(
            capturedAt: built.capturedAt,
            phase: built.phase,
            currentTargetID: built.currentTargetID,
            sections: built.sections,
            flatTargets: WindowHubSectionMerger.flatTargets(from: built.sections),
            timedOutProviders: built.timedOutProviders
        )
    }

    func reconcileLoadingAfterFullPass(settings: WindowHubSettings) {
        loadingPIDs = loadingPIDs.filter { pid in
            NSRunningApplication(processIdentifier: pid) != nil
        }
        guard settings.browserTabDiscoveryEnabled else {
            loadingPIDs = []
            return
        }
        let chromiumPIDs = snapshot.sections.compactMap { section -> pid_t? in
            guard BrowserAppleScriptTabReader.isChromium(section.bundleIdentifier) else { return nil }
            return section.pid
        }
        loadingPIDs = Set(chromiumPIDs)
    }

    func runChromiumJXAUpgrade(settings: WindowHubSettings) async {
        let chromiumPIDs = snapshot.sections.compactMap { section -> pid_t? in
            guard BrowserAppleScriptTabReader.isChromium(section.bundleIdentifier) else { return nil }
            return section.pid
        }
        guard !chromiumPIDs.isEmpty else {
            loadingPIDs = []
            return
        }

        await WindowHubEnumerator.upgradeChromiumApps(settings: settings, pids: chromiumPIDs) { section, streamPhase in
            await self.mergeStreamedSection(section, streamPhase: streamPhase)
        }

        loadingPIDs = []
        replaceSnapshot(canonicalSnapshot(
            from: WindowHubSnapshot(
                capturedAt: Date(),
                phase: .complete,
                currentTargetID: snapshot.currentTargetID,
                sections: snapshot.sections,
                flatTargets: snapshot.flatTargets,
                timedOutProviders: snapshot.timedOutProviders
            )
        ))
    }

    func persistSnapshot() {
        let cached = WindowHubCachedSnapshot(
            capturedAt: snapshot.capturedAt,
            currentTargetID: snapshot.currentTargetID,
            sections: snapshot.sections
        )
        WindowHubSnapshotCache.save(cached)
    }
}
