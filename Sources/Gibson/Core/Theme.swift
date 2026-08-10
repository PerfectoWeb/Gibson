import AppKit

/// Colour families offered in the configuration sheet.
enum Palette: String, CaseIterable {
    case green
    case amber
    case cyan
    case magenta

    var title: String {
        switch self {
        case .green: return "Phosphor Green"
        case .amber: return "Amber CRT"
        case .cyan: return "Ice Cyan"
        case .magenta: return "Neon Magenta"
        }
    }

    fileprivate var hue: CGFloat {
        switch self {
        case .green: return 0.39
        case .amber: return 0.10
        case .cyan: return 0.50
        case .magenta: return 0.84
        }
    }
}

/// A ladder of tints derived from a single hue. Panels never pick a colour of
/// their own, they pick a rung.
struct Theme {
    let palette: Palette
    let background: CGColor
    let panelFill: CGColor
    let grid: CGColor
    let border: CGColor
    let dim: CGColor
    let mid: CGColor
    let bright: CGColor
    let accent: CGColor
    let warning: CGColor
    let alert: CGColor

    init(palette: Palette) {
        self.palette = palette
        let h = palette.hue
        background = Theme.hsb(h, 0.90, 0.020)
        panelFill = Theme.hsb(h, 0.85, 0.050)
        grid = Theme.hsb(h, 0.80, 0.150)
        border = Theme.hsb(h, 0.75, 0.330)
        dim = Theme.hsb(h, 0.85, 0.460)
        mid = Theme.hsb(h, 0.80, 0.720)
        bright = Theme.hsb(h, 0.58, 1.000)
        accent = Theme.hsb(h, 0.16, 1.000)
        warning = Theme.hsb(0.11, 0.90, 1.000)
        alert = Theme.hsb(0.00, 0.78, 1.000)
    }

    /// Blend between the dim and bright ends of the ladder.
    func level(_ t: CGFloat) -> CGColor {
        let clamped = min(max(t, 0), 1)
        let key = LevelKey(hue: palette.hue, level: clamped)
        if let hit = Theme.levels[key] { return hit }
        let colour = Theme.hsb(palette.hue, 0.85 - 0.27 * clamped, 0.42 + 0.58 * clamped)
        Theme.levels[key] = colour
        return colour
    }

    func fade(_ color: CGColor, _ alpha: CGFloat) -> CGColor {
        let key = FadeKey(source: ObjectIdentifier(color), alpha: alpha)
        if let hit = Theme.fades[key] { return hit.result }
        let colour = color.copy(alpha: alpha) ?? color
        // The source is held alongside the result: the key is its address, and a
        // released colour could see that address reused by another one.
        Theme.fades[key] = (color, colour)
        return colour
    }

    // Panels ask for the same handful of tints thousands of times a second, and
    // both the NSColor bridge and copy(alpha:) allocate. Returning the same
    // object also lets Core Graphics reuse its resolved device colour.

    private struct LevelKey: Hashable {
        let hue: CGFloat
        let level: CGFloat
    }

    private struct FadeKey: Hashable {
        let source: ObjectIdentifier
        let alpha: CGFloat
    }

    private static var levels: [LevelKey: CGColor] = [:]
    private static var fades: [FadeKey: (source: CGColor, result: CGColor)] = [:]

    private static func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat) -> CGColor {
        NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: 1).cgColor
    }
}
