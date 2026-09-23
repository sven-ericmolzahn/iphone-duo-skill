# Arrangement views

An arrangement view holds exactly two views — a **primary** and a **secondary** — and decides where each goes from three inputs: the size classes, the container's aspect ratio, and the active reserved regions (the fold). You describe the relationship; the system does the geometry, including the geometry you would get wrong: snapping the panes to the two halves of a half-folded display and re-laying out live as the hinge moves.

It sits *between* navigation containers (`NavigationStack`, `NavigationSplitView`, `TabView`) and content containers (`List`, `ScrollView`):

```
NavigationStack            ← navigation, outside
└─ ArrangementView         ← layout
   ├─ primary   (may contain a ScrollView / List)
   └─ secondary (may contain a ScrollView / List)
```

**Contents:** [Which style](#which-style) · [Split](#split) · [Pane sizing](#pane-sizing-the-part-everyone-gets-wrong) · [Measured behaviour](#measured-behaviour) · [Backgrounds under the bar](#backgrounds-that-have-to-run-under-the-bar) · [Overlay](#overlay) · [Reading the arrangement from inside](#reading-the-arrangement-from-inside-a-pane) · [UIKit](#uikit) · [Migration recipe](#migration-recipe) · [When not to use one](#when-not-to-use-one)

## Which style

| Relationship | Style | Flat, wide | Flat, tall | Half-folded |
|---|---|---|---|---|
| Two peers, neither may be covered (player + queue, podcast + transcript, hero + shelf) | `.split` | side by side | stacked | one pane per half |
| Foreground over background (reading controls over a page, shutter over a viewfinder) | `.overlay` | primary layered over secondary | same | the two move to opposite sides of the fold |

Existing code is the best hint: two real panes in an `HStack`/`VStack` want `.split`; content-plus-controls in a `ZStack` wants `.overlay`. If selection in one pane *drives* the other, that is navigation — use `NavigationSplitView` instead, entered on the same condition as below (`split-views.md`).

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
private func usesPanes(in viewport: CGSize) -> Bool {
    horizontalSizeClass == .regular                                  // Apple's axis: size class
        && verticalSizeClass == .regular                             // not a Max iPhone in landscape
        && viewport.width > viewport.height                          // the split's own rule
        && viewport.width >= Self.primaryMin + Self.secondaryMin     // room for both floors
}

var body: some View {
    GeometryReader { proxy in
        if #available(iOS 27.1, *), usesPanes(in: proxy.size) {
            ArrangementView { … } secondary: { … }
                .arrangementViewStyle(.split.axes(.horizontal))
        } else {
            singleColumn        // today's layout, unchanged
        }
    }
}
```

Read the size inside a `GeometryReader`, not into `@State` through `onGeometryChange`. A measured `@State` starts at `.zero`, so the first evaluation always takes the single-column branch and the measurement then swaps the layout. The `GeometryReader` decides in the same pass that lays the screen out.

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
Re-runnable with [DuoProbe](https://github.com/sven-ericmolzahn/iphone-duo-probe), which is where the folded figures below come from.

| Configuration | Flat | Half-folded (hinge band x 455.5…495.5) |
|---|---|---|
| Preference on the *container* (`.splitArrangementLayoutRatio(0.42)`) | 433.5 / 433.5 — ignored | — |
| `min/ideal/max` on the primary **only** | 330 / 537 ✓ | primary 330, secondary **126**, both left of the hinge, right half blank ✗ |
| Bare `minWidth: 240` on the primary only | 434 / 434 ✓ | primary **456**, secondary **372** ✓ |
| Primary `min/ideal/max` **+ `minWidth` on the secondary** | 330 / 537 ✓ | primary **456**, secondary **372** — one pane per half, hinge clear ✓ |
| `minWidth: 400` on the primary (inside the 455.5 half) | ✓ | primary **456**, secondary **372** ✓ |
| `minWidth: 500` on the primary (beyond the half) | ✓ | **nothing renders** — both panes gone ✗ |

Four things to take from that table:

1. **The `idealWidth` is the trigger, not the missing floor.** A primary with only a `minWidth` shared the display correctly even with a floorless secondary. It is when the primary names an ideal width that it takes that width, hands the remainder to the secondary, and the pair ends up inside one half. So the rule is conditional: once a pane declares an ideal, give its partner a floor.
2. **A floor that cannot fit a half deletes the arrangement.** At `minWidth: 500` against a 455.5-point half, both panes vanished — not primary-only, not clamped, not logged. `400` was fine. The flat container is 867 points wide, so this passes every test until someone folds the device. Budget floors against the half.
3. The fold **overrides `maxWidth`**: the primary took 456 although capped at 440. That is correct behaviour; there is no need to withdraw size preferences when folded.
4. The re-layout is **live**. In one log the division region went inactive → active and the panes re-flowed without any code observing the hinge.

## Backgrounds that have to run under the bar

The arrangement hands each pane a rectangle, and a pane's edges are the *arrangement's* — on the inner display in landscape the trailing pane stops where the vertical bar starts. Measured with the arrangement inside the safe area: a hero pane 330 points wide ending at x = 867, the bar occupying 867…951, and the pane's own `safeAreaInsets` all zero. The pane does not know the bar is there.

So a full-bleed background that has to run under the bar cannot be drawn inside the pane:

- `.ignoresSafeArea()` on the pane's content grows the scene past its own bounds, but not towards the screen edge: it grows over the **neighbouring** pane, and everything laid out inside moves with it. The symptom in the app this was measured in was the first ~20 points of every line of text sheared off at a hard vertical line.
- `.offset(x:)` to push it back takes the same width off the other side.

Draw it as a plain sibling *behind* the whole arrangement instead, and keep only content in the panes:

```swift
ZStack {
    GeometryReader { screen in                       // spans the screen: nothing clips a ZStack sibling
        HeroRoom()
            .frame(width: max(screen.size.width - heroPaneMinX, 1))
            .offset(x: heroPaneMinX)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)

    ArrangementView {
        Shelf()
            .splitArrangementLayoutSize(minWidth: 360)
    } secondary: {
        Hero(drawsRoom: false)                       // the book and the words only
            .ignoresSafeArea(.container, edges: .vertical)      // vertical is safe: no neighbour that way
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { heroPaneMinX = $0 }
            .splitArrangementLayoutSize(minWidth: 300, idealWidth: 330, maxWidth: 440)
    }
    .arrangementViewStyle(.split.axes(.horizontal))
}
```

The pane reports upward where it begins — and, if the background is anchored to the words, where those begin — and the sibling draws from there to the screen edge.

`backgroundExtensionEffect()` is the system's answer to the same problem and does reach under the bar, applied **to the pane**; applied to the image inside the pane it did nothing. It mirrors the view's edge pixels outward, which suits a photograph or a colour field and not a blurred backdrop, where the mirror axis is plainly visible as a seam.

**An open observation, not a recommendation.** `.ignoresSafeArea(.container, edges: .horizontal)` on the `ArrangementView` *itself* does widen the split to the whole screen — measured, the trailing pane then ran from x 621 to 951, flush with the screen edge. But the content inset that pane's own content needed then rendered wrong: the scene measured in the right place (`frame(in: .global)` = the pane, its content block at x = 20, width 206) and *drew* shifted left, clipped. A paging `TabView` inside the pane is the suspect; that was not proved. Unless you want to chase it, the sibling above is the cheaper answer.

## Choosing the container from the device

A recurring suggestion is to branch on whether the device folds — arrangement if it does, `NavigationSplitView` if it does not — so that "on the outer display it behaves like a normal iPhone". Measured on an iPhone Duo (iPhone19,4), it does not.

There is no foldable API: `fold`, `foldable` and `folding` do not occur in the 27.1 UIKit headers or the SwiftUI / SwiftUICore interfaces, so the test is a hard-coded model list, and therefore a **constant**. It stays true while the outer display is showing, so the arrangement applies there too:

| Outer display, closed (content 382 × 584, compact/regular) | Result |
|---|---|
| Branch on the device | primary 382 × 292 **stacked above** secondary 382 × 292 |
| Branch on the display's reserved regions | one column 382 × 574 with a back button |

**The outer display reports no division region at all, even with `.includeInactive`.** That is the honest signal, and it is per display rather than per device. Two caveats before reaching for it:

- It is empty on the **first** geometry evaluation and populated on a later one. A container chosen from `reservedRegions` therefore swaps after the first frame, visibly, on every launch. Choose layout from size classes and container size; use reserved regions to position content.
- On the Duo the device test is always true, so it changes nothing there — it only swaps in a different container on every *other* iPhone, which means two layouts to maintain for no gain in the pose it was meant to improve.

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
   - don't make a `.fill` image the pane itself. As a pane's content, `Image(…).resizable().aspectRatio(contentMode: .fill)` sized the pane from the image and ran past the pane's edges. Put it in an overlay of something flexible, `Color.clear.overlay { image }.clipped()`, so the pane decides the size and the image fills it;
   - drop any height cap that was a percentage of the viewport;
   - *centre* the content vertically — hung from the top it leaves the same empty stretch the hero was meant to avoid, just rotated;
   - let the key visual grow with the pane, within a cap;
   - if the hero faded into the page at its bottom edge, give it the same fade on its **trailing** edge so there is no seam between the panes.
4. **Safe areas per pane.** A pane may ignore the safe area *vertically* — there is no neighbouring pane that way — so a hero can still run to the top and bottom edges (put the content back inside yourself). Horizontally it cannot: a background that has to pass under the vertical bar belongs behind the whole arrangement, see [Backgrounds that have to run under the bar](#backgrounds-that-have-to-run-under-the-bar). Leave the scrolling pane inside the safe area so its first row isn't under the bars.
5. **Re-measure anything computed from width** in the narrower pane: grid column counts, truncation, caps.
6. **Floors on both panes**, then test flat *and* half-folded.

## When not to use one

- Inside a `ScrollView`, `List` or `NavigationSplitView` column — parts can become unreachable.
- Around navigation: no `NavigationStack`/`NavigationSplitView`/`TabView` *inside* a pane.
- For more than two regions. Nesting arrangements is not a substitute for a real multi-column design.
- When one column of scrolling content is the honest design. Cap its width and let it scroll through the fold.
