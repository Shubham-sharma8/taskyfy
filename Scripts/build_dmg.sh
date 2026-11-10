#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="Taskyfy"
APP_BUNDLE="${ROOT_DIR}/${APP_NAME}.app"
BG_PNG="${ROOT_DIR}/00-dmg-background.png"
DMG_FINAL="${ROOT_DIR}/${APP_NAME}.dmg"
DMG_RW="${ROOT_DIR}/.build/${APP_NAME}-rw.dmg"
STAGING_DIR="${ROOT_DIR}/.build/dmg-staging"
VOL_NAME="${APP_NAME}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: ${APP_BUNDLE} not found." >&2
  exit 1
fi

if [[ ! -f "$BG_PNG" ]]; then
  echo "Error: ${BG_PNG} not found." >&2
  exit 1
fi

echo "==> Verifying existing signature on ${APP_NAME}.app..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Ensure any previous mount of Taskyfy is detached
if [[ -d "/Volumes/${VOL_NAME}" ]]; then
  hdiutil detach "/Volumes/${VOL_NAME}" -force >/dev/null 2>&1 || true
fi

rm -rf "$STAGING_DIR" "$DMG_RW" "$DMG_FINAL"
mkdir -p "$STAGING_DIR/.background"

echo "==> Copying signed ${APP_NAME}.app with ditto (preserving signature & stapled ticket)..."
ditto "$APP_BUNDLE" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Building Retina multi-resolution background.tiff (600x400 @1x + 1200x800 @2x)..."
BG_1X="${ROOT_DIR}/.build/bg_1x.png"
BG_2X="${ROOT_DIR}/.build/bg_2x.png"
cp "$BG_PNG" "$BG_2X"
sips -s dpiWidth 144 -s dpiHeight 144 "$BG_2X" >/dev/null
sips -z 400 600 -s dpiWidth 72 -s dpiHeight 72 "$BG_PNG" --out "$BG_1X" >/dev/null
tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$STAGING_DIR/.background/background.tiff" >/dev/null
rm -f "$BG_1X" "$BG_2X"

# Optional volume icon from app bundle
if [[ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
  cp "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
  SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
fi

echo "==> Creating read-write disk image..."
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$DMG_RW" >/dev/null

echo "==> Mounting read-write disk image for Finder layout customization..."
MOUNT_DIR="/Volumes/${VOL_NAME}"
hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW" >/dev/null

# Mark volume as having a custom icon if present
if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
  SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true

echo "==> Applying Finder window geometry & icon positions (600x400)..."
osascript <<EOF
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 548}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 116
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file ".background:background.tiff"
    set position of item "${APP_NAME}.app" of container window to {165, 178}
    set position of item "Applications" of container window to {435, 178}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
sleep 1

echo "==> Detaching read-write disk image..."
hdiutil detach "$MOUNT_DIR" -force >/dev/null

echo "==> Converting to compressed read-only UDZO DMG: ${DMG_FINAL}..."
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_FINAL" >/dev/null
rm -rf "$DMG_RW" "$STAGING_DIR"

echo "==> Done! Created ${DMG_FINAL} ($(du -h "$DMG_FINAL" | awk '{print $1}'))"
