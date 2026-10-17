#!/usr/bin/env bash
# Runs the headless self test against a built Panels.app and fails on any FAIL line.
# Usage: scripts/selftest.sh [path/to/Panels.app]   (default: Debug build in ./build)
set -u
APP="${1:-build/Build/Products/Debug/Panels.app}"
DATA="$(mktemp -d)"
LOG="$(mktemp)"
trap 'rm -rf "$DATA"' EXIT

PANELS_SELFTEST=1 PANELS_DATA_DIR="$DATA" PANELS_TIMER_SPEED=60 PANELS_SELFTEST_LOG="$LOG" \
  "$APP/Contents/MacOS/Panels" &
PID=$!

# Give the run 5 minutes, then kill it.
for _ in $(seq 1 300); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "self test timed out"; kill "$PID" 2>/dev/null; cat "$LOG"; exit 1
fi

cat "$LOG"
if grep -q '^FAIL' "$LOG"; then echo "self test: FAILURES"; exit 1; fi
if ! tail -n 1 "$LOG" | grep -q 'ALL PASSED'; then echo "self test: did not finish"; exit 1; fi
echo "self test: ok"
