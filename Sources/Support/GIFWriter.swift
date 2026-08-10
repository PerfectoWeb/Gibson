import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Writes an animated GIF with ImageIO. Used by the artwork tools, not by the
/// screen saver itself.
enum GIFWriter {
    static func write(_ frames: [CGImage], to path: String, frameDuration: Double) -> Bool {
        guard !frames.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { return false }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDuration,
                kCGImagePropertyGIFUnclampedDelayTime: frameDuration
            ]
        ] as CFDictionary

        for frame in frames {
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// A bitmap context sized in pixels, with the canvas working in points.
    static func context(size: CGSize, scale: CGFloat) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: Int(size.width * scale),
                                  height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        return ctx
    }
}
