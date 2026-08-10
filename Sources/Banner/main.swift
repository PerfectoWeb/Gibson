import AppKit

// Renders docs/images/banner.gif, the animated header of the README: a terminal
// window in which the wordmark resolves out of falling digits, hands over to a
// pair of typed captions and comes back. The rain never stops and the last
// frame lands exactly on the first, so the loop has no seam. The area around
// the window is transparent, so the banner sits on either GitHub theme.
//
// Usage: banner <output.gif>

private let size = CGSize(width: 1000, height: 290)
private let frameCount = 64
private let frameDuration = 0.1
private let loopLength = Double(frameCount) * frameDuration

private let theme = Theme(palette: .green)
private let margin: CGFloat = 10
private let radius: CGFloat = 9

private let window = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
private let barHeight: CGFloat = 30
private let bar = CGRect(x: window.minX, y: window.minY, width: window.width, height: barHeight)
private let body = CGRect(x: window.minX, y: bar.maxY,
                          width: window.width, height: window.maxY - bar.maxY)

// MARK: - Script

/// A line that types itself, sits for a beat under a blinking cursor and is
/// wiped again. Times are on the loop clock, in seconds.
private struct Caption {
    let text: String
    let start: Double
    let hold: Double

    var typeRate: Double { 0.04 }
    var eraseRate: Double { 0.012 }
    var full: Double { start + typeRate * Double(text.count) }
    var end: Double { full + hold + eraseRate * Double(text.count) }

    /// Characters on screen, or nil when the line is not up yet or already gone.
    func visible(at time: Double) -> Int? {
        guard time >= start, time < end else { return nil }
        if time < full { return Int((time - start) / typeRate) }
        if time < full + hold { return text.count }
        return text.count - Int((time - full - hold) / eraseRate)
    }
}

private let captions = [
    Caption(text: "LIVE SYSTEM TELEMETRY", start: 1.75, hold: 0.75),
    Caption(text: "MACOS SCREEN SAVER", start: 3.75, hold: 0.75)
]

// The wordmark is whole at t = 0, so the tail of the loop has to put it back.
private let dissolveStart = 1.1
private let dissolveLength = 0.5
private let assembleStart = 5.65
private let assembleLength = 0.65

// MARK: - Geometry

private let pixel: CGFloat = 6
private let letterSpacing = pixel * 1.6
private let markWidth = PixelFont.width("GIBSON", face: PixelFont.bold,
                                        pixel: pixel, letterSpacing: letterSpacing)
private let markHeight = PixelFont.height(face: PixelFont.bold, pixel: pixel)
private let markLeft = (body.midX - markWidth / 2).rounded()
private let markTop = (body.midY - markHeight / 2).rounded()

private let captionPixel: CGFloat = 4
private let captionSpacing = captionPixel * 1.5
private let captionHeight = PixelFont.height(face: PixelFont.thin, pixel: captionPixel)
private let captionTop = (body.midY - captionHeight / 2).rounded()

/// Rectangles of every lit dot in the wordmark, in the order they are drawn.
private let markDots: [CGRect] = {
    var rects: [CGRect] = []
    var x = markLeft
    for character in "GIBSON" {
        guard let rows = PixelFont.bold.glyphs[character] else { continue }
        for (row, line) in rows.enumerated() {
            for (column, mark) in line.enumerated() where mark == "#" {
                rects.append(CGRect(x: x + CGFloat(column) * pixel,
                                    y: markTop + CGFloat(row) * pixel,
                                    width: pixel, height: pixel))
            }
        }
        x += CGFloat(PixelFont.bold.cellWidth) * pixel + letterSpacing
    }
    return rects
}()

/// Order in which dots light up and go out. Random but fixed, so the shape
/// resolves out of the rain instead of fading in as a block.
private let dotOrder: [CGFloat] = markDots.indices.map { hashUnit(UInt64($0) &* 7717) }

// MARK: - Frame

private func draw(frame index: Int, in canvas: Canvas) {
    let time = Double(index) * frameDuration

    canvas.fillRounded(window, radius, theme.panelFill)

    canvas.withState { canvas in
        canvas.clipRounded(window, radius)
        canvas.fill(bar, theme.fade(theme.border, 0.4))
    }
    canvas.line(CGPoint(x: bar.minX, y: bar.maxY), CGPoint(x: bar.maxX, y: bar.maxY), theme.border)

    let titleFont = Fonts.mono(12, bold: true)
    canvas.text("gibson@localhost: ~/telemetry",
                at: CGPoint(x: bar.minX + 14, y: bar.midY + CTFontGetCapHeight(titleFont) / 2),
                font: titleFont, color: theme.fade(theme.mid, 0.9), tracking: 0.8)
    drawControls(canvas)

    canvas.withState { canvas in
        canvas.clip(to: body)
        drawRain(canvas, frame: index, time: time)
        drawMark(canvas, time: time)
        drawCaption(canvas, time: time)
    }

    var y = window.minY
    while y < window.maxY {
        canvas.fill(CGRect(x: window.minX, y: y, width: window.width, height: 1),
                    CGColor(gray: 0, alpha: 0.28))
        y += 3
    }
    canvas.strokeRounded(window, radius, theme.border, width: 1.5)
}

private func drawControls(_ canvas: Canvas) {
    let control: CGFloat = 11
    var x = bar.maxX - 14 - control
    for glyph in [0, 1, 2] {
        let box = CGRect(x: x, y: bar.midY - control / 2, width: control, height: control)
        canvas.stroke(box, theme.fade(theme.mid, 0.8))
        let inner = box.insetBy(dx: control * 0.28, dy: control * 0.28)
        switch glyph {
        case 0:
            canvas.line(CGPoint(x: inner.minX, y: inner.minY),
                        CGPoint(x: inner.maxX, y: inner.maxY), theme.mid)
            canvas.line(CGPoint(x: inner.maxX, y: inner.minY),
                        CGPoint(x: inner.minX, y: inner.maxY), theme.mid)
        case 1:
            canvas.stroke(inner, theme.mid)
        default:
            canvas.line(CGPoint(x: inner.minX, y: inner.midY),
                        CGPoint(x: inner.maxX, y: inner.midY), theme.mid)
        }
        x -= control * 1.7
    }
}

private let rainFont = Fonts.mono(11)
private let rainAlphabet = ["0", "1", "#", "$", "%", "&", "*", "+", "=", "<", ">", "/", "?", "!", ":"]

/// A short ramp instead of a continuous gradient: the trail reads the same and
/// the palette stays small, which is most of the GIF budget.
private let rainSteps = 5
private let rainColours: [CGColor] = (0 ..< rainSteps).map { step in
    let fade = CGFloat(step + 1) / CGFloat(rainSteps)
    return theme.fade(theme.level(0.28 + fade * 0.5), fade * 0.6)
}

private func drawRain(_ canvas: Canvas, frame: Int, time: Double) {
    let advance = Fonts.advance(rainFont)
    let lineHeight = Fonts.lineHeight(rainFont) * 1.05
    let columns = Int(body.width / advance)
    let visibleRows = Int(body.height / lineHeight)
    let trail = max(6, visibleRows / 2)
    let rows = visibleRows + trail
    let ascent = CTFontGetAscent(rainFont)
    let headColour = theme.fade(theme.level(0.85), 0.85)

    // Hard edged glyphs, both because a character ROM had no grey and because
    // antialiasing spends the 256 colour GIF palette on nothing.
    canvas.ctx.setShouldAntialias(false)
    defer { canvas.ctx.setShouldAntialias(true) }

    for column in 0 ..< columns {
        let seed = UInt64(column) &* 6364136223846793005
        // Whole sweeps per loop, so every column is back where it started when
        // the GIF wraps.
        let sweeps = 1 + Int(hashUnit(seed) * 4)
        let speed = CGFloat(rows * sweeps) / CGFloat(loopLength)
        let offset = hashUnit(seed &+ 1) * CGFloat(rows)
        let head = (CGFloat(time) * speed + offset).truncatingRemainder(dividingBy: CGFloat(rows))
        let x = body.minX + CGFloat(column) * advance

        for step in 0 ..< trail {
            // The gap between the tail and the next head is the part of the
            // column that sits below the window, so the wrap is never seen.
            let row = ((Int(head) - step) % rows + rows) % rows
            let y = body.minY + CGFloat(row) * lineHeight
            guard y < body.maxY else { continue }

            let ramp = (rainSteps - 1) - step * rainSteps / trail
            guard ramp >= 0 else { continue }
            let colour = step == 0 ? headColour : rainColours[ramp]
            let glyph = rainAlphabet[Int(hashUnit(seed &+ UInt64(row) &* 31
                &+ UInt64(frame / 2) &* 977) * CGFloat(rainAlphabet.count)) % rainAlphabet.count]
            canvas.text(glyph, at: CGPoint(x: x, y: y + ascent), font: rainFont, color: colour)
        }
    }
}

private func drawMark(_ canvas: Canvas, time: Double) {
    // One progress value for the whole cycle: dots above it are lit. The mark
    // comes apart at the start of the loop and is rebuilt at the end of it.
    let progress: CGFloat
    if time < dissolveStart {
        progress = 1
    } else if time < dissolveStart + dissolveLength {
        progress = 1 - CGFloat((time - dissolveStart) / dissolveLength)
    } else if time < assembleStart {
        progress = 0
    } else {
        progress = CGFloat((time - assembleStart) / assembleLength).clamped(0, 1)
    }
    guard progress > 0.001 else { return }

    let dot = pixel - max(0.5, pixel * 0.14)
    for (index, rect) in markDots.enumerated() {
        let threshold = dotOrder[index] * 0.8
        guard progress > threshold else { continue }
        let settle = ((progress - threshold) / 0.2).clamped(0, 1)
        canvas.fill(CGRect(x: rect.minX, y: rect.minY + (1 - settle) * pixel * 0.7,
                           width: dot, height: dot),
                    theme.fade(theme.accent, 0.35 + settle * 0.65))
    }
}

private func drawCaption(_ canvas: Canvas, time: Double) {
    for caption in captions {
        guard let count = caption.visible(at: time), count >= 0 else { continue }
        let width = PixelFont.width(caption.text, face: PixelFont.thin,
                                    pixel: captionPixel, letterSpacing: captionSpacing)
        let left = (body.midX - width / 2).rounded()
        let shown = String(caption.text.prefix(count))

        PixelFont.draw(shown, face: PixelFont.thin, in: canvas,
                       at: CGPoint(x: left, y: captionTop),
                       pixel: captionPixel, letterSpacing: captionSpacing,
                       color: theme.fade(theme.accent, 0.95))

        // Steady while the line moves, blinking once it settles.
        let settled = time >= caption.full && time < caption.full + caption.hold
        if !settled || Int((time - caption.full) / 0.28) % 2 == 0 {
            let cursor = left + PixelFont.width(shown, face: PixelFont.thin,
                                                pixel: captionPixel, letterSpacing: captionSpacing)
            canvas.fill(CGRect(x: cursor + (count > 0 ? captionSpacing : 0), y: captionTop,
                               width: CGFloat(PixelFont.thin.cellWidth) * captionPixel,
                               height: captionHeight),
                        theme.fade(theme.mid, 0.75))
        }
    }
}

// MARK: - Render

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images/banner.gif"
var frames: [CGImage] = []

for index in 0 ..< frameCount {
    guard let ctx = GIFWriter.context(size: size, scale: 1) else { exit(1) }
    draw(frame: index, in: Canvas(ctx: ctx, size: size))
    guard let image = ctx.makeImage() else { exit(1) }
    frames.append(image)
}

guard GIFWriter.write(frames, to: output, frameDuration: frameDuration) else {
    print("failed to write \(output)")
    exit(1)
}
print("wrote \(output), \(frames.count) frames")
