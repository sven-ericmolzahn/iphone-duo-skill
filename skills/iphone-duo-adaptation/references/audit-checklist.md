# Auditing an app for iPhone Duo

`scripts/audit.sh <project-dir>` finds what grep can find. This checklist covers the rest — and the rest is most of it, because the commonest failures are not API misuse but layouts that were only ever looked at on one size of screen.

Work top to bottom: the order is by *visible effect per line of diff*.

**Contents:** [0 · Setup](#0--setup) · [1 · Stretched and centred](#1--stretched-and-centred-layouts-small-diffs-big-effect) · [2 · Safe-area assumptions](#2--safe-area-assumptions) · [3 · Bars](#3--bars) · [4 · Structure](#4--structure-the-real-work) · [5 · The fold](#5--the-fold) · [6 · Camera](#6--camera) · [7 · Scenes and state](#7--scenes-state-and-continuity) · [8 · Reporting](#8--reporting-what-you-did)

## 0 · Setup

- [ ] `scripts/check-sdk.sh` — know which APIs exist before planning around them.
- [ ] Note the deployment target. Everything new is `#available(iOS 27.1, *)` (some bar APIs 27.0) **with a fallback that is the current behaviour**.
- [ ] Build with the iOS 27.1 SDK and run on the iPhone Duo simulator once *before changing anything*, on both displays. Screenshot it. You need the "before".
- [ ] `UIRequiresFullScreen` is not set; the app is not locked to one size.

## 1 · Stretched and centred layouts (small diffs, big effect)

Open every top-level screen on the inner display in landscape (951 × 669) and look for:

- [ ] **Controls that span the width** — search fields, segmented filters, primary buttons, form rows with `.frame(maxWidth: .infinity)`. Cap them at a readable measure (≈ 560 pt) and align them with the content they govern (leading, if a grid or list starts at the leading margin below them).
- [ ] **Pages of cards and text that span the width** — settings, profiles, detail pages. One cap on the *column*, not on every section; sections keep their own margins inside it:
      ```swift
      content.frame(maxWidth: 560).frame(maxWidth: .infinity)
      ```
- [ ] **Things that *should* use the width** — grids of covers, photos, products. Compute columns from the measured container width, round rather than truncate, prefer an even count when a hinge exists.
- [ ] **Heights that are a percentage of the viewport.** The inner display in landscape is only 669 points tall; 60 % heroes leave nothing below them.
- [ ] **Hard-coded content widths and `UIScreen`-derived sizes.**
- [ ] One shared constant for the readable measure, in the design system — not the same literal in five files.

Check afterwards that the phone-width path is pixel-identical: a cap above the phone's width must change nothing there.

## 2 · Safe-area assumptions

- [ ] No constant stands in for an inset (`?? 59`, `+ 44`, `topPadding = 47`).
- [ ] No measurement is discarded because it is small or zero (`if inset > 0`). Accept it; if transient values during transitions are a problem, bound the measurement by another *measurement* (the window's inset), not by a guess.
- [ ] Nothing assumes symmetry (`leading * 2`, "centre of the screen"). Use `bounds.inset(by:)` / centre within the safe area.
- [ ] Nothing assumes the large inset is *trailing* — in Split View it is leading.
- [ ] Full-bleed backgrounds ignore the safe area; their foreground content is put back inside it explicitly.
- [ ] "The" window is never `connectedScenes.first` / `windows.first` / `keyWindow`.

## 3 · Bars

- [ ] Every toolbar item has a **title and a symbol**. Title-only and custom-view items do not present vertically.
- [ ] Items are declared through system containers. Hand-made bars and floating button stacks are found and, where possible, replaced — especially on pushed screens.
- [ ] Back/Close use `.cancellationAction`; Done uses `.topBarPinnedTrailing`; related items are grouped, not spaced by hand.
- [ ] `visibilityPriority` marks what must stay visible: the most-used action and anything showing status.
- [ ] Custom "more" menus move into `ToolbarOverflowMenu`.
- [ ] Meaningful text items (Select ⇄ Done, a cart total) are `.horizontalOnly`. Text that only repeats a symbol is dropped in favour of the symbol, with a badge if it carried a count.
- [ ] A badge whose count loads after the item appears changes the item's symbol with it (`bell.fill` → `bell.badge.fill`); in a vertical bar the badge alone did not update.
- [ ] Screens that are all about their actions set `.toolbarVerticalCompressionBehavior(.prefersToolbarItems)`.
- [ ] Hero images and coloured headers run under the bar (`backgroundExtensionEffect()`), rather than stopping at it with a hard edge. It mirrors the view's edge outward, so a blurred or soft-edged backdrop shows the mirror axis as a seam and wants a background drawn behind the layout instead. In an arrangement the modifier goes on the pane, never on the image inside it.
- [ ] Sheets: checked on the outer display; single-button sheets may disable the vertical bar.

## 4 · Structure (the real work)

For each top-level screen on a regular-width, wide container, ask Apple's question: *is this a centred phone layout on a display that is now wide?*

- [ ] List → detail flows use `NavigationSplitView` / `UISplitViewController` and show both levels on the inner display in landscape. In portrait they collapse to one column: there `NavigationSplitView` hides the list or lays it over the detail (`split-views.md`).
- [ ] One column comes from collapsing the same `NavigationSplitView` (a compact size-class override), not from an `if` that swaps in a `NavigationStack`: the swap rebuilds both columns and closes every sheet presented from them. Test: open an edit sheet from a detail, change a value, rotate and fold.
- [ ] Folded with a detail open, the detail has a back button to the list.
- [ ] Switching tabs across a fold (unfold on tab A, then open tab B) leaves no second copy of B's toolbar items in the vertical bar.
- [ ] No `navigationSplitViewColumnWidth` on the list column — with one, the columns stop snapping to the fold.
- [ ] A detail column whose screens push a second level has a stack bound to a path, emptied when the selection changes; otherwise the pushed screen outlives the selection.
- [ ] Features that open in sheets from a dashboard were considered as a hub: the dashboard as the list, the feature beside it. Screens that are both sheet and detail own a `NavigationStack` (and a Close button) only as a sheet.
- [ ] Two-peer screens use `ArrangementView` with `.split`; layered screens use `.overlay`. See `arrangement-views.md`.
- [ ] Overlay arrangements checked in the table-top pose: content on the upright half, controls on the flat one. No `overlayArrangementEdge(VerticalEdge.bottom)`, which kept both on the flat half.
- [ ] Every pane has its own minimum size. The arrangement is entered only when the container can satisfy both.
- [ ] The single-column path is still there, unchanged, for compact width and tall containers.
- [ ] The same hierarchy and the same functions exist on both displays. More *levels* visible on the inner display is good; features that exist only there is not.
- [ ] The entry condition checks the **vertical** size class as well — a Plus/Max iPhone in landscape is regular width, compact height, and must stay on the old layout.
- [ ] iPad impact noted: a rule like "regular in both size classes and wider than tall" changes iPad-landscape too.

## 5 · The fold

Only for content positioned by hand:

- [ ] Interactive elements stay outside active `.division` frames.
- [ ] Hand-placed elements near the top/trailing corner check `.occlusion` frames.
- [ ] Scrolling content is left alone.
- [ ] Nothing assumes the fold is at `width / 2` or is a line (it is a ~40-point band, off-centre in content coordinates).
- [ ] Movement on folding is small; nothing teleports.

## 6 · Camera

See `camera-and-scenes.md`. In short: discovery session instead of a fixed device, reconfigure when the display changes (folding is not a scene-phase change), `RotationCoordinator` for orientation, check `supportedFlashModes` and friends before setting anything.

## 7 · Scenes, state and continuity

- [ ] Opening and closing the device mid-task loses nothing: scroll position, selection, text being typed, a presented sheet.
- [ ] State is per scene where the app supports multiple windows; "open in new window" uses `UIWindowSceneActivationAction` (new windows exist only on the inner display).
- [ ] Widgets, Live Activities and the Dynamic Island presentation were looked at on the outer display, where the island expands *vertically*.

## 8 · Reporting what you did

When you report back, separate three things, because on this device they are easy to blur:

1. **Verified** — seen in a capture or a log, in which pose.
2. **Changed but not seen** — and why (a pose you couldn't reach, a device you couldn't drive).
3. **Behaviour changes outside the Duo** — typically iPad landscape.

If an API turned out to be a no-op in the configuration you tested (it happens — see the `.principal` note in `vertical-bars.md`), say so rather than describing it as a fix.
