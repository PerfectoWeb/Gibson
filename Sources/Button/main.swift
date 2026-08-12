import AppKit

// Renders docs/images/download.png, the call to action at the top of the
// README. Drawn with the saver's own Canvas, Theme and Fonts, so the button
// looks like the thing it downloads. Transparent outside the plate, so it sits
// on either GitHub theme.
//
// Usage: button <output.png>

private let logical = CGSize(width: 460, height: 108)
private let theme = Theme(palette: .green)

private func draw(_ canvas: Canvas) {
    let plate = canvas.bounds.insetBy(dx: 6, dy: 6)
    let radius: CGFloat = 10

    canvas.fillRounded(plate, radius, theme.panelFill)
    canvas.strokeRounded(plate, radius, theme.accent, width: 2)
    canvas.brackets(plate.insetBy(dx: -4, dy: -4), theme.accent, length: 14, width: 2)

    let title = Fonts.mono(23, bold: true)
    let caption = Fonts.mono(11.5)
    let titleText = "DOWNLOAD"
    let captionText = "MACOS 14+ \u{00B7} UNIVERSAL \u{00B7} FREE"

    // Monospace, so the run width is the advance times the count plus the
    // tracking between them. Measured rather than guessed, because the whole
    // group is centred and a wrong width shows up as a lopsided button.
    func runWidth(_ text: String, _ font: CTFont, tracking: CGFloat) -> CGFloat {
        CGFloat(text.count) * Fonts.advance(font) + CGFloat(text.count - 1) * tracking
    }

    let titleWidth = runWidth(titleText, title, tracking: 3)
    let captionWidth = runWidth(captionText, caption, tracking: 1.6)
    let textWidth = max(titleWidth, captionWidth)
    let iconWidth: CGFloat = 40
    let gap: CGFloat = 26
    let groupLeft = (plate.midX - (iconWidth + gap + textWidth) / 2).rounded()

    // Download glyph: a stem, a head and the tray it lands in.
    let icon = CGRect(x: groupLeft, y: plate.midY - 21, width: iconWidth, height: 42)
    let stemX = icon.midX
    canvas.line(CGPoint(x: stemX, y: icon.minY + 1), CGPoint(x: stemX, y: icon.minY + 24),
                theme.accent, width: 3)
    canvas.polyline([CGPoint(x: stemX - 11, y: icon.minY + 14),
                     CGPoint(x: stemX, y: icon.minY + 26),
                     CGPoint(x: stemX + 11, y: icon.minY + 14)], theme.accent, width: 3)
    canvas.polyline([CGPoint(x: icon.minX + 2, y: icon.maxY - 12),
                     CGPoint(x: icon.minX + 2, y: icon.maxY - 2),
                     CGPoint(x: icon.maxX - 2, y: icon.maxY - 2),
                     CGPoint(x: icon.maxX - 2, y: icon.maxY - 12)], theme.accent, width: 3)

    let textLeft = icon.maxX + gap
    canvas.text(titleText, at: CGPoint(x: textLeft + (textWidth - titleWidth) / 2, y: plate.midY - 4),
                font: title, color: theme.accent, tracking: 3)
    canvas.text(captionText,
                at: CGPoint(x: textLeft + (textWidth - captionWidth) / 2, y: plate.midY + 22),
                font: caption, color: theme.fade(theme.mid, 0.9), tracking: 1.6)

    canvas.withState { canvas in
        canvas.clipRounded(plate, radius)
        var y = plate.minY
        while y < plate.maxY {
            canvas.fill(CGRect(x: plate.minX, y: y, width: plate.width, height: 1),
                        CGColor(gray: 0, alpha: 0.24))
            y += 3
        }
    }
}

private func render(scale: CGFloat) -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil,
                              width: Int(logical.width * scale), height: Int(logical.height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    draw(Canvas(ctx: ctx, size: logical))
    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images/download.png"
guard let data = render(scale: 2) else { exit(1) }
try? FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try? data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
