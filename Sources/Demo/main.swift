import AppKit

// Development host. `make demo` builds the saver sources into a plain app so
// you can iterate without installing anything into System Settings.

final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var saver: GibsonView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let view = GibsonView(frame: frame, isPreview: false) else { return }

        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Gibson (demo)"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)

        view.startAnimation()
        self.window = window
        saver = view
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let application = NSApplication.shared
let delegate = DemoDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
application.run()
