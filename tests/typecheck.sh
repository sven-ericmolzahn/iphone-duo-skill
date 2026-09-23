#!/usr/bin/env bash
# Type-checks every code sample the skill ships against the installed iOS
# simulator SDK. Run it after each new Xcode seed: these are beta APIs, and a
# rename shows up here before it shows up in anybody's app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)"; then
  echo "error: no iOS simulator SDK — install Xcode and run 'xcode-select -s'." >&2
  exit 2
fi
echo "SDK: $SDK"
xcodebuild -version 2>/dev/null | tr '\n' ' '; echo

status=0
check() { # <file> <min-iOS> [extra swiftc flags…]
  local file="$1" min="$2"; shift 2
  printf '%-64s ' "${file#"$ROOT"/} (iOS $min)"
  if out="$(swiftc -typecheck -sdk "$SDK" -target "arm64-apple-ios${min}-simulator" "$@" "$file" 2>&1)"; then
    if grep -q "warning:" <<<"$out"; then echo "ok, with warnings"; grep "warning:" <<<"$out" | sed 's/^/    /'; else echo "ok"; fi
  else
    echo "FAILED"; sed 's/^/    /' <<<"$out"; status=1
  fi
}

check "$ROOT/tests/Samples.swift" 26.0
check "$ROOT/tests/SamplesUIKit.swift" 26.0
# The probe has to build in apps that deploy far further back than the Duo,
# and next to the app's own types (tests/AppTypes.swift: a `Logger`).
check "$ROOT/skills/iphone-duo-adaptation/assets/DuoLayoutProbe.swift" 17.0 -D DEBUG "$ROOT/tests/AppTypes.swift"

# Again with MainActor as the default isolation — what new Xcode project
# templates use (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor). Code that compiles
# on its own can still fail there: a plain struct's Equatable conformance
# becomes main-actor-isolated and no longer satisfies a Sendable requirement.
echo "-- default isolation: MainActor"
check "$ROOT/tests/Samples.swift" 26.0 -default-isolation MainActor
check "$ROOT/tests/SamplesUIKit.swift" 26.0 -default-isolation MainActor
check "$ROOT/skills/iphone-duo-adaptation/assets/DuoLayoutProbe.swift" 17.0 -D DEBUG -default-isolation MainActor "$ROOT/tests/AppTypes.swift"

exit $status
