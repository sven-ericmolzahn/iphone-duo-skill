# Arrangement views

An arrangement view holds exactly two views — a **primary** and a **secondary** — and decides where each goes from three inputs: the size classes, the container's aspect ratio, and the active reserved regions (the fold). You describe the relationship; the system does the geometry, including the geometry you would get wrong: snapping the panes to the two halves of a half-folded display and re-laying out live as the hinge moves.

It sits *between* navigation containers (`NavigationStack`, `NavigationSplitView`, `TabView`) and content containers (`List`, `ScrollView`):

```
NavigationStack            ← navigation, outside
└─ ArrangementView         ← layout
   ├─ primary   (may contain a ScrollView / List)
   └─ secondary (may contain a ScrollView / List)
```

**Contents:** [Which style](#which-style) · [Split](#split) · [Pane sizing](#pane-sizing-the-part-everyone-gets-wrong) · [Measured behaviour](#measured-behaviour) · [Overlay](#overlay) · [Reading the arrangement from inside](#reading-the-arrangement-from-inside-a-pane) · [UIKit](#uikit) · [Migration recipe](#migration-recipe) · [When not to use one](#when-not-to-use-one)

## Which style

| Relationship | Style | Flat, wide | Flat, tall | Half-folded |
|---|---|---|---|---|
| Two peers, neither may be covered (player + queue, podcast + transcript, hero + shelf) | `.split` | side by side | stacked | one pane per half |
| Foreground over background (reading controls over a page, shutter over a viewfinder) | `.overlay` | primary layered over secondary | same | the two move to opposite sides of the fold |

Existing code is the best hint: two real panes in an `HStack`/`VStack` want `.split`; content-plus-controls in a `ZStack` wants `.overlay`. If selection in one pane *drives* the other, that is navigation — use `NavigationSplitView` instead.

## Split

```swift
@available(iOS 27.1, *)
struct PlayerScreen: View {
    var body: some View {
        NavigationStack {
            ArrangementView {
                PlayerView()
                    .splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)
            } secondary: {
                QueueView()
                    .splitArrangementLayoutSize(minWidth: 360)
            }
            .arrangementViewStyle(.split.axes(.horizontal))
        }
    }
}
```

- `.split` with no `axes` splits horizontally when the container is wider than tall and vertically when taller than wide.
- `.split.axes(.horizontal)` restricts it. **When the split can't happen on an allowed axis, only the primary is shown** — the secondary is not stacked below, it is gone. (Apple states this in Tech Talk 111463.) So with a horizontal-only split you must either not be in the arrangement on a tall container, or accept a primary-only screen there.

A robust entry condition for a horizontal-only, two-pane screen:

```swift
private var usesPanes: Bool {
    horizontalSizeClass == .regular                                  // Apple's axis: size class
        && verticalSizeClass == .regular                             // not a Max iPhone in landscape
        && viewport.width > viewport.height                          // the split's own rule
        && viewport.width >= Self.primaryMin + Self.secondaryMin     // room for both floors
}

var body: some View {
    ZStack {
        Color.clear.onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        if #available(iOS 27.1, *), usesPanes {
            ArrangementView { … } secondary: { … }
                .arrangementViewStyle(.split.axes(.horizontal))
        } else {
            singleColumn        // today's layout, unchanged
        }
    }
}
```

`if #available(iOS 27.1, *), usesPanes` is valid Swift. On iPhone Duo this condition is true for the inner display in landscape (flat or folded) and false for the outer display and for the inner display in portrait. It is also true on an iPad in landscape — usually what you want, but a behaviour change worth telling the user about.

**Why the vertical size class is in there.** Plus and Max iPhones have been *regular width, compact height* in landscape for a decade. "Regular width and wider than tall" is true for them too, so without the vertical check a two-pane layout designed for a 669-point-tall display appears on a 440-point-tall one — a regression on shipping devices, introduced by Duo work, that nobody tests because nobody rotates the phone. iPhone Duo's inner display is regular in both directions; no other iPhone is.

Using the container's aspect ratio here is not the "branching on orientation" anti-pattern: it is the same rule the split style itself applies, evaluated on the *container*, and it stays correct in Split View multitasking where device orientation says nothing.

## Pane sizing: the part everyone gets wrong

The sizing modifiers are `View` modifiers that **a pane applies to itself** — the same idea as `navigationSplitViewColumnWidth`:

```swift
ArrangementView {
    Primary().splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)   // ✓ on the pane
} secondary: {
    Secondary().splitArrangementLayoutSize(minWidth: 360)                                  // ✓ on the pane
}
.arrangementViewStyle(.split)
// .splitArrangementLayoutRatio(0.4)   ✗ here it compiles, does nothing, and the split stays 50/50
```

| Modifier | Use it when |
|---|---|
| `splitArrangementLayoutSize(min/ideal/maxWidth:, min/ideal/maxHeight:)` | The pane holds something of a fixed physical size — a cover, a player, a form. A ratio makes such a pane absurd on a large screen: built around one book cover, a 0.42 ratio took 574 points of a 1366-point tablet. |
| `splitArrangementLayoutRatio(_:)` and the `min/ideal/max` × `Horizontal/Vertical` form | Both panes scale naturally with the screen (two text columns, map + list). |
| `splitArrangementFixedLayoutSize(horizontal:vertical:)` | The pane should take its content's own size on that axis. |

**Give every pane a `minWidth` (and a `minHeight` if it can stack).** A pane without a floor is a pane the system may squeeze to nothing in order to satisfy the other pane's preference.

## Measured behaviour

Inner display, landscape, content area 867 × 611 points; primary `min 280 / ideal 330 / max 440`.

| Configuration | Flat | Half-folded (hinge band x 455.5…495.5) |
|---|---|---|
| Preference on the *container* (`.splitArrangementLayoutRatio(0.42)`) | 433.5 / 433.5 — ignored | — |
| Preference on the primary **only** | 330 / 537 ✓ | primary 330, secondary **≈ 145**, both left of the hinge, right half blank ✗ |
| Primary preference **+ `minWidth: 360` on the secondary** | 330 / 537 ✓ | primary **455.5**, secondary **371.3** — one pane per half, hinge clear ✓ |

Three things to take from that table:

1. The floor on the secondary is what makes folding work. At 145 points a list's heading wrapped to three lines, a stat line stacked one character per row, a search field collapsed to its icon and filter chips to single letters.
2. The fold **overrides `maxWidth`**: the primary took 455.5 although capped at 440. That is correct behaviour; there is no need to withdraw size preferences when folded.
3. The re-layout is **live**. In one log the division region went inactive → active and the secondary went 537 → 371 without any code observing the hinge.

## Overlay

```swift
ArrangementView {
    ReaderControls()
        .overlayArrangementEdge(VerticalEdge.bottom)     // spell out the type: there are two overloads
} secondary: {
    PageView()
}
.arrangementViewStyle(.overlay)
```

- With no active division the primary is layered over the secondary.
- Partially folded, the primary goes to the trailing/bottom side of the fold and the secondary to the leading/top side. For a book-like pose that puts a page on one side and its controls on the other; on a table-top pose, content on the upright half and controls on the half lying flat, where they are easy to tap.
- The primary can adapt to which situation it is in — see the next section.

## Reading the arrangement from inside a pane

```swift
@Environment(\.overlayArrangementZIndex) private var zIndex      // > 0: layered over the other pane
@Environment(\.splitArrangementAxis) private var splitAxis       // .horizontal / .vertical / nil

var body: some View {
    HStack {
        Button("Previous", systemImage: "chevron.left") { }
        if zIndex == 0 { Text(chapterTitle) }        // side by side now: room to say more
        Button("Next", systemImage: "chevron.right") { }
    }
}
```

Use these to change *density* — collapse a list to a strip while it is layered, expand it when it has a half to itself. Don't use them to add or remove functionality.

## UIKit

```swift
let arrangement = UIArrangementViewController()
arrangement.setViewController(PlayerViewController(), for: .primary)
arrangement.setViewController(QueueViewController(), for: .secondary)

var split = UISplitArrangement.split.axes(.horizontal)

var primary = split.defaultViewProperties
primary.width.minimum   = .absolute(280)
primary.width.preferred = .absolute(330)
primary.width.maximum   = .absolute(440)
split.setViewProperties(primary, for: .primary)

var secondary = split.defaultViewProperties
secondary.width.minimum = .absolute(360)              // the floor that keeps folding sane
split.setViewProperties(secondary, for: .secondary)

arrangement.updateArrangement(split)                  // (_, animated: true) to animate a change

let root = UINavigationController(rootViewController: arrangement)   // navigation around it
```

`UISplitArrangement.Dimension` offers `.automatic`, `.intrinsic`, `.fractional(_:)` and `.absolute(_:)`. `UIOverlayArrangement.overlay` is the layered style; its view properties carry an `edge`. Ask `arrangement.state(for: .primary)` for `zIndex`, `splitAxis` and `isHidden` to adapt density.

## Migration recipe

From a single scrolling column with a hero on top (the most common phone layout) to two panes on wide containers:

1. **Extract** the hero and the rest into two functions/properties that both layouts can call. The single-column path must stay byte-for-byte what it was — verify that on a phone-width display before going further.
2. **Add the entry condition** above and an `ArrangementView` behind `#available`.
3. **Give the hero a "pane" mode.** What changes in a pane as tall as the screen:
   - drop any height cap that was a percentage of the viewport;
   - *centre* the content vertically — hung from the top it leaves the same empty stretch the hero was meant to avoid, just rotated;
   - let the key visual grow with the pane, within a cap;
   - if the hero faded into the page at its bottom edge, give it the same fade on its **trailing** edge so there is no seam between the panes.
4. **Safe areas per pane.** Let the hero pane `ignoresSafeArea()` so its background runs to the edges (put the content back inside yourself), and leave the scrolling pane inside the safe area so its first row isn't under the bars.
5. **Re-measure anything computed from width** in the narrower pane: grid column counts, truncation, caps.
6. **Floors on both panes**, then test flat *and* half-folded.

## When not to use one

- Inside a `ScrollView`, `List` or `NavigationSplitView` column — parts can become unreachable.
- Around navigation: no `NavigationStack`/`NavigationSplitView`/`TabView` *inside* a pane.
- For more than two regions. Nesting arrangements is not a substitute for a real multi-column design.
- When one column of scrolling content is the honest design. Cap its width and let it scroll through the fold.
