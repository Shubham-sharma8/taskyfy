#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> [1/5] Generating Taskyfy Prism-Pulse AppIcon.icns..."
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET_DIR"
mkdir -p "$ROOT_DIR/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Resources/AppIcon.icns"

echo "==> [2/5] Building Taskyfy and TaskyfyHelper in release mode..."
swift build -c release --product Taskyfy
swift build -c release --product TaskyfyHelper

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/Taskyfy.app"

echo "==> [3/5] Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" \
         "$APP_BUNDLE/Contents/Resources" \
         "$APP_BUNDLE/Contents/Library/LaunchServices" \
         "$APP_BUNDLE/Contents/Library/LaunchDaemons"

cp "$BIN_DIR/Taskyfy" "$APP_BUNDLE/Contents/MacOS/Taskyfy"
cp "$BIN_DIR/TaskyfyHelper" "$APP_BUNDLE/Contents/Library/LaunchServices/TaskyfyHelper"
cp "$ROOT_DIR/Resources/LaunchDaemons/app.taskyfy.helper.plist" "$APP_BUNDLE/Contents/Library/LaunchDaemons/app.taskyfy.helper.plist"
cp "$ROOT_DIR/Sources/TaskyfyCore/Resources/processes.json" "$APP_BUNDLE/Contents/Resources/processes.json"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Taskyfy</string>
    <key>CFBundleExecutable</key>
    <string>Taskyfy</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>app.taskyfy.mac</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Taskyfy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>200</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Taskyfy Telemetry Studio</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>app.taskyfy.mac.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>taskyfy</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> [4/5] Signing TaskyfyHelper and Taskyfy.app..."
codesign --force --sign - --identifier "app.taskyfy.helper" "$APP_BUNDLE/Contents/Library/LaunchServices/TaskyfyHelper"
codesign --force --deep --sign - --identifier "app.taskyfy.mac" "$APP_BUNDLE"

echo "==> [5/5] Verifying bundle signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "==> Successfully built $APP_BUNDLE"
