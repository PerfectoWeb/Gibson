import Foundation
import ScreenSaver

/// Thin wrapper over ScreenSaverDefaults. Everything is namespaced by the
/// bundle identifier: the saver shares its host process with other savers.
final class Preferences {
    static let shared = Preferences()

    private let store: UserDefaults

    private enum Key {
        static let palette = "palette"
        static let liveMetrics = "liveMetrics"
        static let maskSensitiveInfo = "maskSensitiveInfo"
        static let scanlines = "scanlines"
        static let glitches = "glitches"
    }

    private init() {
        let identifier = Bundle(for: GibsonView.self).bundleIdentifier
            ?? "com.perfecto-web.Gibson"
        store = ScreenSaverDefaults(forModuleWithName: identifier) ?? .standard
        store.register(defaults: [
            Key.palette: Palette.green.rawValue,
            Key.liveMetrics: true,
            Key.maskSensitiveInfo: true,
            Key.scanlines: true,
            Key.glitches: true
        ])
    }

    var palette: Palette {
        get { Palette(rawValue: store.string(forKey: Key.palette) ?? "") ?? .green }
        set { store.set(newValue.rawValue, forKey: Key.palette) }
    }

    /// When off, panels fall back to synthesised values instead of reading the host.
    var liveMetrics: Bool {
        get { store.bool(forKey: Key.liveMetrics) }
        set { store.set(newValue, forKey: Key.liveMetrics) }
    }

    /// Hides host name, user name and local addresses behind asterisks.
    var maskSensitiveInfo: Bool {
        get { store.bool(forKey: Key.maskSensitiveInfo) }
        set { store.set(newValue, forKey: Key.maskSensitiveInfo) }
    }

    var scanlines: Bool {
        get { store.bool(forKey: Key.scanlines) }
        set { store.set(newValue, forKey: Key.scanlines) }
    }

    var glitches: Bool {
        get { store.bool(forKey: Key.glitches) }
        set { store.set(newValue, forKey: Key.glitches) }
    }

    func save() {
        store.synchronize()
    }

    /// Same call as `save`, named for the other direction: it also pulls in a
    /// write made by another process, which is where the options sheet runs.
    func refresh() {
        store.synchronize()
    }
}
