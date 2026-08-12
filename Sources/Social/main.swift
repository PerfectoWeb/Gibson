import AppKit

// Renders docs/images/social-preview.png, the card GitHub shows when a link to
// the repository is pasted anywhere. It is a real frame of the running saver
// with the wordmark set over it, so the card cannot promise something the
// screen saver does not do.
//
// Usage: social <output.png> [width] [height] [warmup]

private let arguments = CommandLine.arguments
private let output = arguments.count > 1 ? arguments[1] : "docs/images/social-preview.png"
private let width = arguments.count > 2 ? Int(arguments[2]) ?? 1280 : 1280
private let height = arguments.count > 3 ? Int(arguments[3]) ?? 640 : 640
private let warmup = arguments.count > 4 ? Double(arguments[4]) ?? 12 : 12

private let theme = Theme(palette: .green)

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

// Synthetic readings and masking on: the card is published, and nobody needs
// this machine's process list or host name in it.
Preferences.shared.liveMetrics = false
Preferences.shared.maskSensitiveInfo = true
Preferences.shared.save()

private let frame = NSRect(x: 0, y: 0, width: width, height: height)
guard let view = GibsonView(frame: frame, isPreview: false) else { exit(1) }
// This window is never brought to the front, and a saver that skips hidden
// frames would draw an empty card.
view.pausesWhenHidden = false
private let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
window.contentView = view
window.orderBack(nil)
view.layoutSubtreeIfNeeded()
view.startAnimation()

/// The saver is driven by the clock, so the only way to reach a frame where
/// every panel has data is to let it run.
private let end = Date().addingTimeInterval(warmup)
while Date() < end {
    view.animateOneFrame()
    RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 30))
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let root = view.layer
else { exit(1) }

root.displayIfNeeded()
root.render(in: ctx)

private let canvas = Canvas(ctx: ctx, size: CGSize(width: width, height: height))
private let bounds = canvas.bounds

// Knock the dashboard back a stop. The card is read at a couple of hundred
// pixels wide in a chat window, and the name has to win at that size.
canvas.fill(bounds, CGColor(gray: 0, alpha: 0.34))

private let pixel = (bounds.width * 0.0082).rounded()
private let letterSpacing = pixel * 1.6
private let markWidth = PixelFont.width("GIBSON", face: PixelFont.bold,
                                        pixel: pixel, letterSpacing: letterSpacing)
private let markHeight = PixelFont.height(face: PixelFont.bold, pixel: pixel)

private let caption = "LIVE SYSTEM TELEMETRY"
private let captionPixel = (pixel * 0.42).rounded()
private let captionSpacing = (markWidth - CGFloat(caption.count)
    * CGFloat(PixelFont.thin.cellWidth) * captionPixel) / CGFloat(caption.count - 1)
private let captionHeight = PixelFont.height(face: PixelFont.thin, pixel: captionPixel)

private let gap = markHeight * 0.5
private let plate = CGRect(x: bounds.midX - markWidth / 2 - pixel * 5,
                           y: bounds.midY - (markHeight + gap + captionHeight) / 2 - pixel * 3.5,
                           width: markWidth + pixel * 10,
                           height: markHeight + gap + captionHeight + pixel * 7)

canvas.fillRounded(plate, pixel, theme.fade(theme.panelFill, 0.93))
canvas.strokeRounded(plate, pixel, theme.border, width: 1.5)
canvas.brackets(plate.insetBy(dx: -pixel * 1.2, dy: -pixel * 1.2), theme.accent,
                length: pixel * 2.6, width: 2)

private let markTop = (plate.minY + pixel * 3.5).rounded()
PixelFont.draw("GIBSON", face: PixelFont.bold, in: canvas,
               at: CGPoint(x: (bounds.midX - markWidth / 2).rounded(), y: markTop),
               pixel: pixel, letterSpacing: letterSpacing, color: theme.accent)

PixelFont.draw(caption, face: PixelFont.thin, in: canvas,
               at: CGPoint(x: (bounds.midX - markWidth / 2).rounded(),
                           y: (markTop + markHeight + gap).rounded()),
               pixel: captionPixel, letterSpacing: captionSpacing,
               color: theme.fade(theme.mid, 0.95))

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { exit(1) }

try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: output).deletingLastPathComponent(),
    withIntermediateDirectories: true)
try? data.write(to: URL(fileURLWithPath: output))
print("wrote \(output), \(width)x\(height)")
exit(0)
