# AGENTS.md — Contributor & AI Agent Guidelines for Taskyfy

This file provides architectural conventions, memory safety invariants, and operational guidelines for AI agents and human contributors working on `Taskyfy`.

---

## 1. Project Overview & Architecture Invariants

`Taskyfy` is a dual-process macOS telemetry studio built with Swift 5.10 and SwiftUI. It operates across three distinct architectural boundaries:

1. **Client UI (`Taskyfy.app`)**:
   - Pure SwiftUI views with AppKit window hosting (`NSHostingController`).
   - Single-direction state flow through `@Bindable` `Monitor` and `UIState`.
   - Global Carbon hotkey registration (`⌥⌘T`) and `NSStatusItem` menu bar popover.

2. **Privileged / Unprivileged Helper Daemon (`TaskyfyHelper`)**:
   - Headless background process launched on demand via `SMAppService` or launchd.
   - Listens on Mach service `app.taskyfy.helper`.
   - Gathers kernel process resource usage (`proc_pid_rusage(RUSAGE_INFO_V6)`).
   - Enforces a 120-second idle termination policy (`IdleExit`) to ensure zero background battery drain when client is closed.

3. **Core Engine (`TaskyfyCore`)**:
   - Zero-allocation binary wire protocol: `RawProcRecord` (exactly 64 bytes, aligned).
   - Darwin / Mach kernel callers: `host_processor_info`, `mach_host_self()`, `getloadavg`, `sysctlbyname`.
   - IOKit & SMC temperature readers with fallback heuristics for virtualized environments.
   - SQLite3 WAL database (`HistoryStore`) executing non-blocking minute-granularity rollups.

---

## 2. Invariants & Safety Rules

- **Do Not Modify Swift Sources Without Explicit Task Request**: Never mutate files under `Sources/` or `Tests/` unless the prompt specifically demands feature additions or bug fixes.
- **Darwin Pointer Lifecycle**: Any call to `host_processor_info` or raw Mach APIs allocating kernel memory MUST be paired with `vm_deallocate` inside a `defer` block.
- **Wire Record Compatibility**: `RawProcRecord.byteStride` is strictly 64 bytes. If adding or altering fields, binary compatibility between `TaskyfyHelper` and `TaskyfyCore` must be preserved.
- **Thread Safety & Immutability**: All data models (`CPUSample`, `MemoryStats`, `AppGroup`, `ThermalStats`) are `Sendable` structs. Never mutate objects in place across threads; pass immutable snapshots.
- **MainActor UI**: All views, popovers, and status bar title changes must run on `@MainActor`. Background telemetry sampling occurs on detached tasks or private dispatch queues.
- **SQLite WAL Mode**: `HistoryStore` operates in WAL mode (`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`). Keep lock contention near zero; use parameterized statements for security.

---

## 3. Essential Commands & Verification

Always verify your changes by executing these commands before completing any task:

```bash
# 1. Clean build
swift build

# 2. Run test suite (5 architectural verification stages)
swift run TaskyfyTests

# 3. Assemble and codesign macOS bundle
bash Scripts/build_app.sh

# 4. Bootstrap test
./setup.sh
```

---

## 4. Keyboard Shortcuts Reference

| Shortcut | Description | Location |
|----------|-------------|----------|
| `⌘K` | Command Palette | Global within main window |
| `⌥⌘T` | Toggle Menu Bar Popover | System-wide Carbon HotKey |
| `⌘I` | Toggle Process Inspector | Main window sidebar |
| `⌘R` | Immediate Telemetry Refresh | Main window / Menu bar |
| `⌘,` | Settings & Appearance | Main window sheet |

---

## 5. Directory Layout

```
Taskyfy/
├── Package.swift                    # Swift Package Manager manifest
├── Sources/
│   ├── Taskyfy/                     # SwiftUI macOS Studio Application
│   │   ├── App/                     # App entry point, AppDelegate, MenuBarController
│   │   ├── Views/                   # Overview, Apps, Memory, Energy, Sensors, Network, Inspector
│   │   ├── Components/              # Custom Sparklines, Donut Rings, Gauges
│   │   └── Theme/                   # Aurora Glass theme & accent palettes
│   ├── TaskyfyCore/                 # Core telemetry engine & storage
│   │   ├── Models/                  # Telemetry, Event, and Formatting models
│   │   ├── Readers/                 # CPUReader, SensorReader, ProcessReader, Sampler
│   │   ├── Services/                # HistoryStore (SQLite WAL), EventDetector, HelperClient
│   │   ├── State/                   # Telemetry Monitor clock & UIState
│   │   └── Resources/               # Built-in process signatures (processes.json)
│   └── TaskyfyHelper/               # Lightweight Mach XPC daemon
├── Tests/
│   └── TaskyfyTests/                # Wire protocol, SQLite WAL, leak engine tests
├── Scripts/
│   ├── build_app.sh                 # App bundle assembly & ad-hoc code-signing
│   └── generate_icon.swift          # Prism-pulse vector iconset generator
├── Resources/                       # LaunchDaemons plists & AppIcon.icns
└── .github/                         # CI workflows & issue templates
```
