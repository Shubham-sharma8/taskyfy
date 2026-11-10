import Foundation
import AppKit
import ApplicationServices

// MARK: - SystemEvent

public struct SystemEvent: Identifiable, Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case highCPU
        case memoryGrowth
        case memoryPressure
        case thermal
        case spotlight
        case swap
        case unplugged
        case pluggedIn

        public var symbolName: String {
            switch self {
            case .highCPU: return "flame.fill"
            case .memoryGrowth: return "chart.line.uptrend.xyaxis"
            case .memoryPressure: return "memorychip.fill"
            case .thermal: return "thermometer.high"
            case .spotlight: return "magnifyingglass.circle.fill"
            case .swap: return "arrow.left.arrow.right.circle.fill"
            case .unplugged: return "battery.75percent"
            case .pluggedIn: return "bolt.batteryblock.fill"
            }
        }

        public var badgeLabel: String {
            switch self {
            case .highCPU: return "CPU Spike"
            case .memoryGrowth: return "Memory Leak / Growth"
            case .memoryPressure: return "Memory Pressure"
            case .thermal: return "Thermal Limit"
            case .spotlight: return "Spotlight Indexing"
            case .swap: return "Swap Activity"
            case .unplugged: return "On Battery"
            case .pluggedIn: return "AC Power"
            }
        }
    }

    public enum Severity: Int, Sendable, Codable, Comparable {
        case info = 0
        case warning = 1
        case critical = 2

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let severity: Severity
    public let title: String
    public let detail: String
    public let relatedAppKey: String?
    public let relatedAppName: String?
    public let relatedPID: Int32?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        severity: Severity,
        title: String,
        detail: String,
        relatedAppKey: String? = nil,
        relatedAppName: String? = nil,
        relatedPID: Int32? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.relatedAppKey = relatedAppKey
        self.relatedAppName = relatedAppName
        self.relatedPID = relatedPID
    }
}

// MARK: - BrowserKind

public enum BrowserKind: String, Sendable, Codable, CaseIterable {
    case safari
    case chrome
    case brave
    case edge
    case arc
    case vivaldi
    case opera

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        case .arc: return "Arc"
        case .vivaldi: return "Vivaldi"
        case .opera: return "Opera"
        }
    }

    public var taskManagerShortcutHint: String {
        switch self {
        case .safari: return "Window ▸ Activity Monitor or close heavy tabs"
        case .chrome, .brave, .vivaldi: return "Window ▸ Task Manager"
        case .edge: return "Tools ▸ Browser Task Manager (⇧Esc)"
        case .arc: return "Extensions / View ▸ Task Manager"
        case .opera: return "Developer ▸ Task Manager (⇧Esc)"
        }
    }

    public static func detect(name: String, bundleID: String?) -> BrowserKind? {
        let lowerBundle = (bundleID ?? "").lowercased()
        let lowerName = name.lowercased()

        if lowerBundle.contains("com.apple.safari") || lowerName == "safari" || lowerName.contains("safari web content") {
            return .safari
        }
        if lowerBundle.contains("com.google.chrome") || lowerName.contains("google chrome") {
            return .chrome
        }
        if lowerBundle.contains("com.brave.browser") || lowerName.contains("brave browser") {
            return .brave
        }
        if lowerBundle.contains("com.microsoft.edgemac") || lowerName.contains("microsoft edge") {
            return .edge
        }
        if lowerBundle.contains("company.thebrowser.browser") || lowerName == "arc" || lowerName.hasPrefix("arc ") {
            return .arc
        }
        if lowerBundle.contains("com.vivaldi.vivaldi") || lowerName.contains("vivaldi") {
            return .vivaldi
        }
        if lowerBundle.contains("com.operasoftware.opera") || lowerName.contains("opera") {
            return .opera
        }
        return nil
    }

    /// Activates the browser and attempts to invoke its built-in Task Manager menu item via Accessibility (`AXUIElement`).
    @discardableResult
    public func openTaskManager(pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        app.activate()
        guard AXIsProcessTrusted() else {
            return false
        }

        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }

        let targetTitles = ["Task Manager", "Task Manager…", "Browser Task Manager"]
        return Self.searchAndPressMenu(element: menuBar as! AXUIElement, targets: targetTitles, depth: 0)
    }

    private static func searchAndPressMenu(element: AXUIElement, targets: [String], depth: Int) -> Bool {
        guard depth < 5 else { return false }
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let title = titleRef as? String,
           targets.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
            return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return false
        }

        for child in children {
            if searchAndPressMenu(element: child, targets: targets, depth: depth + 1) {
                return true
            }
        }
        return false
    }
}
