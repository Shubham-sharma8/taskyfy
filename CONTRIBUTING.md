# Contributing to Taskyfy

Thank you for your interest in contributing to **Taskyfy**! Whether you are fixing a bug, adding sensor support for newer Apple Silicon revisions, optimizing the SQLite time-series engine, or improving UI animations, your contributions are welcome.

---

## Code of Conduct

We are committed to providing a friendly, safe, and welcoming environment for all contributors, regardless of experience level, background, or identity. Please be respectful and constructive in all discussions, issues, and pull requests.

---

## Getting Started

### Prerequisites

- **macOS Sonoma (14.0)** or later.
- **Xcode 15+** or **Xcode Command Line Tools** (`xcode-select --install`).
- **Swift 5.10+**.

### One-Command Setup

Bootstrap your local development workspace with:

```bash
./setup.sh
```

This script validates your macOS version, verifies compiler tools, compiles all targets in debug mode, runs the test suite, and builds `Taskyfy.app`.

### Manual Build & Test Commands

You can also use standard Swift Package Manager commands:

```bash
# Build all targets (debug)
swift build

# Build release binaries
swift build -c release

# Run the 5-stage architecture and telemetry test suite
swift run TaskyfyTests

# Run the studio app directly from terminal
swift run Taskyfy

# Package the standalone .app bundle
bash Scripts/build_app.sh
```

---

## Architectural Principles & Invariants

When writing code for Taskyfy, adhere to the following core invariants:

1. **Strict Immutability & Thread Safety**:
   - Telemetry models (`CPUSample`, `MemoryStats`, `AppGroup`, `ThermalStats`, `SystemEvent`) are immutable `Sendable` structs.
   - Do not pass mutable reference objects across concurrency boundaries.
   - Background telemetry polling must never block the `@MainActor`. UI updates flow strictly through the `@Bindable` `Monitor` state machine.

2. **Darwin / Mach Kernel Resource Hygiene**:
   - When calling Mach APIs (such as `host_processor_info`), deallocate returned kernel buffers using `vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), byteCount)` inside a `defer` block.
   - Guard against zero or negative PID returns.

3. **64-Byte Wire Protocol Invariant**:
   - `TaskyfyHelper` communicates with `Taskyfy` via an unbuffered 64-byte binary wire struct (`RawProcRecord`).
   - `MemoryLayout<RawProcRecord>.stride` must remain exactly 64 bytes. If extending the protocol, update versioning and ensure zero regressions across both processes.

4. **Non-blocking SQLite WAL Rollups**:
   - All historical metrics are written to SQLite using Write-Ahead Logging (`PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;`).
   - Use parameterized SQL queries for all inserts and selects.

5. **Power & Battery Efficiency**:
   - `TaskyfyHelper` implements `IdleExit` (120-second timeout). It must automatically exit when the main app closes, consuming 0% idle CPU and zero background battery.

---

## Development & PR Workflow

1. **Fork the Repository** on GitHub.
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feat/apple-silicon-m4-sensors
   ```
3. **Implement Your Changes**:
   - Follow existing code patterns and naming conventions.
   - Do not commit generated build artifacts or temporary files (`.build/`, `*.app`, `DerivedData/`).
4. **Run the Test Suite**:
   ```bash
   swift run TaskyfyTests
   ```
   All 41+ assertions must pass without warnings or failures.
5. **Commit with Conventional Commits**:
   - `feat: add GPU core frequency reader for M-series chips`
   - `fix: prevent swap calculation integer overflow on 128GB unified memory`
   - `perf: vectorize process name lookups in ProcessLibrary`
   - `docs: update keyboard shortcut table in README`
6. **Open a Pull Request**:
   - Describe the changes clearly, including any relevant hardware configurations (e.g., M1 Max, M2 Pro, M3 Max, Intel Core i9).
   - Link any related issue numbers.

---

## Using Claude Code & AI Assistants

This repository contains dedicated agent instructions:
- `CLAUDE.md`: Brief command reference and architecture summary for Claude Code.
- `AGENTS.md`: In-depth guide to Swift 5.10 concurrency, Darwin Mach pointers, and wire protocol invariants for autonomous agents.

When using Claude Code:
```bash
claude
```
Claude Code automatically reads `CLAUDE.md` to run tests, compile builds, and verify code hygiene.

---

## License

By contributing to Taskyfy, you agree that your contributions will be licensed under the project's [MIT License](LICENSE).
