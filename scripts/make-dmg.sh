#!/usr/bin/env bash
# Builds a styled Panels.dmg from a built Panels.app.
# Usage: scripts/make-dmg.sh path/to/Panels.app [output.dmg]
# Optional: DMG_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" signs the finished image.
# The window layout comes from scripts/dmg/DS_Store (a saved Finder layout), so no Finder scripting is needed (CI).
# DMG_FINDER_LAYOUT=1 lays the window out with Finder instead and saves the result as the new template.
# Without the template, Finder scripting is tried; if that fails the DMG is built without a layout.
set -eu

APP="${1:?Usage: scripts/make-dmg.sh path/to/Panels.app [output.dmg]}"
OUT="${2:-Panels.dmg}"
HERE="$(cd "$(dirname "$0")" && pwd)"
VOL="Panels"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/panels-dmg.XXXXXX")"
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"

mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Panels.app"
ln -s /Applications "$STAGE/Applications"
TEMPLATE="$HERE/dmg/DS_Store"
USE_TEMPLATE=0
if [ -f "$TEMPLATE" ] && [ "${DMG_FINDER_LAYOUT:-0}" != 1 ]; then
  cp "$TEMPLATE" "$STAGE/.DS_Store"
  USE_TEMPLATE=1
fi

# one TIFF that carries both the 1x and 2x backgrounds, so it is sharp on Retina screens
tiffutil -cathidpicheck "$HERE/dmg/background.png" "$HERE/dmg/background@2x.png" -out "$STAGE/.background/background.tiff" >/dev/null

# volume icon from the app icon
ICONSET="$WORK/Volume.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$HERE/dmg/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$HERE/dmg/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns"

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
hdiutil create -quiet -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT="/Volumes/$VOL"

if command -v SetFile >/dev/null 2>&1; then SetFile -a C "$MOUNT" || true; fi

# window layout (only without the template): 660 by 400 content, app on the left, Applications on the right, background behind
if [ "$USE_TEMPLATE" = 1 ]; then
  echo "using saved window layout"
elif ! timeout 90 osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Panels.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  echo "warning: Finder scripting failed, building the DMG without a custom layout" >&2
elif [ "${DMG_FINDER_LAYOUT:-0}" = 1 ]; then
  sync; sleep 1
  cp "$MOUNT/.DS_Store" "$TEMPLATE" && echo "saved window layout to $TEMPLATE"
fi

sync
hdiutil detach -quiet "$DEVICE" || { sleep 3; hdiutil detach -quiet -force "$DEVICE"; }
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"

if [ -n "${DMG_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$DMG_SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
