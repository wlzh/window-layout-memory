#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
zsh scripts/generate-icon.sh
swift build -c release --product WindowLayoutMemory
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Window Layout Memory.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WindowLayoutMemory" "$APP/Contents/MacOS/WindowLayoutMemory"
strip -S "$APP/Contents/MacOS/WindowLayoutMemory"
if rg -a -q '/Users/|/home/' "$APP/Contents/MacOS/WindowLayoutMemory"; then
    echo 'Release binary contains a local user path' >&2
    exit 1
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier uk.869hr.WindowLayoutMemory "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
zsh scripts/check-app.sh "$APP"
zsh scripts/test-icon-check.sh "$APP"
echo "APP=$APP"
