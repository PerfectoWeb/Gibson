import CoreGraphics
import CoreImage
import Foundation

/// QR module grid, built with CoreImage. No third party dependency, and the
/// payload never changes while the saver runs, so one generation is enough.
enum QRCode {
    /// Where the support code points. Forks should change this one line.
    static let supportURL = "https://perfecto-web.com/d/"

    private static var cache: [String: [[Bool]]] = [:]

    /// Rows top to bottom, `true` for a dark module. Includes the quiet zone
    /// CIQRCodeGenerator adds around the symbol.
    static func modules(for string: String) -> [[Bool]]? {
        if let cached = cache[string] { return cached }
        guard let grid = generate(string) else { return nil }
        cache[string] = grid
        return grid
    }

    private static func generate(_ string: String) -> [[Bool]]? {
        guard let payload = string.data(using: .isoLatin1),
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }
        filter.setValue(payload, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }
        let width = Int(output.extent.width)
        let height = Int(output.extent.height)
        guard width > 0, height > 0 else { return nil }

        guard let image = CIContext(options: [.useSoftwareRenderer: true])
            .createCGImage(output, from: output.extent)
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let ctx = CGContext(data: base, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // The bitmap origin is bottom left, the canvas draws top down.
        return (0 ..< height).map { row in
            let offset = (height - 1 - row) * width
            return (0 ..< width).map { pixels[offset + $0] < 128 }
        }
    }

    /// Draws the symbol centred in `rect`. Polarity is up to the caller: the
    /// rain panel runs it inverted, bright modules on black, so it reads as part
    /// of the panel rather than as a sticker on top of it.
    static func draw(_ modules: [[Bool]], in rect: CGRect, canvas: Canvas,
                     background: CGColor, module moduleColor: CGColor) {
        let count = modules.count
        guard count > 0, let columns = modules.first?.count, columns > 0 else { return }

        // Two extra modules of light margin: CIQRCodeGenerator only leaves one,
        // and scanners want a quiet zone.
        let margin: CGFloat = 2
        let module = (min(rect.width, rect.height)
            / (CGFloat(max(count, columns)) + margin * 2)).rounded(.down)
        guard module >= 1 else { return }
        let size = module * CGFloat(count)
        let origin = CGPoint(x: (rect.midX - size / 2).rounded(),
                             y: (rect.midY - size / 2).rounded())

        canvas.fill(CGRect(x: origin.x - module * margin, y: origin.y - module * margin,
                           width: size + module * margin * 2,
                           height: size + module * margin * 2), background)
        for (row, line) in modules.enumerated() {
            for (column, isSet) in line.enumerated() where isSet {
                canvas.fill(CGRect(x: origin.x + CGFloat(column) * module,
                                   y: origin.y + CGFloat(row) * module,
                                   width: module, height: module), moduleColor)
            }
        }
    }
}
