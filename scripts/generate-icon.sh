#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/icon-tool
swiftc Sources/WindowLayoutMemory/BrandIcon.swift scripts/icon-tool/main.swift -o .build/icon-tool/icon-tool
.build/icon-tool/icon-tool generate .build/icon-tool/AppIcon.iconset
iconutil -c icns .build/icon-tool/AppIcon.iconset -o Resources/AppIcon.icns
echo 'ICON_GENERATION=PASS'
