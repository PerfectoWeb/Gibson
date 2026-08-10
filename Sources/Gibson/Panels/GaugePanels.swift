import CoreGraphics
import CoreText
import Foundation

/// Dial cluster. Each dial is bound to a real metric and the numeric strip
/// underneath repeats the same values in raw form.
final class GaugeClusterPanel: Panel {
    let title: String? = "resource telemetry"
    let redrawInterval: TimeInterval = 1.0 / 20

    private struct Dial {
        let label: String
        let value: CGFloat
        let caption: String
    }

    /// Needle positions, eased towards the sampled values. Metrics arrive once
    /// a second; without the easing the needles would step, not sweep.
    private var needles: [CGFloat] = []

    func update(_ context: RenderContext) {
        let targets = Self.targets(context)
        guard needles.count == targets.count else {
            needles = targets
            return
        }
        for index in targets.indices {
            needles[index] += (targets[index] - needles[index]) * 0.12
        }
    }

    private static func targets(_ context: RenderContext) -> [CGFloat] {
        let metrics = context.metrics
        return [
            CGFloat(metrics.cpuTotal / 100),
            CGFloat(metrics.memory.usedFraction),
            CGFloat(metrics.primaryVolume.usedFraction)
        ]
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let metrics = context.metrics
        let volume = metrics.primaryVolume
        let values = needles.isEmpty ? Self.targets(context) : needles

        let dials = [
            Dial(label: "CPU", value: values[0],
                 caption: Format.percent(Double(values[0]) * 100, decimals: 0)),
            Dial(label: "MEM", value: values[1],
                 caption: Format.bytes(metrics.memory.used)),
            Dial(label: "DISK", value: values[2],
                 caption: Format.bytes(volume.free))
        ]

        // Breathing room above the dials and below the strip, and the dials
        // themselves a little smaller so the panel is not wall to wall.
        let stripHeight = min(body.height * 0.2, 26)
        let topPad = max(4, body.height * 0.05)
        let stripLift: CGFloat = 4
        let dialArea = CGRect(x: body.minX, y: body.minY + topPad, width: body.width,
                              height: body.height - stripHeight - stripLift - topPad - 6)
        let slotWidth = dialArea.width / CGFloat(dials.count)
        let radius = min(slotWidth * 0.34, dialArea.height * 0.42)

        for (index, dial) in dials.enumerated() {
            let center = CGPoint(x: dialArea.minX + slotWidth * (CGFloat(index) + 0.5),
                                 y: dialArea.midY)
            draw(dial, at: center, radius: radius, canvas: canvas, context: context)
        }

        drawStrip(canvas, rect: CGRect(x: body.minX, y: body.maxY - stripHeight - stripLift,
                                       width: body.width, height: stripHeight),
                  context: context)
    }

    private func draw(_ dial: Dial, at center: CGPoint, radius: CGFloat,
                      canvas: Canvas, context: RenderContext) {
        let theme = context.theme
        let start: CGFloat = 135 * .pi / 180
        let sweep: CGFloat = 270 * .pi / 180

        canvas.circle(center, radius * 1.12, theme.fade(theme.border, 0.5))
        arc(canvas, center: center, radius: radius, from: start, to: start + sweep,
            color: theme.fade(theme.border, 0.9), width: max(2, radius * 0.12))
        arc(canvas, center: center, radius: radius,
            from: start, to: start + sweep * dial.value.clamped(0, 1),
            color: dial.value > 0.85 ? theme.warning : theme.bright,
            width: max(2, radius * 0.12))

        let ticks = 24
        for tick in 0 ... ticks {
            let angle = start + sweep * CGFloat(tick) / CGFloat(ticks)
            let outer = radius * 1.26
            let inner = radius * (tick % 6 == 0 ? 1.16 : 1.21)
            let unit = CGPoint(x: cos(angle), y: sin(angle))
            canvas.line(CGPoint(x: center.x + unit.x * inner, y: center.y + unit.y * inner),
                        CGPoint(x: center.x + unit.x * outer, y: center.y + unit.y * outer),
                        tick % 6 == 0 ? theme.mid : theme.fade(theme.border, 0.8))
        }

        let angle = start + sweep * dial.value.clamped(0, 1)
        canvas.line(center,
                    CGPoint(x: center.x + cos(angle) * radius * 0.82,
                            y: center.y + sin(angle) * radius * 0.82),
                    theme.accent, width: 1.4)
        canvas.disc(center, max(1.5, radius * 0.06), theme.accent)

        let valueFont = Fonts.mono((radius * 0.42).clamped(7, 20), bold: true)
        canvas.text(dial.caption, at: CGPoint(x: center.x, y: center.y + radius * 0.62),
                    font: valueFont, color: theme.bright, alignment: .center)
        let labelFont = Fonts.mono((radius * 0.26).clamped(6, 12))
        canvas.text(dial.label, at: CGPoint(x: center.x, y: center.y - radius * 0.42),
                    font: labelFont, color: theme.dim, alignment: .center, tracking: 1.5)
    }

    private static func stripItems(_ context: RenderContext) -> [String] {
        let metrics = context.metrics
        return [
            Format.percent(metrics.cpuTotal, decimals: 0),
            String(format: "%.2f", metrics.loadAverage.first ?? 0),
            "\(metrics.cores.count)C",
            Format.bytes(metrics.memory.wired),
            Format.rate(metrics.network.downBytesPerSecond)
        ]
    }

    private func drawStrip(_ canvas: Canvas, rect: CGRect, context: RenderContext) {
        guard rect.height > 8 else { return }
        let theme = context.theme
        let items = Self.stripItems(context)
        let font = Fonts.mono((rect.height * 0.52).clamped(6, 13), bold: true)
        let slot = rect.width / CGFloat(items.count)
        guard slot > 34 else { return }
        let radius = min(4, rect.height * 0.22)

        for (index, item) in items.enumerated() {
            let cell = CGRect(x: rect.minX + CGFloat(index) * slot + 2, y: rect.minY,
                              width: slot - 4, height: rect.height)
            canvas.strokeRounded(cell, radius, theme.fade(theme.border, 0.8))
            canvas.text(item, at: CGPoint(x: cell.midX, y: cell.midY + CTFontGetCapHeight(font) / 2),
                        font: font, color: theme.mid,
                        maxWidth: cell.width - 4, alignment: .center)
        }
    }

    private func arc(_ canvas: Canvas, center: CGPoint, radius: CGFloat,
                     from start: CGFloat, to end: CGFloat, color: CGColor, width: CGFloat) {
        let steps = max(2, Int(abs(end - start) * radius / 3))
        let points = (0 ... steps).map { step -> CGPoint in
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        canvas.polyline(points, color, width: width)
    }
}

/// Sweeping radar with contacts that light up as the beam passes them.
final class RadarPanel: Panel {
    let title: String? = "perimeter scan"
    let redrawInterval: TimeInterval = 1.0 / 30

    private struct Contact {
        let angle: CGFloat
        let distance: CGFloat
        let code: String
    }

    private lazy var contacts: [Contact] = {
        var rng = Seeded(seed: 0x5CA7)
        return (0 ..< 9).map { _ in
            Contact(angle: rng.range(0, .pi * 2),
                    distance: rng.range(0.25, 0.95),
                    code: String(format: "%04X", rng.int(0x1000, 0xFFFF)))
        }
    }()

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme

        // In a wide slot the scope sits on the left and the contact list fills
        // the rest, rather than leaving a band of empty panel.
        let wide = body.width > body.height * 1.5
        let scope = wide
            ? CGRect(x: body.minX, y: body.minY, width: body.height * 1.1, height: body.height)
            : body
        if wide {
            drawContactList(canvas, in: CGRect(x: scope.maxX + 8, y: body.minY,
                                               width: body.maxX - scope.maxX - 8,
                                               height: body.height),
                            context: context)
        }

        let center = CGPoint(x: scope.midX, y: scope.midY)
        let radius = min(scope.width, scope.height) * 0.45
        let sweep = CGFloat(context.time * 1.1).truncatingRemainder(dividingBy: .pi * 2)

        for ring in 1 ... 4 {
            canvas.circle(center, radius * CGFloat(ring) / 4, theme.fade(theme.border, 0.8))
        }
        for spoke in 0 ..< 8 {
            let angle = CGFloat(spoke) * .pi / 4
            canvas.line(center,
                        CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius),
                        theme.grid)
        }

        // Trailing wedge behind the beam.
        let trail = 40
        for step in 0 ..< trail {
            let angle = sweep - CGFloat(step) * 0.022
            let next = angle - 0.022
            let alpha = (1 - CGFloat(step) / CGFloat(trail)) * 0.22
            canvas.fillPolygon([
                center,
                CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius),
                CGPoint(x: center.x + cos(next) * radius, y: center.y + sin(next) * radius)
            ], theme.fade(theme.bright, alpha))
        }
        canvas.line(center,
                    CGPoint(x: center.x + cos(sweep) * radius, y: center.y + sin(sweep) * radius),
                    theme.accent, width: 1.4)

        let font = Fonts.mono((radius * 0.13).clamped(5, 10))
        for contact in contacts {
            var delta = sweep - contact.angle
            while delta < 0 { delta += .pi * 2 }
            let freshness = max(0, 1 - delta / 1.8)
            guard freshness > 0.02 else { continue }
            let point = CGPoint(x: center.x + cos(contact.angle) * radius * contact.distance,
                                y: center.y + sin(contact.angle) * radius * contact.distance)
            canvas.disc(point, 2.2 + freshness * 1.6, theme.fade(theme.bright, freshness))
            if freshness > 0.5 {
                canvas.text(contact.code, at: CGPoint(x: point.x + 6, y: point.y - 3),
                            font: font, color: theme.fade(theme.mid, freshness))
            }
        }
    }

    private func drawContactList(_ canvas: Canvas, in rect: CGRect, context: RenderContext) {
        guard rect.width > 60 else { return }
        let theme = context.theme
        let font = Fonts.mono((rect.height / 13).clamped(6, 12))
        let lineHeight = Fonts.lineHeight(font) * 1.35
        let sweep = CGFloat(context.time * 1.1).truncatingRemainder(dividingBy: .pi * 2)

        var y = rect.minY + CTFontGetAscent(font)
        canvas.text("CONTACT  BRG   RANGE  STATE", at: CGPoint(x: rect.minX, y: y),
                    font: Fonts.mono(CTFontGetSize(font), bold: true), color: theme.accent)
        y += lineHeight * 1.4

        for contact in contacts {
            guard y < rect.maxY else { break }
            var delta = sweep - contact.angle
            while delta < 0 { delta += .pi * 2 }
            let fresh = delta < 1.2
            let bearing = Int(contact.angle * 180 / .pi)
            let range = Int(contact.distance * 4000)
            let line = "\(contact.code)     \(Format.pad(String(bearing), 3, alignRight: true))°  "
                + "\(Format.pad(String(range), 5, alignRight: true))  \(fresh ? "ACTIVE" : "IDLE")"
            canvas.text(line, at: CGPoint(x: rect.minX, y: y), font: font,
                        color: fresh ? theme.bright : theme.level(0.45), maxWidth: rect.width)
            y += lineHeight
        }
    }
}
