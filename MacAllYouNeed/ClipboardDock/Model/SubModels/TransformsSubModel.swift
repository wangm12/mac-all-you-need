import AppKit
import Core
import Foundation
import Platform

/// Text-transform slice extracted from `ClipboardDockModel`. Owns the actual
/// XPC transform dispatch for the currently focused or multi-selected cards
/// and sets/clears `pendingTransform` around the operation.
///
/// `pendingTransform` and `showTransformMenu` live on the facade so SwiftUI
/// bindings (`$model.showTransformMenu`, `model.pendingTransform` observation)
/// continue to track from the same observation registrar. This sub-model
/// mutates them via an `unowned` back reference.
@MainActor
final class TransformsSubModel {
    private unowned let model: ClipboardDockModel

    init(model: ClipboardDockModel) {
        self.model = model
    }

    func applyTransform(_ transform: TextTransform, saveAsNew: Bool) async {
        let targets: [String]
        if !model.selection.isEmpty {
            targets = model.items.map(\.id).filter { model.selection.contains($0) }
        } else if model.items.indices.contains(model.focusedIndex) {
            targets = [model.items[model.focusedIndex].id]
        } else {
            return
        }

        model.pendingTransform = transform
        for id in targets {
            _ = await model.xpc.transformAndCopy(
                itemID: id,
                transform: transform.rawValue,
                saveAsNew: saveAsNew
            )
        }
        model.pendingTransform = nil
        await model.refresh()
    }
}
