import CoreGraphics

/// A panel placed on a 12 column grid. Rows stretch to fill the display, which
/// is what lets one layout serve a laptop and a 6K monitor.
struct Slot {
    let make: () -> Panel
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

struct GridLayout {
    let columns: Int
    let rows: Int
    let slots: [Slot]

    /// The top row is a header strip and carries less than a full row of
    /// content, so it gets a fraction of a cell and the rows below share what
    /// it gives back.
    static let headerFraction: CGFloat = 0.82

    /// Slots are declared top down, layer frames are bottom up, so the row
    /// offset is measured from the top edge and then flipped.
    func frames(in bounds: CGRect, gutter: CGFloat) -> [(Slot, CGRect)] {
        let cellWidth = (bounds.width - gutter) / CGFloat(columns)
        let cellHeight = (bounds.height - gutter) / CGFloat(rows)

        let headerHeight = (cellHeight * Self.headerFraction).rounded()
        let bodyCell = rows > 1
            ? (bounds.height - gutter - headerHeight) / CGFloat(rows - 1)
            : cellHeight

        return slots.map { slot in
            let isHeader = slot.y == 0 && slot.height == 1
            let height = isHeader
                ? headerHeight - gutter
                : CGFloat(slot.height) * bodyCell - gutter
            let topOffset = slot.y == 0
                ? gutter
                : gutter + headerHeight + CGFloat(slot.y - 1) * bodyCell
            let rect = CGRect(
                x: bounds.minX + gutter + CGFloat(slot.x) * cellWidth,
                y: bounds.maxY - topOffset - height,
                width: CGFloat(slot.width) * cellWidth - gutter,
                height: height
            )
            return (slot, rect.integral)
        }
    }
}

enum LayoutCatalog {
    /// Picks a layout for the display shape. `variant` rotates the secondary
    /// panels so consecutive sessions do not look identical.
    static func layout(for size: CGSize, isPreview: Bool, variant: Int) -> GridLayout {
        if isPreview || min(size.width, size.height) < 320 {
            return compact
        }
        return size.height > size.width * 1.1 ? tall(variant) : wide(variant)
    }

    // MARK: - Wide

    private static func wide(_ variant: Int) -> GridLayout {
        let leftMiddle: () -> Panel = variant % 2 == 0
            ? { GaugeClusterPanel() }
            : { RadarPanel() }
        let centreMiddle: () -> Panel = variant % 2 == 0
            ? { HexDumpPanel() }
            : { HelixPanel() }
        let leftLower: () -> Panel = variant % 2 == 0
            ? { FlowLanesPanel() }
            : { WaveformPanel() }

        return GridLayout(columns: 12, rows: 13, slots: [
            Slot(make: { HeaderPanel() }, x: 0, y: 0, width: 12, height: 1),
            Slot(make: { GlobePanel() }, x: 0, y: 1, width: 3, height: 3),
            Slot(make: { ProcessTablePanel() }, x: 3, y: 1, width: 5, height: 3),
            Slot(make: { AccountsPanel() }, x: 8, y: 1, width: 4, height: 3),
            Slot(make: { ProgressStackPanel() }, x: 0, y: 4, width: 4, height: 1),
            Slot(make: { FileVaultPanel() }, x: 8, y: 4, width: 4, height: 5),
            Slot(make: leftMiddle, x: 0, y: 5, width: 4, height: 3),
            // The inspector and the vitals column share the middle band, split
            // three quarters to one quarter.
            Slot(make: centreMiddle, x: 4, y: 4, width: 3, height: 4),
            Slot(make: { VitalsPanel() }, x: 7, y: 4, width: 1, height: 4),
            Slot(make: leftLower, x: 0, y: 8, width: 4, height: 2),
            Slot(make: { TerminalPanel() }, x: 4, y: 8, width: 4, height: 5),
            Slot(make: { MatrixRainPanel() }, x: 8, y: 9, width: 4, height: 4),
            Slot(make: { BarMeterPanel() }, x: 0, y: 10, width: 4, height: 3)
        ])
    }

    // MARK: - Tall

    private static func tall(_ variant: Int) -> GridLayout {
        let filler: () -> Panel = variant % 2 == 0 ? { RadarPanel() } : { GlobePanel() }
        return GridLayout(columns: 8, rows: 18, slots: [
            Slot(make: { HeaderPanel() }, x: 0, y: 0, width: 8, height: 1),
            Slot(make: { CountdownPanel() }, x: 0, y: 1, width: 5, height: 2),
            Slot(make: { VitalsPanel() }, x: 5, y: 1, width: 3, height: 2),
            Slot(make: { ProcessTablePanel() }, x: 0, y: 3, width: 8, height: 3),
            Slot(make: { ProgressStackPanel() }, x: 0, y: 6, width: 8, height: 1),
            Slot(make: { GaugeClusterPanel() }, x: 0, y: 7, width: 4, height: 3),
            Slot(make: { HelixPanel() }, x: 4, y: 7, width: 4, height: 6),
            Slot(make: filler, x: 0, y: 10, width: 4, height: 3),
            Slot(make: { BarMeterPanel() }, x: 0, y: 13, width: 4, height: 2),
            Slot(make: { HexDumpPanel() }, x: 4, y: 13, width: 4, height: 2),
            Slot(make: { TerminalPanel() }, x: 0, y: 15, width: 4, height: 3),
            Slot(make: { MatrixRainPanel() }, x: 4, y: 15, width: 4, height: 3)
        ])
    }

    // MARK: - Compact

    /// System Settings renders the saver into a thumbnail a few hundred points
    /// wide. Anything with dense text is unreadable there.
    private static var compact: GridLayout {
        GridLayout(columns: 6, rows: 6, slots: [
            Slot(make: { HeaderPanel() }, x: 0, y: 0, width: 6, height: 1),
            Slot(make: { GlobePanel() }, x: 0, y: 1, width: 2, height: 2),
            Slot(make: { BarMeterPanel() }, x: 2, y: 1, width: 2, height: 2),
            Slot(make: { GaugeClusterPanel() }, x: 4, y: 1, width: 2, height: 2),
            Slot(make: { TerminalPanel() }, x: 0, y: 3, width: 4, height: 3),
            Slot(make: { MatrixRainPanel() }, x: 4, y: 3, width: 2, height: 3)
        ])
    }
}
