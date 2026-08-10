import CoreGraphics

/// Bitmap type in the shape of an early PC character ROM, drawn as square
/// pixels with a gap so the grid stays visible. Two faces: a heavy 8x8 for the
/// wordmark and a hairline 5x7 for captions.
///
/// Only the characters currently used are defined. Adding one is a matter of
/// appending its rows to the table.
struct PixelFace {
    let cellWidth: Int
    let cellHeight: Int
    let glyphs: [Character: [String]]
}

enum PixelFont {
    static let bold = PixelFace(cellWidth: 8, cellHeight: 8, glyphs: [
        "G": ["  ####  ", " ##  ## ", "##      ", "##  ### ",
              "##   ## ", " ##  ## ", "  ####  ", "        "],
        "I": [" ###### ", "   ##   ", "   ##   ", "   ##   ",
              "   ##   ", "   ##   ", " ###### ", "        "],
        "B": ["#####   ", "##  ##  ", "##  ##  ", "#####   ",
              "##  ##  ", "##  ##  ", "#####   ", "        "],
        "S": [" #####  ", "##   ## ", "##      ", " #####  ",
              "     ## ", "##   ## ", " #####  ", "        "],
        "O": [" #####  ", "##   ## ", "##   ## ", "##   ## ",
              "##   ## ", "##   ## ", " #####  ", "        "],
        "N": ["##   ## ", "###  ## ", "#### ## ", "## #### ",
              "##  ### ", "##   ## ", "##   ## ", "        "],
        " ": ["        ", "        ", "        ", "        ",
              "        ", "        ", "        ", "        "]
    ])

    static let thin = PixelFace(cellWidth: 5, cellHeight: 7, glyphs: [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."]
    ])

    /// Logo mark: a CRT with two scanlines and a pair of feet.
    static let screenMark = [
        "########",
        "#......#",
        "#.####.#",
        "#......#",
        "#.####.#",
        "#......#",
        "########",
        "..#..#.."
    ]

    static func width(_ text: String, face: PixelFace, pixel: CGFloat,
                      letterSpacing: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return CGFloat(text.count) * CGFloat(face.cellWidth) * pixel
            + CGFloat(text.count - 1) * letterSpacing
    }

    static func height(face: PixelFace, pixel: CGFloat) -> CGFloat {
        CGFloat(face.cellHeight) * pixel
    }

    /// Draws from the top-left corner of the matrix box.
    static func draw(_ text: String, face: PixelFace, in canvas: Canvas, at origin: CGPoint,
                     pixel: CGFloat, letterSpacing: CGFloat, color: CGColor) {
        let dot = max(1, pixel - max(0.4, pixel * 0.14))
        var x = origin.x

        for character in text.uppercased() {
            if let rows = face.glyphs[character] {
                draw(rows: rows, in: canvas, at: CGPoint(x: x, y: origin.y), pixel: pixel,
                     dot: dot, color: color)
            }
            x += CGFloat(face.cellWidth) * pixel + letterSpacing
        }
    }

    /// Draws a raw matrix, for marks that are not part of a face.
    static func draw(rows: [String], in canvas: Canvas, at origin: CGPoint,
                     pixel: CGFloat, color: CGColor) {
        draw(rows: rows, in: canvas, at: origin, pixel: pixel,
             dot: max(1, pixel - max(0.4, pixel * 0.14)), color: color)
    }

    private static func draw(rows: [String], in canvas: Canvas, at origin: CGPoint,
                             pixel: CGFloat, dot: CGFloat, color: CGColor) {
        for (row, line) in rows.enumerated() {
            for (column, mark) in line.enumerated() where mark == "#" {
                canvas.fill(CGRect(x: origin.x + CGFloat(column) * pixel,
                                   y: origin.y + CGFloat(row) * pixel,
                                   width: dot, height: dot), color)
            }
        }
    }
}
