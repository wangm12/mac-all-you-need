import AppKit
import Foundation
import Vision

public enum OCRError: Error {
    case invalidImage
    case requestFailed(Error)
}

public enum OCRService {
    public static func recognize(pngData: Data) async throws -> String {
        guard let image = NSImage(data: pngData),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw OCRError.invalidImage }
        return try await recognize(cgImage: cg)
    }

    public static func recognize(cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: OCRError.requestFailed(err)); return }
                let lines = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do { try handler.perform([request]) } catch { cont.resume(throwing: OCRError.requestFailed(error)) }
        }
    }
}
