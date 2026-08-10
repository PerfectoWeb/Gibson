import CoreGraphics
import CoreText
import Foundation

/// Scrolling console. Lines are typed out a few characters at a time, which is
/// what sells the effect more than the content itself.
final class TerminalPanel: Panel {
    let title: String? = "session log"
    let redrawInterval: TimeInterval = 1.0 / 24

    private var lines: [String] = []
    private var pending = ""
    private var typed = 0
    private var holdUntil: TimeInterval = 0
    private var rng = Seeded(seed: 0xBADC0DE)
    private var lineIndex = 0
    private var primed = false

    func update(_ context: RenderContext) {
        if !primed {
            primed = true
            for _ in 0 ..< 24 { lines.append(nextLine(context)) }
        }
        guard context.time >= holdUntil else { return }

        if typed >= pending.count {
            if !pending.isEmpty {
                lines.append(pending)
                if lines.count > 80 { lines.removeFirst(lines.count - 80) }
            }
            pending = nextLine(context)
            typed = 0
            holdUntil = context.time + Double(rng.range(0.05, 0.35))
            return
        }

        typed = min(pending.count, typed + rng.int(1, 4))
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme
        let font = Fonts.mono((body.height / 22).clamped(6, 12))
        let lineHeight = Fonts.lineHeight(font) * 1.24
        let capacity = max(1, Int(body.height / lineHeight))

        let current = String(pending.prefix(typed))
        var visible = Array(lines.suffix(capacity - 1))
        visible.append(current)

        var y = body.maxY - CGFloat(visible.count) * lineHeight + CTFontGetAscent(font)
        for (index, line) in visible.enumerated() {
            let isCurrent = index == visible.count - 1
            let color = line.hasPrefix(">") ? theme.bright
                : (isCurrent ? theme.level(0.9) : theme.level(0.55))
            canvas.text(line, at: CGPoint(x: body.minX, y: y), font: font, color: color,
                        maxWidth: body.width)
            if isCurrent, context.time.truncatingRemainder(dividingBy: 1) < 0.5 {
                let x = body.minX + CGFloat(line.count) * Fonts.advance(font)
                canvas.fill(CGRect(x: x, y: y - CTFontGetAscent(font) * 0.85,
                                   width: Fonts.advance(font) * 0.8,
                                   height: CTFontGetAscent(font)), theme.bright)
            }
            y += lineHeight
        }
    }

    private func nextLine(_ context: RenderContext) -> String {
        let metrics = context.metrics
        if rng.chance(0.03) { return rng.pick(SyntheticData.easterEggs) }

        let template = SyntheticData.logLines[lineIndex % SyntheticData.logLines.count]
        lineIndex += 1

        let host = context.maskSensitiveInfo ? Format.mask(metrics.hostName, keep: 3) : metrics.hostName
        let user = context.maskSensitiveInfo ? Format.mask(metrics.userName) : metrics.userName

        return template
            .replacingOccurrences(of: "%HOST%", with: host)
            .replacingOccurrences(of: "%USER%", with: user)
            .replacingOccurrences(of: "%IFACE%", with: metrics.network.interface)
            .replacingOccurrences(of: "%HEX%", with: Format.hex(rng.int(0x1000, 0xFFFFFF), width: 8))
            .replacingOccurrences(of: "%NUM%", with: String(rng.int(2, 4096)))
            .replacingOccurrences(of: "%PORT%", with: String(rng.int(20, 9000)))
            .replacingOccurrences(of: "%SERVICE%", with: rng.pick(SyntheticData.services))
            .replacingOccurrences(of: "%SIG%", with: rng.pick(SyntheticData.signatures))
            .replacingOccurrences(of: "%NET%", with: "10.\(rng.int(0, 255)).\(rng.int(0, 255))")
    }
}

/// Hex dump that walks forward through an imaginary address space. Every so
/// often a run of bytes spells something in the ASCII gutter, which is what a
/// real dump does when it crosses a string table.
final class HexDumpPanel: Panel {
    let title: String? = "memory inspector"
    let redrawInterval: TimeInterval = 1.0 / 5

    private static let columns = 8

    /// Each entry is a run of rows, `columns` characters wide.
    private static let strings: [[String]] = [
        ["HACK THE", " PLANET "],
        ["WAKE UP,", " NEO... "],
        ["NO CARRI", "ER      "],
        ["THERE IS", " NO SPOO", "N       "],
        ["GHOST IN", " THE SHE", "LL      "],
        ["ZERO COO", "L WAS HE", "RE      "]
    ]

    /// Constants a real dump would actually contain.
    private static let magic: [[UInt8]] = [
        [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE],
        [0xFE, 0xED, 0xFA, 0xCF, 0x0C, 0x00, 0x00, 0x01],
        [0xC0, 0xFF, 0xEE, 0x00, 0x13, 0x37, 0xC0, 0xDE]
    ]

    private static let support: [String] = {
        let text = QRCode.supportURL
            .replacingOccurrences(of: "https://", with: "")
        return stride(from: 0, to: text.count, by: columns).map { offset in
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: min(columns, text.count - offset))
            return String(text[start ..< end]).padding(toLength: columns, withPad: " ", startingAt: 0)
        }
    }()

    private var address = 0x7FFE_0000

    func update(_ context: RenderContext) {
        address += Self.columns
    }

    /// Bytes to show at `rowAddress`, when it falls inside a planted run.
    private func planted(rowAddress: Int) -> [UInt8]? {
        let slot = rowAddress / Self.columns
        guard slot >= 0 else { return nil }

        for back in 0 ..< 3 {
            guard let run = run(startingAt: slot - back), back < run.count else { continue }
            return run[back]
        }
        return nil
    }

    private func run(startingAt slot: Int) -> [[UInt8]]? {
        guard slot >= 0 else { return nil }
        func rows(_ lines: [String]) -> [[UInt8]] {
            lines.map { Array($0.utf8) }
        }
        if slot % 500 == 0 { return rows(Self.support) }
        if slot % 150 == 0 {
            return rows(Self.strings[Int(hashUnit(UInt64(slot)) * CGFloat(Self.strings.count))
                % Self.strings.count])
        }
        if slot % 60 == 0 {
            return [Self.magic[Int(hashUnit(UInt64(slot) &+ 3) * CGFloat(Self.magic.count))
                % Self.magic.count]]
        }
        return nil
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let theme = context.theme

        // Pick a font that lets a full 8 byte row fit the available width.
        var size = (body.height / 14).clamped(5, 12)
        var font = Fonts.mono(size)
        let columns = Self.columns
        let lineChars = 8 + 2 + columns * 3 + 2 + columns
        while size > 5, CGFloat(lineChars) * Fonts.advance(font) > body.width {
            size -= 0.5
            font = Fonts.mono(size)
        }

        let lineHeight = Fonts.lineHeight(font) * 1.22
        let rows = max(1, Int(body.height / lineHeight))
        let advance = Fonts.advance(font)
        var y = body.minY + CTFontGetAscent(font)

        for row in 0 ..< rows {
            let rowAddress = address + row * columns
            var x = body.minX
            x += canvas.text(Format.hex(rowAddress, width: 8), at: CGPoint(x: x, y: y),
                             font: font, color: theme.dim)
            x += advance * 2

            let plant = planted(rowAddress: rowAddress)
            var ascii = ""
            for column in 0 ..< columns {
                let planted = plant.flatMap { $0.indices.contains(column) ? Int($0[column]) : nil }
                let byte = planted
                    ?? Int(hashUnit(UInt64(rowAddress &+ column) &* 2654435761) * 255)
                let hot = plant != nil || byte > 220
                canvas.text(Format.hex(byte, width: 2), at: CGPoint(x: x, y: y), font: font,
                            color: hot ? theme.bright : theme.level(0.45 + CGFloat(byte) / 512))
                x += advance * 3
                let printable = byte >= 32 && byte <= 126
                ascii.append(printable ? Character(UnicodeScalar(UInt8(byte))) : ".")
            }

            x += advance
            canvas.text("|\(ascii)|", at: CGPoint(x: x, y: y), font: font,
                        color: plant != nil ? theme.bright : theme.mid)
            y += lineHeight
        }
    }
}
