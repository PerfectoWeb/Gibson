import AppKit

// Renders the call to action at the top of the README, in a dark and a light
// variant so GitHub can pick the one that matches the reader's theme. Drawn
// with the saver's own Canvas and Fonts, so the button looks like the thing it
// downloads. Transparent outside the plate.
//
// Usage: button <output-dark.png> <output-light.png>

private let logical = CGSize(width: 460, height: 108)
private let theme = Theme(palette: .green)

/// The saver only ever renders on black, so the light variant cannot come off
/// the ladder in `Theme`. These are the same hue taken the other way: a pale
/// plate with the ink dark enough to hold contrast on a white page.
private struct Scheme {
    let plate: CGColor
    let ink: CGColor
    let caption: CGColor
    let scanline: CGFloat

    static let dark = Scheme(plate: theme.panelFill, ink: theme.accent,
                             caption: theme.fade(theme.mid, 0.9), scanline: 0.24)

    static let light = Scheme(plate: CGColor(red: 0.945, green: 0.980, blue: 0.957, alpha: 1),
                              ink: CGColor(red: 0.043, green: 0.310, blue: 0.153, alpha: 1),
                              caption: CGColor(red: 0.129, green: 0.478, blue: 0.271, alpha: 1),
                              scanline: 0.05)
}

private func draw(_ canvas: Canvas, _ scheme: Scheme) {
    let plate = canvas.bounds.insetBy(dx: 6, dy: 6)
    let radius: CGFloat = 10

    canvas.fillRounded(plate, radius, scheme.plate)
    canvas.strokeRounded(plate, radius, scheme.ink, width: 2)
    canvas.brackets(plate.insetBy(dx: -4, dy: -4), scheme.ink, length: 14, width: 2)

    let title = Fonts.mono(28, bold: true)
    let caption = Fonts.mono(11.5)
    let titleText = "DOWNLOAD"
    let captionText = "MACOS 14+ \u{00B7} UNIVERSAL \u{00B7} FREE"

    // Monospace, so a run is the advance times the count plus the tracking
    // between the glyphs. Measured rather than guessed, because the group is
    // centred and a wrong width shows up as a lopsided button.
    func runWidth(_ text: String, _ font: CTFont, tracking: CGFloat) -> CGFloat {
        CGFloat(text.count) * Fonts.advance(font) + CGFloat(text.count - 1) * tracking
    }

    let titleWidth = runWidth(titleText, title, tracking: 3)
    let captionWidth = runWidth(captionText, caption, tracking: 1.6)
    let textWidth = max(titleWidth, captionWidth)
    let iconWidth: CGFloat = 40
    let gap: CGFloat = 24
    let groupLeft = (plate.midX - (iconWidth + gap + textWidth) / 2).rounded()

    // Download glyph: a stem, a head and the tray it lands in.
    let icon = CGRect(x: groupLeft, y: plate.midY - 21, width: iconWidth, height: 42)
    let stemX = icon.midX
    canvas.line(CGPoint(x: stemX, y: icon.minY + 1), CGPoint(x: stemX, y: icon.minY + 24),
                scheme.ink, width: 3)
    canvas.polyline([CGPoint(x: stemX - 11, y: icon.minY + 14),
                     CGPoint(x: stemX, y: icon.minY + 26),
                     CGPoint(x: stemX + 11, y: icon.minY + 14)], scheme.ink, width: 3)
    canvas.polyline([CGPoint(x: icon.minX + 2, y: icon.maxY - 12),
                     CGPoint(x: icon.minX + 2, y: icon.maxY - 2),
                     CGPoint(x: icon.maxX - 2, y: icon.maxY - 2),
                     CGPoint(x: icon.maxX - 2, y: icon.maxY - 12)], scheme.ink, width: 3)

    // Both lines start on the same edge, one gap away from the glyph.
    let textLeft = (icon.maxX + gap).rounded()
    canvas.text(titleText, at: CGPoint(x: textLeft, y: plate.midY - 3),
                font: title, color: scheme.ink, tracking: 3)
    canvas.text(captionText, at: CGPoint(x: textLeft, y: plate.midY + 24),
                font: caption, color: scheme.caption, tracking: 1.6)

    canvas.withState { canvas in
        canvas.clipRounded(plate, radius)
        var y = plate.minY
        while y < plate.maxY {
            canvas.fill(CGRect(x: plate.minX, y: y, width: plate.width, height: 1),
                        CGColor(gray: 0, alpha: scheme.scanline))
            y += 3
        }
    }
}

private func render(_ scheme: Scheme, scale: CGFloat) -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil,
                              width: Int(logical.width * scale), height: Int(logical.height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    draw(Canvas(ctx: ctx, size: logical), scheme)
    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

private let arguments = CommandLine.arguments
private let darkPath = arguments.count > 1 ? arguments[1] : "docs/images/download-dark.png"
private let lightPath = arguments.count > 2 ? arguments[2] : "docs/images/download-light.png"

for (path, scheme) in [(darkPath, Scheme.dark), (lightPath, Scheme.light)] {
    guard let data = render(scheme, scale: 2) else { exit(1) }
    try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try? data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
