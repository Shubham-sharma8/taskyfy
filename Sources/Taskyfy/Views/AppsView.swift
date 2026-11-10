import SwiftUI
import TaskyfyCore

public struct AppsView: View {
    public enum SortField: String, CaseIterable {
        case memory = "Memory"
        case cpu = "CPU %"
        case energy = "Energy"
        case disk = "Disk I/O"
        case name = "Name"
    }

    public enum FilterMode: String, CaseIterable {
        case grouped = "Grouped"
        case appsOnly = "Apps"
        case systemOnly = "System"
        case flat = "All PIDs"
    }

    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    @State private var sortField: SortField = .memory
    @State private var sortAscending: Bool = false
    @State private var filterMode: FilterMode = .grouped
    @State private var expandedGroups: Set<String> = []

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        let snap = monitor.snapshot

        VStack(spacing: 0) {
            // Toolbar bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.textSecondary)
                    TextField("Filter apps, PIDs…", text: $uiState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !uiState.searchQuery.isEmpty {
                        Button {
                            uiState.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.cardSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(palette.cardBorder, lineWidth: 1)
                )
                .frame(minWidth: 120, maxWidth: 210)

                Picker("", selection: $filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)

                Spacer(minLength: 4)

                Text("\(snap.processes.count) procs · \(snap.appGroups.count) groups")
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            // Column Header Bar
            HStack(spacing: 6) {
                sortHeader("Name", field: .name, alignment: .leading)
                Spacer(minLength: 4)
                Text("Trend")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 42, alignment: .center)
                sortHeader("CPU %", field: .cpu, alignment: .trailing)
                    .frame(width: 56, alignment: .trailing)
                sortHeader("Memory", field: .memory, alignment: .trailing)
                    .frame(width: 70, alignment: .trailing)
                sortHeader("Energy", field: .energy, alignment: .trailing)
                    .frame(width: 52, alignment: .trailing)
                sortHeader("Disk I/O", field: .disk, alignment: .trailing)
                    .frame(width: 66, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6.5)
            .background(palette.cardSurface)

            Rectangle()
                .fill(palette.cardBorder)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filterMode == .flat {
                        let procs = filteredProcesses(from: snap.processes)
                        ForEach(procs) { proc in
                            FlatProcessRow(
                                proc: proc,
                                isSelected: uiState.selectedPID == proc.pid,
                                palette: palette
                            )
                            .onTapGesture {
                                uiState.selectProcess(proc)
                                monitor.selectedPIDForDeepScan = proc.pid
                                monitor.refreshNow()
                            }
                        }
                    } else {
                        let groups = filteredGroups(from: snap.appGroups)
                        ForEach(groups) { group in
                            let isExpanded = expandedGroups.contains(group.id)
                            GroupProcessRow(
                                group: group,
                                sparkValues: (monitor.appSeries[group.id] ?? []).map(\.value),
                                isSelected: uiState.selectedGroupID == group.id,
                                isExpanded: isExpanded,
                                palette: palette,
                                onToggleExpand: {
                                    if isExpanded {
                                        expandedGroups.remove(group.id)
                                    } else {
                                        expandedGroups.insert(group.id)
                                    }
                                },
                                onSelectGroup: {
                                    uiState.selectGroup(group)
                                    monitor.selectedPIDForDeepScan = group.rootPID
                                    monitor.refreshNow()
                                },
                                onSelectChild: { child in
                                    uiState.selectProcess(child, groupID: group.id)
                                    monitor.selectedPIDForDeepScan = child.pid
                                    monitor.refreshNow()
                                },
                                selectedPID: uiState.selectedPID
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func sortHeader(_ title: String, field: SortField, alignment: Alignment) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = (field == .name)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: sortField == field ? .semibold : .medium))
                    .foregroundStyle(sortField == field ? palette.textPrimary : palette.textSecondary)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .frame(maxWidth: field == .name ? .infinity : nil, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    private func filteredGroups(from all: [AppGroup]) -> [AppGroup] {
        let q = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = all.filter { g in
            switch filterMode {
            case .appsOnly:
                if !g.isApp { return false }
            case .systemOnly:
                if g.isApp { return false }
            default:
                break
            }
            guard !q.isEmpty else { return true }
            if g.name.lowercased().contains(q) { return true }
            if let bid = g.bundleID?.lowercased(), bid.contains(q) { return true }
            if "\(g.rootPID)".contains(q) { return true }
            return g.children.contains { $0.name.lowercased().contains(q) || "\($0.pid)".contains(q) }
        }

        return filtered.sorted { a, b in
            let asc = sortAscending
            switch sortField {
            case .memory:
                return asc ? (a.memoryBytes < b.memoryBytes) : (a.memoryBytes > b.memoryBytes)
            case .cpu:
                return asc ? (a.cpuPercent < b.cpuPercent) : (a.cpuPercent > b.cpuPercent)
            case .energy:
                return asc ? (a.energyImpact < b.energyImpact) : (a.energyImpact > b.energyImpact)
            case .disk:
                let da = a.diskReadRate + a.diskWriteRate
                let db = b.diskReadRate + b.diskWriteRate
                return asc ? (da < db) : (da > db)
            case .name:
                return asc
                    ? (a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending)
                    : (a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending)
            }
        }
    }

    private func filteredProcesses(from all: [ProcInfo]) -> [ProcInfo] {
        let q = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = all.filter { p in
            guard !q.isEmpty else { return true }
            return p.name.lowercased().contains(q)
                || "\(p.pid)".contains(q)
                || (p.bundleID?.lowercased().contains(q) == true)
                || p.user.lowercased().contains(q)
        }
        return filtered.sorted { a, b in
            let asc = sortAscending
            switch sortField {
            case .memory: return asc ? (a.memoryBytes < b.memoryBytes) : (a.memoryBytes > b.memoryBytes)
            case .cpu: return asc ? (a.cpuPercent < b.cpuPercent) : (a.cpuPercent > b.cpuPercent)
            case .energy: return asc ? (a.energyImpact < b.energyImpact) : (a.energyImpact > b.energyImpact)
            case .disk:
                let da = a.diskReadRate + a.diskWriteRate
                let db = b.diskReadRate + b.diskWriteRate
                return asc ? (da < db) : (da > db)
            case .name:
                return asc
                    ? (a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending)
                    : (a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending)
            }
        }
    }
}

// MARK: - GroupProcessRow & FlatProcessRow

private struct GroupProcessRow: View {
    let group: AppGroup
    let sparkValues: [Double]
    let isSelected: Bool
    let isExpanded: Bool
    let palette: ThemePalette
    let onToggleExpand: () -> Void
    let onSelectGroup: () -> Void
    let onSelectChild: (ProcInfo) -> Void
    let selectedPID: Int32?

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                if group.processCount > 1 {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Image(nsImage: IconCache.shared.icon(forPath: group.children.first?.executablePath, bundlePath: group.bundlePath, pid: group.rootPID))
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
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

                        if group.memoryGrowthBytes > 150 * 1024 * 1024 {
                            Text(Format.signedBytes(group.memoryGrowthBytes))
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(palette.accentAmber)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(palette.accentAmber.opacity(0.10)))
                        }
                    }

                    if let entry = ProcessLibrary.shared.lookup(name: group.name, bundleID: group.bundleID, path: group.bundlePath) {
                        Text(entry.oneLiner)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    } else if let bid = group.bundleID {
                        Text(bid)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Sparkline(values: sparkValues, color: palette.accentCyan)
                    .frame(width: 42, height: 16)

                Text(Format.percent(group.cpuPercent))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(group.cpuPercent > 80 ? palette.accentAmber : palette.textPrimary)
                    .frame(width: 56, alignment: .trailing)

                Text(Format.bytes(group.memoryBytes))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.accentEmerald)
                    .frame(width: 70, alignment: .trailing)

                Text(String(format: "%.1f", group.energyImpact))
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(group.energyImpact > 50 ? palette.accentAmber : palette.textSecondary)
                    .frame(width: 52, alignment: .trailing)

                Text(Format.rate(group.diskReadRate + group.diskWriteRate))
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 66, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? palette.subtleFill : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelectGroup)

            if isExpanded && group.processCount > 1 {
                VStack(spacing: 1) {
                    ForEach(group.children) { child in
                        HStack(spacing: 6) {
                            Spacer().frame(width: 24)
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 9.5))
                                .foregroundStyle(palette.textSecondary)
                            Text(child.name)
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Text("PID \(child.pid)")
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                            if child.isSuspended {
                                StatusPill(label: "Paused", color: palette.accentAmber)
                            }
                            Spacer(minLength: 4)
                            Text(Format.percent(child.cpuPercent))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 56, alignment: .trailing)
                            Text(Format.bytes(child.memoryBytes))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 70, alignment: .trailing)
                            Text(String(format: "%.1f", child.energyImpact))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 52, alignment: .trailing)
                            Text(Format.rate(child.diskReadRate + child.diskWriteRate))
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 66, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedPID == child.pid ? palette.subtleFill : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectChild(child)
                        }
                    }
                }
            }
        }
    }
}

private struct FlatProcessRow: View {
    let proc: ProcInfo
    let isSelected: Bool
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.shared.icon(forPath: proc.executablePath, pid: proc.pid))
                .resizable()
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(proc.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("PID \(proc.pid) · \(proc.user)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    if proc.isSuspended {
                        StatusPill(label: "Paused", color: palette.accentAmber)
                    }
                }
                if let entry = ProcessLibrary.shared.lookup(name: proc.name, bundleID: proc.bundleID, path: proc.executablePath) {
                    Text(entry.oneLiner)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Text("\(proc.threadCount)t")
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 42, alignment: .center)

            Text(Format.percent(proc.cpuPercent))
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(width: 56, alignment: .trailing)

            Text(Format.bytes(proc.memoryBytes))
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(palette.accentEmerald)
                .frame(width: 70, alignment: .trailing)

            Text(String(format: "%.1f", proc.energyImpact))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 52, alignment: .trailing)

            Text(Format.rate(proc.diskReadRate + proc.diskWriteRate))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.subtleFill : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
