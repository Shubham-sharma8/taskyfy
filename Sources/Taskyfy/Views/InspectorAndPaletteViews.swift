import SwiftUI
import AppKit
import TaskyfyCore

// MARK: - InspectorView (Helium-Inspired Minimal Info Panel)

public struct InspectorView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette
    public var width: CGFloat = 292

    @State private var confirmForceQuit: Bool = false
    @State private var actionFeedback: String?
    @State private var sigTick: Int = 0

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette, width: CGFloat = 292) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
        self.width = width
    }

    public var body: some View {
        let snap = monitor.snapshot
        let selectedGroup = snap.appGroups.first { $0.id == uiState.selectedGroupID }
            ?? snap.appGroups.first { $0.rootPID == uiState.selectedPID }
            ?? snap.appGroups.first
        let selectedProc = snap.processes.first { $0.pid == (uiState.selectedPID ?? selectedGroup?.rootPID) }
            ?? selectedGroup?.children.first

        VStack(alignment: .leading, spacing: 0) {
            // Inspector Header
            HStack {
                Text("\(selectedProc?.name ?? selectedGroup?.name ?? "Process") Info")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("⌘I")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.subtleFill))
                Button {
                    withAnimation(.snappy) { uiState.showInspector = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.backgroundPrimary)

            Rectangle()
                .fill(palette.cardBorder)
                .frame(height: 1)

            if let group = selectedGroup {
                let targetPID = selectedProc?.pid ?? group.rootPID
                let execPath = selectedProc?.executablePath ?? group.children.first?.executablePath ?? group.bundlePath
                let kbEntry = ProcessLibrary.shared.lookup(
                    name: selectedProc?.name ?? group.name,
                    bundleID: group.bundleID,
                    path: execPath
                )
                let _ = sigTick
                let sigRecord = SignatureCache.shared.status(forPath: execPath) {
                    Task { @MainActor in
                        sigTick &+= 1
                    }
                }
                let ports = !(selectedProc?.openPorts ?? []).isEmpty
                    ? (selectedProc?.openPorts ?? [])
                    : group.openPorts

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. Identity Card (Helium Info Card Style)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(nsImage: IconCache.shared.icon(forPath: execPath, bundlePath: group.bundlePath, pid: targetPID))
                                    .resizable()
                                    .frame(width: 36, height: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedProc?.name ?? group.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)

                                    Text("PID \(targetPID) · \(selectedProc?.user ?? "user") · \(group.processCount) proc\(group.processCount == 1 ? "" : "s")")
                                        .font(.system(size: 11, weight: .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 2)
                            }

                            Divider().opacity(0.4)

                            // Clean Key-Value Rows (Helium Inspector style)
                            VStack(spacing: 7) {
                                infoRow(label: "CPU Load:", value: Format.percent(group.cpuPercent), pill: false)
                                infoRow(label: "Memory:", value: Format.bytes(group.memoryBytes), pill: true)
                                infoRow(label: "Energy Impact:", value: String(format: "%.1f", group.energyImpact), pill: false)
                                infoRow(label: "Threads / Wake:", value: "\(selectedProc?.threadCount ?? 1) · \(String(format: "%.0f/s", group.wakeupsPerSec))", pill: false)
                                infoRow(label: "Signature:", value: sigRecord.status.rawValue, pill: true, pillColor: sigColor(sigRecord.status))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.backgroundPrimary))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))

                        // 2. Action Controls (Quit, Force Quit, Pause/Resume, Reveal, Priority)
                        if targetPID > 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Button {
                                        if ProcessReader.terminate(pid: targetPID, force: false) {
                                            actionFeedback = "Sent Quit (SIGTERM) to PID \(targetPID)"
                                            monitor.refreshNow()
                                        }
                                    } label: {
                                        Label("Quit", systemImage: "power")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        confirmForceQuit = true
                                    } label: {
                                        Label("Force Quit", systemImage: "xmark.octagon")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(palette.accentCoral)
                                    .controlSize(.small)
                                }

                                HStack(spacing: 5) {
                                    let isPaused = selectedProc?.isSuspended ?? false
                                    Button {
                                        if ProcessReader.setSuspended(pid: targetPID, suspend: !isPaused) {
                                            actionFeedback = isPaused ? "Resumed PID \(targetPID)" : "Paused PID \(targetPID)"
                                            monitor.refreshNow()
                                        }
                                    } label: {
                                        Text(isPaused ? "Resume" : "Pause")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    if let path = group.bundlePath ?? execPath {
                                        Button {
                                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                        } label: {
                                            Text("Finder")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(path, forType: .string)
                                            actionFeedback = "Copied path"
                                        } label: {
                                            Text("Copy Path")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    Spacer(minLength: 0)

                                    Menu {
                                        Button("Elevated Priority (nice -5)") {
                                            applyNice(pid: targetPID, nice: -5)
                                        }
                                        Button("Normal Priority (nice 0)") {
                                            applyNice(pid: targetPID, nice: 0)
                                        }
                                        Button("Low Priority (nice +10)") {
                                            applyNice(pid: targetPID, nice: 10)
                                        }
                                        Button("Background Idle (nice +20)") {
                                            applyNice(pid: targetPID, nice: 20)
                                        }
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 11))
                                    }
                                    .controlSize(.small)
                                    .frame(width: 28)
                                }

                                if let feedback = actionFeedback {
                                    Text(feedback)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.accentEmerald)
                                }
                            }
                            .confirmationDialog(
                                "Force Quit \(selectedProc?.name ?? group.name) (PID \(targetPID))?",
                                isPresented: $confirmForceQuit
                            ) {
                                Button("Force Quit Immediately", role: .destructive) {
                                    _ = ProcessReader.terminate(pid: targetPID, force: true)
                                    actionFeedback = "Force-terminated PID \(targetPID)"
                                    monitor.refreshNow()
                                }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Unsaved data in this application may be lost.")
                            }
                        }

                        // 3. Browser Task Manager Callout (if browser detected)
                        if let browser = BrowserKind.detect(name: group.name, bundleID: group.bundleID) {
                            BrowserCallout(browser: browser, pid: group.rootPID, palette: palette)
                        }

                        // 4. Knowledge Base Plain-English Explanation & SafeToQuitCallout
                        if let entry = kbEntry {
                            SafeToQuitCallout(entry: entry, palette: palette)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("What is \(entry.title)?")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)

                                Text(entry.summary)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let reasons = entry.whyHigh, !reasons.isEmpty {
                                    Divider().opacity(0.4)
                                    Text("Why Usage Can Be High")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    ForEach(reasons, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("·").foregroundStyle(palette.textSecondary)
                                            Text(item)
                                                .font(.system(size: 11))
                                                .foregroundStyle(palette.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }

                                if let steps = entry.whatToDo, !steps.isEmpty {
                                    Divider().opacity(0.4)
                                    Text("Recommended Actions")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    ForEach(steps, id: \.self) { step in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("✓").foregroundStyle(palette.accentEmerald)
                                            Text(step)
                                                .font(.system(size: 11))
                                                .foregroundStyle(palette.textSecondary)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.backgroundPrimary))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
                        }

                        // 5. Open Listening Ports & Sockets
                        if !ports.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Open Network Ports (\(ports.count))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)

                                ForEach(ports.prefix(10)) { port in
                                    HStack {
                                        Text(port.proto)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundStyle(palette.textSecondary)
                                            .frame(width: 36, alignment: .leading)
                                        Text(":\(port.localPort)")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textPrimary)
                                        Spacer()
                                        Text(port.state)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(port.state == "LISTEN" ? palette.accentEmerald : palette.textSecondary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.backgroundPrimary))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
                        }

                        // 6. 15-Minute Memory Trail
                        if group.memoryTrail.count >= 2 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("15-Min Memory Trail")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                    Spacer()
                                    Text(Format.signedBytes(group.memoryGrowthBytes))
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(group.memoryGrowthBytes > 0 ? palette.accentAmber : palette.accentEmerald)
                                }
                                Sparkline(
                                    values: group.memoryTrail.map { Double($0.memory) },
                                    color: palette.accentCyan
                                )
                                .frame(height: 32)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(palette.backgroundPrimary))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
                        }

                        // 7. Executable Path & Signing Authority
                        if let path = execPath {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Where:")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(palette.textSecondary)
                                Text(path)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                if let auth = sigRecord.authority {
                                    Text("Signed by: \(auth)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: width - 4, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "info.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.textSecondary)
                    Text("Select any application to inspect")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width)
        .background(palette.cardSurface)
        .overlay(
            Rectangle()
                .fill(palette.cardBorder)
                .frame(width: 1),
            alignment: .leading
        )
    }

    private func infoRow(label: String, value: String, pill: Bool, pillColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 6)
            if pill {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(pillColor ?? palette.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill((pillColor ?? palette.textPrimary).opacity(0.08))
                    )
            } else {
                Text(value)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private func sigColor(_ status: SignatureCache.Status) -> Color {
        switch status {
        case .apple, .notarized: return palette.accentEmerald
        case .signed: return palette.textPrimary
        case .adHoc: return palette.accentAmber
        case .unsigned: return palette.accentCoral
        case .unknown: return palette.textSecondary
        }
    }

    private func applyNice(pid: Int32, nice: Int32) {
        if ProcessReader.setPriority(pid: pid, niceValue: nice) {
            actionFeedback = "Set PID \(pid) priority to nice \(nice)"
        } else {
            actionFeedback = "Could not set priority (requires ownership/root)"
        }
    }
}

public struct SafeToQuitCallout: View {
    public let entry: ProcessEntry
    public let palette: ThemePalette

    public var body: some View {
        let (title, color, icon): (String, Color, String) = {
            switch entry.safeToQuit.lowercased() {
            case "yes":
                return ("Safe to Quit", palette.accentEmerald, "checkmark.circle.fill")
            case "no":
                return ("System Critical — Keep Running", palette.accentCoral, "hand.raised.fill")
            default:
                return ("Quit with Caution", palette.accentAmber, "exclamationmark.triangle.fill")
            }
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            if let note = entry.safeToQuitNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.backgroundPrimary))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
    }
}

public struct BrowserCallout: View {
    public let browser: BrowserKind
    public let pid: Int32
    public let palette: ThemePalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(palette.textPrimary)
                Text("\(browser.displayName) Tab Memory")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Each browser tab runs in its own helper process. Use \(browser.taskManagerShortcutHint) to close heavy tabs.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Button("Open \(browser.displayName) Task Manager") {
                _ = browser.openTaskManager(pid: pid)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.backgroundPrimary))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
    }
}

// MARK: - CommandPalette (⌘K)

public struct CommandPalette: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    let palette: ThemePalette

    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    public init(monitor: Monitor, uiState: UIState, palette: ThemePalette) {
        self.monitor = monitor
        self.uiState = uiState
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    uiState.showPalette = false
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    TextField("Search apps, PIDs, ports (e.g. :3000), or macOS daemons…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .focused($isFocused)
                    Button("ESC") {
                        uiState.showPalette = false
                    }
                    .font(.system(size: 10, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(14)

                Rectangle()
                    .fill(palette.cardBorder)
                    .frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        let matchingSections = UIState.Section.allCases.filter {
                            query.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)
                        }
                        if !matchingSections.isEmpty {
                            Text("Sections")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            ForEach(matchingSections) { sec in
                                Button {
                                    uiState.section = sec
                                    uiState.showPalette = false
                                } label: {
                                    HStack {
                                        Image(systemName: sec.symbolName)
                                            .foregroundStyle(palette.textPrimary)
                                            .frame(width: 20)
                                        Text(sec.rawValue)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textPrimary)
                                        Spacer()
                                        Text(sec.subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        let cleanQuery = query.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
                        let matchingGroups = monitor.snapshot.appGroups.filter { grp in
                            guard !cleanQuery.isEmpty else { return false }
                            if grp.name.localizedCaseInsensitiveContains(cleanQuery) || "\(grp.rootPID)".contains(cleanQuery) {
                                return true
                            }
                            return grp.openPorts.contains { "\($0.localPort)".contains(cleanQuery) }
                        }.prefix(8)

                        if !matchingGroups.isEmpty {
                            Text("Running Applications")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            ForEach(Array(matchingGroups)) { grp in
                                Button {
                                    uiState.selectGroup(grp)
                                    uiState.section = .apps
                                    uiState.showPalette = false
                                } label: {
                                    HStack {
                                        Text(grp.name)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(palette.textPrimary)
                                        Spacer()
                                        Text("\(Format.percent(grp.cpuPercent)) · \(Format.bytes(grp.memoryBytes))")
                                            .font(.system(size: 11))
                                            .monospacedDigit()
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        let kbHits = ProcessLibrary.shared.search(query, limit: 6)
                        if !kbHits.isEmpty {
                            Text("Process Encyclopedia")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                            ForEach(kbHits) { item in
                                Button {
                                    uiState.searchQuery = item.title
                                    uiState.section = .apps
                                    uiState.showPalette = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(item.title)
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundStyle(palette.textPrimary)
                                            Spacer()
                                            Text(item.category)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(palette.textSecondary)
                                        }
                                        Text(item.oneLiner)
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 340)
            }
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(palette.backgroundPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
        }
        .onAppear { isFocused = true }
    }
}
