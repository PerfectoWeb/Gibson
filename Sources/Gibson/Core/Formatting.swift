import Foundation

/// Fixed width formatters. Column alignment on screen comes from predictable
/// string lengths, not from measuring anything.
enum Format {
    static func bytes(_ value: UInt64) -> String {
        bytes(Double(value))
    }

    static func bytes(_ value: Double) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var size = value
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 { return "\(Int(size))\(units[index])" }
        return size >= 100
            ? String(format: "%.0f%@", size, units[index])
            : String(format: "%.1f%@", size, units[index])
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let bits = bytesPerSecond * 8
        if bits >= 1_000_000_000 { return String(format: "%.2f Gbps", bits / 1_000_000_000) }
        if bits >= 1_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.0f Kbps", bits / 1_000) }
        return String(format: "%.0f bps", bits)
    }

    static func percent(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", value)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return String(format: "%dd %02d:%02d", days, hours, minutes) }
        return String(format: "%02d:%02d:%02d", hours, minutes, total % 60)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func hex(_ value: Int, width: Int) -> String {
        String(format: "%0\(width)X", value)
    }

    static func pad(_ string: String, _ width: Int, alignRight: Bool = false) -> String {
        if string.count >= width { return String(string.prefix(width)) }
        let padding = String(repeating: " ", count: width - string.count)
        return alignRight ? padding + string : string + padding
    }

    /// Replaces the tail of an identifier so a locked screen does not leak it.
    static func mask(_ string: String, keep: Int = 2) -> String {
        guard string.count > keep else { return String(repeating: "*", count: string.count) }
        return string.prefix(keep) + String(repeating: "*", count: min(6, string.count - keep))
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let dayFormatter = fixed("dd")
    static let monthFormatter = fixed("MMM")
    static let yearFormatter = fixed("yyyy")

    private static func fixed(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
