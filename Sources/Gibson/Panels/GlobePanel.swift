import CoreGraphics
import CoreText
import Foundation

/// Wireframe globe under orthographic projection. Parallels and meridians are
/// generated per frame. Back facing segments are dimmed instead of culled,
/// which is what makes the sphere read as transparent. The rings around it are
/// drawn as dots, every tenth one enlarged like a bearing scale.
final class GlobePanel: Panel {
    let title: String? = "global uplink"
    let redrawInterval: TimeInterval = 1.0 / 30

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        canvas.withState { canvas in
            canvas.clip(to: body)
            drawGlobe(canvas, in: body, context: context)
        }
    }

    private struct Site {
        let latitude: CGFloat
        let longitude: CGFloat
        let code: String
    }

    private lazy var sites: [Site] = {
        var rng = Seeded(seed: 0xEA27)
        return (0 ..< 12).map { _ in
            Site(latitude: rng.range(-1.1, 1.1),
                 longitude: rng.range(0, .pi * 2),
                 code: String(format: "%03d", rng.int(1, 999)))
        }
    }()

    private let parallels = 6
    private let meridians = 10

    private func drawGlobe(_ canvas: Canvas, in body: CGRect, context: RenderContext) {
        let theme = context.theme
        let center = CGPoint(x: body.midX, y: body.midY)
        let radius = min(body.width, body.height) * 0.30
        let spin = CGFloat(context.time) * 0.28
        let tilt: CGFloat = 0.36

        canvas.radialGlow(center, radius * 1.5, theme.mid, alpha: 0.13)
        canvas.brackets(body, theme.fade(theme.border, 0.9), length: min(body.width, body.height) * 0.12)

        // One instrument ring plus the orbit. Two rings and denser dots looked
        // busy and cost noticeably more per frame.
        dottedRing(canvas, center: center, radius: radius * 1.22, dots: 72,
                   rotation: CGFloat(context.time) * 0.09, theme: theme, size: 0.85)
        canvas.circle(center, radius * 1.09, theme.fade(theme.border, 0.8))

        orbit(canvas, center: center, radius: radius * 1.5, time: context.time, theme: theme)

        for index in 1 ..< parallels {
            let latitude = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(index) / CGFloat(parallels)
            drawRing(canvas, center: center, radius: radius, spin: spin, tilt: tilt,
                     theme: theme, sample: { longitude in (latitude, longitude) })
        }

        for index in 0 ..< meridians {
            let longitude = CGFloat.pi * 2 * CGFloat(index) / CGFloat(meridians)
            drawRing(canvas, center: center, radius: radius, spin: spin, tilt: tilt,
                     theme: theme, sample: { angle in (angle - .pi, longitude) })
        }

        scanSweep(canvas, center: center, radius: radius, time: context.time, theme: theme)

        let font = Fonts.mono((radius * 0.15).clamped(5, 10))
        for site in sites {
            let point = project(latitude: site.latitude, longitude: site.longitude + spin,
                                center: center, radius: radius, tilt: tilt)
            guard point.depth > 0 else { continue }
            let pulse = 0.5 + 0.5 * sin(CGFloat(context.time) * 2.4 + site.longitude * 3)
            canvas.disc(point.position, 1.6 + pulse * 1.4, theme.fade(theme.bright, 0.4 + pulse * 0.6))
            if pulse > 0.75 {
                canvas.circle(point.position, 3 + pulse * 5, theme.fade(theme.bright, 1 - pulse))
                canvas.text(site.code, at: CGPoint(x: point.position.x + 5, y: point.position.y - 3),
                            font: font, color: theme.fade(theme.mid, pulse))
            }
        }

        let label = Fonts.mono((body.height * 0.07).clamped(5, 10))
        let lineHeight = Fonts.lineHeight(label)
        // Equal breathing room on the left and the bottom.
        let pad: CGFloat = 12
        canvas.text("LAT \(String(format: "%+06.2f", Double(sin(spin) * 60)))",
                    at: CGPoint(x: body.minX + pad, y: body.maxY - pad - lineHeight),
                    font: label, color: theme.dim)
        canvas.text("LON \(String(format: "%+07.2f", Double(spin.truncatingRemainder(dividingBy: .pi * 2) * 57.3)))",
                    at: CGPoint(x: body.minX + pad, y: body.maxY - pad),
                    font: label, color: theme.dim)
    }

    // MARK: - Rings

    /// Ring of dots with every tenth one enlarged, so it reads as a scale.
    private func dottedRing(_ canvas: Canvas, center: CGPoint, radius: CGFloat, dots: Int,
                            rotation: CGFloat, theme: Theme, size: CGFloat) {
        for index in 0 ..< dots {
            let angle = rotation + CGFloat.pi * 2 * CGFloat(index) / CGFloat(dots)
            let major = index % 10 == 0
            canvas.disc(CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius),
                        major ? size * 1.15 : size * 0.5,
                        major ? theme.bright : theme.fade(theme.mid, 0.5))
        }
    }

    /// Satellite on a tilted ellipse. The track is dotted like the rings.
    private func orbit(_ canvas: Canvas, center: CGPoint, radius: CGFloat,
                       time: TimeInterval, theme: Theme) {
        let tiltCos = cos(CGFloat(0.42)), tiltSin = sin(CGFloat(0.42))
        func point(_ angle: CGFloat) -> CGPoint {
            let x = cos(angle) * radius
            let y = sin(angle) * radius * 0.34
            return CGPoint(x: center.x + x * tiltCos - y * tiltSin,
                           y: center.y + x * tiltSin + y * tiltCos)
        }

        let dots = 60
        for index in 0 ..< dots {
            let major = index % 10 == 0
            canvas.disc(point(CGFloat.pi * 2 * CGFloat(index) / CGFloat(dots)),
                        major ? 1.15 : 0.5,
                        major ? theme.mid : theme.fade(theme.border, 0.95))
        }

        let head = CGFloat(time) * 0.5
        for step in 0 ..< 14 {
            let fade = 1 - CGFloat(step) / 14
            canvas.disc(point(head - CGFloat(step) * 0.035), 1 + fade * 1.6,
                        theme.fade(theme.bright, fade * 0.7))
        }
    }

    /// Horizontal scan travelling down the sphere, clipped to its silhouette.
    private func scanSweep(_ canvas: Canvas, center: CGPoint, radius: CGFloat,
                           time: TimeInterval, theme: Theme) {
        let progress = CGFloat(time * 0.32).truncatingRemainder(dividingBy: 1)
        let y = center.y - radius + progress * radius * 2
        let sphere = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)

        canvas.withState { canvas in
            canvas.ctx.beginPath()
            canvas.ctx.addEllipse(in: sphere)
            canvas.ctx.clip()
            let bandHeight = radius * 0.5
            canvas.verticalFade(CGRect(x: sphere.minX, y: y - bandHeight,
                                       width: sphere.width, height: bandHeight),
                                theme.bright, top: 0, bottom: 0.16)
            canvas.line(CGPoint(x: sphere.minX, y: y), CGPoint(x: sphere.maxX, y: y),
                        theme.fade(theme.accent, 0.5))
        }
    }

    // MARK: - Sphere

    private func drawRing(_ canvas: Canvas, center: CGPoint, radius: CGFloat,
                          spin: CGFloat, tilt: CGFloat, theme: Theme,
                          sample: (CGFloat) -> (CGFloat, CGFloat)) {
        let steps = 40
        var front: [CGPoint] = []
        var back: [CGPoint] = []

        for step in 0 ... steps {
            let angle = CGFloat.pi * 2 * CGFloat(step) / CGFloat(steps)
            let (latitude, longitude) = sample(angle)
            let projected = project(latitude: latitude, longitude: longitude + spin,
                                    center: center, radius: radius, tilt: tilt)
            if projected.depth > 0 {
                if !back.isEmpty {
                    canvas.polyline(back, theme.fade(theme.border, 0.75))
                    back.removeAll(keepingCapacity: true)
                }
                front.append(projected.position)
            } else {
                if !front.isEmpty {
                    canvas.polyline(front, theme.mid)
                    front.removeAll(keepingCapacity: true)
                }
                back.append(projected.position)
            }
        }
        if !front.isEmpty { canvas.polyline(front, theme.mid) }
        if !back.isEmpty { canvas.polyline(back, theme.fade(theme.border, 0.75)) }
    }

    private func project(latitude: CGFloat, longitude: CGFloat, center: CGPoint,
                         radius: CGFloat, tilt: CGFloat) -> (position: CGPoint, depth: CGFloat) {
        let x = cos(latitude) * sin(longitude)
        let y = sin(latitude)
        let z = cos(latitude) * cos(longitude)
        let ty = y * cos(tilt) - z * sin(tilt)
        let tz = y * sin(tilt) + z * cos(tilt)
        return (CGPoint(x: center.x + x * radius, y: center.y - ty * radius), tz)
    }
}
