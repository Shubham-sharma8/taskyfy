import SwiftUI
import TaskyfyCore

// MARK: - MemoryView

public struct MemoryView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let mem = monitor.snapshot.memory
        let advisor = monitor.history.computeRAMAdvisor(totalPhysical: mem.total)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Memory Composition & Pressure Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("Unified Memory Architecture")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    StatusPill(
                                        label: "\(mem.pressureLevel.label) (\(Format.percent(mem.pressure, decimals: 0)))",
                                        color: pressureColor(mem.pressureLevel)
                                    )
                                }
                                Text("\(Format.bytes(mem.used)) used of \(Format.bytes(mem.total)) physical RAM · \(Format.bytes(mem.free)) available")
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("SSD Swap Used")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(palette.textSecondary)
                                Text(Format.bytes(mem.swapUsed))
                                    .font(.system(size: 17, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(mem.swapUsed > 1024 * 1024 * 1024 ? palette.accentAmber : palette.textPrimary)
                            }
                        }

                        // Segmented composition bar
                        GeometryReader { geo in
                            let total = Double(max(1, mem.total))
                            let wApp = geo.size.width * CGFloat(Double(mem.app) / total)
                            let wWired = geo.size.width * CGFloat(Double(mem.wired) / total)
                            let wComp = geo.size.width * CGFloat(Double(mem.compressed) / total)
                            let wCached = geo.size.width * CGFloat(min(Double(mem.cached) / total, max(0, 1.0 - Double(mem.used) / total)))

                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.accentCyan)
                                    .frame(width: max(4, wApp))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.accentViolet)
                                    .frame(width: max(4, wWired))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.accentAmber)
                                    .frame(width: max(2, wComp))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(palette.accentEmerald.opacity(0.65))
                                    .frame(width: max(2, wCached))
                                Spacer(minLength: 0)
                            }
                            .background(RoundedRectangle(cornerRadius: 5).fill(palette.subtleFill))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .frame(height: 12)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            legendDot(label: "App Memory", value: Format.bytes(mem.app), color: palette.accentCyan)
                            legendDot(label: "Wired Kernel", value: Format.bytes(mem.wired), color: palette.accentViolet)
                            legendDot(label: "Compressed", value: Format.bytes(mem.compressed), color: palette.accentAmber)
                            legendDot(label: "Cached Files", value: Format.bytes(mem.cached), color: palette.accentEmerald)
                            legendDot(label: "Available", value: Format.bytes(mem.free), color: palette.textSecondary)
                        }
                    }
                }

                // 2. RAM Advisor Card (SQLite 7-Day Historical Analysis)
                RAMAdvisorCard(advisor: advisor, palette: palette)

                // 2b. Browser & Inactive Cache Relief Bar
                BrowserMemoryReliefCard(
                    appGroups: monitor.snapshot.appGroups,
                    cachedBytes: mem.cached,
                    palette: palette,
                    onInspectGroup: { grp in
                        uiState.selectGroup(grp)
                    }
                )

                // 3. Top Memory Consumers & Memory Growth / Leak Watch
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 280), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Top Memory App Groups", systemImage: "memorychip")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            ForEach(Array(monitor.snapshot.appGroups.prefix(10))) { group in
                                HStack(spacing: 8) {
                                    Image(nsImage: IconCache.shared.icon(forPath: group.children.first?.executablePath, bundlePath: group.bundlePath, pid: group.rootPID))
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(group.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textPrimary)
                                            .lineLimit(1)
                                            .layoutPriority(1)
                                        Text("\(group.processCount) proc\(group.processCount == 1 ? "" : "s")")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    Spacer(minLength: 4)
                                    Sparkline(
                                        values: group.memoryTrail.map { Double($0.memory) },
                                        color: palette.accentCyan
                                    )
                                    .frame(width: 44, height: 16)

                                    Text(Format.bytes(group.memoryBytes))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.accentEmerald)
                                        .frame(width: 70, alignment: .trailing)
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(uiState.selectedGroupID == group.id ? palette.subtleFill : palette.backgroundPrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(palette.cardBorder, lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    uiState.selectGroup(group)
                                }
                            }
                        }
                    }

                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("15-Minute Memory Growth / Leak Watch", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            let growing = monitor.snapshot.appGroups
                                .filter { $0.memoryGrowthBytes > 10 * 1024 * 1024 }
                                .sorted { $0.memoryGrowthBytes > $1.memoryGrowthBytes }
                                .prefix(8)

                            if growing.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("No Rapid Memory Growth Detected")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(palette.accentEmerald)
                                    Text("Taskyfy tracks 15-minute memory trails per application group and flags sustained heap growth automatically.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.textSecondary)
                                }
                                .padding(.vertical, 12)
                            } else {
                                ForEach(Array(growing)) { grp in
                                    HStack {
                                        Text(grp.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(Format.signedBytes(grp.memoryGrowthBytes))
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.accentAmber)
                                        Text("(\(Format.bytes(grp.memoryBytes)))")
                                            .font(.system(size: 11))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture { uiState.selectGroup(grp) }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(14)
        }
    }

    private func legendDot(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private func pressureColor(_ level: PressureLevel) -> Color {
        switch level {
        case .normal: return palette.accentEmerald
        case .warning: return palette.accentAmber
        case .critical: return palette.accentCoral
        }
    }
}

public struct RAMAdvisorCard: View {
    public let advisor: HistoryStore.Advisor
    public let palette: ThemePalette

    public var body: some View {
        GlassCard(palette: palette) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(palette.subtleFill))

                VStack(alignment: .leading, spacing: 2) {
                    Text("RAM Capacity Advisor · 7-Day Telemetry")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Text(advisor.recommendationTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Peak Used: \(Format.bytes(advisor.peakUsed)) · Peak Swap: \(Format.bytes(advisor.peakSwap)) · Pressured Time: \(Format.percent(advisor.pressuredFraction * 100, decimals: 1))")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
        }
    }
}

public struct BrowserMemoryReliefCard: View {
    public let appGroups: [AppGroup]
    public let cachedBytes: UInt64
    public let palette: ThemePalette
    public let onInspectGroup: (AppGroup) -> Void

    @State private var copiedPurge: Bool = false

    public var body: some View {
        let browserGroups = appGroups.filter { BrowserKind.detect(name: $0.name, bundleID: $0.bundleID) != nil }
        let browserTotalBytes = browserGroups.reduce(UInt64(0)) { $0 &+ $1.memoryBytes }
        let browserProcCount = browserGroups.reduce(0) { $0 + $1.processCount }

        GlassCard(palette: palette) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .foregroundStyle(palette.textPrimary)
                        Text("Browser Tab & Purgeable Cache Optimizer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    if !browserGroups.isEmpty {
                        Text("\(browserGroups.map(\.name).joined(separator: ", ")) using \(Format.bytes(browserTotalBytes)) across \(browserProcCount) tab processes · \(Format.bytes(cachedBytes)) disk cache")
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    } else {
                        Text("Reclaimable macOS file cache: \(Format.bytes(cachedBytes)) (freed automatically when apps request RAM)")
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let topBrowser = browserGroups.first,
                   let kind = BrowserKind.detect(name: topBrowser.name, bundleID: topBrowser.bundleID) {
                    Button("Open \(kind.displayName) Task Manager") {
                        onInspectGroup(topBrowser)
                        _ = kind.openTaskManager(pid: topBrowser.rootPID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(copiedPurge ? "Copied `sudo purge` ✓" : "Copy `sudo purge`") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("sudo purge", forType: .string)
                    copiedPurge = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - EnergyView

public struct EnergyView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let bat = monitor.snapshot.battery
        let today = monitor.history.computeEnergyToday()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Live Power Draw & Battery Telemetry (Responsive Grid)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 270), spacing: 12)],
                    spacing: 12
                ) {
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("System Power Draw")
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                    Text(Format.watts(bat.watts))
                                        .font(.system(size: 26, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textPrimary)
                                    Text(bat.isPluggedIn
                                         ? (bat.adapterWatts > 0 ? "AC Power (\(bat.adapterWatts)W Adapter)" : "Connected to AC Power")
                                         : "Discharging on Battery")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                RingGauge(
                                    progress: min(bat.watts / 65.0, 1.0),
                                    primaryText: Format.watts(bat.watts),
                                    secondaryText: "Live",
                                    color: palette.accentEmerald,
                                    size: 56
                                )
                            }

                            AreaChart(
                                points: monitor.powerSeries,
                                color: palette.accentEmerald,
                                height: 64,
                                valueFormatter: { Format.watts($0) }
                            )
                        }
                    }

                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Battery & Today's Energy", systemImage: "battery.100percent")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                StatusPill(
                                    label: bat.hasBattery ? "\(Int(bat.percentage))%" : "Desktop AC",
                                    color: palette.accentEmerald
                                )
                            }

                            HStack(spacing: 16) {
                                energyStat("Health", value: Format.percent(bat.healthPercent, decimals: 0))
                                energyStat("Cycles", value: "\(bat.cycleCount)")
                                energyStat("Temp", value: Format.celsius(bat.temperature))
                                energyStat("Today", value: Format.wattHours(today.wattHoursUsed))
                            }

                            Divider().opacity(0.3)

                            Text("Average Power Today: \(Format.watts(today.avgWatts)) over \(Format.duration(minutes: today.activeMinutes))")
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }

                // 2. Top Energy Consumers
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Top Live Energy Impact Applications", systemImage: "bolt.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)

                        let sortedEnergy = monitor.snapshot.appGroups
                            .sorted { $0.energyImpact > $1.energyImpact }
                            .prefix(12)

                        ForEach(Array(sortedEnergy)) { group in
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

                                Text("\(String(format: "%.0f", group.wakeupsPerSec)) wake/s")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 86, alignment: .trailing)

                                Text(Format.percent(group.cpuPercent))
                                    .font(.system(size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .frame(width: 58, alignment: .trailing)

                                StatusPill(
                                    label: String(format: "%.1f impact", group.energyImpact),
                                    color: group.energyImpact > 50 ? palette.accentAmber : palette.accentEmerald
                                )
                                .frame(width: 96, alignment: .trailing)
                            }
                            .padding(.vertical, 5)
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
            }
            .padding(14)
        }
    }

    private func energyStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }
}
