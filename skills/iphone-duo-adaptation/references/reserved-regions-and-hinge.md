# Reserved regions and the hinge

A **reserved region** is a part of the display that content should avoid or adapt to. iPhone Duo has three, of two kinds.

| Region | Kind | Present when |
|---|---|---|
| Outer front camera | `.occlusion` | always (it grows into the Dynamic Island for Live Activities) |
| Inner front camera (under the display) | `.occlusion` | only while the camera is in use — otherwise it is invisible and the UI doesn't move |
| The fold | `.division` | **active only while the device is partially folded.** Flat, it has no effect. |

**Contents:** [Do you need this at all?](#do-you-need-this-at-all) · [Querying](#querying) · [What the numbers look like](#what-the-numbers-look-like) · [Patterns](#patterns) · [The hinge API](#the-hinge-api-is-for-effects-not-layout)

## Do you need this at all?

Usually not. System components already account for reserved regions:

- alerts, context menus, sheets and popovers move off the fold;
- toolbar buttons are nudged away from the centre;
- `NavigationSplitView` / `UISplitViewController` adjust column widths and margins so the fold falls between columns;
- `ArrangementView` puts one pane on each side;
- standard bars avoid the camera and status bar.

Query regions only for content **you position by hand**: a custom canvas, a game HUD, an absolutely positioned badge, a drawing surface, a custom bar. And scrolling content is exempt — a feed or an article may run straight through the fold; people scroll it past.

## Querying

SwiftUI — from a `GeometryProxy` (so also inside `onGeometryChange`):

```swift
GeometryReader { proxy in
    let hinge   = proxy.reservedRegions(kind: .division).first             // active only
    let cameras = proxy.reservedRegions(kind: .occlusion)
    let hingeEvenWhenFlat = proxy.reservedRegions(kind: .division, options: .includeInactive)
}
```

UIKit — from any view, in its own coordinate space:

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    var area = bounds.inset(by: safeAreaInsets)
    if let hinge = reservedRegions(kind: .division).first {
        area.size.width = min(area.maxX, hinge.frame.minX) - area.minX
    }
    banner.frame = CGRect(x: area.minX, y: area.minY, width: max(area.width, 0), height: 44)
}
```

Facts that matter:

- **`frame` already includes the margins.** The SDK documents `frame` as the region's rect *including* the margins, and `margins` as the clearance included around the reserved rect *for interactive content*. Keep tappable things outside `frame`. The bare physical rect, if you need it for non-interactive drawing, is `frame` inset by `margins`.
- **Default queries return active regions only.** While the device is flat, `reservedRegions(kind: .division)` is empty. Pass `.includeInactive` to learn that a hinge *exists* and where it would be — the way to make decisions that shouldn't flip at the moment of folding.
- Frames are in the coordinate space of the view you ask. Ask the view you are laying out, not the window.
- `layoutDirectionBehavior` defaults to `.mirrors` (frames follow the layout direction); pass `.fixed` for physical coordinates.
- Regions change as the pose changes, and SwiftUI re-evaluates the geometry closure — no observer needed.

## What the numbers look like

Measured at the root of an app's content on the iPhone Duo simulator:

| Pose | Content size | Division | Occlusion (with `.includeInactive`) |
|---|---|---|---|
| Inner, landscape, flat | 867 × 611 | x 455.5…495.5, **inactive** | x 867…951, y −24…96 **active** (bar corner) · x 677.3…735.3, y −3…34 **inactive** (under-display camera, not in use) |
| Inner, landscape, half-folded | 867 × 611 | x 455.5…495.5, **active** | same |
| Inner, portrait, flat | 669 × 786 | spans x 0…669 (a horizontal band), inactive | x 535…669, y −82…0 |

The under-display camera is reported even while it is off — as an *inactive* occlusion — which is the measured form of the HIG's statement that it only affects layout while in use. The fold is a **40-point band**, not a line, and it is not at the centre of the *content*: the vertical bar shifts the content area, so the halves are 455.5 and 371.5 points wide. Never assume `width / 2`. The occlusion frames have negative or out-of-bounds coordinates because the cameras sit outside the safe area, inside the bar region.

## Patterns

Apple calls moving content in response to the pose **displacement**. The guidance, condensed:

- **Choose the scope.** Move one element on its own, or a group together — whichever keeps relationships readable.
- **Move as little as possible.** Small shifts over rearrangement. A control that jumps across the screen is a control people lose.
- **Don't displace continuous content.** Scrolling content adapts by scrolling.
- **Let purpose pick the destination.** On a table-top pose, put what people look at on the upright half and what they touch on the half lying flat.
- **Keep functionality identical across poses.**

Even columns so the fold lands in a gutter (HIG: prefer an even number of columns in grids):

```swift
GeometryReader { proxy in
    let hasHinge = !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
    let fit = max(2, Int(((proxy.size.width + spacing) / (target + spacing)).rounded()))
    let columns = hasHinge && !fit.isMultiple(of: 2) ? fit + 1 : fit
    …
}
```

Note `.rounded()` rather than truncation: 165 points is what an item *wants* to be, not a minimum, and flooring turned 2.96 columns into two fat ones.

Dodging the camera with a hand-placed element:

```swift
let blocked = proxy.reservedRegions(kind: .occlusion)
    .contains { $0.isActive && $0.frame.intersects(badgeFrame) }
```

## The hinge API is for effects, not layout

```swift
.onHingeChange { _, context in
    // nil hinge: this device doesn't have one
    if let hinge = context.hinge, hinge.status == .partiallyOpen {
        tilt = (180 - hinge.angle.degrees) / 12
    } else {
        tilt = 0
    }
}
```

```swift
let interaction = UIHingeInteraction { _, update in
    guard let hinge = update.hinge, hinge.status == .partiallyOpen else { return reset() }
    apply(hinge.angle)            // CGFloat in UIKit, Angle in SwiftUI
}
view.addInteraction(interaction)
```

`status` is `.closed`, `.partiallyOpen` or `.fullyOpen` (UIKit adds `.unknown`); the angle updates continuously. Use it for things that *respond* to the fold — a page curl, a pitch bend, a parallax — and always handle the `nil` hinge so the code is inert on every other iPhone.

Do not drive layout from the angle. Thresholds you invent will disagree with the system's own notion of "partially folded", and the layout tools — size classes, arrangements, active reserved regions — already encode that decision.
