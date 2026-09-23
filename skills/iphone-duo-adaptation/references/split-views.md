# List → detail with NavigationSplitView

When selection in one pane drives the other, that is navigation, and `NavigationSplitView` is the container (`SKILL.md`, *Choosing a layout container*). On iPhone Duo it needs the same entry condition as an arrangement, and a few things behave differently from what iPad experience suggests.

Measured on the iPhone Duo simulator (Xcode 27.1 27A9269, iOS 27.1 runtime 24A94401) while adapting a production SwiftUI app, 2026-09-22. The second half, pushing inside the detail column, is not Duo-specific. It comes up as soon as a screen that used to be a sheet becomes a detail column, which is exactly what Duo work does.

**Contents:** [Where it shows two columns](#where-it-shows-two-columns) · [One container, not two](#one-container-not-two) · [Column widths](#column-widths-leave-them-alone) · [Rows in the list column](#rows-in-the-list-column) · [Pushing inside the detail column](#pushing-inside-the-detail-column) · [A hub instead of sheets](#a-hub-instead-of-sheets) · [Folding with something open](#folding-with-something-open)

## Where it shows two columns

| Display / pose | What `NavigationSplitView` did |
|---|---|
| Outer display (compact width) | collapsed to one stack, as on any iPhone |
| Inner display, landscape, flat | two columns; the list column about 320 points wide (read off a capture, not probed) |
| Inner display, landscape, half-folded | two columns snapped to the fold: the list on the leading half, the detail starting right of the hinge band. With default column widths only, see below |
| Inner display, portrait (669 × 951, regular / regular) | **not** two columns. The list hid behind a sidebar button; with `columnVisibility: .constant(.all)` it was laid *over* the detail instead of beside it |

Portrait is the surprise: regular width in both directions, and still no room for the list beside the detail. Someone opening the schedule sees one event instead of the programme. So show two columns only on the same condition as a horizontal arrangement (regular in **both** size classes, and wider than tall), and one column with the detail pushed everywhere else.

The vertical size class is there for the same reason as in an arrangement: a Plus/Max iPhone in landscape is regular width but compact height. The condition also changes iPad. In portrait an iPad now gets one column, where `NavigationSplitView` alone would have shown its overlay sidebar. Tell the user.

Highlight the selected row, and preselect a detail, **only while both columns are on screen**. On the stack, a highlighted row marks a detail nobody can see.

## One container, not two

The obvious way to get one column is an `if`: `NavigationSplitView` when two fit, `NavigationStack` with a pushed detail otherwise. **Don't.** Rotating or folding flips the branch, SwiftUI builds both columns anew, and everything they had open goes: every sheet and full-screen cover presented from the list or the detail closed, unsaved edits included (measured with an edit sheet: open, change a value, rotate, gone). An iPad rotating would flip the same branch (same condition; not measured on an iPad).

Keep one `NavigationSplitView` and tell it the width is compact where one column should show. It then collapses into a stack exactly as it does on iPhone, and nothing is rebuilt. Hand the columns the real size class back so their content lays out as before:

```swift
struct ListDetailSplit<ListContent: View, DetailContent: View>: View {
    @Binding var showsDetail: Bool                      // set together with the selection
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var detail: () -> DetailContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isWiderThanTall = false

    private var showsBothColumns: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular && isWiderThanTall
    }

    var body: some View {
        NavigationSplitView(
            columnVisibility: .constant(.all),
            preferredCompactColumn: Binding(
                get: { showsDetail ? .detail : .sidebar },
                set: { showsDetail = $0 == .detail }
            )
        ) {
            list()
                .toolbar(removing: .sidebarToggle)
                .environment(\.horizontalSizeClass, horizontalSizeClass)
        } detail: {
            detail()
                .environment(\.horizontalSizeClass, horizontalSizeClass)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.horizontalSizeClass, showsBothColumns ? horizontalSizeClass : .compact)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWiderThanTall = $0 }
        // Folding: see below
        .onChange(of: horizontalSizeClass) { old, new in
            guard old == .regular, new == .compact, showsDetail else { return }
            showsDetail = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                showsDetail = true
            }
        }
    }
}
```

Measured with this container on the Duo: an edit sheet with an unsaved change survived rotating both ways and folding; a full-screen photo viewer opened from the detail survived unfolding, the book pose and folding, still on the same photo; scroll positions survived. On an iPhone 17 Pro (iOS 27.0) it was a plain stack: large title, search on pull-down, push, back button, edge swipe back.

Three things the single container needed:

- **Folding lost the back button.** Rotating goes through the override above; folding changes the *display's* size class, and UIKit collapses the split itself. An open detail then came up as the stack's root, with no way back to the list short of tapping the tab again. Showing the list and pushing the detail again on that change (the `onChange` above) restores the back button; a sheet presented from the detail stayed open through it. The 50 ms are a pause between two navigation updates, not a tuned value.
- **Keep the detail column's container constant.** A detail that is sometimes a `NavigationStack` and sometimes a placeholder without one (nothing selected) is its own branch. Launched on the outer display and then unfolded, the empty column had no stack, and the *list's* toolbar item showed up a second time in the detail's vertical bar. Wrap the placeholder in the same stack as the content.
- **`.searchable` in a column can land in the wrong bar.** A screen in the detail column carrying `.searchable`, preselected while two columns showed, lost its search after folding: the search button replaced the list's toolbar item on the outer display instead. Screens shown in a hub's detail column draw their own search field in the content; keep `.searchable` for where they are a sheet of their own.

## Column widths: leave them alone

With `navigationSplitViewColumnWidth` set on the list, the columns **stopped snapping to the fold** in the half-folded pose, and the detail's content ran onto the hinge band. With default widths they snapped. If rows feel cramped in the ~320-point column, give the rows a narrow form rather than widening the column.

## Rows in the list column

Rows designed for a 402-point iPhone get about 320 points in the flat split. Measured in the list column:

- A `Label` in a row rendered its **icon only**. Use `HStack { Image(systemName:); Text() }` where the words matter.
- `.listRowInsets` leading and trailing values **had no effect**. Pad the row's content instead.
- Anything that sat side by side at phone width (a name next to a status badge and a count) needs a stacked form below ~330 points. Measure the row with `onGeometryChange`; the size class is regular here and says nothing about the column.

## Pushing inside the detail column

A feature that was a sheet with its own `NavigationStack` often pushes a second level (photos → review). In the detail column it keeps a stack for that. Two things went wrong there, and neither is visible until someone changes the selection.

**1. The detail column keeps what was pushed, whatever the root is now.** Measured with a photos screen that had pushed its review screen, then a different row selected in the list:

| Detail column setup | After selecting another row |
|---|---|
| `NavigationStack { root(for: selection) }.id(selection)`, push by `NavigationLink { Review() }` | review screen still on top of the new root ✗ |
| Push by `navigationDestination(isPresented:)` owned by the photos screen, which is gone after the switch | review screen still on top ✗ |
| `NavigationStack(path: $detailPath)`, push by `NavigationLink(value:)`, `detailPath` emptied when the selection changes | popped; reopening photos starts at its root ✓ |

Only emptying a path pops it. So the detail column needs a path, reset on every selection change, and the screens inside it must push **by value** so the pushes land in that path.

**2. A value link does nothing inside an `isPresented` push.** With the container swap that [One container, not two](#one-container-not-two) warns against, the detail was pushed on a separate `NavigationStack` with `navigationDestination(isPresented:)`. Inside a screen pushed that way, a `NavigationLink(value:)` with its `navigationDestination(for:)` declared in the same screen **did nothing**, and nothing appeared in the log. With the single container the detail column keeps its own path-bound stack in both layouts, and value links inside it worked collapsed and expanded (measured on the outer display and the inner one). A screen that is *also* shown elsewhere, as a sheet or in a tab of its own, still needs to know which kind of push works there. Let the host say:

```swift
extension EnvironmentValues {
    /// Set by a host whose stack is bound to a path it resets
    @Entry var pushesByValue = false
}

struct Hub: View {
    @State private var selection: HubDestination? = .photos
    @State private var detailPath = NavigationPath()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Text("Photos").tag(HubDestination.photos)
                Text("Notes").tag(HubDestination.notes)
            }
        } detail: {
            NavigationStack(path: $detailPath) {
                switch selection {
                case .photos: PhotosScreen()
                case .notes: NotesScreen()
                case nil: Text("Select a section")
                }
            }
            .environment(\.pushesByValue, true)
        }
        .onChange(of: selection) { detailPath = NavigationPath() }
    }
}

struct PhotosScreen: View {
    @Environment(\.pushesByValue) private var pushesByValue

    var body: some View {
        let list = List {
            if pushesByValue {
                NavigationLink("Review", value: PhotoRoute.review)
            } else {
                NavigationLink("Review") { ReviewScreen() }
            }
        }
        if pushesByValue {
            list.navigationDestination(for: PhotoRoute.self) { _ in ReviewScreen() }
        } else {
            list
        }
    }
}
```

**Don't fix (2) by pushing the detail by value on the stack as well.** It was tried: the list registered `navigationDestination(for:)` and the stack's path mirrored `showsDetail`. Details whose content comes from the parent's `@State` (`if let event = selectedEvent { EventDetail(event) } else { placeholder }`) then opened on their **placeholder**, although the selection had been set together with the push. If you do go value-based on the stack, build the destination from the pushed value, not from the parent's state.

## A hub instead of sheets

A dashboard whose quick actions open features in sheets (RSVPs, messages, photos) makes a natural sidebar. The features open beside it on the inner display, and on the stack they push instead of presenting. On a regular iPhone that turns a sheet into a push, so agree on it first.

- Keep modal what is modal by nature: a settings flow with its own navigation path, an editor that asks about unsaved changes before closing, a paywall.
- A screen that is sometimes a sheet and sometimes a detail owns a `NavigationStack` only as a sheet. Inside the hub a second stack would nest. Its Close button goes the same way:

  ```swift
  extension View {
      @ViewBuilder
      func inOwnNavigationStack(_ ownsNavigation: Bool) -> some View {
          if ownsNavigation { NavigationStack { self } } else { self }
      }
  }
  ```

- Preselect the first feature when the split appears, so the detail column is never empty, **without** setting the push flag. Otherwise folding the device pushes a feature the person never opened.
- Mark the open feature in the dashboard only while both columns are visible.

## Folding with something open

Observed with the hub above, in the single container:

- **Split → stack** (closing the device): if the push flag was set with the selection, the feature comes back pushed on the outer display, with a back button to the dashboard. What the feature pushed itself in the detail column (the review screen) follows it, because it is the same stack. Anything it presented stays open.
- **Stack → split** (opening it): the feature shows in the detail column, still at the level it was at, and anything it presented stays open.

With a `NavigationSplitView`/`NavigationStack` swap instead, every level below the feature and every presentation was lost in both directions.
