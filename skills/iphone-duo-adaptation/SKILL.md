---
name: iphone-duo-adaptation
description: >-
  Adapt iOS apps (SwiftUI and UIKit) for iPhone Duo, Apple's folding iPhone: two displays, a hinge,
  toolbars and tab bars that move to the side, reserved regions, and the iOS 27.1 layout APIs
  (ArrangementView, UIArrangementViewController, reservedRegions, onHingeChange, axisBehavior,
  toolbarVerticalBehavior). Use this skill whenever the user mentions iPhone Duo, a foldable or
  folding iPhone, the hinge or fold, book or laptop pose, inner or outer display, Device Hub, vertical
  bars, or ArrangementView. Use it too when an iOS layout looks stretched, centred with dead space,
  squeezed or clipped on a wide or short screen, when toolbar items overflow or jump to the side, or
  when auditing an app for iOS 27 / Xcode 27 readiness, even if nobody says "Duo". Provides API
  spellings verified against the shipping SDK, measured device metrics, the traps that cost real
  debugging time, compile-checked samples, and scripts that audit a project and verify the SDK.
license: MIT
compatibility: The scripts and simulator steps need macOS with Xcode 27.1 or later. The guidance itself works with any coding agent.
metadata:
  version: "1.0.0"
  verified-against: "Xcode 27.1 (27A9269), iOS 27.1 SDK and simulator runtime (24A94401), iPhone Duo simulator (iPhone19,4)"
  last-verified: "2026-09-19"
---

# Adapting an app for iPhone Duo

iPhone Duo is Apple's folding iPhone: a compact outer display, a large inner display, a hinge between the halves, and a front camera on each side. Three consequences break real apps:

1. **The screen got wide and short.** A layout that centres a phone-width column — or stretches one — ends up with dead paper or 600-point-wide controls.
2. **The bars moved to the side.** Status bar, Dynamic Island, toolbar and tab bar share one *vertical bar* on the outer display and on the inner display in landscape. Safe areas become asymmetric.
3. **The display folds while the app is running.** A 40-point hinge band becomes a reserved region and the layout must re-flow live, with no scene-phase change to hang it on.

Apple's position is the spine of this skill: **adapt to size classes and container size — never to the device, the pose, or the orientation.** An app that already resizes well gets most of this for free. The skill is about the part that isn't free.

## Ground truth first

These APIs were days old when this was written, so there is little to check a spelling against except the SDK itself. The traps survive a plausibility check: the reserved-region kinds are singular (`.division`, `.occlusion`) where prose pluralises them naturally, and a name that compiles can still be the wrong one. A wrong name costs a build cycle; a wrong mental model costs an afternoon. So before writing code:

```bash
scripts/check-sdk.sh        # which Duo APIs does the installed SDK really have, and in which module?
```

One result surprises everyone once: SwiftUI's layout APIs (`ArrangementView`, `reservedRegions`, `onHingeChange` …) are declared in **SwiftUICore**, not SwiftUI. `import SwiftUI` re-exports them, so code compiles — but grepping `SwiftUI.swiftinterface` alone "proves" they don't exist. Search both. When a symbol is reported missing, don't code against it; at the time of writing that was `AVCaptureDeviceDirectionCoordinator`, described in Tech Talk 111465 and absent from the headers.

If you can't run scripts, trust `references/api-reference.md` (every entry was read from the SDK and compile-checked) over anything remembered or searched.

## How to work

1. **Verify the SDK** — `scripts/check-sdk.sh`. Note the deployment target: everything new needs `#available(iOS 27.1, *)` and a fallback that still works.
2. **Audit** — `scripts/audit.sh <project-dir>` gives a ranked reading list of likely breakage. Grep can't see the biggest class of problem (centred and stretched layouts), so also walk `references/audit-checklist.md`.
3. **Fix cheapest-first.** Roughly: stretched controls → safe-area assumptions → toolbar items → layout restructuring with arrangements → reserved regions for custom-drawn content → camera → multiple scenes. The early items are small diffs with large visible effect; they also remove noise before the structural work.
4. **Verify in every pose, by measurement.** Attach `assets/DuoLayoutProbe.swift`, capture with `scripts/capture-displays.sh`, and compare numbers — see *Verifying* below. Layout bugs on this device routinely look like design problems until you log the values.

**Match the effort to the question.** "Does this code use the API correctly?" is answered by the compiler in seconds: `swiftc -typecheck -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios26.0-simulator File.swift`. Booting a simulator is for questions about *behaviour* — where a pane lands, what an inset is. Use the simulator that is already booted; never create extra ones (each costs gigabytes of disk and RAM on the user's machine), don't drive GUI apps unasked, and delete anything you did create.

Keep the phone and tablet paths working. Most fixes here are neutral or positive on iPad; say so explicitly when a change alters iPad behaviour (a two-pane layout triggered by "regular width and wider than tall" also triggers on an iPad in landscape).

## The device in one table

Measured on the iPhone Duo simulator (`@3x`); "content" is what a root view gets inside the safe area.

| | Outer display (closed) | Inner display, portrait | Inner display, landscape |
|---|---|---|---|
| Points | 466 × 678 | 669 × 951 | 951 × 669 |
| Size classes (h / v) | compact / regular | regular / regular | regular / regular |
| Bars | **vertical**, trailing edge | horizontal, top and bottom | **vertical**, trailing edge |
| Safe-area insets (t / l / b / tr) | bar on the trailing side | 82 / 0 / 83 / 0 | 24 / 0 / 34 / **84** |
| Content | ≈ 382 wide | 669 × 786 | 867 × 611 |
| Hinge (division region) | — | horizontal band | vertical band, x 455.5…495.5 of 867 |

The outer display is *wider and shorter* than any other iPhone (an iPhone 17 Pro is 402 × 874). The inner display ignores `UISupportedInterfaceOrientations` entirely — a portrait-only app gets landscape there. More numbers, and how they were taken: `references/device-and-metrics.md`.

## Rules that matter, and why

- **Decide layout from `horizontalSizeClass` and the container's size.** Not `userInterfaceIdiom` (the inner display is regular width *on a phone*), not orientation (it isn't size, and the inner display doesn't honour yours), not `UIScreen.main` (there are two screens and it is deprecated).
- **Wide is not the same as stretched.** Text has a length at which it reads well and a card has a size at which it looks like a card. Cap columns of content at a readable measure (≈ 560 pt) and let the *paper* get wider. Grids of things — covers, photos — are the exception: they want every point.
- **Treat safe areas as asymmetric.** With a vertical bar only one side is inset. Inset the rect (`bounds.inset(by: safeAreaInsets)`); never subtract one side twice. Never hard-code a status-bar height as a fallback, and don't discard a measured inset because it is small — on this device the top inset ranges from 24 to 82 depending on pose.
- **Backgrounds may run under the bar; foregrounds may not.** Full-bleed imagery behind the vertical bar is good (`backgroundExtensionEffect()` does it for you); anything tappable or readable stays in the safe area.
- **Only system containers get vertical bars.** Items declared with `.toolbar { }` in a `NavigationStack` / `NavigationSplitView`, or on a view controller inside `UINavigationController` / `UITabBarController`, move to the side. Hand-made `UIToolbar`s and floating button stacks don't, and may end up under the camera.
- **Give every toolbar item a title *and* a symbol.** A vertical bar has fixed width and flexible height: it shows symbols. Title-only and custom-view items won't present vertically; the title is still needed for the overflow menu.
- **Same functionality in every pose.** People open and close the device constantly. Rearranging is fine; features that exist only in one pose are not.
- **Small moves.** When the device folds, move only what must move to stay visible and tappable. Controls that jump across the screen are controls people lose.

## Choosing a layout container

| The screen has… | Use | Because |
|---|---|---|
| List → detail (selection drives the other pane) | `NavigationSplitView` / `UISplitViewController` | It's navigation. Collapses on the outer display, expands on the inner, adapts to the fold by itself. |
| Two peers that are both always relevant (player + queue, hero + shelf, map + results) | `ArrangementView` with `.split` | Side by side when wide, stacked when tall, and snaps the panes to the two halves when folded. |
| A foreground layered over a background (controls over a page, shutter over a viewfinder) | `ArrangementView` with `.overlay` | Layered when flat; when partially folded the two move to opposite sides of the hinge. |
| One scrolling column | Nothing new — cap its width | A feed or article scrolls through the fold; scrolling content is exempt from fold avoidance. |
| A grid | Nothing new — compute columns from measured width | Prefer an **even** column count when a hinge exists so the fold falls in a gutter. |

Mapping from existing code: an `HStack`/`VStack` of two real panes becomes a split arrangement; a `ZStack` of content and controls becomes an overlay arrangement.

## ArrangementView essentials

```swift
NavigationStack {                                   // navigation goes AROUND it
    ArrangementView {
        PlayerView()
            .splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)
    } secondary: {
        QueueView()                                 // a ScrollView/List INSIDE a pane is fine
            .splitArrangementLayoutSize(minWidth: 360)
    }
    .arrangementViewStyle(.split.axes(.horizontal))
}
```

Four traps, each of which cost a debugging session to find:

1. **Size preferences belong on the panes, not on the `ArrangementView`.** `splitArrangementLayoutSize`, `splitArrangementLayoutRatio` and `splitArrangementFixedLayoutSize` are `View` modifiers that a *child* uses to describe itself (like `navigationSplitViewColumnWidth`). On the container they are silently ignored and the split stays 50/50.
2. **Every pane needs its own `minWidth`.** With a preference on the primary only, the system honoured it and gave the secondary the leftovers. Half-folded, that was 145 points, all on one side of the hinge, with the other half of the screen blank — text wrapping one character per line. Adding a floor to the secondary made both panes snap to the halves of the display.
3. **`.axes(.horizontal)` shows *only the primary* when the container is taller than wide.** The secondary doesn't stack underneath; it disappears. Either allow both axes (`.split`), or enter the arrangement only when the container is wider than tall and wide enough for both floors — and keep a single-column fallback. Require **regular *vertical* size class too**: a Plus/Max iPhone in landscape is regular width but compact height, and without that check it silently switches to your new two-pane layout on a 440-point-tall screen you never designed for.
4. **Don't put an `ArrangementView` inside a `ScrollView`, `List` or `NavigationSplitView`, and don't put navigation containers inside it.** Arrangements do layout, not navigation.

Two things that are *not* problems, so don't engineer around them: the fold overrides `maxWidth` (a pane capped at 440 took the full 455.5-point half), and the arrangement re-lays out live as the hinge moves — no observer needed.

Prefer point sizes to ratios when a pane holds something of fixed physical size; as a ratio, a pane built around one book cover took half of a 1366-point tablet. UIKit equivalent, overlay details, reading the arrangement from inside a pane (`overlayArrangementZIndex`, `splitArrangementAxis`), and a worked migration: `references/arrangement-views.md`.

## Vertical bars essentials

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { } }      // top
    ToolbarItem(placement: .topBarPinnedTrailing) { Button("Done", systemImage: "checkmark") { } } // then
    ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Compose", systemImage: "square.and.pencil") { }
    }
    .visibilityPriority(.high)                          // last into the overflow menu
    ToolbarItem(placement: .principal) { Text("INBOX") }
        .axisBehavior(.horizontalOnly)                  // meaningful text stays horizontal
    ToolbarOverflowMenu { Button("Settings", systemImage: "gearshape") { } }  // one overflow: the system's
}
```

- Order on the vertical axis: primary navigation (Back, Close) at the top, then prominent actions (Done), then the rest in their groups. Use the semantic placements above rather than manual spacing; group related items with `ToolbarItemGroup`.
- Items overflow bottom-to-top by default. Use `visibilityPriority` to keep the frequently used action (Compose, New Note) and anything carrying status (badges) visible longest.
- When space runs out, choose what survives: `toolbarVerticalCompressionBehavior(.prefersTabBar)` keeps the tab bar and overflows toolbar items (the iOS default — right for navigation-focused apps); `.prefersToolbarItems` keeps the actions and minimises the tab bar (right for task-focused screens).
- Opt out with `toolbarVerticalBehavior(.disabled)` only for full-width, bottom-heavy, non-scrolling UI (a calculator) or a sheet whose only control is Close.
- Custom toolbar views read `@Environment(\.toolbarVerticalEdge)` (`.leading`, `.trailing`, or `nil` for horizontal bars) and switch to a fixed-width, symbol-only form. It can be `.leading`: in Split View multitasking each app's bar sits on its *outer* edge.

Where bars are and aren't vertical (sheets, inspectors, split-view columns), UIKit spellings, tab-bar sidebar placement, and one measured nuance about `.principal` items: `references/vertical-bars.md`.

## Reserved regions and the hinge

```swift
GeometryReader { proxy in
    let hinge = proxy.reservedRegions(kind: .division).first          // active regions only
    let cameras = proxy.reservedRegions(kind: .occlusion)
    // `.includeInactive` also returns the hinge while the device is flat (isActive == false)
}
```

Two kinds: `.division` (the fold — *active only while partially folded*, zero effect when flat) and `.occlusion` (cameras; the inner one only while in use). A region's `frame` already includes the margins recommended for interactive content. System components — alerts, menus, sheets, toolbar buttons, split views, arrangements — avoid the fold on their own; query regions only for content you position by hand. Keep interactive elements out of the fold; let scrolling content pass through it.

`onHingeChange` / `UIHingeInteraction` give the hinge status and a continuous angle. That is for *live effects* (a page that tilts with the fold), not for layout — layout belongs to size classes, arrangements and regions. Details and UIKit forms: `references/reserved-regions-and-hinge.md`.

## Anti-patterns

| Pattern | Why it breaks here | Instead |
|---|---|---|
| `UIScreen.main.bounds` / `.scale` | Two screens; deprecated | Container bounds; `view.window?.windowScene?.screen`; `traitCollection.displayScale` |
| `if UIDevice.current.userInterfaceIdiom == .pad` | Inner display is regular width on a phone | `horizontalSizeClass`, measured width |
| Orientation checks for layout | Not size; inner display ignores supported orientations | Size class or container aspect ratio |
| `safeAreaInsets.top ?? 59` | One phone's status bar, frozen into layout | Fall back to `0`; measure |
| `if inset > 0 { use(inset) }` | Bakes in "there is always a top inset"; keeps stale values | Accept the measurement; bound it some other way |
| `width - safeAreaInsets.left * 2` | Insets are asymmetric with a vertical bar | `bounds.inset(by: safeAreaInsets)` |
| `connectedScenes.first` | First iPhone with multiple scenes | The view's own window scene, else `foregroundActive` |
| `.frame(maxWidth: .infinity)` on controls and cards | 600-point chips and search fields | Cap at a readable measure, align with the content below |
| Hero height as a % of viewport height | 64 % of a 669-point-tall screen leaves one clipped row | Bound by width too, or move the hero into a pane |
| `Int(width / itemWidth)` for grid columns | Floors 2.96 to 2: two fat columns | Round; prefer even counts when a hinge exists |
| `AVCaptureDevice.default(.builtInWideAngleCamera, …)` and a session tied to `scenePhase` | Cameras differ per display; folding isn't a phase change | Discover devices; reconfigure on display change; `RotationCoordinator` |
| `settings.flashMode = .auto` | Uncatchable exception if unsupported; no front camera has a flash | Check `supportedFlashModes` first |

## Verifying

Test matrix — all six, because each has failed independently in practice: outer display portrait · outer landscape · inner portrait · inner landscape flat · inner landscape **half-folded** · inner portrait half-folded. Then Split View multitasking on the inner display (bar on the leading edge for the left-hand app).

- Poses are changed in **Device Hub** (it replaces Simulator.app in Xcode 27.1). There is no `simctl` command and no XCTest API for folding; `XCUIDevice` can rotate only. If you are an agent without screen control, ask the user to set the pose, then measure.
- `scripts/capture-displays.sh` screenshots both displays by id. A plain `simctl io … screenshot` often grabs the display that is switched off — a black image that looks like a crash.
- **Measure, don't eyeball.** Add `.duoLayoutProbe("name")` from `assets/DuoLayoutProbe.swift` and read real sizes, insets, region frames and hinge state from the log. Estimating from screenshots goes wrong quietly: they are `@3x`, often downscaled again by the viewer, and the two displays differ. Several "layout bugs" in the work behind this skill were measurement errors, and several real bugs were invisible until logged.
- **Mind default actor isolation.** New Xcode project templates set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. A plain `struct` you hand to `onGeometryChange(for:)` then gets a main-actor-isolated `Equatable` conformance and the build fails with *"cannot satisfy conformance requirement for a 'Sendable' type parameter"*. Mark such value types `nonisolated` and `Sendable`. The bundled probe already is — it failed in a real app before it was.
- Re-run `tests/typecheck.sh` from the repository after every Xcode update; it checks every sample under both isolation defaults.

Simulator tooling gaps, log commands and a per-pose checklist: `references/simulator-and-verification.md`.

## Reference files

Read only what the task needs.

| File | Read it when |
|---|---|
| `references/api-reference.md` | You need an exact spelling, module, availability or enum case — SwiftUI, UIKit, AVFoundation |
| `references/arrangement-views.md` | Building or debugging a two-pane or layered layout |
| `references/vertical-bars.md` | Toolbar, tab bar, sheet or navigation-bar work |
| `references/reserved-regions-and-hinge.md` | Positioning custom content around the fold or cameras; hinge-driven effects |
| `references/camera-and-scenes.md` | Capture sessions, the second display as a camera accessory, multiple windows |
| `references/device-and-metrics.md` | You need numbers: sizes, insets, regions per pose |
| `references/audit-checklist.md` | Auditing an existing app, or deciding what to fix first |
| `references/simulator-and-verification.md` | Running, capturing, logging and testing on the simulator |

Apple's own material — the HIG page *Designing for iPhone Duo*, the overview *Preparing your app for iPhone Duo*, and Tech Talks 111461–111466 — is linked from `references/api-reference.md`. When this skill and the installed SDK disagree, the SDK wins: fix the code, then open an issue against the skill.
