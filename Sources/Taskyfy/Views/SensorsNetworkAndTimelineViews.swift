import SwiftUI
import AppKit
import TaskyfyCore

// MARK: - SensorsView

public struct SensorsView: View {
    @Bindable var monitor: Monitor
    let palette: ThemePalette

    public init(monitor: Monitor, palette: ThemePalette) {
        self.monitor = monitor
        self.palette = palette
    }

    public var body: some View {
        let th = monitor.snapshot.thermal

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Hero Thermal Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Apple Silicon Thermal Envelope")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    StatusPill(
                                        label: th.state.label,
                                        color: tempColor(th.socTemp),
                                        symbol: "thermometer.medium"
                                    )
                                }
                                Text("SoC Average \(Format.celsius(th.socTemp)) · Peak Core \(Format.celsius(th.socMax)) · \(th.sensors.count) Hardware Sensors Active")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 14) {
                                if let gpu = th.gpuTemp {
                                    miniTempStat("GPU Cluster", celsius: gpu)
                                }
                                if let ssd = th.ssdTemp {
                                    miniTempStat("NVMe SSD", celsius: ssd)
                                }
                                if let bat = th.batteryTemp {
                                    miniTempStat("Battery", celsius: bat)
                                }
                            }
                        }

                        AreaChart(
                            points: monitor.tempSeries,
                            color: tempColor(th.socTemp),
                            fixedMax: 105,
                            height: 68,
                            valueFormatter: { Format.celsius($0) }
                        )
                    }
                }

                // 1b. Cooling & Fan Telemetry Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Cooling & Acoustic Telemetry", systemImage: "fan")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            let headroom = max(0, 105.0 - th.socMax)
                            StatusPill(
                                label: String(format: "%.0f°C Thermal Headroom", headroom),
                                color: headroom > 25 ? palette.accentEmerald : palette.accentAmber
                            )
                        }

                        if th.fans.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "leaf")
                                    .foregroundStyle(palette.accentEmerald)
                                Text("Passive / 0 RPM Cooling Active — Hardware fans are silent or this Mac uses a fanless enclosure.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                ForEach(th.fans) { fan in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(fan.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(palette.textPrimary)
                                            Spacer()
                                            Text(fan.rpm > 0 ? "\(fan.rpm) RPM" : "0 RPM (Silent)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(fan.rpm > 0 ? palette.textPrimary : palette.accentEmerald)
                                        }
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(palette.subtleFill)
                                                Capsule()
                                                    .fill(palette.accentCyan)
                                                    .frame(width: geo.size.width * CGFloat(fan.loadPercent / 100.0))
                                            }
                                        }
                                        .frame(height: 5)
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.backgroundPrimary))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.cardBorder, lineWidth: 1))
                                }
                            }
                        }
                    }
                }

                // 2. Categorized Hardware Sensors Grid
                ForEach(SensorCategory.allCases, id: \.self) { category in
                    let items = th.sensors.filter { $0.category == category }
                    if !items.isEmpty {
                        GlassCard(palette: palette) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.adaptive(minimum: 185), spacing: 10)
                                    ],
                                    spacing: 8
                                ) {
                                    ForEach(items) { sensor in
                                        let c = tempColor(sensor.celsius)
                                        HStack(spacing: 8) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(sensor.name)
                                                    .font(.system(size: 11.5, weight: .regular))
                                                    .foregroundStyle(palette.textPrimary)
                                                    .lineLimit(1)
                                                GeometryReader { geo in
                                                    ZStack(alignment: .leading) {
                                                        Capsule().fill(palette.subtleFill)
                                                        Capsule()
                                                            .fill(c)
                                                            .frame(width: geo.size.width * CGFloat(min(max(sensor.celsius / 105.0, 0), 1)))
                                                    }
                                                }
                                                .frame(height: 4)
                                            }
                                            Spacer(minLength: 4)
                                            Text(Format.celsius(sensor.celsius))
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .monospacedDigit()
                                                .foregroundStyle(c)
                                        }
                                        .padding(9)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(palette.backgroundPrimary))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.cardBorder, lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func miniTempStat(_ title: String, celsius: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text(Format.celsius(celsius))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tempColor(celsius))
                .lineLimit(1)
        }
    }

    private func tempColor(_ celsius: Double) -> Color {
        if celsius >= 82 { return palette.accentCoral }
        if celsius >= 65 { return palette.accentAmber }
        return palette.accentEmerald
    }
}

// MARK: - NetworkView

public struct NetworkView: View {
    public enum PortFilter: String, CaseIterable {
        case all = "All Ports"
        case listening = "LISTEN"
        case devPorts = "Dev (1024–9999)"
    }

    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    @State private var portFilter: PortFilter = .all
    @State private var portSearch: String = ""

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let net = monitor.snapshot.network
        let disk = monitor.snapshot.disk

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Network Throughput Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("Network Throughput")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    StatusPill(label: "\(net.activeInterface) · \(net.localIP)", color: palette.textSecondary, symbol: "wifi")
                                }
                                Text("Session Total: ↓ \(Format.bytes(net.rxTotal)) received · ↑ \(Format.bytes(net.txTotal)) sent")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 18) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("↓ Download")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Format.rate(net.rxRate))
                                        .font(.system(size: 16, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textPrimary)
                                }
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("↑ Upload")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Format.rate(net.txRate))
                                        .font(.system(size: 16, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                        }

                        DualAreaChart(
                            primaryPoints: monitor.rxSeries,
                            secondaryPoints: monitor.txSeries,
                            primaryColor: palette.accentCyan,
                            secondaryColor: palette.accentViolet,
                            primaryLabel: "RX",
                            secondaryLabel: "TX",
                            height: 96
                        )
                    }
                }

                // 2. Disk I/O & Volume Capacity Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("NVMe Storage I/O & Capacity")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    StatusPill(
                                        label: "\(Format.bytes(disk.freeSpace)) Free of \(Format.bytes(disk.totalSpace))",
                                        color: palette.accentEmerald,
                                        symbol: "internaldrive"
                                    )
                                }
                                Text("Session I/O: Read \(Format.bytes(disk.totalRead)) · Written \(Format.bytes(disk.totalWrite))")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: 18) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Read Rate")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Format.rate(disk.readRate))
                                        .font(.system(size: 16, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.accentEmerald)
                                }
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Write Rate")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Format.rate(disk.writeRate))
                                        .font(.system(size: 16, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                        }

                        DualAreaChart(
                            primaryPoints: monitor.diskReadSeries,
                            secondaryPoints: monitor.diskWriteSeries,
                            primaryColor: palette.accentEmerald,
                            secondaryColor: palette.accentAmber,
                            primaryLabel: "Read",
                            secondaryLabel: "Write",
                            height: 88
                        )
                    }
                }

                // 3. Top Disk I/O App Groups
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Top Disk I/O Applications", systemImage: "internaldrive")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)

                        let diskGroups = monitor.snapshot.appGroups
                            .sorted { ($0.diskReadRate + $0.diskWriteRate) > ($1.diskReadRate + $1.diskWriteRate) }
                            .prefix(8)

                        ForEach(Array(diskGroups)) { group in
                            HStack(spacing: 10) {
                                Image(nsImage: IconCache.shared.icon(forPath: group.children.first?.executablePath, bundlePath: group.bundlePath, pid: group.rootPID))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(group.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                Spacer()
                                Text("R: \(Format.rate(group.diskReadRate))")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.accentEmerald)
                                    .frame(width: 100, alignment: .trailing)
                                Text("W: \(Format.rate(group.diskWriteRate))")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 100, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(palette.backgroundPrimary))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.cardBorder, lineWidth: 0.5))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                uiState.selectGroup(group)
                            }
                        }
                    }
                }

                // 4. Live Port & Socket Radar
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Label("Live Port & Socket Radar", systemImage: "network")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            TextField("Search port (3000) or app…", text: $portSearch)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(minWidth: 120, maxWidth: 170)
                                .background(RoundedRectangle(cornerRadius: 6).fill(palette.backgroundPrimary))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.cardBorder, lineWidth: 1))

                            Picker("", selection: $portFilter) {
                                ForEach(PortFilter.allCases, id: \.self) { pf in
                                    Text(pf.rawValue).tag(pf)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 230)
                        }

                        let portEntries = filteredPortEntries(from: monitor.snapshot.processes)

                        if portEntries.isEmpty {
                            Text("No matching active TCP/UDP sockets found.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(portEntries.prefix(25)), id: \.id) { item in
                                HStack(spacing: 8) {
                                    Image(nsImage: IconCache.shared.icon(forPath: item.proc.executablePath, pid: item.proc.pid))
                                        .resizable()
                                        .frame(width: 18, height: 18)

                                    Text(item.proc.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                        .frame(minWidth: 110, maxWidth: 170, alignment: .leading)

                                    Text("PID \(item.proc.pid)")
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .frame(width: 66, alignment: .leading)

                                    Text(item.port.proto)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .frame(width: 44, alignment: .leading)

                                    Text(":\(item.port.localPort)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.accentEmerald)
                                        .frame(width: 62, alignment: .leading)

                                    Text(item.port.state)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(item.port.state == "LISTEN" ? palette.accentEmerald : palette.textSecondary)
                                        .frame(width: 82, alignment: .leading)

                                    Spacer()

                                    Button("Inspect") {
                                        uiState.selectProcess(item.proc)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(RoundedRectangle(cornerRadius: 7).fill(palette.backgroundPrimary))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.cardBorder, lineWidth: 0.5))
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private struct PortRowItem: Identifiable {
        var id: String { "\(proc.pid):\(port.id)" }
        let proc: ProcInfo
        let port: OpenPortInfo
    }

    private func filteredPortEntries(from procs: [ProcInfo]) -> [PortRowItem] {
        let q = portSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items: [PortRowItem] = []
        for p in procs where !p.openPorts.isEmpty {
            for port in p.openPorts {
                switch portFilter {
                case .all:
                    break
                case .listening:
                    if port.state != "LISTEN" { continue }
                case .devPorts:
                    if port.localPort < 1024 || port.localPort > 9999 { continue }
                }
                if !q.isEmpty {
                    let matchPort = "\(port.localPort)".contains(q)
                    let matchName = p.name.lowercased().contains(q)
                    let matchPID = "\(p.pid)".contains(q)
                    if !matchPort && !matchName && !matchPID { continue }
                }
                items.append(PortRowItem(proc: p, port: port))
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.port.state != rhs.port.state {
                return lhs.port.state == "LISTEN"
            }
            return lhs.port.localPort < rhs.port.localPort
        }
    }
}

// MARK: - TimelineView

public struct TimelineView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    @State private var exportStatusMessage: String?

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let sysPoints = monitor.history.fetchSysPoints(range: uiState.timelineRange)
        let sinceTS = Int64(Date().timeIntervalSince1970) - uiState.timelineRange.durationSeconds
        let topApps = monitor.history.fetchTopApps(since: sinceTS, limit: 10)
        let events = monitor.history.fetchEvents(range: uiState.timelineRange, limit: 40)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header & Range Picker + Export Controls
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SQLite WAL Historical Telemetry")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text("\(sysPoints.count) minute buckets recorded · Database \(Format.bytes(monitor.history.databaseFileSizeBytes()))")
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()

                    Picker("", selection: $uiState.timelineRange) {
                        ForEach(HistoryStore.Range.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 185)

                    Menu {
                        Button("Export JSON Snapshot…") { exportTelemetry(asJSON: true) }
                        Button("Export CSV Timeseries…") { exportTelemetry(asJSON: false) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()
                }

                if let msg = exportStatusMessage {
                    StatusPill(label: msg, color: palette.accentEmerald, symbol: "checkmark.circle.fill")
                }

                // Historical CPU & Memory Charts
                let cpuPts: [TimePoint] = sysPoints.isEmpty
                    ? monitor.cpuSeries
                    : sysPoints.map { TimePoint(timestamp: $0.date, value: $0.cpu) }

                let memPts: [TimePoint] = sysPoints.isEmpty
                    ? monitor.memorySeries
                    : sysPoints.map { TimePoint(timestamp: $0.date, value: ($0.memTotal > 0 ? ($0.memUsed / $0.memTotal) * 100.0 : 0)) }

                let pwrPts: [TimePoint] = sysPoints.isEmpty
                    ? monitor.powerSeries
                    : sysPoints.map { TimePoint(timestamp: $0.date, value: $0.power) }

                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Processor Utilization (\(uiState.timelineRange.title))")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                        AreaChart(
                            points: cpuPts,
                            color: palette.accentCyan,
                            fixedMax: 100,
                            height: 80,
                            valueFormatter: { Format.percent($0) }
                        )
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Memory Usage % (\(uiState.timelineRange.title))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            AreaChart(
                                points: memPts,
                                color: palette.accentViolet,
                                fixedMax: 100,
                                height: 70,
                                valueFormatter: { Format.percent($0) }
                            )
                        }
                    }

                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Power Watts (\(uiState.timelineRange.title))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            AreaChart(
                                points: pwrPts,
                                color: palette.accentEmerald,
                                height: 70,
                                valueFormatter: { Format.watts($0) }
                            )
                        }
                    }
                }

                // Historical Top Apps & Recorded Events
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], alignment: .leading, spacing: 12) {
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Historical Top Consumers (\(uiState.timelineRange.rawValue))", systemImage: "chart.bar")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            if topApps.isEmpty {
                                Text("Minute-by-minute app rollups will populate automatically after 60 seconds of monitoring.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(topApps) { item in
                                    HStack {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("Avg \(Format.percent(item.avgCPU))")
                                            .font(.system(size: 11))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textPrimary)
                                        Text("· Peak \(Format.bytes(UInt64(max(0, item.peakMem))))")
                                            .font(.system(size: 11))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.accentEmerald)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Recorded System Events", systemImage: "bell")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            if events.isEmpty {
                                Text("No system anomalies recorded in this time window.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(events.prefix(10)) { ev in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(ev.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(palette.textPrimary)
                                            Spacer()
                                            Text(Format.relativeTime(from: ev.date))
                                                .font(.system(size: 10.5))
                                                .monospacedDigit()
                                                .foregroundStyle(palette.textSecondary)
                                        }
                                        Text(ev.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    private func exportTelemetry(asJSON: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "taskyfy-telemetry-\(uiState.timelineRange.rawValue.lowercased()).\(asJSON ? "json" : "csv")"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if asJSON {
                    let data = try monitor.history.exportJSON(range: uiState.timelineRange)
                    try data.write(to: url)
                } else {
                    let csv = monitor.history.exportCSV(range: uiState.timelineRange)
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                }
                exportStatusMessage = "Exported to \(url.lastPathComponent)"
            } catch {
                exportStatusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
