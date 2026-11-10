import SwiftUI
import TaskyfyCore

// MARK: - PopoverView (Menu Bar Minimal Dashboard)

public struct PopoverView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let onOpenMainWindow: () -> Void

    public init(monitor: Monitor, uiState: UIState, onOpenMainWindow: @escaping () -> Void) {
        self.monitor = monitor
        self.uiState = uiState
        self.onOpenMainWindow = onOpenMainWindow
    }

    public var body: some View {
        let palette = ThemePalette.forTheme(monitor.settings.theme)
        let snap = monitor.snapshot

        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                TaskyfyLogo(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Taskyfy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(snap.processes.count) processes active")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button("Open Studio ↗") {
                    onOpenMainWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 3 Mini Gauges
            HStack(spacing: 8) {
                popoverGaugeCard(
                    title: "CPU",
                    value: Format.percent(snap.cpu.totalUsage, decimals: 0),
                    progress: snap.cpu.totalUsage / 100.0,
                    color: palette.accentCyan,
                    palette: palette
                )
                popoverGaugeCard(
                    title: "RAM",
                    value: Format.percent(snap.memory.usedFraction * 100, decimals: 0),
                    progress: snap.memory.usedFraction,
                    color: palette.accentViolet,
                    palette: palette
                )
                popoverGaugeCard(
                    title: "SoC",
                    value: Format.celsius(snap.thermal.socTemp),
                    progress: min(snap.thermal.socTemp / 100.0, 1.0),
                    color: palette.accentEmerald,
                    palette: palette
                )
            }

            // Top 5 Active Apps
            VStack(alignment: .leading, spacing: 5) {
                Text("Top Consumers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)

                ForEach(Array(snap.appGroups.prefix(5))) { grp in
                    HStack(spacing: 8) {
                        Image(nsImage: IconCache.shared.icon(forPath: grp.children.first?.executablePath, bundlePath: grp.bundlePath, pid: grp.rootPID))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(grp.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(Format.percent(grp.cpuPercent, decimals: 0))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                        Text(Format.bytes(grp.memoryBytes))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(palette.accentEmerald)
                            .frame(width: 62, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        uiState.selectGroup(grp)
                        onOpenMainWindow()
                    }
                }
            }

            Rectangle()
                .fill(palette.cardBorder)
                .frame(height: 1)

            // Footer Network & Power bar
            HStack {
                Label(Format.watts(snap.battery.watts), systemImage: "bolt")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.accentEmerald)
                Spacer()
                Text("↓ \(Format.rate(snap.network.rxRate))  ↑ \(Format.rate(snap.network.txRate))")
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
        .frame(width: 325)
        .background(palette.backgroundPrimary)
        .preferredColorScheme(palette.preferredColorScheme)
    }

    private func popoverGaugeCard(
        title: String,
        value: String,
        progress: Double,
        color: Color,
        palette: ThemePalette
    ) -> some View {
        VStack(spacing: 4) {
            RingGauge(
                progress: progress,
                primaryText: value,
                secondaryText: title,
                color: color,
                size: 52,
                lineWidth: 4.5
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.cardBorder, lineWidth: 1))
    }
}

// MARK: - SettingsView

public struct SettingsView: View {
    @Bindable var monitor: Monitor
    @Bindable var settings: AppSettings
    @Bindable var menuBarState: MenuBarState
    @Environment(\.dismiss) private var dismiss

    @State private var helperMessage: String?

    public init(monitor: Monitor, settings: AppSettings = .shared, menuBarState: MenuBarState = .shared) {
        self.monitor = monitor
        self.settings = settings
        self.menuBarState = menuBarState
    }

    public var body: some View {
        let palette = ThemePalette.forTheme(settings.theme)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TaskyfyLogo(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Taskyfy Preferences")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("100% On-Device · Zero Telemetry · Open Source (MIT)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.accentEmerald)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accentCyan)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. Appearance & Sampling
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Appearance & Sampling Cadence", systemImage: "paintbrush")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            HStack {
                                Text("Visual Theme")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Picker("", selection: $settings.theme) {
                                    ForEach(AppTheme.allCases, id: \.self) { t in
                                        Text(t.displayName).tag(t)
                                    }
                                }
                                .frame(width: 210)
                            }

                            HStack {
                                Text("Live Sampling Interval")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Picker("", selection: $settings.sampleInterval) {
                                    ForEach(SampleInterval.allCases, id: \.self) { iv in
                                        Text(iv.displayName).tag(iv)
                                    }
                                }
                                .frame(width: 210)
                                .onChange(of: settings.sampleInterval) { _, newValue in
                                    monitor.updateInterval(newValue)
                                }
                            }
                        }
                    }

                    // 2. Menu Bar Telemetry Pill
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Menu Bar Telemetry Pill (⌥⌘T)", systemImage: "menubar.rectangle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            HStack {
                                Text("Menu Bar Style")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Picker("", selection: $menuBarState.mode) {
                                    ForEach(MenuBarMode.allCases, id: \.self) { m in
                                        Text(m.displayName).tag(m)
                                    }
                                }
                                .frame(width: 210)
                            }

                            HStack(spacing: 16) {
                                Toggle("CPU %", isOn: $menuBarState.showCPU)
                                Toggle("Memory %", isOn: $menuBarState.showMemory)
                                Toggle("SoC Temp", isOn: $menuBarState.showTemp)
                                Toggle("Power W", isOn: $menuBarState.showPower)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textPrimary)
                        }
                    }

                    // 3. Smart Anomaly Alerts
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Anomaly Detection & Alerts", systemImage: "bell")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            Toggle("Enable macOS Notifications for CPU Spikes, Memory Leaks & Thermal Throttling", isOn: $settings.notificationsEnabled)
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.textPrimary)

                            HStack {
                                Text("Detection Sensitivity")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Picker("", selection: $settings.alertSensitivity) {
                                    ForEach(AlertSensitivity.allCases, id: \.self) { s in
                                        Text(s.displayName).tag(s)
                                    }
                                }
                                .frame(width: 210)
                            }
                        }
                    }

                    // 4. Privileged Read-Only Helper (SMAppService)
                    GlassCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Privileged Read-Only Helper (TaskyfyHelper)", systemImage: "shield")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                StatusPill(
                                    label: HelperClient.shared.installState.rawValue,
                                    color: HelperClient.shared.installState == .enabled ? palette.accentEmerald : palette.textSecondary
                                )
                            }

                            Text("TaskyfyHelper is an optional LaunchDaemon registered via SMAppService that reads kernel_task and root daemon rusage metrics over XPC and exits automatically after 120 seconds of inactivity.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.textSecondary)

                            HStack(spacing: 10) {
                                Button("Install / Enable Helper") {
                                    do {
                                        try HelperClient.shared.registerDaemon()
                                        helperMessage = "Helper registration requested."
                                    } catch {
                                        helperMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("System Login Items…") {
                                    HelperClient.shared.openSystemSettingsLoginItems()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            if let helperMessage {
                                Text(helperMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }

                    // 5. SQLite History Retention
                    GlassCard(palette: palette) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Local SQLite WAL History (\(Format.bytes(monitor.history.databaseFileSizeBytes())))")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(monitor.history.dbURL.path)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Button("Clear History", role: .destructive) {
                                monitor.history.clearAll()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 520)
        .background(palette.backgroundPrimary)
        .preferredColorScheme(palette.preferredColorScheme)
    }
}
