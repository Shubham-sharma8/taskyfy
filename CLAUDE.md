# Taskyfy

**Version:** 2.0.0 | **XPC Service:** `app.taskyfy.helper` | **Stack:** Swift 5.10+, SwiftUI, AppKit, Darwin/Mach, IOKit, SQLite3 (WAL)

## What
High-performance macOS telemetry studio and Activity Monitor alternative featuring 2-process XPC architecture, Apple Silicon P/E cluster metering, Mach/IOKit sensor telemetry, and an embedded SQLite WAL time-series engine.

## Quick Start

```bash
./setup.sh              # Check toolchain, compile, test, and package Taskyfy.app
swift run Taskyfy       # Launch macOS telemetry studio directly
swift run TaskyfyTests  # Run architecture and telemetry test suite
open Taskyfy.app        # Open assembled signed macOS application bundle
```

## Commands

```bash
# Development
swift build                     # Build all targets in debug mode
swift build -c release          # Build all targets in release mode
swift run Taskyfy               # Run main SwiftUI studio window
swift run TaskyfyHelper         # Run standalone XPC telemetry helper

# Testing
swift run TaskyfyTests          # Run 5-part architecture and telemetry suite

# App Bundle & Packaging
bash Scripts/build_app.sh       # Assemble, code-sign, and verify Taskyfy.app
```

## Architecture

```
Taskyfy.app (SwiftUI + AppKit Studio UI)
 ├── MainWindowView (Navigation rail, Overview, Apps, Memory, Energy, Sensors, Network, Timeline)
 ├── MenuBarController (NSStatusItem, PopoverView, Carbon Global Hotkey ⌥⌘T)
 └── CommandPalette (⌘K Spotlight-style quick switcher & search)
       │ (NSXPCConnection / Mach Service: app.taskyfy.helper)
TaskyfyHelper (Privileged/Daemon 64-byte binary wire protocol, 120s IdleExit)
       │ (Darwin / Mach / IOKit Kernel Interfaces)
TaskyfyCore
 ├── Readers: CPUReader (Mach ticks), SensorReader (IOKit/HID/SMC), ProcessReader, NetworkAndDiskReader
 ├── Services: HistoryStore (SQLite WAL time-series), EventDetector (anomalies), ProcessLibrary (200+ signatures)
 └── State: Monitor (Combine & MainActor telemetry clock), SettingsAndUIState
```

Main app receives binary 64-byte `RawProcRecord` structs over XPC, polls Mach/IOKit sensors at 1.5s intervals, writes 1-minute rollup snapshots into SQLite WAL (`~/Library/Application Support/app.taskyfy.mac/taskyfy_history.sqlite`), and evaluates anomaly rules.

## Key Files

```
Package.swift                                    # SPM package definition & framework dependencies
Sources/Taskyfy/App/TaskyfyApp.swift             # @main, AppDelegate, MenuBarController, MainWindowView
Sources/TaskyfyCore/State/Monitor.swift          # Core telemetry state machine & periodic sampler loop
Sources/TaskyfyCore/Readers/CPUReader.swift      # Darwin host_processor_info Mach tick parser (P/E cores)
Sources/TaskyfyCore/Readers/SensorReader.swift   # Apple Silicon IOKit HID & SMC thermal sensor readers
Sources/TaskyfyCore/Services/HistoryStore.swift  # SQLite3 WAL time-series database & JSON/CSV exporter
Sources/TaskyfyCore/Services/HelperClient.swift  # SMAppService daemon manager & NSXPCConnection client
Sources/TaskyfyHelper/main.swift                 # Lightweight daemon, proc_pid_rusage loop, IdleExit
Tests/TaskyfyTests/main.swift                    # 5-stage test suite (Wire protocol, SQLite, Sensors, Events)
Scripts/build_app.sh                             # Generates icon, compiles release, builds & signs .app bundle
```

## Shortcuts

| Shortcut | Scope | Action |
|----------|-------|--------|
| `⌘K` | App | Open Quick Command Palette |
| `⌥⌘T` | System | Global hotkey to toggle Menu Bar Popover |
| `⌘I` | App | Toggle Process Inspector slide-over |
| `⌘R` | App | Force telemetry refresh immediately |
| `⌘,` | App | Open Settings & Appearance modal |

## Configuration

History DB: `~/Library/Application Support/app.taskyfy.mac/taskyfy_history.sqlite` (created automatically).
Helper registration uses macOS `SMAppService` (`Settings > General > Login Items`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
