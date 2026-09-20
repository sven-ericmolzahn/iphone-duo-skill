# DuoProbe — a fixture for checking this skill against the SDK

A minimal SwiftUI app whose only job is to make layout claims falsifiable. Each
strategy is one way of deciding what container to use; you pick one without
tapping, so a pose can be measured unattended.

```bash
xcodegen generate
xcodebuild -project DuoProbe.xcodeproj -scheme DuoProbe -configuration Debug \
  -destination 'platform=iOS Simulator,id=<duo-udid>' -derivedDataPath build build
xcrun simctl install <duo-udid> build/Build/Products/Debug-iphonesimulator/DuoProbe.app
./measure.sh inner-landscape-flat
```

Set the pose in **Device Hub** between runs. `simctl` has no fold, pose or hinge
subcommand, so this cannot be scripted end to end.

| Strategy | What it does |
|---|---|
| `A device` | Hard-coded model list decides between arrangement and split view |
| `B display` | `reservedRegions(kind: .division, options: .includeInactive)` decides |
| `C always` | `ArrangementView` unconditionally, both panes floored |
| `D split` | `NavigationSplitView` unconditionally |
| `E prim-only` | Bare `minWidth` on the primary, nothing on the secondary |
| `F snippet` | Primary `min 280 / ideal 330 / max 440`, floorless secondary |
| `G greedy` | Primary `minWidth: 700` |
| `H fixed` | `F` plus a floor on the secondary |
| `I 400` / `J 500` | Primary floor inside / beyond the 455.5-point half |

`Sources/DuoLayoutProbe.swift` is a symlink to the skill's own asset, so the
fixture cannot drift from what the skill ships. The target deliberately sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which is what a new Xcode 27 project
gets and what breaks a naively written probe.

What these strategies measured on 2026-09-20 is in
`skills/iphone-duo-adaptation/references/arrangement-views.md`.
