import AppKit
import CoreText

enum TextAlignment {
    case left
    case center
    case right
}

/// Drawing surface with a top-left origin so panel code reads like layout code.
/// The flip is applied once here instead of in every panel.
struct Canvas {
    let ctx: CGContext
    let size: CGSize

    init(ctx: CGContext, size: CGSize) {
        self.ctx = ctx
        self.size = size
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.miter)
    }

    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    var width: CGFloat { size.width }
    var height: CGFloat { size.height }

    func clip(to rect: CGRect) { ctx.clip(to: rect) }

    /// Applies to everything drawn afterwards, used for cross fades.
    func alpha(_ value: CGFloat) { ctx.setAlpha(value) }

    func withState(_ body: (Canvas) -> Void) {
        ctx.saveGState()
        body(self)
        ctx.restoreGState()
    }

    // MARK: - Shapes

    func fill(_ rect: CGRect, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fill(rect)
    }

    func fillRounded(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.addPath(Self.roundedPath(rect, radius))
        ctx.fillPath()
    }

    func strokeRounded(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor, width: CGFloat = 1) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.addPath(Self.roundedPath(rect.insetBy(dx: width / 2, dy: width / 2), radius))
        ctx.strokePath()
    }

    func clipRounded(_ rect: CGRect, _ radius: CGFloat) {
        ctx.addPath(Self.roundedPath(rect, radius))
        ctx.clip()
    }

    private static func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        let limit = min(radius, min(rect.width, rect.height) / 2)
        return CGPath(roundedRect: rect, cornerWidth: limit, cornerHeight: limit, transform: nil)
    }

    func stroke(_ rect: CGRect, _ color: CGColor, width: CGFloat = 1) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.stroke(rect.insetBy(dx: width / 2, dy: width / 2))
    }

    func line(_ from: CGPoint, _ to: CGPoint, _ color: CGColor, width: CGFloat = 1) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    func polyline(_ points: [CGPoint], _ color: CGColor, width: CGFloat = 1, closed: Bool = false) {
        guard points.count > 1 else { return }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.beginPath()
        ctx.addLines(between: points)
        if closed { ctx.closePath() }
        ctx.strokePath()
    }

    func fillPolygon(_ points: [CGPoint], _ color: CGColor) {
        guard points.count > 2 else { return }
        ctx.setFillColor(color)
        ctx.beginPath()
        ctx.addLines(between: points)
        ctx.closePath()
        ctx.fillPath()
    }

    func circle(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor, width: CGFloat = 1) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: rect)
    }

    func disc(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: rect)
    }

    /// Corner ticks used as lightweight panel chrome.
    func brackets(_ rect: CGRect, _ color: CGColor, length: CGFloat = 8, width: CGFloat = 1) {
        let l = min(length, min(rect.width, rect.height) / 3)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY + l), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + l, y: rect.minY)),
            (CGPoint(x: rect.maxX - l, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + l)),
            (CGPoint(x: rect.maxX, y: rect.maxY - l), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX - l, y: rect.maxY)),
            (CGPoint(x: rect.minX + l, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - l))
        ]
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.beginPath()
        for corner in corners {
            ctx.move(to: corner.0)
            ctx.addLine(to: corner.1)
            ctx.addLine(to: corner.2)
        }
        ctx.strokePath()
    }

    /// Soft radial falloff, used behind the globe and anywhere a panel needs
    /// depth without a hard edge. Rasterising a gradient is expensive and this
    /// one never changes, so it is baked into an image the first time.
    func radialGlow(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor, alpha: CGFloat) {
        guard radius > 0, alpha > 0 else { return }
        let scale = max(1, abs(ctx.ctm.a))
        guard let image = Canvas.glowImage(radius: radius, color: color,
                                           alpha: alpha, scale: scale) else { return }
        let box = CGRect(x: center.x - radius, y: center.y - radius,
                         width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(image, in: box)
        ctx.restoreGState()
    }

    private struct GlowKey: Hashable {
        let radius: CGFloat
        let color: ObjectIdentifier
        let alpha: CGFloat
        let scale: CGFloat
    }

    private static var glows: [GlowKey: (source: CGColor, image: CGImage)] = [:]

    private static func glowImage(radius: CGFloat, color: CGColor,
                                  alpha: CGFloat, scale: CGFloat) -> CGImage? {
        let key = GlowKey(radius: radius.rounded(), color: ObjectIdentifier(color),
                          alpha: alpha, scale: scale)
        if let hit = glows[key] { return hit.image }

        let side = Int((radius * 2 * scale).rounded())
        guard side > 0,
              let space = gradientSpace,
              let inner = color.copy(alpha: alpha),
              let outer = color.copy(alpha: 0),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [inner, outer] as CFArray,
                                        locations: [0, 1]),
              let ctx = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let centre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: radius * scale, options: [])
        guard let image = ctx.makeImage() else { return nil }
        glows[key] = (color, image)
        return image
    }

    /// Created once: gradients are rebuilt every frame and the colour space
    /// lookup is not free.
    private static let gradientSpace = CGColorSpace(name: CGColorSpace.sRGB)

    /// Vertical falloff between two alphas of the same colour.
    func verticalFade(_ rect: CGRect, _ color: CGColor, top: CGFloat, bottom: CGFloat) {
        guard let space = Canvas.gradientSpace,
              let start = color.copy(alpha: top),
              let end = color.copy(alpha: bottom),
              let gradient = CGGradient(colorsSpace: space,
                                        colors: [start, end] as CFArray,
                                        locations: [0, 1])
        else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    // MARK: - Text

    /// Draws a line built earlier. Panels that repeat a small alphabet thousands
    /// of times a frame build their lines once and come through here.
    func draw(_ line: CTLine, at point: CGPoint) {
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    /// Builds a line without drawing it, for those caches.
    static func line(_ string: String, font: CTFont, color: CGColor,
                     tracking: CGFloat = 0) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
            .init(kCTKernAttributeName as String): tracking
        ]
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
    }

    @discardableResult
    func text(_ string: String, at point: CGPoint, font: CTFont, color: CGColor,
              alignment: TextAlignment = .left, tracking: CGFloat = 0) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
            .init(kCTKernAttributeName as String): tracking
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var x = point.x
        switch alignment {
        case .left: break
        case .center: x -= width / 2
        case .right: x -= width
        }
        ctx.textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, ctx)
        return width
    }

    /// Draws `string` clipped to `width`, truncating with no ellipsis (terminal style).
    @discardableResult
    func text(_ string: String, at point: CGPoint, font: CTFont, color: CGColor,
              maxWidth: CGFloat, alignment: TextAlignment = .left) -> CGFloat {
        let capacity = max(1, Int(maxWidth / Fonts.advance(font)))
        let clipped = string.count > capacity ? String(string.prefix(capacity)) : string
        return text(clipped, at: point, font: font, color: color, alignment: alignment)
    }
}
