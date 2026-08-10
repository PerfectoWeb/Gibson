import CoreText
import QuartzCore

/// Everything a panel needs for one frame.
struct RenderContext {
    let theme: Theme
    let metrics: MetricsSnapshot
    let time: TimeInterval
    let isPreview: Bool
    let maskSensitiveInfo: Bool
    /// Matches the hosting layer's corner radius, so panel chrome follows it.
    let cornerRadius: CGFloat
}

/// A single readout in the dashboard. Each panel owns its animation state and
/// its own redraw cadence; the saver's frame rate is only an upper bound.
protocol Panel: AnyObject {
    /// Label drawn in the panel header. Nil hides the header entirely.
    var title: String? { get }

    /// Seconds between redraws. Text tables are cheap to keep slow, motion
    /// heavy panels ask for the full frame rate.
    var redrawInterval: TimeInterval { get }

    /// Called once per redraw before `draw`, for advancing state.
    func update(_ context: RenderContext)

    /// A value that changes whenever the output would. A panel driven purely by
    /// the metrics snapshot repaints ten times for every new sample otherwise.
    /// Nil, the default, means repaint on every tick.
    func contentKey(_ context: RenderContext) -> Int?

    func draw(_ canvas: Canvas, _ context: RenderContext)
}

extension Panel {
    var title: String? { nil }
    var redrawInterval: TimeInterval { 1.0 }
    func update(_ context: RenderContext) {}
    func contentKey(_ context: RenderContext) -> Int? { nil }
}

/// Shared chrome: fill, hairline border, header strip.
enum PanelChrome {
    /// Background and border only, for panels that carry no header.
    @discardableResult
    static func plain(_ canvas: Canvas, _ context: RenderContext) -> CGRect {
        draw(canvas, context, title: nil)
    }

    @discardableResult
    static func draw(_ canvas: Canvas, _ context: RenderContext, title: String?) -> CGRect {
        let theme = context.theme
        let radius = context.cornerRadius
        // A plain rect fill hits Core Graphics' fast path; the hosting layer
        // masks the corners for us. Only the border needs the rounded path.
        canvas.fill(canvas.bounds, theme.panelFill)
        canvas.strokeRounded(canvas.bounds, radius, theme.border)

        guard let title, !title.isEmpty, canvas.height > 26 else {
            return canvas.bounds.insetBy(dx: 6 + radius / 2, dy: 6)
        }

        let font = Fonts.mono(min(14, canvas.height / 18).clamped(8, 15), bold: true)
        // Text stays centred on the bar, so the extra height is shared.
        let barHeight = (Fonts.lineHeight(font) + 12).rounded()
        let bar = CGRect(x: 1, y: 1, width: canvas.width - 2, height: barHeight)
        // The hosting layer rounds the corners, so a plain rect is enough here.
        canvas.fill(bar, theme.fade(theme.border, 0.35))
        canvas.text(title.uppercased(),
                    at: CGPoint(x: 7 + radius / 2, y: bar.midY + CTFontGetCapHeight(font) / 2),
                    font: font, color: theme.bright, tracking: 1.2)
        canvas.line(CGPoint(x: 1, y: bar.maxY), CGPoint(x: canvas.width - 1, y: bar.maxY), theme.border)

        let inset = 6 + radius / 2
        return CGRect(x: inset, y: bar.maxY + 5,
                      width: canvas.width - inset * 2, height: canvas.height - bar.maxY - 11)
    }
}

/// Hosts one panel in the layer tree and throttles its redraws.
final class PanelLayer: CALayer {
    let panel: Panel
    private var nextRedraw: TimeInterval = 0
    private var lastContentKey: Int?
    private var context: RenderContext?

    init(panel: Panel) {
        self.panel = panel
        super.init()
        needsDisplayOnBoundsChange = true
        masksToBounds = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
                   "transform": NSNull(), "opacity": NSNull()]
    }

    override init(layer: Any) {
        panel = (layer as? PanelLayer)?.panel ?? EmptyPanel()
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    /// Returns true when the panel actually needed the frame.
    @discardableResult
    func tick(_ context: RenderContext) -> Bool {
        self.context = context
        guard context.time >= nextRedraw else { return false }
        nextRedraw = context.time + panel.redrawInterval
        panel.update(context)

        if let key = panel.contentKey(context) {
            guard key != lastContentKey else { return false }
            lastContentKey = key
        }
        setNeedsDisplay()
        return true
    }

    override func draw(in ctx: CGContext) {
        guard let context else { return }
        let canvas = Canvas(ctx: ctx, size: bounds.size)
        panel.draw(canvas, context)
    }
}

/// Placeholder so `init(layer:)` stays non-optional during implicit layer copies.
private final class EmptyPanel: Panel {
    func draw(_ canvas: Canvas, _ context: RenderContext) {}
}
