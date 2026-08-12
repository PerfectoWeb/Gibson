import AppKit

// Offscreen renderer used to produce the README stills.
// Usage: snapshot <output.png> [width] [height] [warmup seconds]

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "docs/screenshot.png"
let width = arguments.count > 2 ? Int(arguments[2]) ?? 2560 : 2560
let height = arguments.count > 3 ? Int(arguments[3]) ?? 1440 : 1440
let warmup = arguments.count > 4 ? Double(arguments[4]) ?? 6 : 6

// A saver view needs a real window so the layer tree gets a backing scale.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

// Everything these tools render ends up published, so the readings are
// synthetic and the host details masked. No real process list, user name or
// address leaves this machine in a screenshot.
Preferences.shared.liveMetrics = false
Preferences.shared.maskSensitiveInfo = true
Preferences.shared.save()

// GIBSON_PALETTE picks the colour scheme for the shot, for the README strip.
if let name = ProcessInfo.processInfo.environment["GIBSON_PALETTE"],
   let palette = Palette(rawValue: name) {
    Preferences.shared.palette = palette
    Preferences.shared.save()
}

let frame = NSRect(x: 0, y: 0, width: width, height: height)
let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                      backing: .buffered, defer: false)
guard let view = GibsonView(frame: frame, isPreview: false) else {
    exit(1)
}
// This window is never brought to the front, and a saver that skips hidden
// frames would hand back an empty picture.
view.pausesWhenHidden = false
window.contentView = view
window.orderBack(nil)

view.layoutSubtreeIfNeeded()
view.startAnimation()

let deadline = Date().addingTimeInterval(warmup)
while Date() < deadline {
    view.animateOneFrame()
    RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 30))
}
view.animateOneFrame()

guard let representation = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: representation) else {
    exit(1)
}

if let root = view.layer {
    root.displayIfNeeded()
    root.render(in: context.cgContext)
}

guard let data = representation.representation(using: .png, properties: [:]) else { exit(1) }
try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: output).deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try? data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
exit(0)
