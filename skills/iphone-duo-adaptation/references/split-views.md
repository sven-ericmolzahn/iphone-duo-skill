# List → detail with NavigationSplitView

When selection in one pane drives the other, that is navigation, and `NavigationSplitView` is the container (`SKILL.md`, *Choosing a layout container*). On iPhone Duo it needs the same entry condition as an arrangement, and a few things behave differently from what iPad experience suggests.

Measured on the iPhone Duo simulator (Xcode 27.1 27A9269, iOS 27.1 runtime 24A94401) while adapting a production SwiftUI app, 2026-09-22. The second half, pushing inside the detail column, is not Duo-specific. It comes up as soon as a screen that used to be a sheet becomes a detail column, which is exactly what Duo work does.

**Contents:** [Where it shows two columns](#where-it-shows-two-columns) · [Column widths](#column-widths-leave-them-alone) · [Rows in the list column](#rows-in-the-list-column) · [Pushing inside the detail column](#pushing-inside-the-detail-column) · [A hub instead of sheets](#a-hub-instead-of-sheets) · [Folding with something open](#folding-with-something-open)

## Where it shows two columns

| Display / pose | What `NavigationSplitView` did |
|---|---|
| Outer display (compact width) | collapsed to one stack, as on any iPhone |
| Inner display, landscape, flat | two columns; the list column about 320 points wide (read off a capture, not probed) |
| Inner display, landscape, half-folded | two columns snapped to the fold: the list on the leading half, the detail starting right of the hinge band. With default column widths only, see below |
| Inner display, portrait (669 × 951, regular / regular) | **not** two columns. The list hid behind a sidebar button; with `columnVisibility: .constant(.all)` it was laid *over* the detail instead of beside it |

Portrait is the surprise: regular width in both directions, and still no room for the list beside the detail. Someone opening the schedule sees one event instead of the programme. So enter the split on the same condition as a horizontal arrangement (regular in **both** size classes, and wider than tall), and push the detail onto a plain stack everywhere else:

```swift
struct ListDetailSplit<ListContent: View, DetailContent: View>: View {
    @Binding var showsDetail: Bool                      // set together with the selection
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var detail: () -> DetailContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isWiderThanTall = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular, verticalSizeClass == .regular, isWiderThanTall {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    list().toolbar(removing: .sidebarToggle)
                } detail: {
                    detail()
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    list().navigationDestination(isPresented: $showsDetail) { detail() }
                }
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isWiderThanTall = $0 }
    }
}
```

The vertical size class is there for the same reason as in an arrangement: a Plus/Max iPhone in landscape is regular width but compact height. The condition also changes iPad. In portrait an iPad now gets the stack, where `NavigationSplitView` alone would have shown its overlay sidebar. Tell the user.

Highlight the selected row, and preselect a detail, **only while both columns are on screen**. On the stack, a highlighted row marks a detail nobody can see.

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

**2. A value link does nothing inside an `isPresented` push.** The same screen is also pushed on the stack (outer display, iPhone), usually with `navigationDestination(isPresented:)` as in the sample above. Inside a screen pushed that way, a `NavigationLink(value:)` with its `navigationDestination(for:)` declared in the same screen **did nothing**, and nothing appeared in the log. So a screen that lives in both places has to push by value in the detail column and push the view on the stack. Let the host say which:

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

Observed with the hub above:

- **Split → stack** (closing the device): if the push flag was set with the selection, the feature comes back pushed on the outer display, with a back button to the dashboard.
- **Stack → split** (opening it): what the feature had pushed itself (the review screen) is gone; the detail column shows the feature at its root. The split's detail stack and the phone stack are different stacks. Restore the second level from state if losing it matters.
