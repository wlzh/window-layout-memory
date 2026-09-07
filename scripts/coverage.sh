#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist/coverage
swift build --scratch-path .build/coverage --product CoreTests -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping
BIN="$(swift build --scratch-path .build/coverage --show-bin-path)/CoreTests"
LLVM_PROFILE_FILE="$PWD/dist/coverage/core.profraw" "$BIN"
xcrun llvm-profdata merge -sparse dist/coverage/core.profraw -o dist/coverage/core.profdata
xcrun llvm-cov report "$BIN" -instr-profile=dist/coverage/core.profdata Sources/LayoutCore/Core.swift | tee dist/coverage/report.txt
awk '$1 == "TOTAL" { gsub(/%/, "", $10); found=1; if ($10+0 < 90) exit 1 } END { if (!found) exit 1 }' dist/coverage/report.txt
echo 'Coverage denominator: LayoutCore only. AppKit, AX, Engine and UI are NOT included.'
