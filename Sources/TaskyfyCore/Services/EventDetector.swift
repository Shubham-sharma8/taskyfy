import Foundation
import UserNotifications

public final class EventDetector: @unchecked Sendable {
    private var cpuStreakByGroup: [String: Int] = [:]
    private var lastAlertByKindAndGroup: [String: Date] = [:]
    private var lastPluggedState: Bool?
    private var lastPressureLevel: PressureLevel = .normal
    private var lastThermalLevel: ThermalLevel = .nominal
    private var lastSwapAlertBytes: UInt64 = 0

    public init() {}

    public func evaluate(
        snapshot: TelemetrySnapshot,
        sensitivityMultiplier: Double = 1.0
    ) -> [SystemEvent] {
        let now = snapshot.timestamp
        var events: [SystemEvent] = []

        // 1. Power plug/unplug transition
        if snapshot.battery.hasBattery {
            if let prevPlugged = lastPluggedState, prevPlugged != snapshot.battery.isPluggedIn {
                let kind: SystemEvent.Kind = snapshot.battery.isPluggedIn ? .pluggedIn : .unplugged
                let title = snapshot.battery.isPluggedIn
                    ? "Connected to AC Power"
                    : "Running on Battery (\(Int(snapshot.battery.percentage))%)"
                let detail = snapshot.battery.isPluggedIn
                    ? "Charging at \(Format.watts(snapshot.battery.watts))"
                    : "Current draw \(Format.watts(snapshot.battery.watts))"
                events.append(
                    SystemEvent(
                        timestamp: now,
                        kind: kind,
                        severity: .info,
                        title: title,
                        detail: detail
                    )
                )
            }
            lastPluggedState = snapshot.battery.isPluggedIn
        }

        // 2. Memory Pressure transition
        if snapshot.memory.pressureLevel > lastPressureLevel && snapshot.memory.pressureLevel != .normal {
            if canFire(key: "memPressure:\(snapshot.memory.pressureLevel.rawValue)", now: now, cooldown: 300) {
                let topApp = snapshot.appGroups.first
                let sev: SystemEvent.Severity = snapshot.memory.pressureLevel == .critical ? .critical : .warning
                events.append(
                    SystemEvent(
                        timestamp: now,
                        kind: .memoryPressure,
                        severity: sev,
                        title: "Memory Pressure is \(snapshot.memory.pressureLevel.label)",
                        detail: "Used \(Format.bytes(snapshot.memory.used)) of \(Format.bytes(snapshot.memory.total)), compressed \(Format.bytes(snapshot.memory.compressed)). Top consumer: \(topApp?.name ?? "System").",
                        relatedAppKey: topApp?.id,
                        relatedAppName: topApp?.name,
                        relatedPID: topApp?.rootPID
                    )
                )
            }
        }
        lastPressureLevel = snapshot.memory.pressureLevel

        // 3. Thermal state transition
        if snapshot.thermal.state > lastThermalLevel && snapshot.thermal.state >= .serious {
            if canFire(key: "thermal:\(snapshot.thermal.state.rawValue)", now: now, cooldown: 300) {
                events.append(
                    SystemEvent(
                        timestamp: now,
                        kind: .thermal,
                        severity: snapshot.thermal.state == .critical ? .critical : .warning,
                        title: "Thermal Throttling (\(snapshot.thermal.state.label))",
                        detail: "SoC peak temperature reached \(Format.celsius(snapshot.thermal.socMax)). macOS is reducing clock speeds to cool down."
                    )
                )
            }
        }
        lastThermalLevel = snapshot.thermal.state

        // 4. Swap spike (> 2 GB and +1 GB above last alert)
        let twoGB: UInt64 = 2 * 1024 * 1024 * 1024
        let oneGB: UInt64 = 1024 * 1024 * 1024
        if snapshot.memory.swapUsed >= twoGB && snapshot.memory.swapUsed >= lastSwapAlertBytes + oneGB {
            if canFire(key: "swapSpike", now: now, cooldown: 600) {
                lastSwapAlertBytes = snapshot.memory.swapUsed
                events.append(
                    SystemEvent(
                        timestamp: now,
                        kind: .swap,
                        severity: .warning,
                        title: "Swap Reached \(Format.bytes(snapshot.memory.swapUsed))",
                        detail: "macOS is paging inactive memory to SSD. Closing heavy unused apps will reduce SSD wear."
                    )
                )
            }
        } else if snapshot.memory.swapUsed < oneGB {
            lastSwapAlertBytes = 0
        }

        // 5. Per-app High CPU, Spotlight indexing & Memory Growth
        let cpuThreshold = 140.0 * sensitivityMultiplier
        let growthThresholdBytes = Int64(Double(450 * 1024 * 1024) * sensitivityMultiplier)
        var activeHighGroups = Set<String>()

        for group in snapshot.appGroups.prefix(20) {
            let lowerName = group.name.lowercased()
            if lowerName.contains("mds_stores") || lowerName.contains("mdworker") || lowerName == "mds" {
                if group.cpuPercent > 80.0 && canFire(key: "spotlight", now: now, cooldown: 900) {
                    events.append(
                        SystemEvent(
                            timestamp: now,
                            kind: .spotlight,
                            severity: .info,
                            title: "Spotlight Indexing Active",
                            detail: "\(group.name) is indexing files at \(Format.percent(group.cpuPercent, decimals: 0)) CPU.",
                            relatedAppKey: group.id,
                            relatedAppName: group.name,
                            relatedPID: group.rootPID
                        )
                    )
                }
                continue
            }

            if lowerName == "kernel_task" || lowerName == "taskyfy" {
                continue
            }

            if group.cpuPercent >= cpuThreshold {
                activeHighGroups.insert(group.id)
                let streak = (cpuStreakByGroup[group.id] ?? 0) + 1
                cpuStreakByGroup[group.id] = streak

                if streak >= 5 && canFire(key: "cpu:\(group.id)", now: now, cooldown: 600) {
                    events.append(
                        SystemEvent(
                            timestamp: now,
                            kind: .highCPU,
                            severity: group.cpuPercent > 280 ? .critical : .warning,
                            title: "\(group.name) Using High CPU (\(Format.percent(group.cpuPercent, decimals: 0)))",
                            detail: "Sustained high processor load across \(group.processCount) process\(group.processCount == 1 ? "" : "es") (\(Format.bytes(group.memoryBytes)) RAM).",
                            relatedAppKey: group.id,
                            relatedAppName: group.name,
                            relatedPID: group.rootPID
                        )
                    )
                }
            }

            if group.memoryTrail.count >= 6 && group.memoryGrowthBytes >= growthThresholdBytes {
                if canFire(key: "growth:\(group.id)", now: now, cooldown: 900) {
                    events.append(
                        SystemEvent(
                            timestamp: now,
                            kind: .memoryGrowth,
                            severity: .warning,
                            title: "\(group.name) Memory Grew by \(Format.signedBytes(group.memoryGrowthBytes))",
                            detail: "Current footprint is \(Format.bytes(group.memoryBytes)) across \(group.processCount) process\(group.processCount == 1 ? "" : "es").",
                            relatedAppKey: group.id,
                            relatedAppName: group.name,
                            relatedPID: group.rootPID
                        )
                    )
                }
            }
        }

        for key in Array(cpuStreakByGroup.keys) where !activeHighGroups.contains(key) {
            cpuStreakByGroup.removeValue(forKey: key)
        }

        return events
    }

    private func canFire(key: String, now: Date, cooldown: TimeInterval) -> Bool {
        if let prev = lastAlertByKindAndGroup[key], now.timeIntervalSince(prev) < cooldown {
            return false
        }
        lastAlertByKindAndGroup[key] = now
        return true
    }
}

// MARK: - AlertCenter

public final class AlertCenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = AlertCenter()
    public static let categoryQuitOrInspect = "TASKYFY_EVENT_ACTIONS"
    public static let actionQuitPID = "TASKYFY_ACTION_QUIT"
    public static let actionOpenBrowserTM = "TASKYFY_ACTION_BROWSER_TM"

    private var isAuthorized = false

    public override init() {
        super.init()
    }

    public func configureIfBundled() {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let quitAction = UNNotificationAction(
            identifier: Self.actionQuitPID,
            title: "Quit App",
            options: [.destructive]
        )
        let browserAction = UNNotificationAction(
            identifier: Self.actionOpenBrowserTM,
            title: "Open Browser Task Manager",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryQuitOrInspect,
            actions: [quitAction, browserAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.isAuthorized = granted
        }
    }

    public func post(event: SystemEvent, enabled: Bool) {
        guard enabled,
              isAuthorized,
              Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.detail
        content.sound = event.severity == .critical ? .defaultCritical : .default
        if let pid = event.relatedPID {
            content.categoryIdentifier = Self.categoryQuitOrInspect
            content.userInfo = [
                "pid": Int(pid),
                "appName": event.relatedAppName ?? "",
                "appKey": event.relatedAppKey ?? ""
            ]
        }

        let req = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let pidInt = info["pid"] as? Int {
            let pid = Int32(pidInt)
            let appName = (info["appName"] as? String) ?? ""
            let appKey = info["appKey"] as? String
            switch response.actionIdentifier {
            case Self.actionQuitPID:
                _ = ProcessReader.terminate(pid: pid, force: false)
            case Self.actionOpenBrowserTM:
                if let browser = BrowserKind.detect(name: appName, bundleID: appKey) {
                    _ = browser.openTaskManager(pid: pid)
                }
            default:
                break
            }
        }
        completionHandler()
    }
}
