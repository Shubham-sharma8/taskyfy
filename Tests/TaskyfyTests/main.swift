import Foundation
import TaskyfyCore

private var passedAssertions = 0
private var failedAssertions = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if condition() {
        passedAssertions += 1
    } else {
        failedAssertions += 1
        fputs("❌ FAIL [\(file):\(line)]: \(message)\n", stderr)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
    if actual == expected {
        passedAssertions += 1
    } else {
        failedAssertions += 1
        fputs("❌ FAIL [\(file):\(line)]: \(message) — expected \(expected), got \(actual)\n", stderr)
    }
}

print("==> Running Taskyfy Architecture & Telemetry Test Suite...")

// 1. Wire Protocol & RawProcRecord Tests
do {
    expectEqual(MemoryLayout<RawProcRecord>.stride, RawProcRecord.byteStride, "RawProcRecord must be 64 bytes")
    let records: [RawProcRecord] = [
        RawProcRecord(
            pid: 0,
            userTime: 100_000,
            systemTime: 500_000,
            footprint: 1_073_741_824,
            energy: 600_000,
            diskRead: 4096,
            diskWrite: 8192,
            wakeups: 42
        ),
        RawProcRecord(
            pid: 412,
            userTime: 250_000,
            systemTime: 50_000,
            footprint: 536_870_912,
            energy: 300_000,
            diskRead: 16_384,
            diskWrite: 32_768,
            wakeups: 19
        )
    ]

    let encoded = HelperClient.encodeRecords(records)
    expectEqual(encoded.count, 2 * RawProcRecord.byteStride, "Encoded Data size")

    let decoded = HelperClient.decodeRecords(from: encoded)
    expectEqual(decoded.count, 2, "Decoded record count")
    expectEqual(decoded[0]?.footprint, 1_073_741_824, "PID 0 footprint")
    expectEqual(decoded[412]?.wakeups, 19, "PID 412 wakeups")
    print("  ✓ [1/5] XPC Wire Protocol (RawProcRecord 64B) passed")
}

// 2. ProcessLibrary Knowledge Base Tests
do {
    let lib = ProcessLibrary.shared
    expect(lib.entries.count > 100, "processes.json should load 100+ process definitions")

    let kernel = lib.lookup(name: "kernel_task")
    expect(kernel != nil, "kernel_task entry exists")
    expectEqual(kernel?.safeToQuit, "no", "kernel_task is not safe to quit")

    let taskyfy = lib.lookup(name: "Taskyfy")
    expect(taskyfy != nil, "Taskyfy self-entry exists")
    expectEqual(taskyfy?.id, "taskyfy", "Taskyfy ID")

    let braveRenderer = lib.lookup(name: "Brave Browser Helper (Renderer)")
    expectEqual(braveRenderer?.id, "brave-browser", "Exact Brave Renderer lookup")

    let genericRenderer = lib.lookup(name: "AcmeElectronApp Helper (Renderer)")
    expectEqual(genericRenderer?.id, "chromium-renderer", "Suffix pattern match for Chromium Renderer")

    let appleDaemon = lib.lookup(name: "com.apple.webkit.networking")
    expect(appleDaemon != nil, "Prefix pattern match for com.apple.*")

    let results = lib.search("spotlight", limit: 10)
    expect(!results.isEmpty, "Search 'spotlight' returns entries")
    print("  ✓ [2/5] ProcessLibrary Knowledge Base & Pattern Matcher passed (\(lib.entries.count) processes, \(lib.patterns.count) patterns)")
}

// 3. SQLite WAL HistoryStore & Export Tests
do {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("taskyfy-test-\(UUID().uuidString).sqlite")
    defer {
        try? FileManager.default.removeItem(at: tempURL)
    }

    let store = HistoryStore(databaseURL: tempURL)
    let nowTS = (Int64(Date().timeIntervalSince1970) / 60) * 60

    for i in 0..<10 {
        let ts = nowTS - Int64(9 - i) * 60
        let sys = HistoryStore.SysPoint(
            ts: ts,
            cpu: 25.0 + Double(i),
            memUsed: 12_000_000_000,
            memTotal: 16_000_000_000,
            pressure: 35.0,
            plevel: i > 7 ? 1 : 0,
            swap: i > 7 ? 1_073_741_824 : 0,
            gpu: 18.5,
            power: 14.2,
            socTemp: 48.0,
            netRx: 125_000,
            netTx: 42_000,
            diskR: 512_000,
            diskW: 256_000,
            battery: 88.0,
            onBattery: true,
            thermal: 0
        )
        let apps = [
            HistoryStore.AppPoint(
                ts: ts,
                key: "com.apple.Safari",
                name: "Safari",
                cpu: 18.0,
                mem: 2_147_483_648,
                energy: 22.0,
                diskW: 64_000
            )
        ]
        store.recordMinute(sys: sys, apps: apps)
    }

    let event = SystemEvent(
        kind: .highCPU,
        severity: .warning,
        title: "Safari High CPU",
        detail: "Sustained CPU usage",
        relatedAppKey: "com.apple.Safari",
        relatedAppName: "Safari",
        relatedPID: 999
    )
    store.recordEvent(event)

    let points = store.fetchSysPoints(range: .hour1)
    expectEqual(points.count, 10, "SQLite sys points count")

    let topApps = store.fetchTopApps(since: nowTS - 3600, limit: 5)
    expectEqual(topApps.first?.name, "Safari", "Top app rollup")

    let events = store.fetchEvents(range: .hour1)
    expectEqual(events.count, 1, "Recorded event count")
    expectEqual(events.first?.title, "Safari High CPU", "Recorded event title")

    let advisor = store.computeRAMAdvisor(totalPhysical: 16_000_000_000)
    expectEqual(advisor.minutes, 10, "RAM Advisor minutes")
    expectEqual(advisor.peakSwap, 1_073_741_824, "RAM Advisor peak swap")

    let jsonData = try store.exportJSON(range: .hour1)
    expect(jsonData.count > 100, "Exported JSON payload non-empty")

    let csvText = store.exportCSV(range: .hour1)
    expect(csvText.contains("timestamp,iso_date,cpu_pct"), "CSV header")
    expectEqual(csvText.components(separatedBy: "\n").count, 11, "CSV row count")

    store.clearAll()
    expect(store.fetchSysPoints(range: .hour1).isEmpty, "Store empty after clearAll")
    print("  ✓ [3/5] SQLite WAL HistoryStore, RAMAdvisor & JSON/CSV Export passed")
}

// 4. EventDetector Anomaly Tests
do {
    let detector = EventDetector()
    let now = Date()

    var trail: [TrailPoint] = []
    for idx in 0..<7 {
        let offset = Double(-360 + idx * 60)
        let mem = UInt64(500_000_000) + UInt64(idx) * UInt64(100_000_000)
        trail.append(TrailPoint(timestamp: now.addingTimeInterval(offset), memory: mem))
    }

    let heavyApp = AppGroup(
        id: "com.test.heavy",
        rootPID: 1234,
        name: "HeavyRenderer",
        bundleID: "com.test.heavy",
        isApp: true,
        cpuPercent: 220.0,
        memoryBytes: 1_100_000_000,
        energyImpact: 180.0,
        processCount: 3,
        memoryTrail: trail
    )

    let snap = TelemetrySnapshot(
        timestamp: now,
        cpu: CPUSample(totalUsage: 85.0, userUsage: 70.0, systemUsage: 15.0),
        memory: MemoryStats(
            total: 16_000_000_000,
            used: 15_000_000_000,
            swapUsed: 3 * 1024 * 1024 * 1024,
            pressure: 82.0,
            pressureLevel: .critical
        ),
        thermal: ThermalStats(state: .serious, socTemp: 89.0, socMax: 94.0),
        appGroups: [heavyApp]
    )

    var allDetected: [SystemEvent] = []
    for _ in 0..<5 {
        allDetected.append(contentsOf: detector.evaluate(snapshot: snap))
    }

    let kinds = Set(allDetected.map(\.kind))
    expect(kinds.contains(.memoryPressure), "Detects memoryPressure")
    expect(kinds.contains(.thermal), "Detects thermal throttling")
    expect(kinds.contains(.swap), "Detects swap spike")
    expect(kinds.contains(.memoryGrowth), "Detects memoryGrowth leak")
    expect(kinds.contains(.highCPU), "Detects sustained highCPU")
    print("  ✓ [4/5] EventDetector Anomaly & Leak Engine passed")
}

// 5. Live Darwin / Mach / IOKit Telemetry Readers Tests
do {
    let sampler = Sampler()
    _ = sampler.takeSnapshot()
    let second = sampler.takeSnapshot(selectedPID: getpid())

    expect(second.memory.total > 0, "Physical memory > 0")
    expect(second.cpu.perCore.count > 0, "Per-core CPU count > 0")
    expect(!second.processes.isEmpty, "Process list non-empty")
    expect(!second.appGroups.isEmpty, "AppGroup list non-empty")
    expect(!second.thermal.sensors.isEmpty, "Thermal sensors non-empty")

    expectEqual(Format.bytes(1024), "1 KB", "Format.bytes")
    expectEqual(Format.rate(0), "0 B/s", "Format.rate")
    expectEqual(Format.percent(42.56, decimals: 1), "42.6%", "Format.percent")
    expectEqual(Format.duration(minutes: 125), "2h 5m", "Format.duration")

    expectEqual(BrowserKind.detect(name: "Google Chrome", bundleID: "com.google.Chrome"), .chrome, "Detect Chrome")
    expectEqual(BrowserKind.detect(name: "Safari", bundleID: "com.apple.Safari"), .safari, "Detect Safari")
    expectEqual(BrowserKind.detect(name: "Arc", bundleID: "company.thebrowser.Browser"), .arc, "Detect Arc")

    let monitor = Monitor()
    monitor.apply(second)
    monitor.pinBaseline()
    expect(monitor.pinnedBaseline != nil, "Baseline snapshot pinned")
    monitor.setSurfaceVisibility(windowVisible: false, popoverVisible: false)
    expectEqual(monitor.isBackgroundMode, true, "Background cadence enabled when surfaces hidden")
    monitor.setSurfaceVisibility(windowVisible: true, popoverVisible: false)
    expectEqual(monitor.isBackgroundMode, false, "Foreground cadence restored when window shown")
    monitor.clearBaseline()
    expect(monitor.pinnedBaseline == nil, "Baseline snapshot cleared")
    print("  ✓ [5/5] Live Darwin/Mach/IOKit Telemetry Sampler passed (\(second.processes.count) processes, \(second.appGroups.count) groups, \(second.cpu.perCore.count) cores)")
}

print("==> Summary: \(passedAssertions) assertions passed, \(failedAssertions) failed.")
if failedAssertions > 0 {
    exit(1)
}
