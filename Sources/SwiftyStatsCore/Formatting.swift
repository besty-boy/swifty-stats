import Foundation

public enum StatsFormatter {
    private static let gbFactor: Double = 1024.0 * 1024.0 * 1024.0
    private static let mbFactor: Double = 1024.0 * 1024.0

    public static func percentInt(_ value: Double) -> String {
        let clamped = min(100, max(0, value))
        return "\(Int(clamped.rounded()))%"
    }

    public static func percentOneDecimal(_ value: Double) -> String {
        let clamped = max(0, value)
        return String(format: "%.1f%%", clamped)
    }

    public static func compactGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / gbFactor
        if gb >= 100 {
            return String(format: "%.0fG", gb)
        }
        return String(format: "%.1fG", gb)
    }

    public static func humanBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / gbFactor
        if gb >= 1.0 {
            return String(format: "%.2f Go", gb)
        }
        let mb = Double(bytes) / mbFactor
        if mb >= 10.0 {
            return String(format: "%.0f Mo", mb)
        }
        return String(format: "%.1f Mo", mb)
    }

    public static func compactBytesShort(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / gbFactor
        if gb >= 1.0 {
            return String(format: "%.1f Go", gb)
        }
        let mb = Double(bytes) / mbFactor
        return String(format: "%.0f Mo", mb)
    }

    public static func temperatureCompact(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let c = celsius else { return "--°" }
        let value = unit == .celsius ? c : (c * 9.0 / 5.0 + 32.0)
        return "\(Int(value.rounded()))°"
    }

    public static func temperatureDetailed(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let c = celsius else { return "--" }
        let value = unit == .celsius ? c : (c * 9.0 / 5.0 + 32.0)
        let suffix = unit == .celsius ? "°C" : "°F"
        return String(format: "%.1f%@", value, suffix)
    }

    public static func wattsCompact(_ watts: Double?) -> String {
        guard let w = watts else { return "--W" }
        let clamped = max(0, w)
        if clamped < 9.95 {
            return String(format: "%.1fW", clamped)
        }
        return "\(Int(clamped.rounded()))W"
    }

    public static func wattsDetailed(_ watts: Double?) -> String {
        guard let w = watts else { return "--" }
        return String(format: "%.1f W", max(0, w))
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds) / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)j \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func batteryTimeRemaining(_ minutes: Int?) -> String? {
        guard let m = minutes, m > 0, m < 60 * 48 else { return nil }
        let h = m / 60
        let rem = m % 60
        if h > 0 {
            return String(format: "%dh%02d", h, rem)
        }
        return "\(rem) min"
    }

    public static func cpuSeverity(_ percent: Double) -> MetricSeverity {
        if percent >= 85 { return .critical }
        if percent >= 65 { return .elevated }
        return .normal
    }

    public static func ramSeverity(_ percent: Double, pressure: MemoryPressureLevel) -> MetricSeverity {
        if pressure == .critical || percent >= 90 { return .critical }
        if pressure == .warning || percent >= 80 { return .elevated }
        return .normal
    }

    public static func tempSeverity(_ celsius: Double?) -> MetricSeverity {
        guard let c = celsius else { return .normal }
        if c >= 85 { return .critical }
        if c >= 70 { return .elevated }
        return .normal
    }

    public static func powerSeverity(_ watts: Double?) -> MetricSeverity {
        guard let w = watts else { return .normal }
        if w >= 55 { return .critical }
        if w >= 30 { return .elevated }
        return .normal
    }
}
