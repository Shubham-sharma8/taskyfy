import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class HistoryStore: @unchecked Sendable {
    public enum Range: String, CaseIterable, Sendable {
        case hour1 = "1H"
        case hours24 = "24H"
        case days7 = "7D"
        case days30 = "30D"

        public var durationSeconds: Int64 {
            switch self {
            case .hour1: return 3600
            case .hours24: return 86_400
            case .days7: return 7 * 86_400
            case .days30: return 30 * 86_400
            }
        }

        public var title: String {
            switch self {
            case .hour1: return "Last Hour"
            case .hours24: return "24 Hours"
            case .days7: return "7 Days"
            case .days30: return "30 Days"
            }
        }
    }

    public struct SysPoint: Identifiable, Sendable, Equatable, Codable {
        public var id: Int64 { ts }
        public let ts: Int64
        public let cpu: Double
        public let memUsed: Double
        public let memTotal: Double
        public let pressure: Double
        public let plevel: Int
        public let swap: Double
        public let gpu: Double
        public let power: Double
        public let socTemp: Double
        public let netRx: Double
        public let netTx: Double
        public let diskR: Double
        public let diskW: Double
        public let battery: Double
        public let onBattery: Bool
        public let thermal: Int

        public var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }

        public init(
            ts: Int64,
            cpu: Double,
            memUsed: Double,
            memTotal: Double,
            pressure: Double,
            plevel: Int,
            swap: Double,
            gpu: Double,
            power: Double,
            socTemp: Double,
            netRx: Double,
            netTx: Double,
            diskR: Double,
            diskW: Double,
            battery: Double,
            onBattery: Bool,
            thermal: Int
        ) {
            self.ts = ts
            self.cpu = cpu
            self.memUsed = memUsed
            self.memTotal = memTotal
            self.pressure = pressure
            self.plevel = plevel
            self.swap = swap
            self.gpu = gpu
            self.power = power
            self.socTemp = socTemp
            self.netRx = netRx
            self.netTx = netTx
            self.diskR = diskR
            self.diskW = diskW
            self.battery = battery
            self.onBattery = onBattery
            self.thermal = thermal
        }
    }

    public struct AppPoint: Identifiable, Sendable, Equatable, Codable {
        public var id: String { "\(ts):\(key)" }
        public let ts: Int64
        public let key: String
        public let name: String
        public let cpu: Double
        public let mem: Double
        public let energy: Double
        public let diskW: Double

        public init(
            ts: Int64,
            key: String,
            name: String,
            cpu: Double,
            mem: Double,
            energy: Double,
            diskW: Double
        ) {
            self.ts = ts
            self.key = key
            self.name = name
            self.cpu = cpu
            self.mem = mem
            self.energy = energy
            self.diskW = diskW
        }
    }

    public struct AppSummary: Identifiable, Sendable, Equatable, Codable {
        public var id: String { key }
        public let key: String
        public let name: String
        public let avgCPU: Double
        public let peakMem: Double
        public let totalEnergy: Double
        public let totalDiskW: Double
        public let sampleMinutes: Int
    }

    public struct EventRecord: Identifiable, Sendable, Equatable, Codable {
        public let id: Int64
        public let ts: Int64
        public let kind: String
        public let severity: Int
        public let title: String
        public let detail: String
        public let appKey: String?
        public let appName: String?

        public var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    }

    public struct Advisor: Sendable, Equatable {
        public let minutes: Int
        public let pressuredFraction: Double
        public let peakSwap: UInt64
        public let peakUsed: UInt64
        public let totalRAM: UInt64

        public var recommendationTitle: String {
            if minutes < 5 {
                return "Collecting baseline telemetry (\(minutes)m sampled)"
            }
            if pressuredFraction > 0.20 || peakSwap > 4 * 1024 * 1024 * 1024 {
                return "Upgrade headroom recommended — frequent swap/compression under load"
            }
            if pressuredFraction > 0.05 || peakSwap > 512 * 1024 * 1024 {
                return "Well-matched for daily work — occasional swap bursts during peaks"
            }
            return "Plenty of RAM headroom — your workload fits comfortably in physical memory"
        }
    }

    public struct BatterySessionSummary: Sendable, Equatable {
        public let unpluggedSince: Date?
        public let activeMinutes: Int
        public let avgWatts: Double
        public let wattHoursUsed: Double
        public let topConsumers: [AppSummary]
    }

    public let dbURL: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.taskyfy.history", qos: .utility)

    public init(databaseURL: URL? = nil) {
        if let custom = databaseURL {
            self.dbURL = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Taskyfy", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.dbURL = dir.appendingPathComponent("history.sqlite")
        }

        queue.sync {
            openAndMigrate()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    private func openAndMigrate() {
        guard sqlite3_open_v2(
            dbURL.path,
            &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            return
        }

        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS sys(
            ts INTEGER PRIMARY KEY,
            cpu REAL,
            mem_used REAL,
            mem_total REAL,
            pressure REAL,
            plevel INTEGER,
            swap REAL,
            gpu REAL,
            power REAL,
            soc_temp REAL,
            net_rx REAL,
            net_tx REAL,
            disk_r REAL,
            disk_w REAL,
            battery REAL,
            on_battery INTEGER,
            thermal INTEGER
        );
        CREATE TABLE IF NOT EXISTS app(
            ts INTEGER,
            key TEXT,
            name TEXT,
            cpu REAL,
            mem REAL,
            energy REAL,
            disk_w REAL,
            PRIMARY KEY(ts, key)
        ) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS app_ts ON app(ts);
        CREATE TABLE IF NOT EXISTS event(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER,
            kind TEXT,
            severity INTEGER,
            title TEXT,
            detail TEXT,
            app_key TEXT,
            app_name TEXT
        );
        CREATE INDEX IF NOT EXISTS event_ts ON event(ts);
        """
        sqlite3_exec(db, schema, nil, nil, nil)
    }

    // MARK: - Write Operations

    public func recordMinute(sys: SysPoint, apps: [AppPoint]) {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)

            let sysSQL = """
            INSERT OR REPLACE INTO sys(
                ts, cpu, mem_used, mem_total, pressure, plevel, swap, gpu, power, soc_temp,
                net_rx, net_tx, disk_r, disk_w, battery, on_battery, thermal
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var sysStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sysSQL, -1, &sysStmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(sysStmt, 1, sys.ts)
                sqlite3_bind_double(sysStmt, 2, sys.cpu)
                sqlite3_bind_double(sysStmt, 3, sys.memUsed)
                sqlite3_bind_double(sysStmt, 4, sys.memTotal)
                sqlite3_bind_double(sysStmt, 5, sys.pressure)
                sqlite3_bind_int(sysStmt, 6, Int32(sys.plevel))
                sqlite3_bind_double(sysStmt, 7, sys.swap)
                sqlite3_bind_double(sysStmt, 8, sys.gpu)
                sqlite3_bind_double(sysStmt, 9, sys.power)
                sqlite3_bind_double(sysStmt, 10, sys.socTemp)
                sqlite3_bind_double(sysStmt, 11, sys.netRx)
                sqlite3_bind_double(sysStmt, 12, sys.netTx)
                sqlite3_bind_double(sysStmt, 13, sys.diskR)
                sqlite3_bind_double(sysStmt, 14, sys.diskW)
                sqlite3_bind_double(sysStmt, 15, sys.battery)
                sqlite3_bind_int(sysStmt, 16, sys.onBattery ? 1 : 0)
                sqlite3_bind_int(sysStmt, 17, Int32(sys.thermal))
                if sqlite3_step(sysStmt) != SQLITE_DONE, let err = sqlite3_errmsg(db) {
                    fputs("HistoryStore sys insert error: \(String(cString: err))\n", stderr)
                }
            }
            sqlite3_finalize(sysStmt)

            let appSQL = "INSERT OR REPLACE INTO app(ts, key, name, cpu, mem, energy, disk_w) VALUES (?,?,?,?,?,?,?);"
            var appStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, appSQL, -1, &appStmt, nil) == SQLITE_OK {
                for a in apps {
                    sqlite3_reset(appStmt)
                    sqlite3_bind_int64(appStmt, 1, a.ts)
                    sqlite3_bind_text(appStmt, 2, a.key, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(appStmt, 3, a.name, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(appStmt, 4, a.cpu)
                    sqlite3_bind_double(appStmt, 5, a.mem)
                    sqlite3_bind_double(appStmt, 6, a.energy)
                    sqlite3_bind_double(appStmt, 7, a.diskW)
                    if sqlite3_step(appStmt) != SQLITE_DONE, let err = sqlite3_errmsg(db) {
                        fputs("HistoryStore app insert error: \(String(cString: err))\n", stderr)
                    }
                }
            }
            sqlite3_finalize(appStmt)

            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    public func recordEvent(_ event: SystemEvent) {
        queue.sync {
            guard let db else { return }
            let sql = "INSERT INTO event(ts, kind, severity, title, detail, app_key, app_name) VALUES (?,?,?,?,?,?,?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, Int64(event.timestamp.timeIntervalSince1970))
            sqlite3_bind_text(stmt, 2, event.kind.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(event.severity.rawValue))
            sqlite3_bind_text(stmt, 4, event.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, event.detail, -1, SQLITE_TRANSIENT)
            if let key = event.relatedAppKey {
                sqlite3_bind_text(stmt, 6, key, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            if let name = event.relatedAppName {
                sqlite3_bind_text(stmt, 7, name, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 7)
            }
            if sqlite3_step(stmt) != SQLITE_DONE, let err = sqlite3_errmsg(db) {
                fputs("HistoryStore event insert error: \(String(cString: err))\n", stderr)
            }
        }
    }

    public func prune(olderThanDays days: Int) {
        let cutoff = Int64(Date().timeIntervalSince1970) - Int64(days) * 86_400
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM sys WHERE ts < \(cutoff); DELETE FROM app WHERE ts < \(cutoff); DELETE FROM event WHERE ts < \(cutoff);", nil, nil, nil)
        }
    }

    public func clearAll() {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM sys; DELETE FROM app; DELETE FROM event; VACUUM;", nil, nil, nil)
        }
    }

    // MARK: - Queries

    public func fetchSysPoints(range: Range) -> [SysPoint] {
        let since = Int64(Date().timeIntervalSince1970) - range.durationSeconds
        return queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT ts, cpu, mem_used, mem_total, pressure, plevel, swap, gpu, power, soc_temp,
                   net_rx, net_tx, disk_r, disk_w, battery, on_battery, thermal
            FROM sys WHERE ts >= ? ORDER BY ts ASC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, since)

            var rows: [SysPoint] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    SysPoint(
                        ts: sqlite3_column_int64(stmt, 0),
                        cpu: sqlite3_column_double(stmt, 1),
                        memUsed: sqlite3_column_double(stmt, 2),
                        memTotal: sqlite3_column_double(stmt, 3),
                        pressure: sqlite3_column_double(stmt, 4),
                        plevel: Int(sqlite3_column_int(stmt, 5)),
                        swap: sqlite3_column_double(stmt, 6),
                        gpu: sqlite3_column_double(stmt, 7),
                        power: sqlite3_column_double(stmt, 8),
                        socTemp: sqlite3_column_double(stmt, 9),
                        netRx: sqlite3_column_double(stmt, 10),
                        netTx: sqlite3_column_double(stmt, 11),
                        diskR: sqlite3_column_double(stmt, 12),
                        diskW: sqlite3_column_double(stmt, 13),
                        battery: sqlite3_column_double(stmt, 14),
                        onBattery: sqlite3_column_int(stmt, 15) != 0,
                        thermal: Int(sqlite3_column_int(stmt, 16))
                    )
                )
            }
            return rows
        }
    }

    public func fetchTopApps(since: Int64, until: Int64? = nil, limit: Int = 10) -> [AppSummary] {
        let endTS = until ?? Int64(Date().timeIntervalSince1970) + 60
        return queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT key, MAX(name), AVG(cpu), MAX(mem), SUM(energy), SUM(disk_w), COUNT(*)
            FROM app
            WHERE ts >= ? AND ts <= ?
            GROUP BY key
            ORDER BY SUM(energy) DESC, AVG(cpu) DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, since)
            sqlite3_bind_int64(stmt, 2, endTS)
            sqlite3_bind_int(stmt, 3, Int32(limit))

            var list: [AppSummary] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "unknown"
                let name = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? key
                list.append(
                    AppSummary(
                        key: key,
                        name: name,
                        avgCPU: sqlite3_column_double(stmt, 2),
                        peakMem: sqlite3_column_double(stmt, 3),
                        totalEnergy: sqlite3_column_double(stmt, 4),
                        totalDiskW: sqlite3_column_double(stmt, 5),
                        sampleMinutes: Int(sqlite3_column_int(stmt, 6))
                    )
                )
            }
            return list
        }
    }

    public func fetchEvents(range: Range, limit: Int = 100) -> [EventRecord] {
        let since = Int64(Date().timeIntervalSince1970) - range.durationSeconds
        return queue.sync {
            guard let db else { return [] }
            let sql = """
            SELECT id, ts, kind, severity, title, detail, app_key, app_name
            FROM event WHERE ts >= ? ORDER BY ts DESC LIMIT ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, since)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var records: [EventRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                records.append(
                    EventRecord(
                        id: sqlite3_column_int64(stmt, 0),
                        ts: sqlite3_column_int64(stmt, 1),
                        kind: sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "info",
                        severity: Int(sqlite3_column_int(stmt, 3)),
                        title: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
                        detail: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "",
                        appKey: sqlite3_column_text(stmt, 6).map { String(cString: $0) },
                        appName: sqlite3_column_text(stmt, 7).map { String(cString: $0) }
                    )
                )
            }
            return records
        }
    }

    public func computeRAMAdvisor(totalPhysical: UInt64) -> Advisor {
        let since = Int64(Date().timeIntervalSince1970) - Range.days7.durationSeconds
        return queue.sync {
            guard let db else {
                return Advisor(minutes: 0, pressuredFraction: 0, peakSwap: 0, peakUsed: 0, totalRAM: totalPhysical)
            }
            let sql = "SELECT COUNT(*), SUM(CASE WHEN plevel > 0 THEN 1 ELSE 0 END), MAX(swap), MAX(mem_used) FROM sys WHERE ts >= ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                return Advisor(minutes: 0, pressuredFraction: 0, peakSwap: 0, peakUsed: 0, totalRAM: totalPhysical)
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, since)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(stmt, 0))
                let pressured = Int(sqlite3_column_int(stmt, 1))
                let peakSwap = UInt64(max(0, sqlite3_column_double(stmt, 2)))
                let peakUsed = UInt64(max(0, sqlite3_column_double(stmt, 3)))
                let frac = count > 0 ? Double(pressured) / Double(count) : 0
                return Advisor(
                    minutes: count,
                    pressuredFraction: frac,
                    peakSwap: peakSwap,
                    peakUsed: peakUsed,
                    totalRAM: totalPhysical
                )
            }
            return Advisor(minutes: 0, pressuredFraction: 0, peakSwap: 0, peakUsed: 0, totalRAM: totalPhysical)
        }
    }

    public func computeEnergyToday() -> BatterySessionSummary {
        let startOfDay = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let points = fetchSysPoints(range: .hours24).filter { $0.ts >= startOfDay }
        let mins = points.count
        let avgW = mins > 0 ? points.reduce(0.0) { $0 + $1.power } / Double(mins) : 0
        let wh = avgW * (Double(mins) / 60.0)
        let top = fetchTopApps(since: startOfDay, limit: 5)
        return BatterySessionSummary(
            unpluggedSince: Date(timeIntervalSince1970: TimeInterval(startOfDay)),
            activeMinutes: mins,
            avgWatts: avgW,
            wattHoursUsed: wh,
            topConsumers: top
        )
    }

    public func databaseFileSizeBytes() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    // MARK: - Telemetry Export (JSON / CSV)

    public func exportJSON(range: Range) throws -> Data {
        struct ExportPayload: Codable {
            let exportedAt: Date
            let range: String
            let systemSamples: [SysPoint]
            let events: [EventRecord]
            let topApps: [AppSummary]
        }
        let since = Int64(Date().timeIntervalSince1970) - range.durationSeconds
        let payload = ExportPayload(
            exportedAt: Date(),
            range: range.rawValue,
            systemSamples: fetchSysPoints(range: range),
            events: fetchEvents(range: range, limit: 250),
            topApps: fetchTopApps(since: since, limit: 25)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public func exportCSV(range: Range) -> String {
        let points = fetchSysPoints(range: range)
        var lines = ["timestamp,iso_date,cpu_pct,mem_used_bytes,mem_total_bytes,pressure_pct,swap_bytes,gpu_pct,power_watts,soc_temp_c,net_rx_bps,net_tx_bps,disk_read_bps,disk_write_bps,battery_pct"]
        let iso = ISO8601DateFormatter()
        for p in points {
            let dateStr = iso.string(from: p.date)
            lines.append(
                "\(p.ts),\(dateStr),\(String(format: "%.2f", p.cpu)),\(Int64(p.memUsed)),\(Int64(p.memTotal)),\(String(format: "%.1f", p.pressure)),\(Int64(p.swap)),\(String(format: "%.1f", p.gpu)),\(String(format: "%.2f", p.power)),\(String(format: "%.1f", p.socTemp)),\(String(format: "%.0f", p.netRx)),\(String(format: "%.0f", p.netTx)),\(String(format: "%.0f", p.diskR)),\(String(format: "%.0f", p.diskW)),\(String(format: "%.0f", p.battery))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - MinuteAccumulator

public final class MinuteAccumulator: @unchecked Sendable {
    private var currentMinuteBucket: Int64 = 0
    private var snapshots: [TelemetrySnapshot] = []
    private var appAccum: [String: (name: String, cpuSum: Double, maxMem: Double, energySum: Double, diskWSum: Double, count: Int)] = [:]

    public init() {}

    public func ingest(_ snapshot: TelemetrySnapshot, into store: HistoryStore) {
        let ts = Int64(snapshot.timestamp.timeIntervalSince1970)
        let bucket = (ts / 60) * 60

        if currentMinuteBucket == 0 {
            currentMinuteBucket = bucket
        } else if bucket > currentMinuteBucket && !snapshots.isEmpty {
            flush(bucket: currentMinuteBucket, to: store)
            currentMinuteBucket = bucket
        }

        snapshots.append(snapshot)
        for group in snapshot.appGroups.prefix(15) {
            var entry = appAccum[group.id] ?? (group.name, 0, 0, 0, 0, 0)
            entry.name = group.name
            entry.cpuSum += group.cpuPercent
            entry.maxMem = max(entry.maxMem, Double(group.memoryBytes))
            entry.energySum += group.energyImpact
            entry.diskWSum += group.diskWriteRate
            entry.count += 1
            appAccum[group.id] = entry
        }
    }

    public func flushNow(to store: HistoryStore) {
        guard !snapshots.isEmpty else { return }
        let bucket = currentMinuteBucket > 0 ? currentMinuteBucket : ((Int64(Date().timeIntervalSince1970) / 60) * 60)
        flush(bucket: bucket, to: store)
    }

    private func flush(bucket: Int64, to store: HistoryStore) {
        let count = Double(max(1, snapshots.count))
        let last = snapshots.last!

        let sys = HistoryStore.SysPoint(
            ts: bucket,
            cpu: snapshots.reduce(0.0) { $0 + $1.cpu.totalUsage } / count,
            memUsed: snapshots.reduce(0.0) { $0 + Double($1.memory.used) } / count,
            memTotal: Double(last.memory.total),
            pressure: snapshots.reduce(0.0) { $0 + $1.memory.pressure } / count,
            plevel: snapshots.map(\.memory.pressureLevel.rawValue).max() ?? 0,
            swap: snapshots.map { Double($0.memory.swapUsed) }.max() ?? 0,
            gpu: snapshots.reduce(0.0) { $0 + $1.gpu.utilization } / count,
            power: snapshots.reduce(0.0) { $0 + $1.battery.watts } / count,
            socTemp: snapshots.reduce(0.0) { $0 + $1.thermal.socTemp } / count,
            netRx: snapshots.reduce(0.0) { $0 + $1.network.rxRate } / count,
            netTx: snapshots.reduce(0.0) { $0 + $1.network.txRate } / count,
            diskR: snapshots.reduce(0.0) { $0 + $1.disk.readRate } / count,
            diskW: snapshots.reduce(0.0) { $0 + $1.disk.writeRate } / count,
            battery: last.battery.percentage,
            onBattery: !last.battery.isPluggedIn,
            thermal: snapshots.map(\.thermal.state.rawValue).max() ?? 0
        )

        let apps: [HistoryStore.AppPoint] = appAccum.map { key, val in
            let c = Double(max(1, val.count))
            return HistoryStore.AppPoint(
                ts: bucket,
                key: key,
                name: val.name,
                cpu: val.cpuSum / c,
                mem: val.maxMem,
                energy: val.energySum / c,
                diskW: val.diskWSum / c
            )
        }

        snapshots.removeAll(keepingCapacity: true)
        appAccum.removeAll(keepingCapacity: true)
        store.recordMinute(sys: sys, apps: apps)
    }
}
