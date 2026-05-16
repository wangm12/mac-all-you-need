import FeatureCore
import SwiftUI

struct FeaturesTabView: View {
    let controller: AppController
    @ObservedObject private var statePublisher: FeatureStatePublisher
    @State private var pendingUninstall: FeatureDescriptor?

    init(controller: AppController) {
        self.controller = controller
        self.statePublisher = controller.featureStatePublisher
    }

    var body: some View {
        MAYNSettingsPage(
            title: "Features",
            subtitle: "Enable or disable product features. Settings for each feature remain available even when disabled."
        ) {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(controller.runtime.registry.descriptors, id: \.id) { descriptor in
                        FeatureCardView(
                            descriptor: descriptor,
                            state: statePublisher.state(for: descriptor.id),
                            onAction: { handle($0, for: descriptor) }
                        )
                    }
                }
                .padding(20)
            }
        }
        .sheet(item: $pendingUninstall) { descriptor in
            UninstallConfirmationSheet(
                descriptor: descriptor,
                onCancel: { pendingUninstall = nil },
                onConfirm: { sheet in
                    pendingUninstall = nil
                    Task { await performUninstall(descriptor: descriptor, sheetState: sheet) }
                }
            )
        }
    }

    private func handle(_ action: FeatureCardView.Action, for descriptor: FeatureDescriptor) {
        switch action {
        case .install:
            // Wired in Phase 06 to the real PackDownloader.
            break
        case .enable:
            Task { try? await controller.runtime.applyTransition(.enable, for: descriptor.id) }
        case .disable:
            Task { try? await controller.runtime.applyTransition(.disable, for: descriptor.id) }
        case .uninstall:
            pendingUninstall = descriptor
        case .cancelDownload, .retryInstall:
            break  // Phase 06
        }
    }

    private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
        do {
            try Self.applyCacheSelections(sheetState, in: descriptor, cacheManager: FeatureCacheManager())
        } catch {
            // Surface as a banner in a future polish pass; for now the user can
            // see the directory still on disk and try again.
            NSLog("FeaturesTabView uninstall: cache deletion failed: \(error)")
        }
        try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
        // Phase 06 will additionally call PackUninstaller for asset features.
    }

    /// Static so tests can exercise cache deletion without instantiating SwiftUI.
    static func applyCacheSelections(
        _ sheetState: UninstallSheetState,
        in descriptor: FeatureDescriptor,
        cacheManager: FeatureCacheManager
    ) throws {
        try cacheManager.deleteCaches(sheetState.checkedCacheIDs, in: descriptor)
    }
}

extension FeatureDescriptor: Identifiable {}
