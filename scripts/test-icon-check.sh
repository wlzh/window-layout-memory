#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-$PWD/dist/Window Layout Memory.app}"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
APP="$TEMP/Fixture.app"
ditto "$SOURCE" "$APP"
zsh scripts/check-app.sh "$APP" > "$TEMP/check.log" 2>&1
mv "$APP/Contents/Resources/AppIcon.icns" "$TEMP/icon.icns"
codesign --force --sign - "$APP" 2>/dev/null
if zsh scripts/check-app.sh "$APP" > "$TEMP/check.log" 2>&1; then
    echo 'FAIL: missing icon accepted' >&2
    exit 1
fi
mv "$TEMP/icon.icns" "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Set CFBundleIconFile Missing.icns' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null
if zsh scripts/check-app.sh "$APP" > "$TEMP/check.log" 2>&1; then
    echo 'FAIL: wrong icon reference accepted' >&2
    exit 1
fi
echo 'ICON_PACKAGE_TESTS passed=3 failed=0'
