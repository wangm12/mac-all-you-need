import AppKit
import Foundation

/// Extracts a single representative color from an NSImage (typically an app
/// icon) so it can be used as a tinted header background.
///
/// Implementation: rasterize the icon to a tiny bitmap (32×32 RGBA) and
/// average the non-transparent pixels in pure Swift. CIAreaAverage was the
/// previous approach but had ~50ms first-call overhead from CIContext +
/// CIFilter setup, which made app icons appear gray for a noticeable
/// moment after the dock opened. Direct averaging runs in <1ms — fast
/// enough to call synchronously from SwiftUI body. Cached by NSImage
/// identity since icons are stable per-app.
enum AppIconColor {
    private static let cache = NSCache<NSImage, NSColor>()

    /// Synchronous lookup — checks cache first, then computes on the spot.
    /// At 32×32 the average pass is well under a millisecond on Apple
    /// Silicon, comparable to a single SwiftUI text layout pass.
    static func dominant(of image: NSImage) -> NSColor? {
        if let cached = cache.object(forKey: image) { return cached }
        guard let color = computeDominant(of: image, saturatedOnly: true)
            ?? computeDominant(of: image, saturatedOnly: false)
        else { return nil }
        cache.setObject(color, forKey: image)
        return color
    }

    private static func computeDominant(of image: NSImage, saturatedOnly: Bool) -> NSColor? {
        let target = 32
        let width = target
        let height = target
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Re-rasterize the NSImage at the target size. Use cgImage(forProposedRect:)
        // so vector / multi-rep icons pick the rep nearest to 32×32.
        var proposedRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cg = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        context.interpolationQuality = .low
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sum the saturated, non-transparent pixels. Greyscale and almost-
        // transparent pixels are skipped so the average isn't dragged
        // toward dead-grey by icon padding.
        var sumR: UInt64 = 0
        var sumG: UInt64 = 0
        var sumB: UInt64 = 0
        var counted: UInt64 = 0
        let stride = 4
        for i in Swift.stride(from: 0, to: pixels.count, by: stride) {
            let a = pixels[i + 3]
            if a < 64 { continue } // skip near-transparent
            let r = pixels[i]
            let g = pixels[i + 1]
            let b = pixels[i + 2]
            if saturatedOnly {
                // Skip near-grayscale pixels so the average reflects branded
                // color, not the white/grey background.
                let mn = min(r, g, b)
                let mx = max(r, g, b)
                if mx - mn < 12 { continue }
            }
            sumR += UInt64(r)
            sumG += UInt64(g)
            sumB += UInt64(b)
            counted += 1
        }

        guard counted > 0 else { return nil }
        let avgR = CGFloat(sumR / counted) / 255
        let avgG = CGFloat(sumG / counted) / 255
        let avgB = CGFloat(sumB / counted) / 255
        return NSColor(srgbRed: avgR, green: avgG, blue: avgB, alpha: 1.0)
    }
}
