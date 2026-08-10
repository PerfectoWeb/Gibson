import CoreGraphics
import Foundation

/// SplitMix64. Seeded so a panel can regenerate the same decorative data every
/// frame without allocating or storing it.
struct Seeded: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678_9ABC_DEF
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }

    mutating func range(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        lower + unit() * (upper - lower)
    }

    mutating func int(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        return lower + Int(next() % UInt64(upper - lower))
    }

    /// Requires a non-empty array, like a plain subscript. Every caller passes a
    /// static table.
    mutating func pick<T>(_ values: [T]) -> T {
        values[int(0, values.count)]
    }

    mutating func chance(_ probability: CGFloat) -> Bool {
        unit() < probability
    }
}

/// Deterministic value noise, used for jitter that should not flicker frame to frame.
func noise(_ x: CGFloat, seed: UInt64 = 0) -> CGFloat {
    let i = floor(x)
    let f = x - i
    let smooth = f * f * (3 - 2 * f)
    return hashUnit(UInt64(bitPattern: Int64(i)) &+ seed) * (1 - smooth)
        + hashUnit(UInt64(bitPattern: Int64(i) &+ 1) &+ seed) * smooth
}

func hashUnit(_ value: UInt64) -> CGFloat {
    var z = value &* 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z = z ^ (z >> 31)
    return CGFloat(z >> 11) / CGFloat(UInt64(1) << 53)
}

extension CGFloat {
    func clamped(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lower), upper)
    }
}

extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double {
        Swift.min(Swift.max(self, lower), upper)
    }
}
