import Foundation

public enum Format {
    public static func bytes(_ value: UInt64) -> String {
        let b = Double(value)
        if b < 1024 {
            return "\(value) B"
        }
        let kb = b / 1024.0
        if kb < 1024 {
            return String(format: "%.0f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return mb >= 100 ? String(format: "%.0f MB", mb) : String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024.0
        if gb < 1024 {
            return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.2f GB", gb)
        }
        let tb = gb / 1024.0
        return String(format: "%.2f TB", tb)
    }

    public static func signedBytes(_ value: Int64) -> String {
        let sign = value >= 0 ? "+" : "-"
        return sign + bytes(UInt64(abs(value)))
    }

    public static func rate(_ bytesPerSec: Double) -> String {
        let safe = max(0, bytesPerSec)
        if safe < 1024 {
            return String(format: "%.0f B/s", safe)
        }
        let kb = safe / 1024.0
        if kb < 1024 {
            return kb >= 100 ? String(format: "%.0f KB/s", kb) : String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return mb >= 100 ? String(format: "%.0f MB/s", mb) : String(format: "%.1f MB/s", mb)
        }
        let gb = mb / 1024.0
        return String(format: "%.2f GB/s", gb)
    }

    public static func percent(_ value: Double, decimals: Int = 1) -> String {
        let clamped = max(0, value)
        return String(format: "%.\(decimals)f%%", clamped)
    }

    public static func watts(_ value: Double) -> String {
        let clamped = max(0, value)
        return String(format: "%.1f W", clamped)
    }

    public static func wattHours(_ value: Double) -> String {
        let clamped = max(0, value)
        return String(format: "%.1f Wh", clamped)
    }

    public static func celsius(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(format: "%.0f°C", value)
    }

    public static func duration(minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        let hrs = minutes / 60
        let mins = minutes % 60
        if hrs > 0 {
            return mins > 0 ? "\(hrs)h \(mins)m" : "\(hrs)h"
        }
        return "\(mins)m"
    }

    public static func duration(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 {
            return "\(total)s"
        }
        return duration(minutes: total / 60)
    }

    public static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let delta = max(0, Int(now.timeIntervalSince(date)))
        if delta < 10 {
            return "just now"
        }
        if delta < 60 {
            return "\(delta)s ago"
        }
        let mins = delta / 60
        if mins < 60 {
            return "\(mins)m ago"
        }
        let hrs = mins / 60
        if hrs < 24 {
            return "\(hrs)h ago"
        }
        let days = hrs / 24
        return "\(days)d ago"
    }
}
