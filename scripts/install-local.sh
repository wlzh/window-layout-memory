#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/dist/Window Layout Memory.app"
TARGET="/Applications/Window Layout Memory.app"
test -d "$SOURCE"
codesign --verify --deep --strict "$SOURCE"
if pgrep -x WindowLayoutMemory >/dev/null; then
    echo 'Quit Window Layout Memory before installing. No files changed.' >&2
    exit 1
fi
if [[ -e "$TARGET" ]]; then
    BACKUP="$HOME/Library/Application Support/WindowLayoutMemory-app-backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP"
    ditto "$TARGET" "$BACKUP/Window Layout Memory.app"
fi
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET/Contents/Info.plist"
echo "INSTALLED=$TARGET"
echo 'User layout data was not modified. Accessibility permission is user-controlled.'
