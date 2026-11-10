import Foundation
import Observation

public enum AppTheme: String, CaseIterable, Sendable, Codable {
    case solarisDaylight = "solaris"
    case systemAdaptive = "system"
    case cyberGraphite = "graphite"
    case obsidianAurora = "obsidian"

    public var displayName: String {
        switch self {
        case .solarisDaylight: return "Paper White (Default)"
        case .systemAdaptive: return "System Appearance"
        case .cyberGraphite: return "Graphite Dark"
        case .obsidianAurora: return "Midnight Slate"
        }
    }
}

public enum MenuBarMode: String, CaseIterable, Sendable, Codable {
    case pill = "pill"
    case compact = "compact"
    case iconOnly = "iconOnly"

    public var displayName: String {
        switch self {
        case .pill: return "Telemetry Pill"
        case .compact: return "Compact Metrics"
        case .iconOnly: return "Prism Icon Only"
        }
    }
}

public enum SampleInterval: Double, CaseIterable, Sendable, Codable {
    case fast = 1.0
    case balanced = 2.0
    case eco = 5.0

    public var displayName: String {
        switch self {
        case .fast: return "1.0s (Ultra-Live)"
        case .balanced: return "2.0s (Balanced)"
        case .eco: return "5.0s (Low Power)"
        }
    }
}

public enum AlertSensitivity: String, CaseIterable, Sendable, Codable {
    case strict = "strict"
    case balanced = "balanced"
    case relaxed = "relaxed"

    public var multiplier: Double {
        switch self {
        case .strict: return 0.75
        case .balanced: return 1.0
        case .relaxed: return 1.35
        }
    }

    public var displayName: String {
        switch self {
        case .strict: return "High Sensitivity"
        case .balanced: return "Balanced"
        case .relaxed: return "Relaxed (Fewer Alerts)"
        }
    }
}

public enum RetentionDays: Int, CaseIterable, Sendable, Codable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    public var displayName: String {
        "\(rawValue) Days"
    }
}

@Observable
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    public var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "taskyfy.theme.v2") }
    }
    public var sampleInterval: SampleInterval {
        didSet { defaults.set(sampleInterval.rawValue, forKey: "taskyfy.sampleInterval") }
    }
    public var alertSensitivity: AlertSensitivity {
        didSet { defaults.set(alertSensitivity.rawValue, forKey: "taskyfy.alertSensitivity") }
    }
    public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "taskyfy.notificationsEnabled") }
    }
    public var retentionDays: RetentionDays {
        didSet { defaults.set(retentionDays.rawValue, forKey: "taskyfy.retentionDays") }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "taskyfy.onboarded") }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = AppTheme(rawValue: defaults.string(forKey: "taskyfy.theme.v2") ?? "") ?? .solarisDaylight
        let intervalRaw = defaults.double(forKey: "taskyfy.sampleInterval")
        self.sampleInterval = SampleInterval(rawValue: intervalRaw > 0 ? intervalRaw : 1.0) ?? .fast
        self.alertSensitivity = AlertSensitivity(rawValue: defaults.string(forKey: "taskyfy.alertSensitivity") ?? "") ?? .balanced
        if defaults.object(forKey: "taskyfy.notificationsEnabled") == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = defaults.bool(forKey: "taskyfy.notificationsEnabled")
        }
        let retRaw = defaults.integer(forKey: "taskyfy.retentionDays")
        self.retentionDays = RetentionDays(rawValue: retRaw > 0 ? retRaw : 30) ?? .days30
        self.hasCompletedOnboarding = defaults.bool(forKey: "taskyfy.onboarded")
    }
}

@Observable
public final class MenuBarState: @unchecked Sendable {
    public static let shared = MenuBarState()

    public var mode: MenuBarMode = .pill
    public var showCPU: Bool = true
    public var showMemory: Bool = true
    public var showPower: Bool = false
    public var showTemp: Bool = true
    public var showNetwork: Bool = false
    public var hiddenByNotch: Bool = false

    public init() {}
}

@Observable
public final class LicenseManager: @unchecked Sendable {
    public static let shared = LicenseManager()

    public private(set) var isProUnlocked: Bool = true
    public private(set) var editionLabel: String = "Taskyfy Pro — Unlocked Architecture Edition"

    public init() {}
}

@Observable
public final class UIState: @unchecked Sendable {
    public enum Section: String, CaseIterable, Identifiable, Sendable {
        case overview = "Overview"
        case apps = "Apps & Processes"
        case memory = "Memory & Swap"
        case energy = "Energy & Power"
        case sensors = "Thermals & Sensors"
        case network = "Network & Disk"
        case timeline = "History Timeline"

        public var id: String { rawValue }

        public var symbolName: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .apps: return "list.bullet.rectangle"
            case .memory: return "memorychip"
            case .energy: return "bolt.circle"
            case .sensors: return "thermometer.medium"
            case .network: return "arrow.up.arrow.down.circle"
            case .timeline: return "clock.arrow.circlepath"
            }
        }

        public var subtitle: String {
            switch self {
            case .overview: return "Live telemetry deck"
            case .apps: return "Grouped tree & ports"
            case .memory: return "Pressure & RAM advisor"
            case .energy: return "Watts & battery health"
            case .sensors: return "Die sensors & cooling"
            case .network: return "Throughput & I/O"
            case .timeline: return "SQLite WAL scrubber"
            }
        }
    }

    public var section: Section = .overview
    public var selectedGroupID: String?
    public var selectedPID: Int32?
    public var showInspector: Bool = true
    public var showPalette: Bool = false
    public var showSettingsSheet: Bool = false
    public var timelineRange: HistoryStore.Range = .hours24
    public var searchQuery: String = ""

    public init() {}

    public func selectGroup(_ group: AppGroup) {
        selectedGroupID = group.id
        selectedPID = group.rootPID
        showInspector = true
    }

    public func selectProcess(_ proc: ProcInfo, groupID: String? = nil) {
        if let groupID {
            selectedGroupID = groupID
        }
        selectedPID = proc.pid
        showInspector = true
    }
}
