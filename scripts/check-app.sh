#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/Window Layout Memory.app}"
NAME="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$APP/Contents/Info.plist")"
test "$NAME" = AppIcon.icns
test -s "$APP/Contents/Resources/$NAME"
cmp Resources/AppIcon.icns "$APP/Contents/Resources/$NAME"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
iconutil -c iconset "$APP/Contents/Resources/$NAME" -o "$TEMP/AppIcon.iconset"
.build/icon-tool/icon-tool check "$TEMP/AppIcon.iconset"
codesign --verify --deep --strict "$APP"
echo 'APP_ICON_AND_SIGNATURE=PASS'
