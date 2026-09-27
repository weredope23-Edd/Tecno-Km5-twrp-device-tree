#!/usr/bin/env bash
set -eo pipefail

SLICE="${1:?slice number required}"
: "${TWRP_DIR:?TWRP_DIR is required}"
: "${DEVICE_PATH:?DEVICE_PATH is required}"
: "${LUNCH_TARGET:?LUNCH_TARGET is required}"
: "${BUILD_TARGET:?BUILD_TARGET is required}"
: "${BUILD_JOBS:?BUILD_JOBS is required}"

cd "$TWRP_DIR"
export ALLOW_MISSING_DEPENDENCIES=true
export TARGET_RELEASE=bp2a
export LC_ALL=C
export TMPDIR="$TWRP_DIR/tmp"
mkdir -p "$TMPDIR" "$GITHUB_WORKSPACE/checkpoint"

source build/envsetup.sh
lunch "$LUNCH_TARGET" >/dev/null 2>&1

LOG="$GITHUB_WORKSPACE/checkpoint/slice-${SLICE}.log"
MON="$GITHUB_WORKSPACE/checkpoint/resource-${SLICE}.log"
: > "$LOG"
: > "$MON"

echo "=== slice $SLICE start $(date -u) ===" | tee -a "$LOG"
echo "target=$BUILD_TARGET jobs=$BUILD_JOBS" | tee -a "$LOG"

(
  while :; do
    echo "=== $(date -u) ===" >> "$MON"
    free -h >> "$MON" 2>&1
    df -h "$GITHUB_WORKSPACE" >> "$MON" 2>&1
    ps -eo pid,ppid,%mem,%cpu,rss,vsz,stat,comm --sort=-rss | head -25 >> "$MON" 2>&1
    echo >> "$MON"
    sleep 15
  done
) &
MONITOR_PID=$!

set +e
timeout --signal=TERM --kill-after=60s 45m mka "$BUILD_TARGET" -j"$BUILD_JOBS" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
set -e

kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true

echo "mka exit code: $RC" | tee -a "$LOG"
echo "=== slice $SLICE end $(date -u) ===" | tee -a "$LOG"

IMG="$TWRP_DIR/out/target/product/km5n/vendor_boot.img"
if [ -s "$IMG" ]; then
  echo "BUILD_COMPLETE=true" > "$GITHUB_WORKSPACE/checkpoint/status.txt"
  echo "BUILD_COMPLETE=true" >> "$GITHUB_ENV"
  exit 0
fi

if [ "$RC" -eq 124 ]; then
  echo "CHECKPOINT: slice $SLICE reached 45 minutes; existing outputs are retained for the next slice." | tee -a "$LOG"
  echo "BUILD_COMPLETE=false" > "$GITHUB_WORKSPACE/checkpoint/status.txt"
  exit 0
fi

echo "BUILD_COMPLETE=false" > "$GITHUB_WORKSPACE/checkpoint/status.txt"
exit "$RC"
