# The device, in numbers

Everything here was **measured** on the iPhone Duo simulator (`iPhone19,4`, iOS 27.1 runtime 24A94401, Xcode 27.1 build 27A9269) — display sizes from `xcrun simctl io <udid> enumerate`, everything else logged from a running app with `assets/DuoLayoutProbe.swift`. Where a value comes from Apple's documentation instead, it says so. Simulator values can differ from hardware; treat them as the shape of the problem, and never hard-code them.

**Contents:** [Displays](#displays) · [Size classes and bars](#size-classes-and-bars-per-configuration) · [Safe-area insets](#safe-area-insets) · [The fold](#the-fold) · [Poses](#poses) · [What fires when it folds](#what-fires-when-the-device-folds) · [Worked arithmetic](#worked-arithmetic-why-phone-layouts-break)

## Displays

| | Pixels | Points (@3x) | Aspect | Simulator screen |
|---|---|---|---|---|
| Outer | 1398 × 2034 | **466 × 678** | 1 : 1.455 | id 1, `primary` |
| Inner | 2007 × 2853 | **669 × 951** | 1 : 1.42 | id 3, `primary-1` |

For comparison, an iPhone 17 Pro is 402 × 874 (1 : 2.17). The outer display is *wider and shorter* than any other iPhone; the inner display is closer to a small tablet than to a phone, but it is still an iPhone — iOS patterns apply.

Screen ids may differ between Xcode versions; `scripts/capture-displays.sh` discovers them instead of assuming.

## Size classes and bars per configuration

| Configuration | Horizontal | Vertical | Bars |
|---|---|---|---|
| Outer display, portrait | compact | regular | vertical, trailing |
| Outer display, landscape | compact | compact | vertical, trailing |
| Inner display, portrait | regular | regular | horizontal (top + bottom) |
| Inner display, landscape | regular | regular | vertical, trailing |
| Inner display, Split View | read what you are given | | vertical, on the app's **outer** edge |

(Size classes per Apple's Tech Talk 111461; bar positions per the HIG and confirmed by measurement for the outer-portrait and both inner configurations.)

Two consequences worth internalising:

- `horizontalSizeClass == .regular` is true **on a phone** — and not only this one: Plus/Max iPhones are regular width (compact height) in landscape. iPhone Duo's inner display is the first iPhone surface that is regular in *both* directions, which is the discriminator to use for tablet-like layouts. Code that treats "regular" as "iPad" — or treats `userInterfaceIdiom == .phone` as "narrow" — is wrong here.
- The inner display **does not honour `UISupportedInterfaceOrientations`**. A portrait-only app is shown in landscape when the device is held that way.

## Safe-area insets

Measured at the root of a `NavigationStack` inside a `TabView`:

| Configuration | Top | Leading | Bottom | Trailing | Content size |
|---|---|---|---|---|---|
| Inner, landscape | 24 | 0 | 34 | **84** | 867 × 611 |
| Inner, portrait | **82** | 0 | **83** | 0 | 669 × 786 |
| Outer, portrait | small | 0 | — | bar-width | ≈ 382 wide (read from a screenshot, not logged) |

- The **vertical bar is 84 points** of trailing inset. It holds the status bar, the camera / Dynamic Island, toolbar items and the tab bar.
- The top inset ranges from 24 to 82 across poses of the *same* device. Any constant — 44, 47, 59 — is wrong somewhere.
- The insets are asymmetric. `width - leading * 2` and "centre on the screen" are both bugs; inset the rect and centre within the safe area.
- In Split View the bar of the left-hand app is on the leading side. Code that assumes "the big inset is trailing" breaks there.

## The fold

| | Value |
|---|---|
| Kind | `.division` |
| Frame, inner landscape | x **455.5 … 495.5** of an 867-point-wide content area — a **40-point band** |
| Frame, inner portrait | spans the full width (x 0 … 669): a horizontal band |
| `isActive` | `false` when flat, `true` when partially folded |
| Halves, inner landscape | 455.5 (leading) and 371.5 (trailing) points of content |

The halves are unequal because the vertical bar takes 84 points from the trailing side. "The hinge is at `width / 2`" is false in content coordinates.

Camera occlusions measured: `(867, −24, 84, 120)` in inner landscape and `(535, −82, 134, 82)` in inner portrait — outside the safe area, inside the bar region, which is why standard layouts never collide with them.

## Poses

Apple's names, from the design Tech Talk: **book** (partially folded, held like a book, hinge vertical), **laptop** / table-top (one half flat on a surface, the other upright), **standing** (resting on its edges), plus closed and fully open. The HIG's instruction is explicit: *don't design a layout per pose.* Design for compact width and regular width, make the layout resizable, and let arrangements and reserved regions handle the fold.

## What fires when the device folds

| Event | Fires? |
|---|---|
| `scenePhase` / scene activation | **No.** Nothing that hangs off scene lifecycle will notice. |
| Size class change | When the app moves between displays (compact ⇄ regular) |
| Geometry change (`onGeometryChange`, `layoutSubviews`) | Yes |
| Reserved region `isActive` | Yes — flat ⇄ partially folded |
| `onHingeChange` / `UIHingeInteraction` | Yes, continuously |
| `ArrangementView` re-layout | Yes, by itself — observed live: secondary pane 537 → 371 points as the division became active |

Anything with a lifecycle tied to the display — capture sessions above all — needs one of the signals in the lower rows.

## Worked arithmetic: why phone layouts break

A hero sized as "64 % of the viewport height, clamped to 380…600" is reasonable at 874 points of height: 559. On the inner display in landscape the height is 669: the hero takes **428**, leaving about 240 points — one clipped row — for everything else, while the hero's 140-point cover sits in a 951-point-wide room, 85 % of it empty.

A filter control whose four segments each take `maxWidth: .infinity` inside a 20-point margin is four comfortable ~85-point pills on a 402-point phone and four **~200-point** pills at 867.

A grid that computes columns as `Int((width + spacing) / (165 + spacing))` gets `Int(2.96) = 2` in a 537-point pane: two 253-point covers where three 152-point ones were intended.

None of these is a Duo-specific API problem. They are layouts that were only ever evaluated at one width and one height — which is why the audit starts with them.
