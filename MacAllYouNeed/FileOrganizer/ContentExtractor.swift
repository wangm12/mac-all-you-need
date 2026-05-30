import Core
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Routes files to the appropriate extraction strategy (Vision OCR, PDFKit, plain text).
actor ContentExtractor {
    static let shared = ContentExtractor()
    static let snippetMaxLength = 500

    func extract(from url: URL) async -> ExtractedContent {
        let ext = url.pathExtension.lowercased()
        let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"

        if let pdfContent = extractPDF(from: url) { return pdfContent }
        if let textContent = extractText(from: url) { return textContent }
        if let imageContent = extractImage(from: url) { return imageContent }

        return ExtractedContent(originalURL: url, utTypeIdentifier: uti, kind: .unknown, snippet: "")
    }

    private func extractPDF(from url: URL) -> ExtractedContent? {
        guard let pdf = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<min(pdf.pageCount, 3) {
            text += pdf.page(at: i)?.string ?? ""
        }
        let snippet = String(text.prefix(ContentExtractor.snippetMaxLength))
        return ExtractedContent(
            originalURL: url,
            utTypeIdentifier: "com.adobe.pdf",
            kind: .pdf,
            snippet: snippet,
            metadata: ["pageCount": "\(pdf.pageCount)"]
        )
    }

    private func extractText(from url: URL) -> ExtractedContent? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let snippet = String(content.prefix(ContentExtractor.snippetMaxLength))
        return ExtractedContent(originalURL: url, utTypeIdentifier: "public.plain-text", kind: .text, snippet: snippet)
    }

    private func extractImage(from url: URL) -> ExtractedContent? {
        guard let cgImageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, nil) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        let text = (request.results as? [VNRecognizedTextObservation])?.compactMap {
            $0.topCandidates(1).first?.string
        }.joined(separator: " ") ?? ""

        let snippet = String(text.prefix(ContentExtractor.snippetMaxLength))
        let metadata = ["width": "\(cgImage.width)", "height": "\(cgImage.height)"]
        return ExtractedContent(originalURL: url, utTypeIdentifier: "public.image", kind: .image, snippet: snippet, metadata: metadata)
    }
}
