#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
zsh scripts/test-all.sh
zsh scripts/build-app.sh
VERSION="$(tr -d '[:space:]' < VERSION)"
CHANNEL="$(tr -d '[:space:]' < RELEASE_CHANNEL)"
ARCH="$(uname -m)"
mkdir -p dist/release
ARCHIVE="WindowLayoutMemory-v${VERSION}-${CHANNEL}-macos-${ARCH}.zip"
ditto -c -k --keepParent "dist/Window Layout Memory.app" "dist/release/$ARCHIVE"
cd dist/release
shasum -a 256 "$ARCHIVE" > SHA256.txt
shasum -a 256 -c SHA256.txt
unzip -t "$ARCHIVE"
