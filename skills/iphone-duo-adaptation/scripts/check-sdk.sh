#!/usr/bin/env bash
#
# check-sdk.sh — what does the installed iOS SDK *actually* ship for iPhone Duo?
#
# The Duo APIs are new and were still in beta when this skill was written.
# Blog posts, video summaries and even documentation prose disagree with the
# SDK in places, and a wrong spelling costs a build cycle. This asks the SDK.
#
# The non-obvious part it encodes: SwiftUI's layout APIs (ArrangementView,
# reservedRegions, onHingeChange …) are declared in **SwiftUICore**, not in
# SwiftUI. `import SwiftUI` re-exports them, but grepping only
# SwiftUI.swiftinterface makes them look missing.
#
# Usage: scripts/check-sdk.sh            (informational; always exits 0 unless
#                                         no SDK can be found)

set -uo pipefail

if ! SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)"; then
  echo "error: no iOS simulator SDK found. Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app" >&2
  exit 2
fi
FW="$SDK/System/Library/Frameworks"

first() { ls "$@" 2>/dev/null | head -1; }
SWIFTUI="$(first "$FW"/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64*-simulator.swiftinterface)"
CORE="$(first "$FW"/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64*-simulator.swiftinterface)"
UIKIT_IF="$(first "$FW"/UIKit.framework/Modules/UIKit.swiftmodule/arm64*-simulator.swiftinterface)"
UIKIT_H="$FW/UIKit.framework/Headers"
AVF_H="$FW/AVFoundation.framework/Headers"

echo "Xcode : $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo "SDK   : $SDK"
echo

present=0; missing=0

# row <label> <extended-regex>   — reports every place the pattern is found
row() {
  local label="$1" pattern="$2" where=""
  [ -n "$SWIFTUI" ]  && grep -Eq "$pattern" "$SWIFTUI"  2>/dev/null && where="$where SwiftUI"
  [ -n "$CORE" ]     && grep -Eq "$pattern" "$CORE"     2>/dev/null && where="$where SwiftUICore"
  [ -n "$UIKIT_IF" ] && grep -Eq "$pattern" "$UIKIT_IF" 2>/dev/null && where="$where UIKit(swift)"
  [ -d "$UIKIT_H" ]  && grep -rEq "$pattern" "$UIKIT_H" 2>/dev/null && where="$where UIKit(headers)"
  [ -d "$AVF_H" ]    && grep -rEq "$pattern" "$AVF_H"   2>/dev/null && where="$where AVFoundation"
  if [ -n "$where" ]; then
    printf '  ✓ %-44s%s\n' "$label" "$where"; present=$((present + 1))
  else
    printf '  ✗ %-44s MISSING from this SDK\n' "$label"; missing=$((missing + 1))
  fi
}

echo "SwiftUI — layout"
row "ArrangementView"                         "struct ArrangementView<"
row "arrangementViewStyle(_:)"                "func arrangementViewStyle\("
row ".split / .overlay styles"                "struct (Split|Overlay)ArrangementViewStyle"
row "splitArrangementLayoutSize(...)"           "func splitArrangementLayoutSize\("
row "splitArrangementLayoutRatio(...)"          "func splitArrangementLayoutRatio\("
row "splitArrangementFixedLayoutSize(...)"      "func splitArrangementFixedLayoutSize\("
row "overlayArrangementEdge(_:)"              "func overlayArrangementEdge\("
row "\\.overlayArrangementZIndex (env)"       "var overlayArrangementZIndex"
row "\\.splitArrangementAxis (env)"           "var splitArrangementAxis"
row "ReservedRegion"                          "struct ReservedRegion "
row "GeometryProxy.reservedRegions(kind:...)"   "func reservedRegions\(kind:"
row "onHingeChange(isEnabled:_:)"             "func onHingeChange\("
row "DeviceHinge / DeviceHingeContext"        "struct DeviceHingeContext"
echo
echo "SwiftUI — bars, tabs, sheets"
row "axisBehavior(_:)"                        "func axisBehavior\("
row "toolbarVerticalBehavior(_:)"             "func toolbarVerticalBehavior\("
row "toolbarVerticalCompressionBehavior(_:)"  "func toolbarVerticalCompressionBehavior\("
row "visibilityPriority(_:)"                  "func visibilityPriority\("
row "ToolbarOverflowMenu"                     "struct ToolbarOverflowMenu<"
row "\\.toolbarVerticalEdge (env)"            "var toolbarVerticalEdge"
row "defaultTabBarPlacement(_:)"              "func defaultTabBarPlacement\("
row "presentationPlacement(_:)"               "func presentationPlacement\("
row "backgroundExtensionEffect()"             "func backgroundExtensionEffect\("
row "sceneAccessory { }"                      "func sceneAccessory<"
row "CameraCaptureAccessory"                  "struct CameraCaptureAccessory<"
echo
echo "UIKit"
row "UIArrangementViewController"             "@interface UIArrangementViewController"
row "UISplitArrangement / UIOverlayArrangement" "@interface UI(Split|Overlay)Arrangement "
row "UIView.reservedRegions(kind:options:)"   "reservedRegionsOfKind:|func reservedRegions\(kind:"
row "UIHinge / UIHingeInteraction"            "@interface UIHingeInteraction"
row "UIBarButtonItem.axisBehavior"            "UIBarButtonItemAxisBehavior axisBehavior"
row "UIBarButtonItem.visibilityPriority"      "UIBarButtonItemVisibilityPriority visibilityPriority"
row "preferredVerticalBarBehavior"            "preferredVerticalBarBehavior"
row "verticalBarCompressionBehavior"          "verticalBarCompressionBehavior"
row "UITraitCollection.verticalBarEdge"       "UIVerticalBarEdge verticalBarEdge"
row "UIBackgroundExtensionView"               "@interface UIBackgroundExtensionView"
row "UISceneAccessory.cameraCapture"          "cameraCaptureSceneAccessoryWithConfiguration"
echo
echo "AVFoundation"
row ".builtInOuterUltraWideCamera"            "AVCaptureDeviceTypeBuiltInOuterUltraWideCamera"
row ".builtInInnerUltraWideCamera"            "AVCaptureDeviceTypeBuiltInInnerUltraWideCamera"
row "dynamicAspectRatio"                      "dynamicAspectRatio"
row "AVCaptureDevice.RotationCoordinator"     "@interface AVCaptureDeviceRotationCoordinator"
row "AVCaptureDeviceDirectionCoordinator"     "AVCaptureDeviceDirectionCoordinator"
row "AVCaptureDeviceDescriptor"               "AVCaptureDeviceDescriptor"
echo
echo "$present present, $missing missing."
[ "$missing" -gt 0 ] && echo "Missing APIs were announced but are not in this SDK build — don't write code against them; re-run after the next Xcode update."

echo
echo "Simulator"
if xcrun simctl list devicetypes 2>/dev/null | grep -qi "iPhone Duo"; then
  echo "  ✓ 'iPhone Duo' device type available"
  xcrun simctl list devices 2>/dev/null | grep -i "iPhone Duo" | sed 's/^ */    /'
else
  echo "  ✗ no 'iPhone Duo' device type — it ships with the iOS 27.1 simulator runtime (Xcode 27.1+)."
fi
exit 0
