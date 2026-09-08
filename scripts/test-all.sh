#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift run CoreTests
swift build --product WindowLayoutMemory
swift run WindowLayoutMemory --self-test-engine
swift run WindowLayoutMemory --self-test-preview
swift run WindowLayoutMemory --self-test-about
git diff --check
plutil -lint Resources/Info.plist
test "$(tr -d '[:space:]' < VERSION)" = "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
test "$(tr -d '[:space:]' < BUILD_NUMBER)" = "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)"
test "$(tr -d '[:space:]' < RELEASE_CHANNEL)" = "$(/usr/libexec/PlistBuddy -c 'Print WLMReleaseChannel' Resources/Info.plist)"
echo 'BUILD_AND_METADATA=PASS; HARDWARE_AND_PERFORMANCE=NOT_RUN'
