#!/bin/bash
#
# stress.sh — concurrency stress for radar board locking
# Spawns N parallel 'radar set' with distinct names against a temp board.
# Fails unless exactly N items survive (tests sidecar lock prevents lost updates).
#
# Usage: ./scripts/stress.sh [N=60]
# Requires: swift build available; runs against .build/debug/radar

set -euo pipefail

N=${1:-60}
BOARD=$(mktemp -t "radar-stress-$$-XXXXXX.json")
LOCK="$BOARD.lock"

cleanup() {
    rm -f "$BOARD" "$LOCK" 2>/dev/null || true
    # also remove any stray corrupt from this run (shouldn't be any)
    rm -f "${BOARD}.corrupt-"* 2>/dev/null || true
}
trap cleanup EXIT

export RADAR_BOARD_PATH="$BOARD"

echo "Building radar..."
swift build --product radar >/dev/null

RADAR_BIN=".build/debug/radar"

echo "Running stress: $N parallel sets against $BOARD ..."

pids=()
for i in $(seq 1 "$N"); do
    "$RADAR_BIN" set "task-$i" --type note --status active --summary "parallel-$i" >/dev/null 2>&1 &
    pids+=($!)
done

# Wait for all
for pid in "${pids[@]}"; do
    wait "$pid" || true
done

# Count items via board (JSON)
COUNT=$( "$RADAR_BIN" board | python3 -c '
import sys, json, sys
try:
    data = json.load(sys.stdin)
    print(len(data) if isinstance(data, list) else 0)
except Exception:
    print(0)
' )

echo "Result: $COUNT items (expected $N)"

if [ "$COUNT" -ne "$N" ]; then
    echo "FAIL: lost updates (got $COUNT/$N). Check locking."
    # Dump for debug
    echo "Board contents head:"
    head -c 500 "$BOARD" || true
    exit 1
fi

echo "PASS: $N/$N items survived concurrent sets."
exit 0
