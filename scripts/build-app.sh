#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release --product WindowLayoutMemory
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Window Layout Memory.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WindowLayoutMemory" "$APP/Contents/MacOS/WindowLayoutMemory"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
codesign --force --sign - --identifier uk.869hr.WindowLayoutMemory "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "APP=$APP"
