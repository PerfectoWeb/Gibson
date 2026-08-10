import QuartzCore

/// Static CRT treatment: scanlines plus a vignette. Redrawn only when the
/// bounds change, so it costs nothing per frame.
final class OverlayLayer: CALayer {
    var theme = Theme(palette: .green)
    var enabled = true

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(in ctx: CGContext) {
        guard enabled else { return }
        let canvas = Canvas(ctx: ctx, size: bounds.size)
        let line = CGColor(gray: 0, alpha: 0.22)
        var y: CGFloat = 0
        while y < canvas.height {
            canvas.fill(CGRect(x: 0, y: y, width: canvas.width, height: 1), line)
            y += 3
        }

        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)] as CFArray
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.55, 1])
        else { return }
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: max(canvas.width, canvas.height) * 0.75,
                               options: .drawsAfterEndLocation)
    }
}

/// Cold boot log, typed out a character at a time and then faded. The middle of
/// the script is shuffled on every launch, so two sessions never open the same
/// way.
final class BootLayer: CALayer {
    var theme = Theme(palette: .green)
    var enabled = true

    private static let checks = [
        "checking parity ............. ok",
        "mounting /dev/telemetry ..... ok",
        "probing cores ............... ok",
        "opening raw socket .......... ok",
        "seeding entropy pool ........ ok",
        "calibrating phosphor ........ ok",
        "loading panel modules ....... ok",
        "handshake @ 56k ............. ok",
        "decrypting session key ...... ok",
        "spinning up the globe ....... ok"
    ]

    private static let asides = [
        ["> whoami", "operator"],
        ["> knock, knock", "nobody home"],
        ["> uptime", "long enough"],
        ["> who else is on", "just you. probably."],
        ["> status", "the screen is yours"]
    ]

    /// Characters per second. Fast enough that the whole thing clears in ~2s.
    private static let rate: Double = 105

    private var script: [String] = []
    private var revealed = 0
    private var total = 1
    private var finished = false

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    func reset() {
        script = Self.makeScript()
        total = max(1, script.reduce(0) { $0 + $1.count })
        revealed = 0
        finished = false
        opacity = 1
        isHidden = !enabled
        setNeedsDisplay()
    }

    private static func makeScript() -> [String] {
        var lines = ["GIBSON // COLD BOOT", ""]
        lines += checks.shuffled().prefix(Int.random(in: 4 ... 6))
        lines.append("")
        lines += asides.randomElement() ?? []
        lines.append("")
        lines.append("> run gibson")
        return lines
    }

    func advance(time: TimeInterval) {
        guard !finished, enabled else { return }
        let target = min(total, Int(time * Self.rate))
        if target != revealed {
            revealed = target
            setNeedsDisplay()
        }
        guard revealed >= total else { return }
        finished = true

        // Nothing else will ever draw here, and a full screen backing store is
        // the largest single allocation in the layer tree.
        opacity = 0
        isHidden = true
        contents = nil
        removeFromSuperlayer()
    }

    override func draw(in ctx: CGContext) {
        guard revealed > 0 else { return }
        let canvas = Canvas(ctx: ctx, size: bounds.size)
        let font = Fonts.mono((canvas.height / 68).clamped(9, 15))
        let lineHeight = Fonts.lineHeight(font) * 1.45
        let origin = CGPoint(x: (canvas.width * 0.055).rounded(), y: canvas.height * 0.1)

        var budget = revealed
        var y = origin.y
        for line in script {
            guard budget > 0 || line.isEmpty else { break }
            let shown = String(line.prefix(budget))
            let isPrompt = line.hasPrefix(">")
            let width = canvas.text(shown, at: CGPoint(x: origin.x, y: y), font: font,
                                    color: isPrompt ? theme.bright : theme.mid)
            if shown.count < line.count || line == script.last {
                canvas.fill(CGRect(x: origin.x + width + 1,
                                   y: y - CTFontGetAscent(font) * 0.82,
                                   width: Fonts.advance(font) * 0.85,
                                   height: CTFontGetAscent(font) * 0.95),
                            theme.bright)
                if shown.count < line.count { break }
            }
            budget -= line.count
            y += lineHeight
        }
    }
}
