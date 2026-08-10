import AppKit

// Renders Resources/thumbnail.png, the tile System Settings shows in the
// screen saver picker. Deterministic: no metrics, no randomness beyond a fixed
// hash, so rebuilding does not produce a different image.

// Usage: cover [output.png] [width height]
//
// Without a size it draws the picker tile and its @2x twin. With one it draws
// a single image, which is how the repository social preview is made.

/// The picker draws its tiles at roughly 1.65:1 and scales to fill, so artwork
/// in 16:9 loses a slice off each side. Matching that shape means nothing is
/// cropped there, and a host that wants 16:9 only trims a little off the top
/// and bottom, which the margins below absorb.
private let arguments = CommandLine.arguments
private let custom: CGSize? = {
    guard arguments.count > 3, let width = Double(arguments[2]),
          let height = Double(arguments[3]) else { return nil }
    return CGSize(width: width, height: height)
}()
private let logical = custom ?? CGSize(width: 640, height: 389)

private func render(scale: CGFloat) -> Data? {
    let pixels = CGSize(width: logical.width * scale, height: logical.height * scale)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil,
                              width: Int(pixels.width), height: Int(pixels.height),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.scaleBy(x: scale, y: scale)

    draw(Canvas(ctx: ctx, size: logical))

    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

private func draw(_ canvas: Canvas) {
    let theme = Theme(palette: .green)
    let bounds = canvas.bounds

    canvas.fill(bounds, CGColor(red: 0, green: 0.012, blue: 0.008, alpha: 1))

    // One window, drawn with the chrome the dashboard uses, so the tile reads
    // as a piece of what gets installed.
    //
    // Equal margins all round, with extra on the sides: the picker scales the
    // tile to fill and trims horizontally, and how much varies, so the frame
    // needs room to survive it.
    let margin = (bounds.height * 0.105).rounded()
    let panel = bounds.insetBy(dx: margin + bounds.width * 0.055, dy: margin)
    let radius = bounds.height * 0.022

    canvas.fillRounded(panel, radius, theme.panelFill)

    // Title bar: label on the left, window controls on the right.
    let barHeight = (bounds.height * 0.072).rounded()
    let bar = CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: barHeight)
    canvas.withState { canvas in
        canvas.clipRounded(panel, radius)
        canvas.fill(bar, theme.fade(theme.border, 0.4))
    }
    canvas.line(CGPoint(x: bar.minX, y: bar.maxY), CGPoint(x: bar.maxX, y: bar.maxY), theme.border)

    let titleFont = Fonts.mono((barHeight * 0.42).clamped(6, 12), bold: true)
    canvas.text("gibson@localhost: ~/telemetry",
                at: CGPoint(x: bar.minX + barHeight * 0.55,
                            y: bar.midY + CTFontGetCapHeight(titleFont) / 2),
                font: titleFont, color: theme.fade(theme.mid, 0.9), tracking: 0.8)

    let control = (barHeight * 0.4).rounded()
    var controlX = bar.maxX - barHeight * 0.55 - control
    // Drawn right to left, so they read minimise, zoom, close.
    for glyph in [0, 1, 2] {
        let box = CGRect(x: controlX, y: bar.midY - control / 2, width: control, height: control)
        canvas.stroke(box, theme.fade(theme.mid, 0.8))
        let inner = box.insetBy(dx: control * 0.28, dy: control * 0.28)
        switch glyph {
        case 0:  // close
            canvas.line(CGPoint(x: inner.minX, y: inner.minY),
                        CGPoint(x: inner.maxX, y: inner.maxY), theme.mid)
            canvas.line(CGPoint(x: inner.maxX, y: inner.minY),
                        CGPoint(x: inner.minX, y: inner.maxY), theme.mid)
        case 1:  // zoom
            canvas.stroke(inner, theme.mid)
        default: // minimise
            canvas.line(CGPoint(x: inner.minX, y: inner.midY),
                        CGPoint(x: inner.maxX, y: inner.midY), theme.mid)
        }
        controlX -= control * 1.7
    }

    canvas.strokeRounded(panel, radius, theme.border, width: 1.5)

    // Wordmark.
    let pixel = (bounds.height * 0.016).rounded()
    let spacing = pixel * 1.6
    let wordWidth = PixelFont.width("GIBSON", face: PixelFont.bold, pixel: pixel,
                                    letterSpacing: spacing)
    let logoHeight = PixelFont.height(face: PixelFont.bold, pixel: pixel)
    let captionHeight = PixelFont.height(face: PixelFont.thin, pixel: 2)
    let gap = logoHeight * 0.5
    // Centre the pair in the window body, below the title bar.
    let body = CGRect(x: panel.minX, y: bar.maxY, width: panel.width, height: panel.maxY - bar.maxY)
    let logoTop = (body.midY - (logoHeight + gap + captionHeight) / 2).rounded()
    let wordLeft = (panel.midX - wordWidth / 2).rounded()

    PixelFont.draw("GIBSON", face: PixelFont.bold, in: canvas,
                   at: CGPoint(x: wordLeft + 2, y: logoTop + 2),
                   pixel: pixel, letterSpacing: spacing, color: theme.fade(theme.dim, 0.45))
    PixelFont.draw("GIBSON", face: PixelFont.bold, in: canvas,
                   at: CGPoint(x: wordLeft, y: logoTop),
                   pixel: pixel, letterSpacing: spacing, color: theme.accent)

    // Caption, tracked out until it measures exactly as wide as the wordmark.
    let caption = "LIVE SYSTEM TELEMETRY"
    let captionPixel: CGFloat = 2
    let glyphs = CGFloat(caption.count)
    let captionSpacing = (wordWidth - glyphs * CGFloat(PixelFont.thin.cellWidth) * captionPixel)
        / (glyphs - 1)
    let captionTop = (logoTop + logoHeight + gap).rounded()
    PixelFont.draw(caption, face: PixelFont.thin, in: canvas,
                   at: CGPoint(x: wordLeft, y: captionTop),
                   pixel: captionPixel, letterSpacing: captionSpacing,
                   color: theme.fade(theme.mid, 0.95))

    // Scanlines last, so they sit over the panel as well.
    var y: CGFloat = 0
    while y < bounds.height {
        canvas.fill(CGRect(x: 0, y: y, width: bounds.width, height: 1), CGColor(gray: 0, alpha: 0.3))
        y += 3
    }
}

let output = arguments.count > 1 ? arguments[1] : "Resources/thumbnail.png"
let base = URL(fileURLWithPath: output)

try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
guard let standard = render(scale: 1) else { exit(1) }
try? standard.write(to: base)

guard custom == nil else {
    print("wrote \(base.path)")
    exit(0)
}

let retina = base.deletingLastPathComponent()
    .appendingPathComponent(base.deletingPathExtension().lastPathComponent + "@2x.png")
guard let doubled = render(scale: 2) else { exit(1) }
try? doubled.write(to: retina)
print("wrote \(base.path) and \(retina.lastPathComponent)")
