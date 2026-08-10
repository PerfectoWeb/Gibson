import CoreGraphics
import CoreText
import Foundation

/// Falling digits, nothing else. Each column is a pure function of time, which
/// means the panel keeps no state between frames. Two things break the
/// regularity: a share of the cells drop a punctuation glyph instead of a bit,
/// and every few seconds a couple of rows tear sideways.
final class MatrixRainPanel: Panel {
    let redrawInterval: TimeInterval = 1.0 / 15

    /// Glyphs that occasionally stand in for a 0 or a 1.
    private static let symbols = Array("#$%&*+=<>/\\|^~?!@:;")

    /// Everything the rain can print: the two bits, then the punctuation.
    private static let alphabet = ["0", "1"] + symbols.map(String.init)

    /// Share of cells that show a symbol rather than a bit.
    private static let symbolChance: CGFloat = 0.12

    private let glitchPeriod: TimeInterval = 6
    private let glitchLength: TimeInterval = 0.22

    /// The support code surfaces briefly, then goes away again.
    private let supportDelay: TimeInterval = 45
    private let supportPeriod: TimeInterval = 150
    private let supportLength: TimeInterval = 12

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        PanelChrome.plain(canvas, context)
        let body = canvas.bounds.insetBy(dx: 3 + context.cornerRadius / 2, dy: 3)

        canvas.withState { canvas in
            canvas.clip(to: body)
            let cells = grid(in: body)
            drawRain(canvas, in: body, cells: cells, context: context)
            drawTears(canvas, in: body, cells: cells, context: context)
            drawSupport(canvas, in: body, context: context)
        }
    }

    // MARK: - Support code

    private func drawSupport(_ canvas: Canvas, in rect: CGRect, context: RenderContext) {
        guard context.time >= supportDelay else { return }
        let local = (context.time - supportDelay).truncatingRemainder(dividingBy: supportPeriod)
        guard local < supportLength else { return }

        // No fade. The code cuts in and out over a handful of dropped frames,
        // the way a tube settles, and jumps sideways while it is doing it.
        let edge = min(local, supportLength - local)
        var offset: CGFloat = 0
        if edge < 0.4 {
            guard Int(edge / 0.07) % 2 == 1 else { return }
            offset = (hashUnit(UInt64(edge * 1000)) - 0.5) * 14
        }

        guard let modules = QRCode.modules(for: QRCode.supportURL) else { return }

        let theme = context.theme
        let side = (min(rect.width, rect.height) * 0.52).rounded()
        let box = CGRect(x: (rect.midX - side / 2 + offset).rounded(),
                         y: (rect.midY - side / 2).rounded(),
                         width: side, height: side)

        canvas.withState { canvas in
            // The quiet zone is opaque, in the panel's own fill, and carries a
            // hairline the same colour as every other panel edge. That reads as
            // a region cut into the terminal rather than a patch floating over
            // it, which is what a translucent backdrop looked like.
            QRCode.draw(modules, in: box, canvas: canvas,
                        background: theme.panelFill, module: theme.mid)
            let quiet = box.insetBy(dx: side * 0.02, dy: side * 0.02)
            canvas.stroke(quiet, theme.fade(theme.border, 0.9))

            // Scanlines over the symbol, the same treatment as the whole screen.
            let bleed = box.insetBy(dx: -side * 0.1, dy: -side * 0.1)
            var y = bleed.minY
            while y < bleed.maxY {
                canvas.fill(CGRect(x: bleed.minX, y: y, width: bleed.width, height: 1),
                            CGColor(gray: 0, alpha: 0.34))
                y += 3
            }
        }
    }

    // MARK: - Geometry

    private struct Grid {
        let font: CTFont
        let advance: CGFloat
        let lineHeight: CGFloat
        let columns: Int
        let visibleRows: Int
        let trailLength: Int
        let rows: Int
    }

    private func grid(in rect: CGRect) -> Grid {
        let font = Fonts.mono((rect.width / 34).clamped(6, 13))
        let advance = max(1, Fonts.advance(font))
        let lineHeight = max(1, Fonts.lineHeight(font) * 1.05)
        let visibleRows = max(1, Int(rect.height / lineHeight))
        // Trails cover roughly half the column, which keeps the rain dense
        // whatever the panel height turns out to be.
        let trailLength = max(10, visibleRows / 2)
        return Grid(font: font, advance: advance, lineHeight: lineHeight,
                    columns: max(1, Int(rect.width / advance)),
                    visibleRows: visibleRows, trailLength: trailLength,
                    rows: visibleRows + trailLength)
    }

    // MARK: - Rain

    private func drawRain(_ canvas: Canvas, in rect: CGRect, cells: Grid,
                          context: RenderContext) {
        let lines = trail(for: cells, theme: context.theme)
        let ascent = CTFontGetAscent(cells.font)

        for column in 0 ..< cells.columns {
            let seed = UInt64(column) &* 6364136223846793005
            let speed = 4 + hashUnit(seed) * 12
            let offset = hashUnit(seed &+ 1) * CGFloat(cells.rows)
            let head = (CGFloat(context.time) * speed + offset)
                .truncatingRemainder(dividingBy: CGFloat(cells.rows))
            let x = rect.minX + CGFloat(column) * cells.advance

            for step in 0 ..< cells.trailLength {
                let row = Int(head) - step
                guard row >= 0 else { continue }
                let y = rect.minY + CGFloat(row) * cells.lineHeight
                guard y < rect.maxY else { continue }

                canvas.draw(lines[step][glyphIndex(column: column, row: row, time: context.time)],
                            at: CGPoint(x: x, y: y + ascent))
            }
        }
    }

    /// One prepared line per glyph per trail position. The alphabet is 21
    /// characters and the colour depends only on the distance from the head, so
    /// the whole panel draws out of a table this size instead of building a
    /// line and two colours for each of twelve thousand cells a second.
    private var cachedTrail: [[CTLine]] = []
    private var cachedTrailKey: TrailKey?

    private struct TrailKey: Equatable {
        let fontSize: CGFloat
        let length: Int
        let palette: Palette
    }

    private func trail(for cells: Grid, theme: Theme) -> [[CTLine]] {
        let key = TrailKey(fontSize: CTFontGetSize(cells.font),
                           length: cells.trailLength,
                           palette: theme.palette)
        if key == cachedTrailKey { return cachedTrail }

        cachedTrail = (0 ..< cells.trailLength).map { step in
            let fade = 1 - CGFloat(step) / CGFloat(cells.trailLength)
            let colour = step == 0
                ? theme.accent
                : theme.fade(theme.level(0.3 + fade * 0.5), fade * 0.85)
            return Self.alphabet.map { Canvas.line($0, font: cells.font, color: colour) }
        }
        cachedTrailKey = key
        return cachedTrail
    }

    /// Index into `alphabet`: 0 and 1 first, then the punctuation.
    private func glyphIndex(column: Int, row: Int, time: TimeInterval) -> Int {
        let seed = UInt64(column) &* 6364136223846793005
            &+ UInt64(row) &* 31
            &+ UInt64(Int(time * 6))
        let roll = hashUnit(seed)
        if roll > 1 - Self.symbolChance {
            let index = Int(hashUnit(seed &+ 5) * CGFloat(Self.symbols.count))
            return 2 + min(index, Self.symbols.count - 1)
        }
        return roll > 0.5 ? 1 : 0
    }

    // MARK: - Tears

    /// A short horizontal displacement of two or three rows, like a bad line on
    /// a CRT. Redraws only the affected bands.
    private func drawTears(_ canvas: Canvas, in rect: CGRect, cells: Grid,
                           context: RenderContext) {
        let phase = context.time.truncatingRemainder(dividingBy: glitchPeriod)
        guard phase < glitchLength else { return }

        let theme = context.theme
        let pass = UInt64(context.time / glitchPeriod)
        let bands = 2 + Int(hashUnit(pass) * 2)

        for band in 0 ..< bands {
            let seed = pass &* 977 &+ UInt64(band) &* 41
            let rowCount = 1 + Int(hashUnit(seed) * 2)
            let firstRow = Int(hashUnit(seed &+ 1) * CGFloat(max(1, cells.visibleRows - rowCount)))
            let shift = (hashUnit(seed &+ 2) - 0.5) * rect.width * 0.35

            let bandRect = CGRect(x: rect.minX,
                                  y: rect.minY + CGFloat(firstRow) * cells.lineHeight,
                                  width: rect.width,
                                  height: CGFloat(rowCount) * cells.lineHeight)
            canvas.withState { canvas in
                canvas.clip(to: bandRect)
                canvas.fill(bandRect, theme.panelFill)
                for row in firstRow ..< (firstRow + rowCount) {
                    let y = rect.minY + CGFloat(row) * cells.lineHeight
                        + CTFontGetAscent(cells.font)
                    for column in 0 ..< cells.columns {
                        // Skip cells and vary the weight so the band reads as a
                        // displaced row rather than a solid bar of text.
                        let cell = seed &+ UInt64(column) &* 7 &+ UInt64(row) &* 13
                        let roll = hashUnit(cell)
                        guard roll > 0.38 else { continue }
                        canvas.text(Self.alphabet[glyphIndex(column: column, row: row,
                                                             time: context.time)],
                                    at: CGPoint(x: rect.minX + CGFloat(column) * cells.advance + shift,
                                                y: y),
                                    font: cells.font,
                                    color: theme.fade(theme.accent, 0.35 + roll * 0.6))
                    }
                }
                canvas.line(CGPoint(x: bandRect.minX, y: bandRect.minY),
                            CGPoint(x: bandRect.maxX, y: bandRect.minY),
                            theme.fade(theme.bright, 0.5))
            }
        }
    }
}
