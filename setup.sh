#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Taskyfy — One-Command macOS Bootstrap & Setup Script
# ==============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "======================================================"
echo "         Taskyfy macOS Telemetry Studio Setup         "
echo "======================================================"
echo ""

# 1. Platform Check
echo "==> [1/5] Checking macOS host environment..."
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Error: Taskyfy requires macOS (Darwin). Current OS: $(uname -s)"
    exit 1
fi

MACOS_VERSION="$(sw_vers -productVersion | cut -d. -f1)"
if (( MACOS_VERSION < 14 )); then
    echo "⚠️  Warning: Taskyfy targets macOS 14.0 (Sonoma) or newer."
    echo "   Detected macOS version: $(sw_vers -productVersion)"
else
    echo "  ✓ macOS $(sw_vers -productVersion) detected (compatible)"
fi

# 2. Toolchain Prerequisites
echo "==> [2/5] Checking build toolchain..."
command -v swift >/dev/null 2>&1 || {
    echo "❌ Error: 'swift' toolchain not found."
    echo "   Please install Xcode or Xcode Command Line Tools via:"
    echo "   xcode-select --install"
    exit 1
}

SWIFT_VERSION="$(swift --version | head -n 1)"
echo "  ✓ Swift compiler: $SWIFT_VERSION"

command -v iconutil >/dev/null 2>&1 || {
    echo "⚠️  'iconutil' not found in PATH (needed for .icns generation during .app builds)"
}

# 3. Compile Package Targets
echo "==> [3/5] Building Taskyfy Core, Studio, and Helper targets..."
swift build

# 4. Run Test Suite
echo "==> [4/5] Running Taskyfy telemetry test suite..."
swift run TaskyfyTests

# 5. Build Standalone Application Bundle
echo "==> [5/5] Assembling signed Taskyfy.app bundle..."
if [[ -f "$ROOT_DIR/Scripts/build_app.sh" ]]; then
    bash "$ROOT_DIR/Scripts/build_app.sh"
fi

echo ""
echo "======================================================"
echo "  ✓ Setup completed successfully!                      "
echo "======================================================"
echo ""
echo "Next steps:"
echo "  1. Run CLI Studio:        swift run Taskyfy"
echo "  2. Run Tests:             swift run TaskyfyTests"
echo "  3. Launch Desktop App:    open Taskyfy.app"
echo "  4. Install into /Apps:    cp -R Taskyfy.app /Applications/"
echo ""
echo "Using Claude Code? CLAUDE.md has full project context & shortcuts."
