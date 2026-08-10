import CoreGraphics
import CoreText
import Foundation

/// Top strip: identity on the left, clock on the right, live counters between.
final class HeaderPanel: Panel {
    let redrawInterval: TimeInterval = 0.25

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let theme = context.theme
        let metrics = context.metrics
        PanelChrome.plain(canvas, context)

        let size = (canvas.height * 0.22).clamped(6, 12)
        let font = Fonts.mono(size)
        let baseline = canvas.height / 2 + CTFontGetCapHeight(font) / 2
        let padding = max(18, canvas.height * 0.3)

        // Clock first, so the left hand segments know where to stop.
        let now = Date()
        let clockFont = Fonts.mono((canvas.height * 0.42).clamped(8, 22), bold: true)
        let clockBaseline = canvas.height / 2 + CTFontGetCapHeight(clockFont) / 2
        let clockWidth = canvas.text(Format.timeFormatter.string(from: now),
                                     at: CGPoint(x: canvas.width - padding, y: clockBaseline),
                                     font: clockFont, color: theme.bright, alignment: .right)

        var rightEdge = canvas.width - padding - clockWidth - Fonts.advance(font) * 2
        if rightEdge > canvas.width * 0.45 {
            rightEdge = drawDate(canvas, endingAt: rightEdge, theme: theme, now: now)
                - Fonts.advance(font) * 2
        }

        // Logo: the CRT mark and the wordmark, both from the 8x8 character ROM
        // the cover art uses, so the header carries the same identity. Solid
        // blocks read heavier than antialiased glyphs, so the logo is knocked
        // back slightly to sit level with the text beside it.
        var x = padding
        let pixel = max(2, (canvas.height * 0.034).rounded())
        let spacing = pixel * 1.5
        let markWidth = CGFloat(8) * pixel
        let markGap = pixel * 4
        let logoTop = ((canvas.height - PixelFont.height(face: PixelFont.bold, pixel: pixel)) / 2).rounded()

        // Rounded so the matrix lands on whole pixels, otherwise every dot is
        // antialiased and the logo reads dimmer than the text beside it.
        let logoX = x.rounded()
        PixelFont.draw(rows: PixelFont.screenMark, in: canvas, at: CGPoint(x: logoX, y: logoTop),
                       pixel: pixel, color: theme.mid)
        PixelFont.draw("GIBSON", face: PixelFont.bold, in: canvas,
                       at: CGPoint(x: (logoX + markWidth + markGap).rounded(), y: logoTop),
                       pixel: pixel, letterSpacing: spacing, color: theme.mid)
        x += markWidth + markGap
            + PixelFont.width("GIBSON", face: PixelFont.bold, pixel: pixel, letterSpacing: spacing)
            + size

        let host = context.maskSensitiveInfo ? Format.mask(metrics.hostName, keep: 3) : metrics.hostName
        let user = context.maskSensitiveInfo ? Format.mask(metrics.userName) : metrics.userName

        let segments = [
            "\(user)@\(host)",
            metrics.osVersion,
            "UP \(Format.duration(metrics.uptime))",
            "LOAD \(String(format: "%.2f", metrics.loadAverage.first ?? 0))",
            "PROC \(metrics.processCount)",
            "THERM \(metrics.thermalState)"
        ]

        for segment in segments {
            let width = CGFloat(segment.count + 4) * Fonts.advance(font)
            guard x + width < rightEdge else { break }
            canvas.text("//", at: CGPoint(x: x, y: baseline), font: font, color: theme.dim)
            x += Fonts.advance(font) * 3
            x += canvas.text(segment, at: CGPoint(x: x, y: baseline), font: font, color: theme.mid)
            x += Fonts.advance(font)
        }
    }

    /// Date as split flap cells: day inverted, month and year outlined. One
    /// visual language for all three groups, deliberately unlike the clock.
    private func drawDate(_ canvas: Canvas, endingAt right: CGFloat, theme: Theme,
                          now: Date) -> CGFloat {
        let cellHeight = (canvas.height * 0.41).rounded()
        let cellFont = Fonts.mono((cellHeight * 0.66).clamped(6, 15), bold: true)
        let cellWidth = (Fonts.advance(cellFont) + cellHeight * 0.3).rounded()
        let gap = max(1.5, cellWidth * 0.11)
        let groupGap = cellWidth * 0.5

        let groups: [(characters: [Character], inverted: Bool)] = [
            (Array(Format.dayFormatter.string(from: now)), true),
            (Array(Format.monthFormatter.string(from: now).uppercased()), false),
            (Array(Format.yearFormatter.string(from: now)), false)
        ]

        let cells = CGFloat(groups.reduce(0) { $0 + $1.characters.count })
        let total = cells * cellWidth + (cells - CGFloat(groups.count)) * gap
            + groupGap * CGFloat(groups.count - 1)
        var x = right - total
        let left = x
        let top = (canvas.height - cellHeight) / 2
        let baseline = canvas.height / 2 + CTFontGetCapHeight(cellFont) / 2

        for (index, group) in groups.enumerated() {
            for character in group.characters {
                let cell = CGRect(x: x, y: top, width: cellWidth, height: cellHeight)
                if group.inverted {
                    canvas.fill(cell, theme.mid)
                } else {
                    canvas.stroke(cell, theme.border)
                }
                canvas.text(String(character), at: CGPoint(x: cell.midX, y: baseline),
                            font: cellFont,
                            color: group.inverted ? theme.background : theme.bright,
                            alignment: .center)
                x += cellWidth + gap
            }
            if index < groups.count - 1 { x += groupGap - gap }
        }

        return left
    }
}

/// One tile per reading rather than a single card. The panel draws no chrome of
/// its own: each metric gets its own bordered block, and the stack fills the
/// slot exactly so it lines up with the panel beside it.
final class VitalsPanel: Panel {
    let redrawInterval: TimeInterval = 0.5

    func contentKey(_ context: RenderContext) -> Int? {
        context.metrics.timestamp.hashValue
    }

    private struct Vital {
        let label: String
        let value: String
        /// Drives the hairline at the foot of the tile. Nil for readings that
        /// have no natural ceiling, like throughput.
        let fraction: CGFloat?
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let theme = context.theme
        let metrics = context.metrics
        let volume = metrics.primaryVolume

        let vitals = [
            Vital(label: "CPU", value: Format.percent(metrics.cpuTotal),
                  fraction: CGFloat(metrics.cpuTotal / 100)),
            Vital(label: "RAM", value: Format.percent(metrics.memory.usedFraction * 100),
                  fraction: CGFloat(metrics.memory.usedFraction)),
            Vital(label: "SWAP", value: Format.bytes(metrics.memory.swapUsed),
                  fraction: metrics.memory.swapTotal > 0
                      ? CGFloat(Double(metrics.memory.swapUsed) / Double(metrics.memory.swapTotal))
                      : 0),
            Vital(label: "DISK FREE", value: Format.bytes(volume.free),
                  fraction: CGFloat(1 - volume.usedFraction)),
            Vital(label: "NET IN", value: Format.rate(metrics.network.downBytesPerSecond),
                  fraction: nil),
            Vital(label: "NET OUT", value: Format.rate(metrics.network.upBytesPerSecond),
                  fraction: nil),
            Vital(label: "LOAD", value: String(format: "%.2f", metrics.loadAverage.first ?? 0),
                  fraction: nil),
            Vital(label: "THREADS", value: String(metrics.threadCount), fraction: nil)
        ]

        let gap = max(3, context.cornerRadius * 0.9)
        let columns = max(1, min(4, Int(canvas.width / 150)))
        let maxRows = max(1, Int(canvas.height / 54))
        let rows = min(maxRows, Int(ceil(Double(vitals.count) / Double(columns))))
        let tileWidth = (canvas.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let tileHeight = (canvas.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for (index, vital) in vitals.prefix(columns * rows).enumerated() {
            let tile = CGRect(x: CGFloat(index % columns) * (tileWidth + gap),
                              y: CGFloat(index / columns) * (tileHeight + gap),
                              width: tileWidth, height: tileHeight)
            draw(vital, in: tile, canvas: canvas, context: context, theme: theme)
        }
    }

    private func draw(_ vital: Vital, in tile: CGRect, canvas: Canvas,
                      context: RenderContext, theme: Theme) {
        let radius = context.cornerRadius
        canvas.fillRounded(tile, radius, theme.panelFill)
        canvas.strokeRounded(tile, radius, theme.border)

        let inset = max(5, tile.height * 0.16)
        let valueSize = (tile.height * 0.34).clamped(9, 22)
        let labelFont = Fonts.mono(valueSize * 0.58)
        let valueFont = Fonts.mono(valueSize, bold: true)

        canvas.text(vital.label,
                    at: CGPoint(x: tile.minX + inset,
                                y: tile.minY + inset + CTFontGetAscent(labelFont) * 0.7 + 2),
                    font: labelFont, color: theme.dim, tracking: 1.2)
        canvas.text(vital.value,
                    at: CGPoint(x: tile.minX + inset, y: tile.maxY - inset * 1.15 - 4),
                    font: valueFont, color: theme.bright,
                    maxWidth: tile.width - inset * 2)

        guard let fraction = vital.fraction else { return }
        let track = CGRect(x: tile.minX + inset, y: tile.maxY - inset * 0.75,
                           width: tile.width - inset * 2, height: max(1.5, tile.height * 0.035))
        canvas.fill(track, theme.fade(theme.border, 0.7))
        canvas.fill(CGRect(x: track.minX, y: track.minY,
                           width: track.width * fraction.clamped(0, 1), height: track.height),
                    fraction > 0.85 ? theme.warning : theme.bright)
    }
}

/// Oversized countdown, the "time until decryption complete" gag.
final class CountdownPanel: Panel {
    let title: String? = "estimated time until decryption complete"
    let redrawInterval: TimeInterval = 0.2

    private let total: TimeInterval = 4 * 3600

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme
        let remaining = total - context.time.truncatingRemainder(dividingBy: total)

        let font = Fonts.mono(min(body.height * 0.8, body.width / 5.2), bold: true)
        let baseline = body.midY + CTFontGetCapHeight(font) / 2
        canvas.text(Format.clock(remaining), at: CGPoint(x: body.midX, y: baseline),
                    font: font, color: theme.bright, alignment: .center, tracking: 2)

        let small = Fonts.mono((body.height * 0.11).clamped(6, 11))
        let progress = 1 - remaining / total
        canvas.text(String(format: "%.4f%% COMPLETE", progress * 100),
                    at: CGPoint(x: body.midX, y: body.maxY - 2),
                    font: small, color: theme.dim, alignment: .center)
    }
}
