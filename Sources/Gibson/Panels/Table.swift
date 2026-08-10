import CoreGraphics
import CoreText

/// Shared column layout for the two table panels. Columns are dropped from the
/// right until the remaining ones fit the available width, so the same table
/// works in a narrow slot and on an ultrawide display.
struct Table {
    struct Column {
        let title: String
        let chars: Int
        var alignRight = false
        var accent = false
    }

    var columns: [Column]
    var rows: [[String]]
    var rowTint: (Int) -> CGFloat = { _ in 0.6 }

    func draw(_ canvas: Canvas, in rect: CGRect, theme: Theme, fontSize: CGFloat) {
        let font = Fonts.mono(fontSize)
        let headerFont = Fonts.mono(fontSize, bold: true)
        let advance = Fonts.advance(font)
        let lineHeight = (Fonts.lineHeight(font) * 1.28).rounded()
        guard lineHeight > 0, advance > 0 else { return }

        var visible = columns
        while visible.count > 1, width(of: visible, advance: advance) > rect.width {
            visible.removeLast()
        }

        var y = rect.minY + CTFontGetAscent(font)
        let ascent = CTFontGetAscent(font)

        var x = rect.minX
        for column in visible {
            let text = Format.pad(column.title, column.chars, alignRight: column.alignRight)
            canvas.text(text, at: CGPoint(x: x, y: y), font: headerFont, color: theme.accent)
            x += CGFloat(column.chars + 1) * advance
        }
        y += lineHeight * 0.35
        canvas.line(CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y), theme.border)
        y += lineHeight * 0.8 + ascent * 0.2

        let capacity = max(0, Int((rect.maxY - y + lineHeight) / lineHeight))
        for (index, row) in rows.prefix(capacity).enumerated() {
            let tint = rowTint(index)
            x = rect.minX
            for (columnIndex, column) in visible.enumerated() {
                guard columnIndex < row.count else { break }
                let text = Format.pad(row[columnIndex], column.chars, alignRight: column.alignRight)
                let color = column.accent ? theme.bright : theme.level(tint)
                canvas.text(text, at: CGPoint(x: x, y: y), font: font, color: color)
                x += CGFloat(column.chars + 1) * advance
            }
            y += lineHeight
        }
    }

    private func width(of columns: [Column], advance: CGFloat) -> CGFloat {
        CGFloat(columns.reduce(0) { $0 + $1.chars + 1 }) * advance
    }
}
