import SwiftUI
import AppKit
import Carbon
import TaskyfyCore

// MARK: - MainWindowView

public struct MainWindowView: View {
    @Bindable var monitor: Monitor
    @Bindable var uiState: UIState
    @Bindable var settings: AppSettings

    public init(monitor: Monitor, uiState: UIState, settings: AppSettings = .shared) {
        self.monitor = monitor
        self.uiState = uiState
        self.settings = settings
    }

    public var body: some View {
        let palette = ThemePalette.forTheme(settings.theme)
        let snap = monitor.snapshot

        GeometryReader { geo in
            let totalWidth = max(760, geo.size.width)
            let totalHeight = max(520, geo.size.height)
            let isCompact = totalWidth < 1100
            let sidebarWidth: CGFloat = isCompact ? 188 : 208
            let inspectorWidth: CGFloat = uiState.showInspector ? (isCompact ? 268 : 292) : 0
            let centerWidth = max(360, totalWidth - sidebarWidth - inspectorWidth)

            ZStack {
                palette.backgroundPrimary
                    .ignoresSafeArea()

                HStack(spacing: 0) {
                    // Left Minimal Sidebar
                    sidebarView(palette: palette, snap: snap, width: sidebarWidth)
                        .frame(width: sidebarWidth, height: totalHeight)
                        .clipped()

                    // Center Workspace + Top Breadcrumb Header
                    VStack(spacing: 0) {
                        topBar(palette: palette, snap: snap, isCompact: centerWidth < 620)
                        Rectangle()
                            .fill(palette.cardBorder)
                            .frame(height: 1)

                        Group {
                            switch uiState.section {
                            case .overview:
                                OverviewView(monitor: monitor, uiState: uiState, palette: palette)
                            case .apps:
                                AppsView(monitor: monitor, uiState: uiState, palette: palette)
                            case .memory:
                                MemoryView(monitor: monitor, uiState: uiState, palette: palette)
                            case .energy:
                                EnergyView(monitor: monitor, uiState: uiState, palette: palette)
                            case .sensors:
                                SensorsView(monitor: monitor, palette: palette)
                            case .network:
                                NetworkView(monitor: monitor, uiState: uiState, palette: palette)
                            case .timeline:
                                TimelineView(monitor: monitor, uiState: uiState, palette: palette)
                            }
                        }
                        .frame(width: centerWidth)
                        .frame(maxHeight: .infinity)
                        .clipped()
                    }
                    .frame(width: centerWidth, height: totalHeight)
                    .clipped()

                    // Right Slide-Over Inspector
                    if uiState.showInspector {
                        InspectorView(
                            monitor: monitor,
                            uiState: uiState,
                            palette: palette,
                            width: inspectorWidth
                        )
                        .frame(width: inspectorWidth, height: totalHeight)
                        .clipped()
                        .transition(.move(edge: .trailing))
                    }
                }
                .frame(width: totalWidth, height: totalHeight)

                // Command Palette Overlay (⌘K)
                if uiState.showPalette {
                    CommandPalette(monitor: monitor, uiState: uiState, palette: palette)
                        .transition(.opacity)
                }
            }
            .frame(width: totalWidth, height: totalHeight)
        }
        .preferredColorScheme(palette.preferredColorScheme)
        .onChange(of: uiState.selectedPID) { _, newPID in
            monitor.selectedPIDForDeepScan = newPID
        }
        .onChange(of: monitor.snapshot.appGroups.first?.id) { _, _ in
            if uiState.selectedGroupID == nil, let first = monitor.snapshot.appGroups.first {
                uiState.selectedGroupID = first.id
                uiState.selectedPID = first.rootPID
                monitor.selectedPIDForDeepScan = first.rootPID
            }
        }
        .sheet(isPresented: $uiState.showSettingsSheet) {
            SettingsView(monitor: monitor, settings: settings)
        }
        .background(
            HStack {
                Button("") { uiState.showPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { withAnimation(.snappy) { uiState.showInspector.toggle() } }
                    .keyboardShortcut("i", modifiers: .command)
                Button("") { monitor.refreshNow() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("") { uiState.showSettingsSheet = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    private func sidebarView(palette: ThemePalette, snap: TelemetrySnapshot, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Brand Header (with top clearance for macOS window traffic lights)
            HStack(spacing: 8) {
                TaskyfyLogo(size: 24)
                Text("Taskyfy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("v2.0")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(palette.subtleFill))
            }
            .padding(.horizontal, 14)
            .padding(.top, 34)
            .padding(.bottom, 6)

            // Quick Command Trigger
            Button {
                uiState.showPalette = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Text("Quick Search")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(palette.subtleFill))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.backgroundPrimary))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Text("Telemetry")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)

            // Navigation Items (Single-Line Apple HIG Sidebar)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(UIState.Section.allCases) { sec in
                        let active = uiState.section == sec
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                uiState.section = sec
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: sec.symbolName)
                                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                                    .frame(width: 18)

                                Text(shortSectionTitle(sec))
                                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text(sectionLiveBadge(sec, snap: snap))
                                    .font(.system(size: 11, weight: .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(active ? palette.subtleFill : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 4)

            // Preferences & Appearance Section (Matching Helium / Apple Sidebar Reference)
            Rectangle()
                .fill(palette.cardBorder)
                .frame(height: 1)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 2) {
                Text("Preferences & Studio")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .padding(.bottom, 2)

                Button {
                    uiState.showSettingsSheet = true
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 18)
                        Text("Settings")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Button(t.displayName) { settings.theme = t }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 18)
                        Text("Appearance")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5.5)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: width)
        .background(palette.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(palette.cardBorder)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func shortSectionTitle(_ sec: UIState.Section) -> String {
        switch sec {
        case .overview: return "Overview"
        case .apps: return "Processes"
        case .memory: return "Memory"
        case .energy: return "Energy"
        case .sensors: return "Sensors"
        case .network: return "Network"
        case .timeline: return "History"
        }
    }

    private func topBar(palette: ThemePalette, snap: TelemetrySnapshot, isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("Taskyfy")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                Text("›")
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                Text(uiState.section.rawValue)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if !isCompact {
                    if let base = monitor.pinnedBaseline {
                        let dCPU = snap.cpu.totalUsage - base.cpu.totalUsage
                        let dRAM = Int64(snap.memory.used) - Int64(base.memory.used)
                        Button {
                            monitor.clearBaseline()
                        } label: {
                            StatusPill(
                                label: String(format: "Δ %+.0f%% · %@ ✕", dCPU, Format.signedBytes(dRAM)),
                                color: palette.textPrimary,
                                symbol: "pin.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            monitor.pinBaseline()
                        } label: {
                            StatusPill(label: "Pin Baseline", color: palette.textSecondary, symbol: "pin")
                        }
                        .buttonStyle(.plain)
                    }
                }

                StatusPill(label: "CPU \(Format.percent(snap.cpu.totalUsage, decimals: 0))", color: palette.textPrimary, symbol: "cpu")
                StatusPill(label: "RAM \(Format.percent(snap.memory.usedFraction * 100, decimals: 0))", color: palette.textPrimary, symbol: "memorychip")
                if !isCompact {
                    StatusPill(label: Format.celsius(snap.thermal.socTemp), color: palette.accentEmerald, symbol: "thermometer.medium")
                    StatusPill(label: Format.watts(snap.battery.watts), color: palette.textSecondary, symbol: "bolt.fill")
                }
            }

            Button {
                withAnimation(.snappy) {
                    uiState.showInspector.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(uiState.showInspector ? palette.textPrimary : palette.textSecondary)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(uiState.showInspector ? palette.subtleFill : Color.clear))
            }
            .buttonStyle(.plain)
            .help("Toggle Process Inspector (⌘I)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.backgroundPrimary)
    }

    private func sectionLiveBadge(_ sec: UIState.Section, snap: TelemetrySnapshot) -> String {
        switch sec {
        case .overview: return Format.percent(snap.cpu.totalUsage, decimals: 0)
        case .apps: return "\(snap.appGroups.count)"
        case .memory: return Format.percent(snap.memory.usedFraction * 100, decimals: 0)
        case .energy: return Format.watts(snap.battery.watts)
        case .sensors: return Format.celsius(snap.thermal.socTemp)
        case .network: return Format.rate(snap.network.rxRate)
        case .timeline: return uiState.timelineRange.rawValue
        }
    }
}

// MARK: - MenuBarController (NSStatusItem + NSPopover + Global HotKey ⌥⌘T)

@MainActor
public final class MenuBarController: NSObject {
    private let monitor: Monitor
    private let uiState: UIState
    private let menuBarState: MenuBarState
    private let onOpenMainWindow: () -> Void
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var updateTimer: Timer?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    public init(
        monitor: Monitor,
        uiState: UIState,
        menuBarState: MenuBarState = .shared,
        onOpenMainWindow: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.uiState = uiState
        self.menuBarState = menuBarState
        self.onOpenMainWindow = onOpenMainWindow
        super.init()
        setupStatusItem()
        setupPopover()
        registerGlobalHotKey()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
        refreshTitle()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTitle()
            }
        }
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 325, height: 340)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                monitor: monitor,
                uiState: uiState,
                onOpenMainWindow: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.onOpenMainWindow()
                }
            )
        )
    }

    public func refreshTitle() {
        guard let button = statusItem?.button else { return }
        let snap = monitor.snapshot

        if menuBarState.mode == .iconOnly {
            button.title = " ◆"
            return
        }

        var parts: [String] = ["◆"]
        if menuBarState.showCPU {
            parts.append(String(format: "%.0f%%", snap.cpu.totalUsage))
        }
        if menuBarState.showMemory {
            parts.append(String(format: "%.0f%%", snap.memory.usedFraction * 100))
        }
        if menuBarState.showTemp && snap.thermal.socTemp > 0 {
            parts.append(String(format: "%.0f°", snap.thermal.socTemp))
        }
        if menuBarState.showPower {
            parts.append(String(format: "%.0fW", snap.battery.watts))
        }
        button.title = " " + parts.joined(separator: " · ") + " "
    }

    @objc public func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let controller = Unmanaged<MenuBarController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    controller.togglePopover(nil)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &hotKeyHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x544B4659), id: 1)
        let modifiers = UInt32(optionKey | cmdKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

// MARK: - AppDelegate & @main TaskyfyApp

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let monitor = Monitor()
    public let uiState = UIState()
    private var menuBarController: MenuBarController?
    private var mainWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AlertCenter.shared.configureIfBundled()
        applyEnvironmentOverrides()
        monitor.start()

        menuBarController = MenuBarController(
            monitor: monitor,
            uiState: uiState,
            onOpenMainWindow: { [weak self] in
                self?.showMainWindow()
            }
        )

        showMainWindow()

        if let shotDir = ProcessInfo.processInfo.environment["TASKYFY_SCREENSHOT_DIR"], !shotDir.isEmpty {
            Task { @MainActor in
                await runAutomatedScreenshotSuite(outDir: shotDir)
            }
        }
    }

    private func captureWindowPNG(to url: URL) {
        guard let window = mainWindow,
              let rootView = window.contentView?.superview ?? window.contentView else { return }
        window.displayIfNeeded()
        rootView.layoutSubtreeIfNeeded()
        let bounds = rootView.bounds
        guard bounds.width > 10, bounds.height > 10,
              let rep = rootView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        rootView.cacheDisplay(in: bounds, to: rep)

        // Compose onto a clean Helium-style #F5F5F3 marketing backdrop with soft window shadow & rounded corners
        let pad: CGFloat = 36
        let canvasSize = NSSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
        let composed = NSImage(size: canvasSize)
        composed.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(CGColor(red: 0.961, green: 0.961, blue: 0.953, alpha: 1.0)) // #F5F5F3
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            let winRect = CGRect(x: pad, y: pad, width: bounds.width, height: bounds.height)
            let clipPath = CGPath(roundedRect: winRect, cornerWidth: 12, cornerHeight: 12, transform: nil)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.12))
            ctx.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            ctx.addPath(clipPath)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(clipPath)
            ctx.clip()
            let winImg = NSImage(size: bounds.size)
            winImg.addRepresentation(rep)
            winImg.draw(in: winRect)
            ctx.restoreGState()

            ctx.addPath(clipPath)
            ctx.setStrokeColor(CGColor(gray: 0.0, alpha: 0.10))
            ctx.setLineWidth(1.0)
            ctx.strokePath()
        }
        composed.unlockFocus()

        if let tiff = composed.tiffRepresentation,
           let outRep = NSBitmapImageRep(data: tiff),
           let png = outRep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private func runAutomatedScreenshotSuite(outDir: String) async {
        let dirURL = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        // Wait 3.2 seconds so 3+ live samples populate sparklines and charts
        try? await Task.sleep(nanoseconds: 3_200_000_000)

        guard let window = mainWindow else { return }

        // 1. Multi-screen size responsive verification
        let screenSizes: [(String, CGFloat, CGFloat)] = [
            ("screen-compact-900x620.png", 900, 620),
            ("screen-standard-1180x760.png", 1180, 760),
            ("screen-wide-1380x860.png", 1380, 860)
        ]
        uiState.section = .overview
        uiState.showInspector = true
        for (name, w, h) in screenSizes {
            window.setContentSize(NSSize(width: w, height: h))
            window.center()
            try? await Task.sleep(nanoseconds: 450_000_000)
            captureWindowPNG(to: dirURL.appendingPathComponent(name))
        }

        // 2. Marketing screenshots at 1280x800 across all studio views
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.center()
        try? await Task.sleep(nanoseconds: 400_000_000)

        let marketingSections: [(String, UIState.Section, Bool)] = [
            ("01-taskyfy-overview-hero.png", .overview, true),
            ("02-taskyfy-processes-grouped.png", .apps, true),
            ("03-taskyfy-memory-advisor.png", .memory, true),
            ("04-taskyfy-energy-watts.png", .energy, false),
            ("05-taskyfy-sensors-thermals.png", .sensors, false),
            ("06-taskyfy-network-port-radar.png", .network, false),
            ("07-taskyfy-history-sqlite-wal.png", .timeline, false)
        ]

        for (filename, sec, showInsp) in marketingSections {
            uiState.section = sec
            uiState.showInspector = showInsp
            uiState.showPalette = false
            try? await Task.sleep(nanoseconds: 450_000_000)
            captureWindowPNG(to: dirURL.appendingPathComponent(filename))
        }

        // 3. Command Palette (⌘K) overlay screenshot
        uiState.section = .overview
        uiState.showInspector = true
        uiState.showPalette = true
        try? await Task.sleep(nanoseconds: 450_000_000)
        captureWindowPNG(to: dirURL.appendingPathComponent("08-taskyfy-command-palette.png"))

        uiState.showPalette = false
        NSApp.terminate(nil)
    }

    private func applyEnvironmentOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let secName = env["TASKYFY_SECTION"]?.lowercased() {
            switch secName {
            case "overview": uiState.section = .overview
            case "apps", "processes": uiState.section = .apps
            case "memory": uiState.section = .memory
            case "energy": uiState.section = .energy
            case "sensors", "thermals": uiState.section = .sensors
            case "network": uiState.section = .network
            case "timeline", "history": uiState.section = .timeline
            default: break
            }
        }
        if let hideInsp = env["TASKYFY_HIDE_INSPECTOR"], hideInsp == "1" {
            uiState.showInspector = false
        }
        if let showPal = env["TASKYFY_SHOW_PALETTE"], showPal == "1" {
            uiState.showPalette = true
        }
    }

    public func showMainWindow() {
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            monitor.setSurfaceVisibility(windowVisible: true, popoverVisible: false)
            return
        }

        let env = ProcessInfo.processInfo.environment
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let customW = env["TASKYFY_WIDTH"].flatMap(Double.init).map { CGFloat($0) }
        let customH = env["TASKYFY_HEIGHT"].flatMap(Double.init).map { CGFloat($0) }

        let targetWidth = customW ?? min(max(1020, visibleFrame.width * 0.88), 1340)
        let targetHeight = customH ?? min(max(660, visibleFrame.height * 0.85), 860)

        let hosting = NSHostingController(
            rootView: MainWindowView(monitor: monitor, uiState: uiState)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 860, height: 560)
        window.title = "Taskyfy — macOS Telemetry Studio"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.contentViewController = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    public func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
}

@main
public struct TaskyfyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {}

    public var body: some Scene {
        Settings {
            SettingsView(monitor: appDelegate.monitor)
        }
    }
}
