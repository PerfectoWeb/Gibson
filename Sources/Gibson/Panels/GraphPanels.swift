import CoreGraphics
import CoreText
import Foundation

/// Rows of segmented progress bars. The first rows track real metrics, the rest
/// are filler tasks that keep looping.
final class ProgressStackPanel: Panel {
    let redrawInterval: TimeInterval = 0.1

    private let tasks = ["INDEX", "DECRYPT", "SCAN", "UPLOAD", "VERIFY", "PATCH"]

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let theme = context.theme
        PanelChrome.plain(canvas, context)

        let inset = max(5, canvas.height * 0.12)
        let area = canvas.bounds.insetBy(dx: inset, dy: inset)
        let font = Fonts.mono((area.height / 3.6).clamped(6, 11))
        let rowHeight = area.height / 2
        // The gap belongs between the columns, not after the last one, otherwise
        // the right margin ends up a whole gap wider than the left.
        let gap = inset
        let columnWidth = (area.width - gap * 2) / 3

        for index in 0 ..< 6 {
            let column = index % 3
            let row = index / 3
            let cell = CGRect(x: area.minX + CGFloat(column) * (columnWidth + gap),
                              y: area.minY + CGFloat(row) * rowHeight,
                              width: columnWidth,
                              height: rowHeight)

            let value = progress(index: index, context: context)
            let label = tasks[index]
            canvas.text(label, at: CGPoint(x: cell.minX, y: cell.minY + CTFontGetAscent(font)),
                        font: font, color: theme.dim)
            canvas.text("\(Int(value * 100))%",
                        at: CGPoint(x: cell.maxX, y: cell.minY + CTFontGetAscent(font)),
                        font: font, color: theme.mid, alignment: .right)

            let bar = CGRect(x: cell.minX, y: cell.minY + Fonts.lineHeight(font) + 2,
                             width: cell.width, height: max(3, cell.height * 0.32))
            Meter.bar(canvas, in: bar, value: value, theme: theme)
        }
    }

    private func progress(index: Int, context: RenderContext) -> CGFloat {
        switch index {
        case 0: return CGFloat(context.metrics.cpuTotal / 100)
        case 1: return CGFloat(context.metrics.memory.usedFraction)
        case 2: return CGFloat(context.metrics.primaryVolume.usedFraction)
        default:
            let speed = 0.05 + CGFloat(index) * 0.017
            return CGFloat((context.time * Double(speed)).truncatingRemainder(dividingBy: 1))
        }
    }

}

/// Vertical equaliser driven by the CPU history ring.
final class BarMeterPanel: Panel {
    let title: String? = "cpu load history"
    let redrawInterval: TimeInterval = 0.1

    func contentKey(_ context: RenderContext) -> Int? {
        context.metrics.timestamp.hashValue
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme
        // Fixed number of columns, filled from the right as history accumulates.
        let count = max(8, min(120, Int(body.width / 11)))
        let history = context.metrics.cpuHistory.suffix(count)
        let slice = [Double](repeating: 0, count: count - history.count) + history
        let step = body.width / CGFloat(count)
        let barWidth = max(2, step * 0.62)
        let blockHeight = max(2, body.height / 22)

        for (index, value) in slice.enumerated() {
            let column = CGRect(x: body.minX + CGFloat(index) * step, y: body.minY,
                                width: barWidth, height: body.height)
            Meter.column(canvas, in: column, value: CGFloat(value / 100), theme: theme,
                         blockHeight: blockHeight)
        }

        let font = Fonts.mono((body.height * 0.1).clamped(6, 11), bold: true)
        canvas.text(Format.percent(context.metrics.cpuTotal),
                    at: CGPoint(x: body.maxX - 10, y: body.minY + CTFontGetAscent(font) + 10),
                    font: font, color: theme.bright, alignment: .right)
    }
}

/// Oscilloscope traces over a graticule.
final class WaveformPanel: Panel {
    let title: String? = "signal analyser"
    let redrawInterval: TimeInterval = 1.0 / 30

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme

        // Graticule
        for column in 1 ..< 8 {
            let x = body.minX + body.width * CGFloat(column) / 8
            canvas.line(CGPoint(x: x, y: body.minY), CGPoint(x: x, y: body.maxY), theme.grid)
        }
        for row in 1 ..< 4 {
            let y = body.minY + body.height * CGFloat(row) / 4
            canvas.line(CGPoint(x: body.minX, y: y), CGPoint(x: body.maxX, y: y), theme.grid)
        }

        let amplitude = 1.1 + CGFloat(context.metrics.cpuTotal / 160)
        let traces: [(CGFloat, CGFloat, CGFloat)] = [
            (1.0, 2.2, 1.0), (1.7, -1.4, 0.62), (3.1, 0.8, 0.34)
        ]

        for (index, trace) in traces.enumerated() {
            let (frequency, speed, weight) = trace
            var points: [CGPoint] = []
            points.reserveCapacity(Int(body.width / 2) + 1)
            var x = body.minX
            while x <= body.maxX {
                let phase = (x - body.minX) / body.width * .pi * 2 * frequency
                    + CGFloat(context.time) * speed
                let value = sin(phase) * 0.5 + sin(phase * 2.7 + 1.1) * 0.22
                let y = body.midY - value * body.height * 0.36 * amplitude * weight
                points.append(CGPoint(x: x, y: y))
                x += 2
            }
            canvas.polyline(points, theme.level(index == 0 ? 1 : 0.5 - CGFloat(index) * 0.1),
                            width: index == 0 ? 1.6 : 1)
        }
    }
}

/// Horizontal lanes of drifting markers, the "data in transit" strip.
final class FlowLanesPanel: Panel {
    let redrawInterval: TimeInterval = 1.0 / 30

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let theme = context.theme
        PanelChrome.plain(canvas, context)

        let inset = max(6, canvas.height * 0.1)
        let area = canvas.bounds.insetBy(dx: inset, dy: inset)
        let laneCount = max(2, Int(area.height / 30))
        let laneHeight = area.height / CGFloat(laneCount)

        for lane in 0 ..< laneCount {
            let y = area.minY + (CGFloat(lane) + 0.5) * laneHeight
            canvas.line(CGPoint(x: area.minX, y: y), CGPoint(x: area.maxX, y: y),
                        theme.fade(theme.border, 0.6))

            let direction: CGFloat = lane % 2 == 0 ? 1 : -1
            let speed = 40 + CGFloat(lane % 3) * 25
            let markerSize = min(laneHeight * 0.3, 7)
            let spacing = 58 + CGFloat(lane % 4) * 17
            let offset = (CGFloat(context.time) * speed * direction)
                .truncatingRemainder(dividingBy: spacing)

            var x = area.minX + offset - spacing
            while x < area.maxX + spacing {
                if x > area.minX - markerSize, x < area.maxX + markerSize {
                    let brightness = 0.35 + 0.65 * abs(sin((x - area.minX) / area.width * .pi))
                    let tip = CGPoint(x: x + markerSize * direction, y: y)
                    canvas.fillPolygon([
                        tip,
                        CGPoint(x: x - markerSize * direction, y: y - markerSize),
                        CGPoint(x: x - markerSize * direction, y: y + markerSize)
                    ], theme.level(brightness))
                }
                x += spacing
            }
        }
    }
}
