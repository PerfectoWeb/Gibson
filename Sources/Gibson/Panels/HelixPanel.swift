import CoreGraphics
import CoreText
import Foundation

/// Twisting ribbon of dots with scattered readouts, the tall decorative column.
final class HelixPanel: Panel {
    let title: String? = "sequence stream"
    let redrawInterval: TimeInterval = 1.0 / 30

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme
        let phase = CGFloat(context.time) * 0.9
        // The ribbon runs along whichever axis the slot is longer on.
        let horizontal = body.width > body.height * 1.25
        let length = horizontal ? body.width : body.height
        let amplitude = (horizontal ? body.height : body.width) * 0.33
        let turns = (length / max(amplitude, 1) * 0.9).clamped(4, 14)
        let steps = max(24, Int(length / 4))

        func place(_ t: CGFloat, _ lateral: CGFloat) -> CGPoint {
            horizontal
                ? CGPoint(x: body.minX + t * length, y: body.midY + lateral)
                : CGPoint(x: body.midX + lateral, y: body.minY + t * length)
        }

        for strand in 0 ..< 2 {
            let offset = CGFloat(strand) * .pi
            for step in 0 ... steps {
                let t = CGFloat(step) / CGFloat(steps)
                let angle = t * turns + phase + offset
                let depth = (cos(angle) + 1) / 2
                canvas.disc(place(t, sin(angle) * amplitude), 1 + depth * 2.6,
                            theme.fade(theme.level(0.35 + depth * 0.65), 0.35 + depth * 0.65))
            }
        }

        // Rungs between the strands.
        for step in stride(from: 0, through: steps, by: 4) {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = t * turns + phase
            let depth = (cos(angle) + 1) / 2
            canvas.line(place(t, sin(angle) * amplitude),
                        place(t, sin(angle + .pi) * amplitude),
                        theme.fade(theme.border, 0.3 + depth * 0.5))
        }

        // Floating numbers, positioned from a stable hash so they do not jitter.
        let font = Fonts.mono((body.width * 0.06).clamped(6, 12), bold: true)
        for index in 0 ..< 8 {
            let seed = UInt64(index) &* 977
            let t = ((hashUnit(seed) + CGFloat(context.time) * 0.03)
                .truncatingRemainder(dividingBy: 1))
            let y = body.minY + t * body.height
            let x = body.minX + hashUnit(seed &+ 1) * body.width
            let value = Int(hashUnit(seed &+ 2) * 9999)
            let fade = sin(t * .pi)
            canvas.text(String(value), at: CGPoint(x: x, y: y), font: font,
                        color: theme.fade(theme.mid, 0.25 + fade * 0.75))
        }
    }
}
