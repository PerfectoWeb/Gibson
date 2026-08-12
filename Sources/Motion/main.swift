import AppKit

// Records the running dashboard into docs/images/dashboard.gif, the animated
// demo in the README.
//
// Usage: motion <output.gif> [width] [height] [warmup] [frames] [interval]

private let arguments = CommandLine.arguments
private let output = arguments.count > 1 ? arguments[1] : "docs/images/dashboard.gif"
private let width = arguments.count > 2 ? Int(arguments[2]) ?? 1100 : 1100
private let height = arguments.count > 3 ? Int(arguments[3]) ?? 619 : 619
private let warmup = arguments.count > 4 ? Double(arguments[4]) ?? 25 : 25
private let frameCount = arguments.count > 5 ? Int(arguments[5]) ?? 44 : 44
private let interval = arguments.count > 6 ? Double(arguments[6]) ?? 0.1 : 0.1

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

// Everything these tools render ends up published, so the readings are
// synthetic and the host details masked. No real process list, user name or
// address leaves this machine in a screenshot.
Preferences.shared.liveMetrics = false
Preferences.shared.maskSensitiveInfo = true
Preferences.shared.save()

if let name = ProcessInfo.processInfo.environment["GIBSON_PALETTE"],
   let palette = Palette(rawValue: name) {
    Preferences.shared.palette = palette
    Preferences.shared.save()
}

let frame = NSRect(x: 0, y: 0, width: width, height: height)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
guard let view = GibsonView(frame: frame, isPreview: false) else { exit(1) }
// This window is never brought to the front, and a saver that skips hidden
// frames would record an empty picture.
view.pausesWhenHidden = false
window.contentView = view
window.orderBack(nil)
view.layoutSubtreeIfNeeded()
view.startAnimation()

/// Runs the saver in real time, since every panel is driven by the clock.
private func pump(_ seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        view.animateOneFrame()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0 / 30))
    }
}

private func capture() -> CGImage? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep),
          let root = view.layer
    else { return nil }
    root.displayIfNeeded()
    root.render(in: ctx.cgContext)
    return rep.cgImage
}

pump(warmup)

var frames: [CGImage] = []
for _ in 0 ..< frameCount {
    pump(interval)
    guard let image = capture() else { exit(1) }
    frames.append(image)
}

guard GIFWriter.write(frames, to: output, frameDuration: interval) else {
    print("failed to write \(output)")
    exit(1)
}
print("wrote \(output), \(frames.count) frames")
exit(0)
