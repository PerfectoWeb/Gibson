import CoreGraphics
import CoreText
import Foundation

/// Icon grid that gets sealed one entry at a time. Folders come first, then
/// files, and each entry shorts out for half a second before it flips to
/// locked. Purely theatrical: the names are generated, nothing on disk is read
/// or touched.
final class FileVaultPanel: Panel {
    let title: String? = "file manager"
    /// Fast enough that the short circuit flicker reads as a flicker.
    let redrawInterval: TimeInterval = 1.0 / 20

    private struct Item {
        let name: String
        let isFolder: Bool
    }

    private enum State {
        case clear
        case locking(since: TimeInterval)
        case locked
    }

    private static let folderWords = [
        "audit", "payroll", "budget", "contracts", "forecast", "legal_hold",
        "vendors", "board", "patents", "tax", "clients", "escrow", "archive",
        "backups", "hr", "m_and_a", "treasury", "compliance"
    ]

    private static let fileWords = [
        "client_list", "cap_table", "wire_log", "keystore", "master_index",
        "nda_signed", "q4_report", "access_log", "salary_band", "merger_terms",
        "board_minutes", "vendor_keys", "risk_matrix", "settlement"
    ]

    private static let folderSuffixes = ["", "", "_2024", "_2025", "_q3", "_q4", "_v2", "_final"]
    private static let fileTypes = ["xlsx", "pdf", "csv", "key", "db", "p12", "docx"]

    private let lockDuration: TimeInterval = 0.55
    private let restDuration: TimeInterval = 6

    private var items: [Item] = []
    private var states: [State] = []
    private var cursor = 0
    private var nextEvent: TimeInterval = 0
    private var restUntil: TimeInterval = 0

    // MARK: - State

    func update(_ context: RenderContext) {
        if items.isEmpty {
            regenerate()
            nextEvent = context.time + 1.5
        }

        for index in states.indices {
            if case let .locking(since) = states[index], context.time - since >= lockDuration {
                states[index] = .locked
            }
        }

        guard context.time >= restUntil, context.time >= nextEvent else { return }

        if cursor >= items.count {
            regenerate()
            restUntil = context.time + 1.2
            nextEvent = context.time + 1.2
            return
        }

        states[cursor] = .locking(since: context.time)
        cursor += 1
        nextEvent = context.time + Double.random(in: 0.3 ... 1.1)
        if cursor >= items.count { restUntil = context.time + restDuration }
    }

    private func regenerate() {
        var generated: [Item] = []
        for word in Self.folderWords.shuffled().prefix(20) {
            generated.append(Item(name: word + (Self.folderSuffixes.randomElement() ?? ""),
                                  isFolder: true))
        }
        for word in Self.fileWords.shuffled().prefix(14) {
            let type = Self.fileTypes.randomElement() ?? "dat"
            generated.append(Item(name: "\(word).\(type)", isFolder: false))
        }
        items = generated
        states = Array(repeating: .clear, count: generated.count)
        cursor = 0
    }

    // MARK: - Drawing

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme
        guard !items.isEmpty else { return }

        let footerHeight = min(body.height * 0.12, 18)
        let grid = CGRect(x: body.minX, y: body.minY,
                          width: body.width, height: body.height - footerHeight)

        let target = (grid.width / 6).clamped(52, 104)
        let columns = max(2, Int(grid.width / target))
        let cellWidth = grid.width / CGFloat(columns)
        let rows = max(1, Int(grid.height / (cellWidth * 0.92)))
        let cellHeight = grid.height / CGFloat(rows)
        let visible = min(items.count, columns * rows)
        let font = Fonts.mono((cellHeight * 0.14).clamped(5, 10))

        for index in 0 ..< visible {
            let cell = CGRect(x: grid.minX + CGFloat(index % columns) * cellWidth,
                              y: grid.minY + CGFloat(index / columns) * cellHeight,
                              width: cellWidth, height: cellHeight)
            draw(index: index, in: cell, canvas: canvas, context: context, font: font)
        }

        var sealed = 0
        for state in states.prefix(visible) {
            if case .locked = state { sealed += 1 }
        }
        let footerFont = Fonts.mono((footerHeight * 0.62).clamped(6, 11), bold: true)
        canvas.text("ENCRYPTED \(sealed)/\(visible)",
                    at: CGPoint(x: body.minX, y: body.maxY),
                    font: footerFont, color: sealed >= visible ? theme.alert : theme.mid)
        canvas.text("\(Int(Double(sealed) / Double(max(1, visible)) * 100))%",
                    at: CGPoint(x: body.maxX, y: body.maxY),
                    font: footerFont, color: theme.bright, alignment: .right)
    }

    private func draw(index: Int, in cell: CGRect, canvas: Canvas, context: RenderContext,
                      font: CTFont) {
        let theme = context.theme
        let item = items[index]
        let state = states[index]

        let iconHeight = cell.height * 0.42
        let iconWidth = min(cell.width * 0.52, iconHeight * 1.2)
        let icon = CGRect(x: cell.midX - iconWidth / 2,
                          y: cell.minY + cell.height * 0.1,
                          width: iconWidth, height: iconHeight)

        var colour = theme.mid
        var label = item.name
        var labelColour = theme.dim

        switch state {
        case .clear:
            break
        case .locked:
            colour = theme.alert
            labelColour = theme.fade(theme.alert, 0.85)
        case let .locking(since):
            let progress = ((context.time - since) / lockDuration).clamped(0, 1)
            let frame = Int((context.time - since) * 26)
            let live = hashUnit(UInt64(frame) &+ UInt64(index) &* 31) > 0.42
            colour = live ? theme.accent : theme.alert
            labelColour = colour
            if progress < 0.75 {
                label = scramble(item.name, seed: UInt64(frame))
            }
        }

        if item.isFolder {
            drawFolder(icon, canvas: canvas, colour: colour, theme: theme)
        } else {
            drawFile(icon, canvas: canvas, colour: colour, theme: theme)
        }

        if case let .locking(since) = state {
            drawShort(icon, canvas: canvas, theme: theme, index: index,
                      elapsed: context.time - since)
        }

        if case .locked = state {
            // Corner badge rather than a stamp across the icon, so the folder
            // or page shape still reads at a glance.
            let badge = icon.height * 0.42
            // The page glyph is inset inside its box, so the badge has to follow
            // it in rather than hang off the right edge.
            let right = item.isFolder ? icon.maxX : icon.maxX - icon.width * 0.1
            LockGlyph.draw(canvas,
                           in: CGRect(x: right - badge * 1.05, y: icon.maxY - badge * 1.32,
                                      width: badge * 0.8, height: badge),
                           color: theme.alert)
        }

        canvas.text(label, at: CGPoint(x: cell.midX, y: cell.maxY - Fonts.lineHeight(font) * 0.5),
                    font: font, color: labelColour,
                    maxWidth: cell.width - 4, alignment: .center)
    }

    /// Manila folder: a tab, a body, and the lip of the flap across the front.
    private func drawFolder(_ rect: CGRect, canvas: Canvas, colour: CGColor, theme: Theme) {
        let tabWidth = rect.width * 0.4
        let tabHeight = rect.height * 0.16
        let outline = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX + tabWidth, y: rect.minY),
            CGPoint(x: rect.minX + tabWidth + tabHeight, y: rect.minY + tabHeight),
            CGPoint(x: rect.maxX, y: rect.minY + tabHeight),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        canvas.fillPolygon(outline, theme.fade(colour, 0.12))
        canvas.polyline(outline, colour, width: 1.3, closed: true)
        canvas.line(CGPoint(x: rect.minX, y: rect.minY + tabHeight * 2.1),
                    CGPoint(x: rect.maxX, y: rect.minY + tabHeight * 2.1),
                    theme.fade(colour, 0.6))
    }

    /// Sheet of paper with a folded corner and a few lines of body text.
    private func drawFile(_ rect: CGRect, canvas: Canvas, colour: CGColor, theme: Theme) {
        let page = rect.insetBy(dx: rect.width * 0.1, dy: 0)
        let fold = page.width * 0.3
        let outline = [
            CGPoint(x: page.minX, y: page.minY),
            CGPoint(x: page.maxX - fold, y: page.minY),
            CGPoint(x: page.maxX, y: page.minY + fold),
            CGPoint(x: page.maxX, y: page.maxY),
            CGPoint(x: page.minX, y: page.maxY)
        ]
        canvas.fillPolygon(outline, theme.fade(colour, 0.1))
        canvas.polyline(outline, colour, width: 1.3, closed: true)
        canvas.polyline([
            CGPoint(x: page.maxX - fold, y: page.minY),
            CGPoint(x: page.maxX - fold, y: page.minY + fold),
            CGPoint(x: page.maxX, y: page.minY + fold)
        ], theme.fade(colour, 0.8))

        for line in 0 ..< 3 {
            let y = page.minY + fold * 1.6 + CGFloat(line) * page.height * 0.17
            guard y < page.maxY - 2 else { break }
            let inset = page.width * (line == 2 ? 0.42 : 0.2)
            canvas.line(CGPoint(x: page.minX + page.width * 0.15, y: y),
                        CGPoint(x: page.maxX - inset, y: y), theme.fade(colour, 0.55))
        }
    }

    /// The short circuit: torn slices of the icon plus a spark across it.
    private func drawShort(_ rect: CGRect, canvas: Canvas, theme: Theme, index: Int,
                           elapsed: TimeInterval) {
        let frame = UInt64(elapsed * 26) &+ UInt64(index) &* 977
        let slices = 3
        for slice in 0 ..< slices {
            let seed = frame &+ UInt64(slice) &* 41
            guard hashUnit(seed) > 0.45 else { continue }
            let height = rect.height * (0.06 + hashUnit(seed &+ 1) * 0.16)
            let y = rect.minY + hashUnit(seed &+ 2) * (rect.height - height)
            let offset = (hashUnit(seed &+ 3) - 0.5) * rect.width * 0.5
            canvas.fill(CGRect(x: rect.minX + offset, y: y, width: rect.width, height: height),
                        theme.fade(theme.alert, 0.5))
        }

        if hashUnit(frame &+ 7) > 0.5 {
            let y = rect.midY + (hashUnit(frame) - 0.5) * rect.height * 0.4
            canvas.line(CGPoint(x: rect.minX - rect.width * 0.15, y: y),
                        CGPoint(x: rect.maxX + rect.width * 0.15, y: y),
                        theme.accent, width: 1.6)
        }
    }

    private func scramble(_ name: String, seed: UInt64) -> String {
        let alphabet = Array("#@$%&*!?/\\|<>0123456789ABCDEF")
        return String(name.enumerated().map { offset, character -> Character in
            let noise = hashUnit(seed &+ UInt64(offset) &* 13)
            return noise > 0.45 ? alphabet[Int(noise * CGFloat(alphabet.count)) % alphabet.count]
                                : character
        })
    }
}

/// Padlock badge for a sealed entry.
enum LockGlyph {
    static func draw(_ canvas: Canvas, in rect: CGRect, color: CGColor) {
        let bodyHeight = rect.height * 0.58
        let body = CGRect(x: rect.minX, y: rect.maxY - bodyHeight,
                          width: rect.width, height: bodyHeight)
        canvas.fill(body, color)

        let shackleRadius = rect.width * 0.28
        let shackleCenter = CGPoint(x: rect.midX, y: body.minY)
        let steps = 24
        let points = (0 ... steps).map { step -> CGPoint in
            let angle = CGFloat.pi + CGFloat.pi * CGFloat(step) / CGFloat(steps)
            return CGPoint(x: shackleCenter.x + cos(angle) * shackleRadius,
                           y: shackleCenter.y + sin(angle) * shackleRadius)
        }
        canvas.polyline(points, color, width: max(1, rect.width * 0.1))

        let keyRadius = max(1, rect.width * 0.09)
        canvas.disc(CGPoint(x: body.midX, y: body.midY - keyRadius * 0.4), keyRadius,
                    CGColor(gray: 0, alpha: 1))
    }
}
