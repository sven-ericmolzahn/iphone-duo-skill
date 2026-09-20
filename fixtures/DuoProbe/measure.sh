#!/usr/bin/env bash
#
# measure.sh — run every layout strategy in the CURRENT pose and print what was
# measured. The pose itself has to be set in Device Hub: simctl has no fold,
# pose or hinge subcommand (checked against Xcode 27.1).
#
# Usage: ./measure.sh <pose-label> [udid]
#
set -uo pipefail
POSE="${1:-unlabelled}"
DEVICE="${2:-}"
BUNDLE=dev.local.DuoProbe

if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun simctl list devices booted 2>/dev/null | grep -i "iPhone Duo" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
fi
[ -z "$DEVICE" ] && { echo "error: no booted 'iPhone Duo' simulator. Boot one, then retry." >&2; exit 2; }

for s in A B C D E F G H I J; do
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl launch "$DEVICE" "$BUNDLE" -strategy $s >/dev/null 2>&1 || {
    echo "error: $BUNDLE is not installed on $DEVICE — build and install it first." >&2; exit 2; }
  sleep 2.2
done

echo "######## POSE: $POSE   device: $DEVICE"
xcrun simctl spawn "$DEVICE" log show --last 60s --style compact \
  --predicate 'subsystem == "dev.local.DuoProbe"' 2>&1 \
  | grep -E "strategy=|size=|hinge=|displayCheck" \
  | sed 's/.*dev\.local\.DuoProbe:[a-zA-Z]*\] //' | awk '!seen[$0]++'
