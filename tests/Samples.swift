//
//  Samples.swift — every SwiftUI snippet in the skill, in compilable form.
//
//  Not an app. `tests/typecheck.sh` type-checks this against the installed
//  iOS SDK so that a snippet in the skill can never drift from the API that
//  actually ships. If a new Xcode seed renames something, this file fails
//  first — fix it here, then fix the prose.
//

import SwiftUI

// MARK: - Placeholders

struct PlayerView: View { var body: some View { Color.red } }
struct QueueView: View { var body: some View { List(0..<20, id: \.self) { Text("\($0)") } } }
struct PageView: View { var body: some View { ScrollView { Text("page") } } }
struct Banner: View { var body: some View { Text("banner") } }
struct Teleprompter: View { var body: some View { Text("script") } }
struct CameraView: View { var body: some View { Color.black } }

// MARK: - Arrangement: split, with a size preference on EACH pane

@available(iOS 27.1, *)
struct PlayerScreen: View {
    var body: some View {
        NavigationStack {                       // navigation OUTSIDE the arrangement
            ArrangementView {
                PlayerView()
                    // Preferences live on the pane, not on the ArrangementView.
                    .splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)
            } secondary: {
                QueueView()                     // a ScrollView/List INSIDE a pane is fine
                    // Every pane needs its own floor, or the fold squeezes it.
                    .splitArrangementLayoutSize(minWidth: 360)
            }
            .arrangementViewStyle(.split.axes(.horizontal))
        }
    }
}

// MARK: - Arrangement: availability-gated, with a single-column fallback

struct LibraryScreen: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let primaryMin: CGFloat = 280
    private static let secondaryMin: CGFloat = 360

    /// Regular in BOTH size classes (a Max iPhone in landscape is regular
    /// width, compact height), wider than tall, and wide enough for both floors.
    private func usesPanes(in viewport: CGSize) -> Bool {
        horizontalSizeClass == .regular
            && verticalSizeClass == .regular
            && viewport.width > viewport.height
            && viewport.width >= Self.primaryMin + Self.secondaryMin
    }

    var body: some View {
        // Decided in the pass that lays it out; a size measured into @State
        // starts at .zero, so its first evaluation always takes the fallback.
        GeometryReader { proxy in
            if #available(iOS 27.1, *), usesPanes(in: proxy.size) {
                ArrangementView {
                    PlayerView()
                        .splitArrangementLayoutSize(minWidth: Self.primaryMin, idealWidth: 330, maxWidth: 440)
                } secondary: {
                    QueueView()
                        .splitArrangementLayoutSize(minWidth: Self.secondaryMin)
                }
                .arrangementViewStyle(.split.axes(.horizontal))
            } else {
                ScrollView { VStack { PlayerView().frame(height: 300); QueueView().frame(height: 600) } }
            }
        }
    }
}

// MARK: - Arrangement: a filling image as a pane

@available(iOS 27.1, *)
struct CoverBesideForm: View {
    var body: some View {
        ArrangementView {
            // The image in an overlay of a flexible view: as the pane itself,
            // a .fill image sized the pane from the image and overflowed it.
            Color.clear
                .overlay { Image(systemName: "photo").resizable().scaledToFill() }
                .clipped()
                .splitArrangementLayoutSize(minWidth: 320)
        } secondary: {
            Form { Text("Names") }
                .splitArrangementLayoutSize(minWidth: 340)
        }
        .arrangementViewStyle(.split.axes(.horizontal))
    }
}

// MARK: - Arrangement: ratio and fixed-size preferences

@available(iOS 27.1, *)
struct RatioScreen: View {
    var body: some View {
        ArrangementView {
            PlayerView()
                .splitArrangementLayoutRatio(0.4)
        } secondary: {
            QueueView()
                .splitArrangementLayoutRatio(minHorizontal: 0.4, idealHorizontal: 0.6, maxHorizontal: 0.7)
                .splitArrangementFixedLayoutSize(horizontal: false, vertical: false)
        }
        .arrangementViewStyle(.split)           // both axes: side by side when wide, stacked when tall
    }
}

// MARK: - Arrangement: a full-bleed background behind the panes

@available(iOS 27.1, *)
struct HeroBesideShelf: View {
    @State private var heroPaneMinX: CGFloat = 0

    var body: some View {
        ZStack {
            // The background is a sibling of the arrangement, not a pane's own.
            // A pane's trailing edge is the arrangement's, so a background drawn
            // inside one cannot reach under the vertical bar: ignoring the safe
            // area there grows the scene over the neighbouring pane instead, and
            // the content laid out in it moves with it. Nothing clips a sibling.
            GeometryReader { screen in
                LinearGradient(colors: [.orange, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: max(screen.size.width - heroPaneMinX, 1))
                    .offset(x: heroPaneMinX)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ArrangementView {
                QueueView()
                    .splitArrangementLayoutSize(minWidth: 360)
            } secondary: {
                PlayerView()
                    // Vertical is safe: there is no neighbouring pane that way.
                    .ignoresSafeArea(.container, edges: .vertical)
                    // All the pane has to report is where it begins.
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { heroPaneMinX = $0 }
                    .splitArrangementLayoutSize(minWidth: 300, idealWidth: 330, maxWidth: 440)
            }
            .arrangementViewStyle(.split.axes(.horizontal))
        }
    }
}

// MARK: - Arrangement: overlay, and reading the arrangement from inside a pane

@available(iOS 27.1, *)
struct ReaderScreen: View {
    var body: some View {
        ArrangementView {
            ReaderControls()
                .overlayArrangementEdge(VerticalEdge.bottom)
        } secondary: {
            PageView()
        }
        .arrangementViewStyle(.overlay)
    }
}

@available(iOS 27.1, *)
struct ReaderControls: View {
    /// > 0 while this pane is layered over the other one; 0 once the fold has
    /// moved the panes side by side.
    @Environment(\.overlayArrangementZIndex) private var zIndex
    /// `.horizontal`, `.vertical`, or nil when not inside a split arrangement.
    @Environment(\.splitArrangementAxis) private var splitAxis

    var body: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left") { }
            if zIndex == 0 { Text("Chapter 3").font(.headline) }    // room to say more
            Button("Next", systemImage: "chevron.right") { }
        }
        .labelStyle(.iconOnly)
        .accessibilityHint(splitAxis == .horizontal ? "Side by side" : "Stacked")
    }
}

// MARK: - Reserved regions: keep custom-drawn content clear of the hinge

@available(iOS 27.1, *)
struct HingeAwareBanner: View {
    var body: some View {
        GeometryReader { proxy in
            // Active regions only: this is empty while the device is flat.
            // `frame` already includes the margins for interactive content.
            let hinge = proxy.reservedRegions(kind: .division).first
            let width = hinge.map { $0.frame.minX } ?? proxy.size.width
            Banner()
                .frame(width: max(width, 0), alignment: .leading)
        }
    }
}

@available(iOS 27.1, *)
struct FoldFriendlyGrid: View {
    let target: CGFloat = 165
    let spacing: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            // `.includeInactive` reports the hinge even while flat, so the
            // column count doesn't jump at the moment of folding.
            let hasHinge = !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            let fit = max(2, Int(((proxy.size.width + spacing) / (target + spacing)).rounded()))
            // HIG: prefer an even number of columns so content divides cleanly at the fold.
            let columns = hasHinge && !fit.isMultiple(of: 2) ? fit + 1 : fit
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)) {
                    ForEach(0..<40, id: \.self) { _ in Color.gray.aspectRatio(2 / 3, contentMode: .fit) }
                }
            }
        }
    }
}

@available(iOS 27.1, *)
struct CameraAwareBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let cameras = proxy.reservedRegions(kind: .occlusion, options: [], layoutDirectionBehavior: .fixed)
            let blocked = cameras.contains { $0.isActive && $0.frame.intersects(CGRect(x: 0, y: 0, width: 80, height: 80)) }
            Text("LIVE")
                .padding(.top, blocked ? 96 : 12)
        }
    }
}

// MARK: - Hinge: live interaction, not layout

@available(iOS 27.1, *)
struct TiltEffect: View {
    @State private var tilt: Double = 0

    var body: some View {
        PlayerView()
            .rotation3DEffect(.degrees(tilt), axis: (x: 0, y: 1, z: 0))
            .onHingeChange { _, context in
                // A nil hinge means the device doesn't have one.
                if let hinge = context.hinge, hinge.status == .partiallyOpen {
                    tilt = (180 - hinge.angle.degrees) / 12
                } else {
                    tilt = 0
                }
            }
    }
}

// MARK: - Vertical bars

@available(iOS 27.1, *)
struct MailboxScreen: View {
    var body: some View {
        NavigationStack {
            QueueView()
                .toolbar {
                    // Top of the vertical bar: primary navigation, then prominent actions.
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { }
                    }
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button("Done", systemImage: "checkmark") { }
                    }
                    // Title AND symbol on every item: the bar shows the symbol,
                    // the overflow menu shows both.
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Compose", systemImage: "square.and.pencil") { }
                        Button("Filter", systemImage: "line.3.horizontal.decrease") { }
                    }
                    .visibilityPriority(.high)          // last to overflow
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Archive All", systemImage: "archivebox") { }
                    }
                    .visibilityPriority(.low)           // first to overflow
                    // Text that carries meaning stays in a horizontal bar.
                    ToolbarItem(placement: .principal) {
                        Text("INBOX").font(.caption).tracking(1.5)
                    }
                    .axisBehavior(.horizontalOnly)
                    // One overflow menu: the system's.
                    ToolbarOverflowMenu {
                        Button("Export…", systemImage: "square.and.arrow.up") { }
                        Button("Settings", systemImage: "gearshape") { }
                    }
                }
                // Task-focused screen: keep the toolbar, let the tab bar minimise.
                .toolbarVerticalCompressionBehavior(.prefersToolbarItems)
        }
    }
}

@available(iOS 27.1, *)
struct CalculatorLikeScreen: View {
    var body: some View {
        NavigationStack {
            Color.orange
                .toolbar { ToolbarItem { Button("History", systemImage: "clock") { } } }
                // Opt out only for bottom-heavy, full-width, non-scrolling UI.
                .toolbarVerticalBehavior(.disabled)
        }
    }
}

@available(iOS 27.1, *)
struct CustomToolbarControl: View {
    /// `.leading` / `.trailing` while items can sit in a vertical bar; nil otherwise.
    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        if verticalEdge != nil {
            Image(systemName: "person.crop.circle")                 // fixed width, flexible height
        } else {
            Label("Profile", systemImage: "person.crop.circle")
        }
    }
}

@available(iOS 27.0, *)
struct Tabs: View {
    var body: some View {
        TabView {
            Tab("Library", systemImage: "books.vertical") { QueueView() }
            Tab("Feed", systemImage: "person.2") { PageView() }
        }
        // Only for information-dense apps; a handful of tabs is better left alone.
        .defaultTabBarPlacement(.sidebar)
    }
}

// MARK: - Badges instead of text beside a symbol

@available(iOS 26.0, *)
struct InboxToolbar: View {
    var body: some View {
        NavigationStack {
            QueueView().toolbar {
                ToolbarItem { Button("Inbox", systemImage: "tray") { } .badge(7) }
            }
        }
    }
}

/// A count that arrives after the item is shown: in a vertical bar the badge
/// alone did not update; changing the symbol with it makes the bar rebuild it.
@available(iOS 26.0, *)
struct NotificationsToolbar: View {
    let unread: Int

    var body: some View {
        NavigationStack {
            QueueView().toolbar {
                ToolbarItem {
                    Button("Notifications", systemImage: unread > 0 ? "bell.badge.fill" : "bell.fill") { }
                        .badge(min(unread, 99))
                }
            }
        }
    }
}

// MARK: - Backgrounds under a vertical bar, and sheets

struct HeroHeader: View {
    var body: some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFill()
            .frame(height: 320)
            // iOS 26: mirrors and blurs the image out under sidebars — and,
            // on iPhone Duo, under the vertical bar — so it has no hard edge there.
            .backgroundExtensionEffect()
    }
}

@available(iOS 27.0, *)
struct SheetHost: View {
    @State private var showing = false
    var body: some View {
        Button("Filters") { showing = true }
            .sheet(isPresented: $showing) {
                QueueView()
                    // Trailing sheets get vertical bars on the inner display;
                    // centred and leading ones keep horizontal bars.
                    .presentationPlacement(.trailing)
            }
    }
}

// MARK: - Readable measure and asymmetric insets

extension View {
    /// Wide is not the same as stretched: cap a column at a readable measure
    /// and align it with whatever it belongs to.
    func readableColumn(maxWidth: CGFloat = 560, margin: CGFloat = 20, alignment: Alignment = .center) -> some View {
        frame(maxWidth: maxWidth)
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

struct SettingsLikeScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) { ForEach(0..<6, id: \.self) { _ in Color.gray.frame(height: 80) } }
                .readableColumn()
        }
    }
}

// MARK: - Scene accessory: a second display while the camera runs

@available(iOS 27.1, *)
struct TeleprompterCamera: View {
    @State private var isEnabled = true
    @State private var isAvailable = false

    var body: some View {
        CameraView()
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $isEnabled) {
                    Teleprompter()
                }
                .onAvailabilityChange { isAvailable = $0 }
            }
            .toolbar {
                ToolbarItem {
                    Toggle("Teleprompter", systemImage: "text.bubble", isOn: $isEnabled)
                        .disabled(!isAvailable)
                }
            }
    }
}

// MARK: - List → detail: two columns only where the list stays beside the detail

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

// MARK: - List → detail: pushing inside the detail column

enum HubDestination: Hashable { case photos, notes }
enum PhotoRoute: Hashable { case review }

struct NotesScreen: View { var body: some View { Text("notes") } }
struct ReviewScreen: View { var body: some View { Text("review") } }

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

extension View {
    /// Its own stack only when presented alone (a sheet); inside a hub a
    /// second stack would nest.
    @ViewBuilder
    func inOwnNavigationStack(_ ownsNavigation: Bool) -> some View {
        if ownsNavigation { NavigationStack { self } } else { self }
    }
}
