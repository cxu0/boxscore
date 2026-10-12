#!/bin/zsh
# Build, test, install, and launch Boxscore on the iPhone 17 simulator, then
# screenshot it. Usage: scripts/verify.sh [screenshot-path]
# Exits non-zero (with the errors) if the build or any test fails.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=246AC1A1-B10E-446E-8B3E-53E8EBEA687E
SHOT=${1:-${TMPDIR:-/tmp}/boxscore-shot.png}
cd "$(dirname "$0")/.."

echo "== Build + test"
LOG=$(mktemp)
if ! xcodebuild test -project Boxscore.xcodeproj -scheme Boxscore -destination "id=$SIM" >"$LOG" 2>&1; then
  grep -E "error:|recorded an issue|failed on|TEST FAILED|BUILD FAILED" "$LOG" | head -40
  exit 1
fi
echo "$(grep -c "Test case .* passed" "$LOG") tests passed"

echo "== Install + launch"
xcrun simctl bootstatus $SIM -b >/dev/null
open -a Simulator
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Boxscore-*/Build/Products/Debug-iphonesimulator/Boxscore.app | head -1)
xcrun simctl install $SIM "$APP"
xcrun simctl terminate $SIM cooper.Boxscore 2>/dev/null || true
xcrun simctl launch $SIM cooper.Boxscore >/dev/null
sleep 6
xcrun simctl io $SIM screenshot "$SHOT" >/dev/null 2>&1
echo "Screenshot: $SHOT"
