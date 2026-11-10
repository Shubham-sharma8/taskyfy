# Taskyfy — macOS Telemetry Studio

[![CI](https://github.com/shubhamsharma/taskify/actions/workflows/ci.yml/badge.svg)](https://github.com/shubhamsharma/taskify/actions/workflows/ci.yml)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B%20Sonoma-black?logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10%2B-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests Passing](https://img.shields.io/badge/Tests-41%2F41%20Passing-brightgreen.svg)](Tests/TaskyfyTests/main.swift)

**Taskyfy** is a modern, high-performance telemetry studio and Activity Monitor alternative engineered specifically for macOS Sonoma (14.0+) and Apple Silicon architecture. Built entirely in Swift and SwiftUI with an unprivileged, low-overhead design, Taskyfy couples low-level Darwin kernel probes with an embedded SQLite Write-Ahead Logging (WAL) time-series engine to offer real-time system observability, process tree forensics, memory leak detection, and hardware thermal diagnostics.

---

## Highlights & Features

- **Apple Silicon P/E Cluster Profiling**: Real-time microsecond-level Mach tick sampling split across Performance (P) and Efficiency (E) cores with live CPU load bar graphs.
- **2-Process Zero-Allocation XPC Architecture**: Isolates kernel metric collection inside a standalone daemon (`TaskyfyHelper`) communicating over Mach messages via 64-byte binary wire structs (`RawProcRecord`).
- **Memory Pressure & Leak Trails**: Tracks physical footprint (`phys_footprint`), swap memory, compression levels, and displays monotonic 7-sample memory trails to instantly flag runaway allocations.
- **Hardware & Thermal Telemetry**: Direct IOKit HID and Apple SMC integration reading SoC, GPU, SSD, and battery pack temperatures, alongside dynamic fan RPM gauges.
- **Embedded SQLite WAL Historical Engine**: High-throughput time-series store maintaining 1-minute rollup intervals across 1-hour, 6-hour, 24-hour, 7-day, and 30-day horizons with instant JSON/CSV export.
- **Smart RAM Advisor**: Evaluates memory pressure history and swap usage spikes to calculate deterministic RAM upgrade recommendations.
- **Live Anomaly Engine**: Detects persistent CPU spikes, memory leaks, swap pressure degradation, and thermal throttling in real time.
- **Status Bar Menu Extra & Glass Popover**: Compact live metrics (`CPU · RAM · Temp · Watts`) in the macOS menu bar with an interactive floating popover accessible globally.
- **Quick Command Palette (`⌘K`)**: Spotlight-style command bar for instantaneous process filtering, section jumps, and terminal process operations.

---

## Deep Dive Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Taskyfy.app (Client UI)                         │
│  ┌─────────────────────────┐  ┌──────────────────────────────────────┐ │
│  │   SwiftUI Workspace     │  │          MenuBarController           │ │
│  │  • Navigation Rail      │  │  • NSStatusItem (Live Telemetry)     │ │
│  │  • 7 Dedicated Panels   │  │  • Floating NSPopover                │ │
│  │  • Slide-Over Inspector │  │  • Carbon Global Hotkey (⌥⌘T)        │ │
│  └────────────▲────────────┘  └──────────────────▲───────────────────┘ │
│               │                                  │                     │
│               └─────────────────┬────────────────┘                     │
│                                 ▼                                      │
│                  TaskyfyCore State & Telemetry Clock                   │
│          (@Bindable Monitor • 1.5s Adaptive MainActor Dispatch)         │
└─────────────────────────────────┬──────────────────────────────────────┘
                                  │
         ┌────────────────────────┴────────────────────────┐
         │                                                 │
         ▼ (NSXPCConnection / Mach Message)                ▼ (Direct Darwin/Mach)
┌───────────────────────────────────────────┐   ┌────────────────────────────────┐
│               TaskyfyHelper               │   │      Darwin Kernel Probes      │
│  • Standalone Mach Daemon                 │   │  • host_processor_info()       │
│  • Wire Protocol (64-byte RawProcRecord)  │   │  • sysctlbyname(vm.swapusage)  │
│  • proc_listallpids + proc_pid_rusage     │   │  • IOKit HID & SMC Temp Sensors│
│  • 120-Second IdleExit Battery Guard      │   │  • Network ifaddrs & Disk I/O  │
└───────────────────────────────────────────┘   └────────────────▲───────────────┘
                                                                 │
                                                                 ▼
                                                ┌────────────────────────────────┐
                                                │     SQLite WAL Time-Series     │
                                                │  • PRAGMA journal_mode=WAL     │
                                                │  • 1-Minute Historical Rollups │
                                                │  • Anomaly & Leak Detection    │
                                                │  • Zero-alloc JSON/CSV Export  │
                                                └────────────────────────────────┘
```

### 1. 2-Process XPC Separation & Wire Protocol
Rather than performing heavy process walks on the main UI thread, Taskyfy separates telemetry acquisition into `TaskyfyHelper`:
- The helper iterates active processes via `proc_listallpids` and queries `proc_pid_rusage(RUSAGE_INFO_V6)`.
- Records are serialized into contiguous arrays of `RawProcRecord` (exactly 64 bytes per process).
- The wire protocol involves zero JSON or property-list parsing overhead, yielding sub-millisecond serialization over `NSXPCConnection`.
- To prevent background battery drain when the studio is not running, `IdleExit` automatically shuts down the daemon after 120 seconds of inactivity.

### 2. Mach, IOKit & sysctl Telemetry
- **CPU & Cores**: Uses Mach's `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` to read raw user, system, idle, and nice tick counters. Apple Silicon core types are differentiated into Performance and Efficiency clusters via `sysctl hw.perflevel*`.
- **Sensors**: Interfaces with IOKit HID event system and Apple SMC service entries to retrieve calibrated temperature channels for SoC, GPU, NAND storage, and battery cells.
- **Network & Disk**: Uses `getifaddrs` for real-time per-interface bandwidth rates and Darwin `proc_pid_rusage` disk I/O deltas.

### 3. SQLite WAL Historical Store
Taskyfy persists rolling system metrics to a local SQLite database (`taskyfy_history.sqlite`) located in `~/Library/Application Support/app.taskyfy.mac/`:
- Configured with `PRAGMA journal_mode=WAL;` and `PRAGMA synchronous=NORMAL;` for high-throughput, non-blocking concurrent writes.
- Rollups downsample system state and individual application groups into 1-minute epochs.
- Query engines calculate time-windowed rollups (`1h`, `6h`, `24h`, `7d`, `30d`), assess swap volatility for the **RAM Advisor**, and output structured JSON and CSV telemetry logs.

---

## Keyboard Shortcuts

| Shortcut | Scope | Action |
|:---:|:---:|:---|
| <kbd>⌘</kbd> <kbd>K</kbd> | Application | Open Spotlight-style **Quick Command Palette** |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>T</kbd> | System-Wide | **Global Hotkey** to toggle the Menu Bar telemetry popover from any desktop |
| <kbd>⌘</kbd> <kbd>I</kbd> | Application | Toggle the slide-over **Process Inspector** |
| <kbd>⌘</kbd> <kbd>R</kbd> | Application | Trigger an immediate **Telemetry Refresh** |
| <kbd>⌘</kbd> <kbd>,</kbd> | Application | Open **Settings & Theme Customization** modal |

---

## Studio Workspace Panels

1. **Overview**: Executive dashboard showing total CPU usage, cluster topology, memory pressure donut, SoC temperature gauge, battery discharge rate, and top consumers.
2. **Apps & Process Tree**: Consolidated app grouping that folds background helpers (e.g. Chrome Renderers, WebKit networking workers) under their parent application bundle with quick quit/kill actions.
3. **Memory & Leak Hunter**: Breakdown of wired, active, compressed, and swap memory with historical growth trails to diagnose memory leaks.
4. **Energy & Battery**: Wattage draw, battery health percentage, cycle count, thermal throttling levels, and energy impact rankings.
5. **Sensors**: Live thermal map displaying individual thermal zones (SoC, GPU, NAND, Battery) and dual fan speed controls/meters.
6. **Network & Disk**: Real-time upload/download and disk read/write bandwidth charts.
7. **Timeline & Event Log**: Anomaly log identifying CPU spikes, memory leaks, swap spikes, and thermal throttling events alongside the RAM upgrade advisor.

---

## Quick Start & Installation

### Prerequisites
- **macOS 14.0 (Sonoma)** or newer
- **Apple Silicon** (M1/M2/M3/M4) or **Intel** Mac
- **Xcode 15+** or **Xcode Command Line Tools** (`xcode-select --install`)

### One-Command Setup
Clone the repository and run `setup.sh`:

```bash
git clone https://github.com/shubhamsharma/taskify.git
cd taskify
./setup.sh
```

`setup.sh` checks system dependencies, builds all targets, executes the test suite, and packages the signed `Taskyfy.app` bundle.

### Development Commands

```bash
# 1. Compile all debug targets
swift build

# 2. Run the architecture and telemetry test suite
swift run TaskyfyTests

# 3. Launch the studio app directly from terminal
swift run Taskyfy

# 4. Launch standalone XPC helper daemon
swift run TaskyfyHelper

# 5. Compile release targets and assemble signed Taskyfy.app
bash Scripts/build_app.sh

# 6. Launch the built desktop application
open Taskyfy.app

# 7. Open the native Xcode project for GUI debugging & Apple Developer signing
open Taskyfy.xcodeproj
```

### Opening & Signing in Xcode
1. Run `open Taskyfy.xcodeproj` (or regenerate it anytime via `python3 Scripts/generate_xcodeproj.py`).
2. Select the **Taskyfy** project in the Xcode Project Navigator, choose the **Taskyfy** app target, and open the **Signing & Capabilities** tab.
3. Select your Apple Developer **Team** (or *Sign to Run Locally*), and press <kbd>⌘</kbd> <kbd>R</kbd> to build, sign, and run `Taskyfy.app` (which automatically builds and embeds `TaskyfyHelper` into `Contents/Library/LaunchServices/`).

---

## Project Layout

```
taskify/
├── Package.swift                                # SPM package definition & framework dependencies
├── setup.sh                                     # One-command bootstrap and build script
├── CLAUDE.md                                    # Developer & Claude Code context reference (<100 lines)
├── AGENTS.md                                    # Architectural invariants & agent contributor guide
├── CONTRIBUTING.md                              # Contribution guidelines & code standards
├── LICENSE                                      # MIT License
├── Resources/
│   ├── AppIcon.icns                             # High-resolution multi-scale app icon
│   └── LaunchDaemons/
│       └── app.taskyfy.helper.plist             # LaunchDaemon plist for privileged helper registration
├── Scripts/
│   ├── build_app.sh                             # Builds, bundles, codesigns, and verifies Taskyfy.app
│   └── generate_icon.swift                      # Generates prism-pulse vector iconset via AppKit
├── Sources/
│   ├── Taskyfy/                                 # Main macOS SwiftUI Studio Application
│   │   ├── App/
│   │   │   └── TaskyfyApp.swift                 # @main, AppDelegate, MenuBarController, MainWindowView
│   │   ├── Components/
│   │   │   └── ChartsAndRings.swift             # Gauges, donut charts, and mini sparklines
│   │   ├── Theme/
│   │   │   └── GlassTheme.swift                 # Aurora glow palette, typography, and accent themes
│   │   └── Views/
│   │       ├── AppsView.swift                   # Process tree, app grouping, search & filters
│   │       ├── InspectorAndPaletteViews.swift   # Process detail slide-over and ⌘K Command Palette
│   │       ├── MemoryAndEnergyViews.swift       # Memory pressure, leak trails, battery wattages
│   │       ├── OverviewView.swift               # Core telemetry dashboard
│   │       ├── PopoverAndSettingsViews.swift    # Status bar floating popover & preferences sheet
│   │       └── SensorsNetworkAndTimelineViews.swift # Thermal matrix, network IO, event timeline
│   ├── TaskyfyCore/                             # Shared Telemetry Engine & Data Layer
│   │   ├── Models/
│   │   │   ├── EventModels.swift                # SystemEvent, Anomaly rules, and Advisor recommendations
│   │   │   ├── Format.swift                     # Microsecond, byte, and wattage formatters
│   │   │   └── TelemetryModels.swift            # CPUSample, MemoryStats, ThermalStats, RawProcRecord
│   │   ├── Readers/
│   │   │   ├── CPUReader.swift                  # Mach host_processor_info P/E cluster reader
│   │   │   ├── NetworkAndDiskReader.swift       # ifaddrs and Darwin rusage disk rate samplers
│   │   │   ├── ProcessReader.swift              # Kernel process table and app grouping logic
│   │   │   ├── Sampler.swift                    # Orchestrates unified 1.5s telemetry snapshot
│   │   │   └── SensorReader.swift               # IOKit HID and Apple SMC temperature readers
│   │   ├── Resources/
│   │   │   └── processes.json                   # Knowledge base of 200+ known macOS process signatures
│   │   ├── Services/
│   │   │   ├── EventDetector.swift              # Anomaly detection engine (leaks, throttling, spikes)
│   │   │   ├── HelperClient.swift               # SMAppService registration and XPC connection manager
│   │   │   ├── HistoryStore.swift               # SQLite3 WAL time-series store and JSON/CSV exporter
│   │   │   ├── ProcessLibrary.swift             # Pattern matcher for known processes and daemons
│   │   │   └── SignatureCache.swift             # Code-signing and bundle identifier cache
│   │   └── State/
│   │       ├── Monitor.swift                    # Central Observable state machine & telemetry ticker
│   │       └── SettingsAndUIState.swift         # User preferences, themes, and selection states
│   └── TaskyfyHelper/                           # Standalone Mach XPC Daemon
│       └── main.swift                           # proc_pid_rusage sampler with 120s IdleExit
├── Tests/
│   └── TaskyfyTests/
│       └── main.swift                           # Comprehensive 5-part architecture verification suite
└── .github/
    ├── ISSUE_TEMPLATE/
    │   ├── bug_report.md                        # Bug report template
    │   └── feature_request.md                   # Feature request template
    └── workflows/
        └── ci.yml                               # GitHub Actions macOS Sonoma CI workflow
```

---

## Using with Claude Code

This project includes custom developer instructions tailored for [Claude Code](https://claude.ai/code):

- `CLAUDE.md`: Concise, fast-reference architectural blueprint and verified copy-paste commands.
- `AGENTS.md`: Detailed safety invariants for Darwin kernel pointers, Swift 5.10 concurrency, and XPC wire protocol stability.

To get started with Claude Code:

```bash
claude
```

Claude Code automatically ingests `CLAUDE.md` to ensure any refactor, test run, or feature addition strictly adheres to the project's architectural invariants.

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on code style, testing requirements, and the pull request submission process.

---

## License

Taskyfy is licensed under the [MIT License](LICENSE).
© 2026 Taskyfy Contributors.
