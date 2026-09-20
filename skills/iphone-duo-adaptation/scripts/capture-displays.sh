#!/usr/bin/env bash
#
# capture-displays.sh — screenshot BOTH displays of an iPhone Duo simulator.
#
# `simctl io <device> screenshot` with no --display grabs one display, and on a
# folded or unfolded Duo it is often the one that is switched off — a solid
# black image that looks like a crashed app. This captures every integrated
# display by id and tells you which one is live.
#
# Usage: scripts/capture-displays.sh [udid|booted] [out-dir]
#        (defaults: the booted 'iPhone Duo', ./duo-captures)

set -uo pipefail

DEVICE="${1:-}"
OUT="${2:-./duo-captures}"

if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun simctl list devices booted 2>/dev/null | grep -i "iPhone Duo" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  [ -z "$DEVICE" ] && DEVICE="booted"
fi

enumerate="$(xcrun simctl io "$DEVICE" enumerate 2>/dev/null)" || { echo "error: no such booted simulator: $DEVICE" >&2; exit 2; }

# Integrated screens only (the list also has CarPlay, TV-out and scene screens).
ids="$(printf '%s\n' "$enumerate" | awk '/Screen ID:/ {id=$3} /Screen Type: Integrated/ {print id}')"
if [ -z "$ids" ]; then echo "error: no integrated displays reported for $DEVICE" >&2; exit 2; fi

mkdir -p "$OUT"
stamp="$(date +%H%M%S)"
echo "device: $DEVICE"

for id in $ids; do
  file="$OUT/display-$id-$stamp.png"
  if ! xcrun simctl io "$DEVICE" screenshot --type=png --display="$id" "$file" >/dev/null 2>&1; then
    echo "  display $id: capture failed"; continue
  fi
  w="$(sips -g pixelWidth  "$file" 2>/dev/null | awk '/pixelWidth/  {print $2}')"
  h="$(sips -g pixelHeight "$file" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
  kb="$(( $(wc -c < "$file") / 1024 ))"
  # A switched-off display is solid black and compresses to almost nothing.
  if [ "$kb" -lt 60 ]; then state="OFF (blank image)"; else state="live"; fi
  long=$(( w > h ? w : h ))
  # iPhone Duo: the inner display's long edge is 2853 px, the outer's 2034 px.
  if [ "$long" -ge 2500 ]; then which="inner"; else which="outer"; fi
  printf '  display %s: %-5s %4sx%-4s px = %sx%s pt @3x  %-18s %s\n' \
    "$id" "$which" "$w" "$h" "$((w / 3))" "$((h / 3))" "$state" "$file"
done

echo
echo "Screenshot coordinates are pixels; divide by 3 for points. If you are reading a"
echo "downscaled copy of the image, undo that scale too — or log real values with"
echo "assets/DuoLayoutProbe.swift instead of measuring pictures."
exit 0
