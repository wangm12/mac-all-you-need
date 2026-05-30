import AppKit
import Foundation
import Vision

/// Main-app Vision OCR wrapper used by the clipboard enrichment coordinator to
/// index text inside captured images for search. Distinct from the daemon's
/// capture-time `OCRService`; this one runs lazily in the background on records
/// the daemon already stored.
actor ImageOCRService {
    static let shared = ImageOCRService()
    static let maxLongestSide = 8192

    /// Clamp the requested longest-side dimension to the Vision-safe cap.
    static func downsampledMaxDimension(forLongestSide side: Int) -> Int {
        min(side, maxLongestSide)
    }

    func recognize(cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try? handler.perform([request])
            let text = (request.results as? [VNRecognizedTextObservation])?.compactMap {
                $0.topCandidates(1).first?.string
            }.joined(separator: "\n") ?? ""
            continuation.resume(returning: text.isEmpty ? nil : text)
        }
    }
}
