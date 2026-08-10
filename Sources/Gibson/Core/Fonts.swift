import AppKit
import CoreText

/// Cached monospaced fonts. Panels ask for a size on every redraw, which makes
/// an uncached lookup surprisingly expensive.
enum Fonts {
    private struct Key: Hashable {
        let size: CGFloat
        let bold: Bool
    }

    private static var cache: [Key: CTFont] = [:]
    private static var advances: [Key: CGFloat] = [:]

    static func mono(_ size: CGFloat, bold: Bool = false) -> CTFont {
        let key = Key(size: (size * 2).rounded() / 2, bold: bold)
        if let cached = cache[key] { return cached }

        let font = NSFont(name: bold ? "SFMono-Bold" : "SFMono-Regular", size: key.size)
            ?? NSFont(name: bold ? "Menlo-Bold" : "Menlo-Regular", size: key.size)
            ?? NSFont.monospacedSystemFont(ofSize: key.size, weight: bold ? .bold : .regular)
        let ctFont = font as CTFont
        cache[key] = ctFont
        advances[key] = measureAdvance(ctFont)
        return ctFont
    }

    /// Width of a single character. Valid because every font here is monospaced.
    static func advance(_ font: CTFont) -> CGFloat {
        let key = Key(size: CTFontGetSize(font),
                      bold: CTFontGetSymbolicTraits(font).contains(.traitBold))
        if let cached = advances[key] { return cached }
        let width = measureAdvance(font)
        advances[key] = width
        return width
    }

    private static func measureAdvance(_ font: CTFont) -> CGFloat {
        var character: UniChar = 0x30
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        return advance.width > 0 ? advance.width : CTFontGetSize(font) * 0.6
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }
}
