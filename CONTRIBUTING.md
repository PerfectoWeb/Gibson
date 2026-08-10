# Contributing

Thanks for taking a look. New panels, layout variants and colour schemes are the
most useful contributions, and bug reports are just as welcome.

Open an issue before a large change so nobody duplicates work. Small fixes can
go straight to a pull request.

## Getting set up

You need macOS 14 or newer and either Xcode or the Command Line Tools. There is
nothing else to install.

```bash
git clone https://github.com/PerfectoWeb/Gibson.git
cd Gibson
make demo
```

`make demo` compiles the saver sources into an ordinary app and opens a
resizable window. It is the fastest way to work: no installing, no logging out,
and resizing the window shows you immediately how a panel behaves at other
sizes.

Useful while iterating:

```bash
GIBSON_VARIANT=0 make demo   # pin the layout variant
GIBSON_PALETTE=amber make screenshot
make install                 # into ~/Library/Screen Savers
make reinstall               # remove the installed bundle first
```

If System Settings keeps showing an old build or an old tile, that is macOS
caching, not your build. [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) has
the sequence that clears it.

## Adding a panel

A panel is any class conforming to `Panel`. It draws into a `Canvas` whose
origin is the top-left corner, and it declares how often it wants to be redrawn.

```swift
final class UptimePanel: Panel {
    let title: String? = "uptime"
    let redrawInterval: TimeInterval = 1.0

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let font = Fonts.mono((body.height * 0.4).clamped(8, 28), bold: true)
        canvas.text(Format.duration(context.metrics.uptime),
                    at: CGPoint(x: body.midX, y: body.midY),
                    font: font, color: context.theme.bright, alignment: .center)
    }
}
```

Then give it a slot in `Core/Layout.swift`. Slots are declared on a grid using
top-left coordinates, and the grid stretches to whatever the display is:

```swift
Slot(make: { UptimePanel() }, x: 0, y: 4, width: 4, height: 1)
```

Things worth knowing:

- **Size to the slot, not to pixels.** Derive font sizes and spacing from
  `body.height` or `body.width` and clamp them. The same panel has to survive a
  480 point preview thumbnail and a 6K display.
- **Pick an honest redraw interval.** A text table at 1 Hz costs almost nothing.
  Reserve `1.0 / 30` for panels that actually move. Panels are throttled
  individually, so a slow panel does not hold back a fast one.
- **Take colours from the theme.** `theme.dim` through `theme.accent`, or
  `theme.level(t)`. A literal colour breaks all four schemes at once.
- **Keep state in the panel.** `update(_:)` runs right before `draw(_:_:)` and is
  the place to advance animation.
- **Never sample the system from a panel.** Everything available is already on
  `context.metrics`, sampled on a background queue. If you need a new reading,
  add it to `MetricsSnapshot` and to the relevant sampler.
- **Label invented data as invented.** If a panel shows made up content, say so
  in the README table. Half the point of this project is that the real numbers
  are actually real.

## Adding a metric

`Metrics/Samplers.swift` holds the mach and sysctl calls, `SystemMonitor` runs
them on a timer and publishes an immutable `MetricsSnapshot`. Add the field to
the snapshot, fill it in `SystemMonitor.refresh()`, and give
`MetricsSnapshot.simulated(at:)` a plausible value so the panel still works when
live metrics are switched off.

Two rules that come from real crashes:

- The saver is sandboxed. A denied call must return an empty or zero value, not
  trap.
- Kernel counters are unsigned. Guard every subtraction between two samples.

## Code style

- Swift 5 language mode, four space indent, 110 column soft limit.
- `swiftformat` config is in `.swiftformat`. `make lint` runs it if you have it
  installed. Not required, but it keeps diffs small.
- Comments explain why, not what. Skip them when the code already says it.
- No force unwrapping. Prefer an early `guard`.

## Pull requests

- One change per pull request.
- Include a screenshot for anything visual. `make screenshot` renders a frame
  offscreen at a fixed size, which makes before and after easy to compare:

  ```bash
  make screenshot && mv docs/screenshot.png /tmp/before.png
  # make your change
  make screenshot && mv docs/screenshot.png /tmp/after.png
  ```

- Say which macOS version and hardware you tested on.
- Add a line to `CHANGELOG.md` under Unreleased.
- CI builds the universal bundle and the helper tools on every push, so a
  compile error gets caught there. Please build locally first anyway.

## Reporting a bug

The issue templates ask for macOS version, hardware and display setup because
almost every layout bug turns out to be resolution dependent. A screenshot is
worth more than a description for anything visual.
