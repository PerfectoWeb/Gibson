import CoreGraphics

/// Segmented meters. The block at the head of the fill is the brightest and the
/// trail behind it fades out. Both bar styles share that ramp, which is what
/// keeps a vertical column and a horizontal bar looking related.
enum Meter {
    /// Brightness along a fill: 0 at the tail, 1 at the head.
    private static func ramp(_ position: CGFloat) -> CGFloat {
        0.22 + 0.78 * pow(position.clamped(0, 1), 1.7)
    }

    /// Vertical column of blocks growing upwards.
    static func column(_ canvas: Canvas, in rect: CGRect, value: CGFloat, theme: Theme,
                       blockHeight: CGFloat, gap: CGFloat = 1) {
        let step = blockHeight + gap
        let count = max(1, Int(rect.height / step))
        let lit = Int((value.clamped(0, 1) * CGFloat(count)).rounded())

        for index in 0 ..< count {
            let block = CGRect(x: rect.minX,
                               y: rect.maxY - CGFloat(index + 1) * step,
                               width: rect.width, height: blockHeight)
            guard index < lit else {
                canvas.fill(block, theme.fade(theme.grid, 0.55))
                continue
            }
            let position = lit > 1 ? CGFloat(index) / CGFloat(lit - 1) : 1
            let level = ramp(position)
            let colour = index == lit - 1 ? theme.accent : theme.level(level)
            canvas.fill(block, theme.fade(colour, 0.3 + 0.7 * level))
        }
    }

    /// Horizontal segmented bar growing to the right, inside a hairline track.
    static func bar(_ canvas: Canvas, in rect: CGRect, value: CGFloat, theme: Theme) {
        canvas.stroke(rect, theme.fade(theme.border, 0.9))
        let inner = rect.insetBy(dx: 2, dy: 2)
        guard inner.width > 2, inner.height > 0 else { return }

        let segment = max(2, inner.height * 0.42)
        let gap = max(1, segment * 0.35)
        let count = max(1, Int(inner.width / (segment + gap)))
        let lit = Int(value.clamped(0, 1) * CGFloat(count))

        for index in 0 ..< count {
            let block = CGRect(x: inner.minX + CGFloat(index) * (segment + gap),
                               y: inner.minY, width: segment, height: inner.height)
            guard index < lit else {
                canvas.fill(block, theme.fade(theme.border, 0.32))
                continue
            }
            let position = lit > 1 ? CGFloat(index) / CGFloat(lit - 1) : 1
            let level = ramp(position)
            let colour = index == lit - 1 ? theme.accent : theme.level(level)
            canvas.fill(block, theme.fade(colour, 0.35 + 0.65 * level))
        }
    }
}
