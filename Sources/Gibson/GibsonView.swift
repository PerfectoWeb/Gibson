import ScreenSaver

/// Entry point loaded by the screen saver engine. Owns the layer tree, drives
/// the per panel redraw cadence and hands out render contexts.
@objc(GibsonView)
final class GibsonView: ScreenSaverView {
    private let preferences = Preferences.shared
    private var theme = Theme(palette: .green)
    private var panelLayers: [PanelLayer] = []
    private var overlay = OverlayLayer()
    private var boot = BootLayer()

    private var startedAt = Date()
    private var layoutSize: CGSize = .zero
    /// What the layer tree was last built with, so changes made in the options
    /// sheet can be picked up while the view is already running.
    private var appliedPalette: Palette?
    private var appliedScanlines: Bool?
    private var nextPreferenceCheck: TimeInterval = 0
    private var monitorRetained = false

    /// The sheet outlives any single view instance, so the reference lives on
    /// the type. Handing out a second window while the first is still presented
    /// leaves the host with a dead sheet and silently swallows every later
    /// click on Options.
    private static var sheetWindow: NSWindow?
    private var cornerRadius: CGFloat = 6
    private var variant = 0
    private let tear = CALayer()
    private var glitchDeadline: TimeInterval = 3
    private var glitchUntil: TimeInterval = 0

    private var elapsed: TimeInterval { -startedAt.timeIntervalSinceNow }

    // MARK: - Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30
        wantsLayer = true
        // GIBSON_VARIANT pins the layout while working on a panel.
        variant = ProcessInfo.processInfo.environment["GIBSON_VARIANT"]
            .flatMap(Int.init) ?? Int.random(in: 0 ... 1)
        theme = Theme(palette: preferences.palette)

        tear.opacity = 0
        tear.actions = ["opacity": NSNull(), "bounds": NSNull(),
                        "position": NSNull(), "backgroundColor": NSNull()]

        let root = layer ?? CALayer()
        root.backgroundColor = theme.background
        root.addSublayer(tear)
        root.addSublayer(overlay)
        root.addSublayer(boot)
        layer = root
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
        startedAt = Date()
        theme = Theme(palette: preferences.palette)
        layer?.backgroundColor = theme.background
        // The boot layer takes itself out of the tree once it has played, to
        // give back its backing store.
        if boot.superlayer == nil { layer?.addSublayer(boot) }
        boot.frame = bounds
        boot.reset()
        setMonitor(running: preferences.liveMetrics)
    }

    override func stopAnimation() {
        super.stopAnimation()
        setMonitor(running: false)
    }

    /// Balanced on a latch rather than on the preference: toggling live metrics
    /// while the saver runs would otherwise leave the sampler retained forever,
    /// or release a count this view never took.
    private func setMonitor(running: Bool) {
        guard running != monitorRetained else { return }
        monitorRetained = running
        if running {
            SystemMonitor.shared.retain()
        } else {
            SystemMonitor.shared.release()
        }
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != layoutSize {
            layoutSize = bounds.size
            rebuildLayers()
        }
    }

    private func rebuildLayers() {
        panelLayers.forEach { $0.removeFromSuperlayer() }
        panelLayers.removeAll()

        let layout = LayoutCatalog.layout(for: bounds.size, isPreview: isPreview, variant: variant)
        let gutter: CGFloat = isPreview ? 3 : (min(bounds.width, bounds.height) * 0.014).clamped(6, 30)
        let scale = window?.backingScaleFactor ?? 2
        cornerRadius = isPreview ? 2 : (min(bounds.width, bounds.height) * 0.0042).clamped(2, 8)

        for (slot, frame) in layout.frames(in: bounds, gutter: gutter) {
            let panelLayer = PanelLayer(panel: slot.make())
            panelLayer.frame = frame
            panelLayer.contentsScale = scale
            panelLayer.cornerRadius = cornerRadius
            panelLayer.opacity = 0
            layer?.insertSublayer(panelLayer, below: overlay)
            panelLayers.append(panelLayer)
        }

        overlay.frame = bounds
        overlay.contentsScale = scale
        overlay.theme = theme
        overlay.enabled = preferences.scanlines
        overlay.setNeedsDisplay()
        tear.frame = .zero

        boot.frame = bounds
        boot.contentsScale = scale
        boot.theme = theme
        boot.enabled = !isPreview
        boot.setNeedsDisplay()
    }

    // MARK: - Frame loop

    /// The offscreen artwork tools drive the frame loop by hand from windows
    /// they never bring to the front, so they turn this off.
    var pausesWhenHidden = true

    /// macOS does not always tear down `legacyScreenSaver` once the screen is
    /// unlocked. The host keeps calling us, the window sits behind everything
    /// the user is working in, and a saver that keeps drawing burns a core for
    /// nothing. Nobody is looking at pixels that are not on screen.
    private var isOnScreen: Bool {
        guard pausesWhenHidden, let window else { return true }
        return window.occlusionState.contains(.visible)
    }

    override func animateOneFrame() {
        super.animateOneFrame()
        guard isOnScreen else {
            setMonitor(running: false)
            return
        }
        let time = elapsed
        let context = RenderContext(
            theme: theme,
            metrics: currentMetrics(at: time),
            time: time,
            isPreview: isPreview,
            maskSensitiveInfo: preferences.maskSensitiveInfo,
            cornerRadius: cornerRadius
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyPreferenceChanges(at: time)

        for (index, panelLayer) in panelLayers.enumerated() {
            let delay = isPreview ? 0 : 1.4 + Double(index) * 0.06
            let progress = ((time - delay) / 0.5).clamped(0, 1)
            if panelLayer.opacity < 1 {
                panelLayer.opacity = Float(progress)
            }
            guard progress > 0 else { continue }
            panelLayer.tick(context)
        }

        if !isPreview {
            boot.advance(time: time)
            updateGlitch(time: time)
        }

        CATransaction.commit()
    }

    /// The options sheet is presented on its own instance of this class, so the
    /// running view never hears about the change. Polling the defaults twice a
    /// second is cheap and works whichever instance did the writing.
    private func applyPreferenceChanges(at time: TimeInterval) {
        guard time >= nextPreferenceCheck else { return }
        nextPreferenceCheck = time + 0.5
        // The sheet often runs in another process, whose write this process
        // will not see until its own preferences cache is refreshed.
        preferences.refresh()

        setMonitor(running: preferences.liveMetrics && isAnimating)

        let palette = preferences.palette
        let scanlines = preferences.scanlines
        guard palette != appliedPalette || scanlines != appliedScanlines else { return }
        appliedPalette = palette
        appliedScanlines = scanlines

        theme = Theme(palette: palette)
        layer?.backgroundColor = theme.background
        overlay.theme = theme
        overlay.enabled = scanlines
        overlay.setNeedsDisplay()
        boot.theme = theme
        // Panels read the theme out of the render context, so a repaint is all
        // they need.
        panelLayers.forEach { $0.setNeedsDisplay() }
    }

    private func currentMetrics(at time: TimeInterval) -> MetricsSnapshot {
        guard preferences.liveMetrics else { return .simulated(at: time) }
        let live = SystemMonitor.shared.snapshot
        // The first sample lands a second in; show something in the meantime.
        return live.cores.isEmpty ? .simulated(at: time) : live
    }

    /// Flashes a horizontal tear band across the screen. Panels are never moved:
    /// nudging their frames reads as a rendering bug rather than as an effect.
    private func updateGlitch(time: TimeInterval) {
        guard preferences.glitches else { return }

        if tear.opacity > 0, time > glitchUntil {
            tear.opacity = 0
        }

        guard time > glitchDeadline, tear.opacity == 0 else { return }
        glitchDeadline = time + Double.random(in: 5 ... 13)
        glitchUntil = time + 0.09

        let height = CGFloat.random(in: 2 ... 7)
        tear.frame = CGRect(x: 0, y: CGFloat.random(in: 0 ... max(1, bounds.height - height)),
                            width: bounds.width, height: height)
        tear.backgroundColor = theme.fade(theme.bright, 0.16)
        tear.opacity = 1
    }

    // MARK: - Configuration

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        // The host reads this property more than once per click. Handing back
        // the window that is already up, rather than building another one, is
        // what keeps the second click working.
        if let existing = Self.sheetWindow, existing.isVisible || existing.sheetParent != nil {
            return existing
        }

        let controller = ConfigureSheetController()
        controller.onDismiss = { Self.sheetWindow = nil }

        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled]
        window.title = "Gibson"
        window.isReleasedWhenClosed = false
        Self.sheetWindow = window
        // Applying the change is the render loop's job, see
        // applyPreferenceChanges: the sheet may well belong to another instance.
        return window
    }
}
