# Running, capturing and verifying on the simulator

**Contents:** [Setup](#setup) · [The pose matrix](#the-pose-matrix) · [Capturing both displays](#capturing-both-displays) · [Measuring instead of eyeballing](#measuring-instead-of-eyeballing) · [Tooling gaps](#tooling-gaps-as-of-xcode-271-27a9269) · [For agents with screen control](#for-agents-with-screen-control) · [For agents without screen control](#for-agents-without-screen-control) · [UI tests](#ui-tests)

## Setup

- Xcode 27.1 or later. The **iPhone Duo** device type comes with the iOS 27.1 simulator runtime: `xcrun simctl list devicetypes | grep -i duo`.
- In Xcode 27.1 the simulator UI is **Device Hub** (`DeviceHub.app`); `Simulator.app` is gone. Poses — closed, open, partially folded, rotated — are set there.
- Build and run as usual (`xcodebuild … -destination 'platform=iOS Simulator,name=iPhone Duo'`, or your usual tooling). Launching with `xcrun simctl launch` on an app that is *already running* only foregrounds it: new launch arguments and `SIMCTL_CHILD_` environment variables are ignored until you `simctl terminate` first.

## The pose matrix

Each row has produced a bug the others didn't.

| # | Display / pose | What to look for |
|---|---|---|
| 1 | Outer, portrait | Vertical bar present; compact-width layout intact; nothing under the camera |
| 2 | Outer, landscape | compact/compact; bar item overflow; sheets |
| 3 | Inner, portrait | Horizontal bars return; regular width but *taller than wide* — two-pane layouts that are horizontal-only must fall back |
| 4 | Inner, landscape, flat | The wide case: stretched controls, dead space, two-pane layouts, grid columns |
| 5 | Inner, landscape, **half-folded** | Panes snap to the halves; nothing interactive on the fold; nothing squeezed |
| 6 | Inner, portrait, half-folded (table-top) | Look-at content on the upright half, touch-content on the flat half |
| 7 | Inner, Split View multitasking | Bar on the **leading** edge for the left-hand app; roughly half the width |
| 8 | Transitions | Open ⇄ close mid-task: state survives; capture sessions follow the display |

Also run the existing phone and tablet destinations once. The fixes this skill suggests are meant to be invisible at phone width and neutral-to-positive on iPad — confirm it.

## Capturing both displays

```bash
scripts/capture-displays.sh            # booted iPhone Duo, into ./duo-captures
```

Under the hood: `xcrun simctl io <udid> enumerate` lists two *Integrated* screens, and `xcrun simctl io <udid> screenshot --display=<id> file.png` captures one of them. Without `--display` you get whichever display the tool picks — frequently the one that is switched off, as a solid black image. **A black screenshot on this device means "wrong display" far more often than "crashed app".**

| Capture size | It is |
|---|---|
| 1398 × 2034 (or 2034 × 1398) | outer display |
| 2007 × 2853 (or 2853 × 2007) | inner display |

## Measuring instead of eyeballing

Add the probe (DEBUG-only; copy `assets/DuoLayoutProbe.swift` into the app target):

```swift
LibraryView().duoLayoutProbe("library")
```

Read it back:

```bash
xcrun simctl spawn booted log show --last 2m --style compact --predicate 'category == "DuoProbe"'
```

Real output, inner display in landscape, fully open:

```
[library] size=867.0x611.0 insets(t/l/b/tr)=24.0/0.0/34.0/84.0 division=[x455.5…495.5 y-24.0…645.0 inactive] occlusion=[x677.3…735.3 y-3.0…34.0 inactive | x867.0…951.0 y-24.0…96.0 ACTIVE] classes=regular/regular barEdge=trailing
[library] hinge=fullyOpen angle=180.0°
```

Everything this skill claims about the device is in those two lines: the 84-point vertical bar, the 40-point hinge band that exists but is *inactive* while flat, the under-display camera that is reported but inactive until it is used, and the bar edge. Half-fold the device and `division` flips to `ACTIVE` with no other change.

Put a probe on each pane of an arrangement to see what each one was actually given.

Why insist on this: screenshots are `@3x`, image viewers and agent tooling usually downscale them again, and the two displays have different sizes — so a coordinate read off a picture is off by an unknown factor. In the work this skill came from, a "the content isn't centred" bug was a misread screenshot (the layout was correct), while a genuinely broken split (50/50 instead of 330/537) looked plausible by eye and was only caught by the numbers.

Convert deliberately when you must: **points = original pixels ÷ 3**, after undoing any display scaling of the image you are looking at.

## Tooling gaps (as of Xcode 27.1, 27A9269)

Observed, not documented; expect them to change.

- **No command-line fold.** `simctl` has no fold, hinge or pose command (`simctl ui` offers appearance, content size and contrast only). Poses are a Device Hub UI action.
- **No XCTest fold either.** `XCUIDevice` can set `orientation`; the XCTest / XCUIAutomation headers contain no hinge, fold or pose API.
- **Synthetic touches may not reach the inner display.** With `simctl`-based touch injection, taps landed while the outer display was live and were silently dropped while the inner display was live — both with inner-display coordinates and with coordinates normalised to the outer display. Screenshots were byte-identical before and after. If taps "succeed" and nothing changes, check which display is live before debugging the app.
- **`SimulatorKit.framework` moved** to `Xcode.app/Contents/SharedFrameworks/`. Automation tools that load it from `Contents/Developer/Library/PrivateFrameworks/` fail with "Failed to load essential private frameworks" until they are updated.
- **Restarting `CoreSimulatorService`** (a common fix for dead simulator input) shuts the device down; it boots again *closed*, so the pose you were testing is lost.
- Apps built against an older deployment target than the simulator runtime's minimum simply refuse to install on older-runtime iPads — if you verify a wide layout on an iPad instead, pick one whose runtime is ≥ the app's deployment target.
- **`xcrun simctl pbcopy` did not reach the app.** Pasting into a text field after `pbcopy` pasted nothing. Type the text instead.
- **Typed text follows the simulator's keyboard layout.** With a German layout, `@` typed by an automation tool arrived as `"`, so an email address came out wrong without any error. Type the parts around it and tap the on-screen keyboard's `@` key on an email field, then read the field back before submitting.

## For agents with screen control

With a tool that drives macOS apps you can set the poses yourself, and tap the inner display:

- Device Hub's pose controls are accessibility buttons: **Closed**, **Book**, **Open** and **Rotate Right**, next to Home, Screenshot and Record. Press them by accessibility rather than by coordinate.
- Clicks and drags on the device in the Device Hub window reach whichever display is live, **including the inner display**, where `simctl` touch injection is dropped (above). That is how to tap through a flow on the inner display.
- The device image moves, rotates and changes size with every pose. Take a fresh screenshot of the window before computing a coordinate, and convert through the display's rectangle in that screenshot.
- A drag that starts a few points above the display's bottom edge is the **home gesture**: the app went to the home screen. Start scroll drags well inside the content.
- Let a scroll settle before tapping. A tap during the deceleration landed on whichever row had scrolled under the pointer.

## For agents without screen control

You can build, launch, capture and read logs; you usually cannot fold the device. So:

1. Do everything that doesn't depend on the pose first.
2. Ask the user for **one specific pose** ("open it, landscape, leave it half-folded"), then capture and read the probe. One round-trip per pose, not per question.
3. State plainly which rows of the matrix you verified and which you did not.
4. A wide layout (row 4) can also be checked on an iPad simulator, where input works normally — but rows 5–7 exist only on the Duo.

## UI tests

- Pin the language and locale in the test launch (`-AppleLanguages "(en)"`), as always.
- `XCUIDevice.shared.orientation = .landscapeLeft` works for rotation. There is no API for folding, so pose-dependent assertions can't be automated yet; keep those as a manual checklist.
- Prefer asserting on *structure* ("the queue is visible beside the player") over frames; frames differ between the two displays and between flat and folded.
