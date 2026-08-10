# Architecture

A tour of how Gibson is put together, for anyone about to change it. Start with
[CONTRIBUTING.md](../CONTRIBUTING.md) if you only want to add a panel.

## The shape of the thing

A `.saver` bundle is a loadable bundle whose principal class is an
`NSView` subclass. macOS finds `GibsonView` through `NSPrincipalClass` in
`Info.plist`, instantiates it, and calls `animateOneFrame()` on a timer.

```
GibsonView (ScreenSaverView)
├── PanelLayer × 13        one CALayer per panel, each with its own redraw clock
├── tear layer             a bar that flashes for the glitch effect
├── OverlayLayer           scanlines and vignette, drawn once per resize
└── BootLayer              the cold boot log, fades out after ~2 seconds
```

Everything is Core Graphics drawing into `CALayer` backing stores. There is no
Metal, no SwiftUI and no timer other than the one `ScreenSaverView` provides.

## The render loop

`animateOneFrame()` runs 30 times a second and does three things:

1. Builds a `RenderContext`: the theme, the newest metrics snapshot, elapsed
   time, and the preferences that affect drawing.
2. Calls `tick(context)` on every `PanelLayer`.
3. Advances the boot overlay and the glitch band.

`PanelLayer.tick` is where the frame budget is spent or saved:

```swift
guard context.time >= nextRedraw else { return false }
nextRedraw = context.time + panel.redrawInterval
panel.update(context)
setNeedsDisplay()
```

A panel that declares `redrawInterval = 1.0` is asked to redraw once a second no
matter how fast the saver runs. Only the globe, the radar, the waveform and the
flow lanes ask for the full 30 Hz. That is the single most important performance
decision in the project: a dashboard of seventeen panels would be unaffordable
if they all redrew every frame.

Panels are throttled independently, so nothing synchronises and the work spreads
across frames on its own.

## Drawing

Panels never touch `CGContext` directly. They get a `Canvas`, which applies the
vertical flip once in its initialiser so that panel code can think top-down:

```swift
ctx.translateBy(x: 0, y: size.height)
ctx.scaleBy(x: 1, y: -1)
ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
```

`Canvas` offers rectangles, rounded rectangles, polylines, discs, gradients and
text. Text goes through Core Text with a cached `CTFont`; `Fonts.advance` gives
the character width, which is what every table and dump uses to lay out columns
without measuring.

Two shared components keep panels visually consistent:

- `PanelChrome` draws the fill, the border and the header strip, and returns the
  body rectangle. Every panel starts with one call to it.
- `Meter` draws segmented bars and columns with a common brightness ramp.

Colour never appears as a literal. `Theme` derives a ladder of tints from a
single hue, and panels pick a rung: `theme.dim`, `theme.mid`, `theme.bright`,
`theme.accent`, or `theme.level(t)` for anything in between.

## Layout

`LayoutCatalog` returns a `GridLayout` for the display shape: landscape,
portrait, or the compact set used in the System Settings preview. A layout is a
list of slots on a grid, declared top down:

```swift
Slot(make: { ProcessTablePanel() }, x: 3, y: 1, width: 5, height: 3)
```

`GridLayout.frames(in:gutter:)` turns those into rectangles. Two details worth
knowing:

- Layer frames have their origin at the bottom left, so the row offset is
  measured from the top and then flipped.
- The top row is a header strip and gets a fraction of a cell; the rows below
  share what it gives back, which keeps the grid gapless.

Each layout has two variants, picked at random per session, so consecutive runs
swap a few of the secondary panels.

## Metrics

`SystemMonitor` is a singleton with a retain count. It runs a `DispatchSourceTimer`
at 1 Hz on a utility queue and publishes an immutable `MetricsSnapshot` behind a
lock. Panels only ever read the snapshot handed to them in the render context,
so no panel can block the render loop on a syscall.

| Source | Reading |
| --- | --- |
| `host_processor_info` | CPU ticks per core, differentiated between samples |
| `host_statistics64` | Wired, compressed, active and inactive pages |
| `sysctl KERN_PROC_ALL` plus `proc_pidinfo` | The process table |
| `getifaddrs` | Interface byte counters and the primary address |
| `URLResourceValues` | Volume capacity |

Sampling cadence differs per source: the process table every three seconds,
volumes every fifteen, everything else every second.

Two things to know before adding a reading:

- The saver runs sandboxed. A denied call must degrade to a zero or an empty
  array, never a trap.
- Counters from the kernel are unsigned. Every subtraction between two samples
  needs a guard, or it traps and takes the whole screen saver down with it.
  There is a comment at each site where this bit us.

## Preferences

Preferences live in `ScreenSaverDefaults`, namespaced by the bundle identifier.
Because the saver is sandboxed, they land inside the host process container, not
in `~/Library/Preferences`, which is why `defaults read com.perfecto-web.Gibson`
appears empty from a terminal.

macOS presents the options sheet on its own instance of `GibsonView`, not on the
one drawing the screen. A dismiss callback would therefore refresh an instance
nobody is looking at. Instead the running view re-reads its preferences twice a
second and repaints when they change, which works whichever instance did the
writing and across processes.

## The picker tile

`Contents/Resources/thumbnail.png` is what System Settings shows in the screen
saver list. It is generated by `Sources/Cover`, which draws with the same
`Canvas`, `Theme` and `PixelFont` as the saver itself, so the tile cannot drift
away from the product. `make cover` regenerates it; the PNGs are committed so an
ordinary build never has to.

The picker scales the tile to fill a box narrower than 16:9, which is why the
artwork is 640×389 and keeps generous margins.

## Testing

There is no unit test target. What the project does have:

- `make demo` runs the panels in a window.
- `Sources/Snapshot` renders a frame offscreen at any size and any warm-up time,
  which makes visual regressions easy to compare and is how the stills in the
  README were produced. `Sources/Motion` does the same for a run of frames and
  writes an animated GIF, `Sources/Banner` draws the animated header and
  `Sources/Social` draws the repository card. All of them force synthetic
  readings and masking on, so nothing published carries a real process list.
- CI builds the universal bundle plus the helper tools and verifies the bundle
  structure, the architectures and the signature. A tag starting with `v` also
  builds a release and attaches the zipped bundle.

For a change that touches drawing, render before and after at the same size and
warm-up and compare the two PNGs.
