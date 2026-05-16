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
            Task {
                try? await controller.packInstallController.install(featureID: descriptor.id)
                await controller.featureStatePublisher.refresh()
            }
        case .enable:
            Task { try? await controller.runtime.applyTransition(.enable, for: descriptor.id) }
        case .disable:
            Task { try? await controller.runtime.applyTransition(.disable, for: descriptor.id) }
        case .uninstall:
            pendingUninstall = descriptor
        case .cancelDownload:
            Task { await controller.packInstallController.cancel(featureID: descriptor.id) }
        case .retryInstall:
            Task {
                try? await controller.packInstallController.install(featureID: descriptor.id)
                await controller.featureStatePublisher.refresh()
            }
        }
    }

    private func performUninstall(descriptor: FeatureDescriptor, sheetState: UninstallSheetState) async {
        for cacheID in sheetState.checkedCacheIDs {
            if let cache = descriptor.assetCaches.first(where: { $0.id == cacheID }) {
                try? FileManager.default.removeItem(at: cache.directoryURL())
            }
        }
        try? await controller.runtime.applyTransition(.disable, for: descriptor.id)
        if descriptor.requiresAsset {
            try? await controller.packInstallController.uninstall(featureID: descriptor.id)
        }
        await controller.featureStatePublisher.refresh()
    }
}

extension FeatureDescriptor: Identifiable {}
