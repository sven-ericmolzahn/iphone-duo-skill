#!/usr/bin/env bash
#
# audit.sh — find the code that is most likely to break on iPhone Duo.
#
# A grep, not a linter: it finds *candidates*. Every hit needs a human (or an
# agent) to read the surrounding code, because each of these patterns is
# sometimes fine. What it buys you is a ranked reading list instead of a
# read-through of the whole app.
#
# Usage: scripts/audit.sh [project-dir]        (default: current directory)
#        MAX=5 scripts/audit.sh .              (matches shown per rule, default 8)

set -uo pipefail

DIR="${1:-.}"
MAX="${MAX:-8}"
if [ ! -d "$DIR" ]; then echo "error: '$DIR' is not a directory" >&2; exit 2; fi

EXCLUDES=(--exclude-dir=.git --exclude-dir=.build --exclude-dir=build --exclude-dir=DerivedData
          --exclude-dir=Pods --exclude-dir=Carthage --exclude-dir=node_modules --exclude-dir=.swiftpm
          --exclude-dir=SourcePackages --exclude-dir=vendor)
SOURCES=(--include=*.swift --include=*.m --include=*.mm --include=*.h)

total=0

# rule <severity> <title> <why / what instead> <extended-regex>
rule() {
  local severity="$1" title="$2" why="$3" pattern="$4" hits count
  hits="$(grep -rnE "${EXCLUDES[@]}" "${SOURCES[@]}" -e "$pattern" "$DIR" 2>/dev/null | grep -vE '^\S+:[0-9]+:\s*(//|\*|///)' )"
  [ -z "$hits" ] && return
  count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  total=$((total + count))
  printf '\n[%s] %s — %s hit(s)\n' "$severity" "$title" "$count"
  printf '    why: %s\n' "$why"
  printf '%s\n' "$hits" | head -n "$MAX" | sed -E "s|^${DIR%/}/||; s/[[:space:]]{2,}/ /g; s/^/      /" | cut -c1-200
  [ "$count" -gt "$MAX" ] && printf '      … and %s more\n' "$((count - MAX))"
}

echo "iPhone Duo audit — $DIR"

rule HIGH "UIScreen.main" \
  "The device has two screens and UIScreen.main is deprecated. Use view.window?.windowScene?.screen, traitCollection.displayScale, and the container's bounds." \
  'UIScreen\.main'

rule HIGH "Layout branched on the device idiom" \
  "The inner display is regular width *on a phone*; an iPad in Split View is compact. Branch on horizontalSizeClass / the container's size." \
  'userInterfaceIdiom'

rule HIGH "Layout branched on orientation" \
  "Orientation is not size, and the inner display ignores UISupportedInterfaceOrientations. Use size classes or the container's aspect ratio." \
  'UIDevice\.current\.orientation|interfaceOrientation|\.isLandscape|\.isPortrait|UIDeviceOrientation'

rule HIGH "Hard-coded safe-area fallback" \
  "A number like 59 or 47 is one phone's status bar. On the Duo the bars can sit at the side: insets are asymmetric and pose-dependent. Fall back to 0 and measure." \
  'safeAreaInsets\.(top|bottom|left|right|leading|trailing)[[:space:]]*\?\?[[:space:]]*[1-9][0-9]*'

rule HIGH "Symmetric-inset arithmetic" \
  "With a vertical bar only one side is inset. Inset the rect (bounds.inset(by:)) instead of subtracting one inset twice." \
  '(safeAreaInsets|layoutMargins)\.(left|right|leading|trailing)[[:space:]]*\*[[:space:]]*2'

rule HIGH "First connected scene" \
  "iPhone Duo is the first iPhone with several scenes; .first is arbitrary. Prefer the view's own window scene, or the foregroundActive one." \
  'connectedScenes[^\n]*\.first|UIApplication\.shared\.windows|\.keyWindow'

rule MEDIUM "Hand-made bars" \
  "Only items in system containers (NavigationStack/.toolbar, UINavigationController, UITabBarController) move into the vertical bar. Custom UIToolbar/UINavigationBar/UITabBar content is ignored." \
  '(UIToolbar|UINavigationBar|UITabBar)\('

rule MEDIUM "System bar hidden" \
  "A hidden navigation bar usually means hand-rolled chrome at the top, which will not move to the side and may sit under the camera or Dynamic Island." \
  'navigationBarHidden\(true\)|toolbar\(\.hidden|setNavigationBarHidden\(true|isNavigationBarHidden[[:space:]]*=[[:space:]]*true'

rule MEDIUM "Fixed widths" \
  "Sizes tied to one screen. Size relative to the container; cap readable content with a maxWidth rather than fixing it." \
  '\.frame\([[:space:]]*width:[[:space:]]*[0-9]{3,}|widthAnchor\.constraint\(equalToConstant:[[:space:]]*[0-9]{3,}'

rule MEDIUM "Fixed split-view column width" \
  "With an explicit column width, NavigationSplitView stopped snapping its columns to the halves of a half-folded Duo, and the detail ran onto the fold. Leave the widths at their defaults; give narrow rows a narrow form instead." \
  'navigationSplitViewColumnWidth\('

rule MEDIUM "Fixed camera pick" \
  "iPhone Duo has an outer and an inner front camera and the usable set changes as the device opens and closes — which is not a scenePhase change. Discover devices, follow the fold, adopt RotationCoordinator." \
  'AVCaptureDevice\.default\('

rule MEDIUM "Flash mode set directly" \
  "capturePhoto throws an uncatchable exception for a mode missing from photoOutput.supportedFlashModes; no front camera has a flash. Check before setting." \
  'flashMode[[:space:]]*=[[:space:]]*\.'

rule LOW "traitCollectionDidChange" \
  "Deprecated since iOS 17. Use registerForTraitChanges — e.g. with UITraitCollection.systemTraitsAffectingVerticalBarEdge." \
  'func traitCollectionDidChange'

rule LOW "Text-only toolbar buttons" \
  "Title-only items don't present vertically. Give every item a title AND a symbol (Button(_:systemImage:), Label) and let the system choose." \
  'ToolbarItem[^\n]*\{[[:space:]]*Button\("[^"]+"\)[[:space:]]*\{'

# Project settings
settings="$(grep -rhoE "${EXCLUDES[@]}" --include=project.pbxproj --include=Info.plist \
  -e 'INFOPLIST_KEY_UIRequiresFullScreen = YES' -e '<key>UIRequiresFullScreen</key>' "$DIR" 2>/dev/null | sort -u)"
if [ -n "$settings" ]; then
  total=$((total + 1))
  printf '\n[HIGH] UIRequiresFullScreen — set\n'
  printf '    why: Every app takes part in Split View multitasking on iPhone Duo; opting out of resizing is the opposite of what this device needs.\n'
fi

target="$(grep -rhoE "${EXCLUDES[@]}" --include=project.pbxproj -e 'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+' "$DIR" 2>/dev/null | sort -u | tr '\n' ' ')"
echo
echo "----------------------------------------------------------------"
[ -n "$target" ] && echo "Deployment target(s): $target— gate the new APIs with #available(iOS 27.1, *)."
echo "$total candidate(s). Read each in context before changing it; see references/audit-checklist.md for what grep cannot see."
exit 0
