#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/coverage
swift build --scratch-path .build/engine-coverage --product WindowLayoutMemory -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping
BIN="$(swift build --scratch-path .build/engine-coverage --show-bin-path)/WindowLayoutMemory"
LLVM_PROFILE_FILE="$PWD/dist/coverage/engine.profraw" "$BIN" --self-test-engine
xcrun llvm-profdata merge -sparse dist/coverage/engine.profraw -o dist/coverage/engine.profdata
xcrun llvm-cov report "$BIN" -instr-profile=dist/coverage/engine.profdata Sources/WindowLayoutMemory/Engine.swift | tee dist/coverage/engine-report.txt
echo 'Engine coverage uses injected window services. Real AX adapter, AppKit UI and hardware are not covered.'
