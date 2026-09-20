# Vertical bars

On iPhone Duo the toolbar, tab bar and navigation controls share one vertical strip with the status bar and the Dynamic Island. It preserves vertical space on a display that is short, and keeps controls under the thumb. Standard components do this by themselves; your job is to give the system items it can lay out vertically, and to say which ones matter when space runs out.

**Contents:** [Where](#where-bars-are-vertical) · [Getting them](#getting-vertical-bars) · [Item anatomy](#what-an-item-needs) · [Order](#order-on-the-vertical-axis) · [Overflow](#overflow-and-priority) · [Tab bar vs toolbar](#when-space-runs-out-tab-bar-or-toolbar) · [Custom views](#custom-views-in-a-bar) · [Opting out](#opting-out) · [Content beside the bar](#content-beside-the-bar) · [Sheets](#sheets) · [Tab bar as sidebar](#tab-bar-as-a-sidebar) · [A measured nuance](#a-measured-nuance-principal-items)

## Where bars are vertical

| Context | Bars |
|---|---|
| Outer display | **vertical**, trailing edge |
| Inner display, landscape | **vertical**, trailing edge (measured: 84-point trailing inset) |
| Inner display, portrait | horizontal — there is vertical room to spare (measured insets: top 82, bottom 83) |
| Split View multitasking | vertical, on each app's **outer** edge — the left-hand app's bar is on the *leading* side |
| `NavigationSplitView`: sidebar and content columns | horizontal |
| `NavigationSplitView`: detail column | vertical |
| Inspectors | horizontal |
| Sheet, outer display | vertical by default |
| Sheet, inner display, centred or leading | horizontal |
| Sheet, inner display, trailing (`presentationPlacement(.trailing)`) | vertical |

In right-to-left languages the bar stays on the same physical side of the device and content adapts around it (Tech Talk 111462).

## Getting vertical bars

1. Build with the iOS 27.1 SDK.
2. Declare items through system containers:

```swift
NavigationStack {
    Content()
        .toolbar {
            ToolbarItem(placement: .bottomBar) { Button("Filter", systemImage: "line.3.horizontal.decrease") { } }
        }
}
```

In UIKit, set items on a view controller inside `UINavigationController` / `UITabBarController`. Items in a hand-instantiated `UIToolbar`, `UINavigationBar` or `UITabBar` are **not considered** — they stay where you put them, which on this device can be under the camera. A hidden navigation bar with hand-drawn chrome has the same problem; on a root tab that is tolerable, on a pushed screen prefer the real bar kept transparent.

## What an item needs

A vertical bar has **fixed width and flexible height** — the inverse of a horizontal bar. It suits symbols.

| Presentation | Symbol | Title |
|---|---|---|
| Vertical bar | required | ignored |
| Horizontal bar | preferred | used if there is no symbol |
| Overflow menu | used | used |

So give every item both: `Button("Compose", systemImage: "square.and.pencil") { }`, `Label`, or a `UIBarButtonItem` with `title` and `image`. **Title-only items and custom-view items do not present vertically.**

Mixed text-and-symbol items (an inbox icon with "7") become symbol-only with a badge: `.badge(7)` / `item.badge = .count(7)`. Ask whether the text merely reinforces the symbol (drop it) or carries information on its own, like a cart total (keep the item horizontal).

## Order on the vertical axis

Top to bottom: **primary navigation** (Back, Close) → **prominent actions** (Done) → everything else in its groups; bottom-bar items sit at the bottom, above the tab bar. The system adds Back itself.

| Role | SwiftUI placement | UIKit |
|---|---|---|
| Custom Back / Close | `.cancellationAction` | `navigationItem.leadingItemGroups` (+ `leftItemsSupplementBackButton = false`) |
| Done and friends | `.topBarPinnedTrailing` | `navigationItem.pinnedTrailingGroup` |
| Related actions | `ToolbarItemGroup` | `UIBarButtonItemGroup` |

Group related items instead of inserting spacers: groups get automatic spacing that adapts as space changes. In a vertical bar a flexible spacer collapses to zero; a fixed spacer keeps its minimum size.

## Overflow and priority

Items overflow **from the bottom up** into a system overflow menu. Change the order:

```swift
ToolbarItemGroup(placement: .topBarTrailing) { … }.visibilityPriority(.high)   // last to go
ToolbarItem { … }.visibilityPriority(.low)                                     // first to go
```

- Prioritise whole groups first, then items within a group.
- Keep visible longest: the action people use most (Compose, New Note), and anything that conveys **status** — a badge is useless inside a menu.
- Put your own "more" actions into the system menu rather than keeping a second ellipsis button: `ToolbarOverflowMenu { … }` / `navigationItem.additionalOverflowItems`. Reserve the ellipsis symbol for overflow; give other menus a different symbol.

## When space runs out: tab bar or toolbar?

```swift
.toolbarVerticalCompressionBehavior(.prefersTabBar)        // keep destinations, overflow the actions
.toolbarVerticalCompressionBehavior(.prefersToolbarItems)  // keep the actions, minimise the tab bar
```

| App | Choose | Why |
|---|---|---|
| Navigation-focused (most apps) | `.automatic` / `.prefersTabBar` | People must always be able to change destination. This is the iOS default. |
| Task-focused screen (an editor, a game, a camera) | `.prefersToolbarItems` | The actions *are* the screen; the tab bar minimises as it does elsewhere on iPhone. |

UIKit: `navigationItem.verticalBarCompressionBehavior = .prefersBarItems` / `.prefersTabBar`. (The UIKit header documents `.automatic` as "prefers the tab bar" on iOS. Some summaries of the Tech Talk state the opposite.)

## Custom views in a bar

A custom view must either fit the bar's fixed width or have a vertical form. Detect the situation:

```swift
@Environment(\.toolbarVerticalEdge) private var verticalEdge     // .leading / .trailing / nil

var body: some View {
    if verticalEdge != nil { Image(systemName: "person.crop.circle") }
    else { Label("Profile", systemImage: "person.crop.circle") }
}
```

then opt the item in with `.axisBehavior(.verticalPreferred)`. UIKit: `traitCollection.verticalBarEdge`, observed with `registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { … }` (not the deprecated `traitCollectionDidChange`), and `item.axisBehavior = .verticalPreferred`.

Keep items horizontal with `.axisBehavior(.horizontalOnly)` when they switch between a symbol and text (Select ⇄ Done), and keep related items on the same axis.

There is no scroll-edge effect behind a vertical bar by default; a background appears with Reduce Transparency. Make sure content beside it stays legible.

## Opting out

```swift
.toolbarVerticalBehavior(.disabled)
// UIKit: override var preferredVerticalBarBehavior: UIVerticalBarBehavior { .disabled }
```

Apple's guidance is *in general, don't*: the side position is the platform pattern people learn once. Legitimate cases are full-width, bottom-heavy, non-scrolling interfaces (Calculator) and control-heavy sheets whose only bar item is Close.

## Content beside the bar

Controls on one edge make the content area asymmetric.

- **Inset foreground** content with the safe area — most layouts get this free. Centre within the safe area, not the screen. Remember the bar can be on the leading side.
- **Extend backgrounds** under the bar: a hero image, a map, a colour field. `backgroundExtensionEffect()` (SwiftUI) or `UIBackgroundExtensionView` (UIKit), both iOS 26, mirror and blur imagery outward so there is no hard edge at the bar.
- A mixed approach works well: full-width header or background, scrolling content inset.
- Put controls near the content they affect. In a split view, actions for the list belong above the list column, not in the trailing bar.

## Sheets

- Outer display: a sheet's bar is vertical by default. For a sheet with a single Close button, disabling the vertical bar keeps the familiar look; the sheet then stops short of the camera and the status bar repositions.
- Inner display: bars are horizontal unless the sheet is placed at the trailing edge with `presentationPlacement(.trailing)`.
- Half-folded, sheets slide aside to avoid resting on the fold. You don't implement that.

## Tab bar as a sidebar

```swift
TabView { … }.defaultTabBarPlacement(.sidebar)          // 27.0
// UIKit: tabBarController.sidebar.preferredPlacement = .sidebar
```

Worth it for information-dense apps with many destinations (Apple's example is Health). With four or five tabs the default — the tab bar at the bottom of the vertical bar — is better: it is what people expect and it costs no content width.

## A measured nuance: `.principal` items

A text-only `.principal` item (a small-caps eyebrow used as a title) was A/B tested on the outer display with `.axisBehavior(.horizontalOnly)` against `.automatic`: **the screenshots were identical**. The system already keeps a principal item horizontal, at the top, while Back and the overflow button sit in the vertical bar.

So `.horizontalOnly` on a principal item is insurance, not a fix — `.automatic` means "the system decides", and it may decide differently where the bar is more crowded. If you add it, say so in a comment; don't report it as having fixed a visible bug.
