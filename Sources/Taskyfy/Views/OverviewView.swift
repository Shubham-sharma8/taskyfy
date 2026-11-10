import SwiftUI
import TaskyfyCore

public struct OverviewView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    @State private var showAllCores: Bool = false

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let snap = monitor.snapshot

        GeometryReader { geo in
            let isNarrow = geo.size.width < 520
            let kpiColumns: [GridItem] = isNarrow
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            let bottomColumns: [GridItem] = geo.size.width < 560
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Live Anomaly Banners
                    if !monitor.recentEvents.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(monitor.recentEvents.prefix(2)) { event in
                                EventBanner(event: event, palette: palette) {
                                    if let appKey = event.relatedAppKey,
                                       let group = snap.appGroups.first(where: { $0.id == appKey }) {
                                        uiState.selectGroup(group)
                                    }
                                }
                            }
                        }
                    }

                    // 2. Responsive 4-Card Telemetry Deck (Always 2x2 on standard/wide, 1-col on compact split)
                    LazyVGrid(
                        columns: kpiColumns,
                        spacing: 12
                    ) {
                    // CPU Hero Card
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                        Text("Processor Load")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Text(Format.percent(snap.cpu.totalUsage))
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("User \(Format.percent(snap.cpu.userUsage, decimals: 0)) · Sys \(Format.percent(snap.cpu.systemUsage, decimals: 0)) · Load \(String(format: "%.2f", snap.cpu.loadAverage.0))")
                                        .font(.system(size: 11, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 4)
                                RingGauge(
                                    progress: snap.cpu.totalUsage / 100.0,
                                    primaryText: Format.percent(snap.cpu.totalUsage, decimals: 0),
                                    secondaryText: "\(snap.cpu.perCore.count)C",
                                    color: palette.accentCyan,
                                    size: 52
                                )
                            }

                            AreaChart(
                                points: monitor.cpuSeries,
                                color: palette.accentCyan,
                                fixedMax: 100,
                                height: 48,
                                valueFormatter: { Format.percent($0) }
                            )
                        }
                    }
                    .onTapGesture { uiState.section = .apps }

                    // Memory Hero Card
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "memorychip")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                        Text("Unified Memory")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Text("\(Format.bytes(snap.memory.used)) / \(Format.bytes(snap.memory.total))")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.78)
                                    Text("App \(Format.bytes(snap.memory.app)) · Wired \(Format.bytes(snap.memory.wired)) · Swap \(Format.bytes(snap.memory.swapUsed))")
                                        .font(.system(size: 11, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 4)
                                RingGauge(
                                    progress: snap.memory.usedFraction,
                                    primaryText: Format.percent(snap.memory.usedFraction * 100, decimals: 0),
                                    secondaryText: snap.memory.pressureLevel.label,
                                    color: memoryTint(snap.memory.pressureLevel),
                                    size: 52
                                )
                            }

                            AreaChart(
                                points: monitor.memorySeries,
                                color: memoryTint(snap.memory.pressureLevel),
                                fixedMax: 100,
                                height: 48,
                                valueFormatter: { Format.percent($0) }
                            )
                        }
                    }
                    .onTapGesture { uiState.section = .memory }

                    // GPU & Acceleration Card
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "display")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                        Text(snap.gpu.modelName)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Text(Format.percent(snap.gpu.utilization))
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Text("Renderer \(Format.percent(snap.gpu.rendererUtilization, decimals: 0)) · Tiler \(Format.percent(snap.gpu.tilerUtilization, decimals: 0)) · VRAM \(Format.bytes(snap.gpu.inUseSystemMemory))")
                                        .font(.system(size: 11, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 4)
                                RingGauge(
                                    progress: snap.gpu.utilization / 100.0,
                                    primaryText: Format.percent(snap.gpu.utilization, decimals: 0),
                                    secondaryText: "GPU",
                                    color: palette.accentViolet,
                                    size: 52
                                )
                            }

                            AreaChart(
                                points: monitor.gpuSeries,
                                color: palette.accentViolet,
                                fixedMax: 100,
                                height: 48,
                                valueFormatter: { Format.percent($0) }
                            )
                        }
                    }
                    .onTapGesture { uiState.section = .sensors }

                    // Power & Thermal Card
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: snap.battery.isPluggedIn ? "bolt" : "battery.75percent")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                        Text("Power & Thermal")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(Format.watts(snap.battery.watts))
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(palette.textPrimary)
                                            .monospacedDigit()
                                            .lineLimit(1)
                                        Text("· \(Format.celsius(snap.thermal.socTemp))")
                                            .font(.system(size: 15, weight: .medium))
                                            .monospacedDigit()
                                            .foregroundStyle(thermalTint(snap.thermal.state))
                                            .lineLimit(1)
                                    }
                                    .minimumScaleFactor(0.8)
                                    Text(snap.battery.hasBattery
                                         ? "\(Int(snap.battery.percentage))% Battery · \(snap.battery.isPluggedIn ? "AC Power" : "On Battery") · \(snap.thermal.state.label)"
                                         : "AC Line Power · Peak \(Format.celsius(snap.thermal.socMax)) · \(snap.thermal.state.label)")
                                        .font(.system(size: 11, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 4)
                                RingGauge(
                                    progress: min(snap.thermal.socTemp / 105.0, 1.0),
                                    primaryText: Format.celsius(snap.thermal.socTemp),
                                    secondaryText: snap.thermal.state.label,
                                    color: thermalTint(snap.thermal.state),
                                    size: 52
                                )
                            }

                            AreaChart(
                                points: monitor.powerSeries,
                                color: palette.accentEmerald,
                                height: 48,
                                valueFormatter: { Format.watts($0) }
                            )
                        }
                    }
                    .onTapGesture { uiState.section = .energy }
                }

                // 3. Per-Core P/E Matrix Card
                GlassCard(palette: palette) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Apple Silicon P/E Core Matrix", systemImage: "square.grid.3x3")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            let eCount = monitor.perCoreSeries.filter { $0.type == .efficiency }.count
                            let pCount = monitor.perCoreSeries.filter { $0.type == .performance }.count
                            if pCount > 0 || eCount > 0 {
                                StatusPill(label: "\(pCount)P · \(eCount)E", color: palette.textSecondary)
                            }
                            if monitor.perCoreSeries.count > 8 {
                                Button(showAllCores ? "Compact" : "Show All") {
                                    withAnimation(.snappy) { showAllCores.toggle() }
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            }
                        }

                        CoreHeatmapGrid(
                            cores: showAllCores ? monitor.perCoreSeries : Array(monitor.perCoreSeries.prefix(8)),
                            palette: palette
                        )
                    }
                }

                // 4. Top Active Apps & Network/Storage Responsive Grid
                LazyVGrid(
                    columns: bottomColumns,
                    alignment: .leading,
                    spacing: 12
                ) {
                    // Top Active AppGroups
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Top Active Applications", systemImage: "app.badge.checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Button("View All (\(snap.appGroups.count)) →") {
                                    uiState.section = .apps
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            }

                            let topCPU = snap.appGroups
                                .sorted { ($0.cpuPercent + $0.energyImpact) > ($1.cpuPercent + $1.energyImpact) }
                                .prefix(6)

                            ForEach(Array(topCPU)) { group in
                                TopAppRow(
                                    group: group,
                                    sparkValues: (monitor.appSeries[group.id] ?? []).map(\.value),
                                    isSelected: uiState.selectedGroupID == group.id,
                                    palette: palette
                                )
                                .onTapGesture {
                                    uiState.selectGroup(group)
                                    monitor.selectedPIDForDeepScan = group.rootPID
                                }
                            }
                        }
                    }

                    // Network/Disk Throughput & Self-Footprint
                    VStack(spacing: 12) {
                        GlassCard(palette: palette) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Network & Disk Throughput", systemImage: "arrow.up.arrow.down.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(snap.network.activeInterface)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(palette.subtleFill))
                                }

                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("↓ Download")
                                            .font(.system(size: 10.5, weight: .regular))
                                            .foregroundStyle(palette.textSecondary)
                                        Text(Format.rate(snap.network.rxRate))
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textPrimary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("↑ Upload")
                                            .font(.system(size: 10.5, weight: .regular))
                                            .foregroundStyle(palette.textSecondary)
                                        Text(Format.rate(snap.network.txRate))
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textPrimary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Disk R/W")
                                            .font(.system(size: 10.5, weight: .regular))
                                            .foregroundStyle(palette.textSecondary)
                                        Text("\(Format.rate(snap.disk.readRate)) / \(Format.rate(snap.disk.writeRate))")
                                            .font(.system(size: 12, weight: .medium))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.accentEmerald)
                                            .lineLimit(1)
                                    }
                                }

                                DualAreaChart(
                                    primaryPoints: monitor.rxSeries,
                                    secondaryPoints: monitor.txSeries,
                                    primaryColor: palette.accentCyan,
                                    secondaryColor: palette.accentViolet,
                                    primaryLabel: "RX",
                                    secondaryLabel: "TX",
                                    height: 72
                                )
                            }
                        }
                        .onTapGesture { uiState.section = .network }

                        // Taskyfy SelfCost & Helper Status Card
                        GlassCard(palette: palette) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Taskyfy Self-Footprint", systemImage: "waveform.path.ecg")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    StatusPill(
                                        label: snap.helperActive ? "XPC Helper Active" : "Standard Mode",
                                        color: palette.accentEmerald,
                                        symbol: "checkmark.circle.fill"
                                    )
                                }

                                HStack(spacing: 16) {
                                    metricPill(title: "Own CPU", value: Format.percent(snap.selfCost.cpuPercent))
                                    metricPill(title: "Own RAM", value: Format.bytes(snap.selfCost.memoryBytes))
                                    metricPill(title: "Disk I/O", value: Format.bytes(snap.selfCost.diskWrittenBytes))
                                    metricPill(title: "SQLite WAL", value: Format.bytes(monitor.history.databaseFileSizeBytes()))
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(14)
            }
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
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

    private func memoryTint(_ level: PressureLevel) -> Color {
        switch level {
        case .normal: return palette.accentEmerald
        case .warning: return palette.accentAmber
        case .critical: return palette.accentCoral
        }
    }

    private func thermalTint(_ level: ThermalLevel) -> Color {
        switch level {
        case .nominal: return palette.accentEmerald
        case .fair: return palette.accentAmber
        case .serious, .critical: return palette.accentCoral
        }
    }
}

// MARK: - TopAppRow & EventBanner

public struct TopAppRow: View {
    public let group: AppGroup
    public let sparkValues: [Double]
    public let isSelected: Bool
    public let palette: ThemePalette

    public var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.shared.icon(forPath: group.children.first?.executablePath, bundlePath: group.bundlePath, pid: group.rootPID))
                .resizable()
                .frame(width: 20, height: 20)

            HStack(spacing: 5) {
                Text(group.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                if group.processCount > 1 {
                    Text("\(group.processCount)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(palette.subtleFill))
                }
            }

            Spacer(minLength: 6)

            Text(Format.percent(group.cpuPercent))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(group.cpuPercent > 80 ? palette.accentAmber : palette.textPrimary)
                .frame(width: 52, alignment: .trailing)

            Text(Format.bytes(group.memoryBytes))
                .font(.system(size: 11.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(palette.accentEmerald)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.subtleFill : palette.backgroundPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
    }
}

public struct EventBanner: View {
    public let event: SystemEvent
    public let palette: ThemePalette
    public let onSelect: () -> Void

    public var body: some View {
        let color: Color = {
            switch event.severity {
            case .info: return palette.textPrimary
            case .warning: return palette.accentAmber
            case .critical: return palette.accentCoral
            }
        }()

        HStack(spacing: 10) {
            Image(systemName: event.kind.symbolName)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(Circle().fill(color.opacity(0.10)))

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(Format.relativeTime(from: event.timestamp))
                        .font(.system(size: 10.5, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
                Text(event.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if event.relatedAppKey != nil {
                Button("Inspect") {
                    onSelect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.cardBorder, lineWidth: 1)
        )
    }
}
