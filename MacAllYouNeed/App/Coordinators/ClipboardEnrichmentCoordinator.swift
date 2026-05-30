import AppKit
import Core
import FeatureCore
import Foundation

/// Background enrichment of stored clipboard records for Smart Text search:
/// computes Apple `NLEmbedding` vectors for semantic ranking and Vision OCR for
/// image records. Runs in small batches off the main work, gated on the
/// `clipboardSmartText` feature being enabled. Injected closures keep the core
/// loop unit-testable without real Vision / NaturalLanguage / store dependencies.
@MainActor
final class ClipboardEnrichmentCoordinator {
    private let clip: ClipboardStore
    /// Embed a record's text → vector. Nil when embedding is unavailable.
    private let embed: (String) async -> [Float]?
    /// OCR a record's image → text. Nil when no text / unavailable.
    private let ocr: (CGImage) async -> String?
    /// Resolve a record id to its decoded CGImage (encrypted blob → image).
    private let imageProvider: (RecordID) async -> CGImage?
    /// Index OCR text into the search store so it participates in FTS search.
    private let indexSearchText: (RecordID, String) -> Void
    private let isEnabled: () -> Bool
    private let isSemanticEnabled: () -> Bool
    private let isOCREnabled: () -> Bool

    private var timer: Timer?
    private var running = false

    init(
        clip: ClipboardStore,
        embed: @escaping (String) async -> [Float]?,
        ocr: @escaping (CGImage) async -> String?,
        imageProvider: @escaping (RecordID) async -> CGImage? = { _ in nil },
        indexSearchText: @escaping (RecordID, String) -> Void = { _, _ in },
        isEnabled: @escaping () -> Bool = {
            FeatureStateReader.read(for: .clipboardSmartText, defaults: AppGroupSettings.defaults)
                .activationState == .enabled
        },
        isSemanticEnabled: @escaping () -> Bool = { SmartTextSettings.semanticEnabled() },
        isOCREnabled: @escaping () -> Bool = { SmartTextSettings.ocrEnabled() }
    ) {
        self.clip = clip
        self.embed = embed
        self.ocr = ocr
        self.imageProvider = imageProvider
        self.indexSearchText = indexSearchText
        self.isEnabled = isEnabled
        self.isSemanticEnabled = isSemanticEnabled
        self.isOCREnabled = isOCREnabled
    }

    /// Process up to `limit` records of each enrichment kind. Safe to call
    /// repeatedly; no-ops when the feature is disabled.
    func runOneBatch(limit: Int) async {
        guard isEnabled() else { return }

        if isSemanticEnabled() {
            let missing = (try? clip.idsMissingEmbedding(limit: limit)) ?? []
            for id in missing {
                guard let meta = try? clip.meta(for: id) else { continue }
                let text = meta.ocrText ?? meta.preview
                guard !text.isEmpty, let vec = await embed(text) else { continue }
                try? clip.setEmbedding(id: id, blob: ClipEmbeddingService.encode(vec))
                await Task.yield()
            }
        }

        if isOCREnabled() {
            let missing = (try? clip.idsMissingOCR(limit: limit)) ?? []
            for id in missing {
                guard let image = await imageProvider(id) else { continue }
                let text = await ocr(image) ?? ""
                // Persist even an empty result so we don't re-OCR the same image.
                try? clip.setOCRText(id: id, text: text)
                if !text.isEmpty { indexSearchText(id, text) }
                await Task.yield()
            }
        }
    }

    /// Begin periodic enrichment. Subsequent calls are ignored while running.
    func start(interval: TimeInterval = 30, batchLimit: Int = 20) {
        guard !running else { return }
        running = true
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runOneBatch(limit: batchLimit) }
        }
        timer.tolerance = interval * 0.2
        self.timer = timer
        // Kick off an immediate first pass instead of waiting a full interval.
        Task { @MainActor in await runOneBatch(limit: batchLimit) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        running = false
    }
}
