import SwiftUI
import os

private let log = Logger(subsystem: "dev.local.DuoProbe", category: "strategy")

// MARK: - The four strategies under test

enum Strategy: String, CaseIterable, Identifiable {
    case deviceCheck  = "A device"     // the Reddit comment: is the DEVICE foldable?
    case displayCheck = "B display"    // does THIS display have a fold?
    case always       = "C always"     // the skill: one arrangement, let it adapt
    case splitView    = "D split"      // baseline: NavigationSplitView everywhere
    case primaryOnly  = "E prim-only"  // minWidth on the primary pane only
    case skillSnippet = "F snippet"    // the skill's own primary prefs, no secondary floor
    case greedy       = "G greedy"     // a large primary floor, no secondary floor
    case snippetFixed = "H fixed"      // F plus a floor on the secondary
    case floor400     = "I 400"        // primary floor inside the larger half (456)
    case floor500     = "J 500"        // primary floor beyond the larger half
    var id: Self { self }
}

/// What a developer realistically writes for "is the device foldable": there is
/// no such API in the 27.1 SDK, so it comes down to a hard-coded model list.
enum DeviceModel {
    static let identifier: String = {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var s = utsname(); uname(&s)
        return withUnsafeBytes(of: &s.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }()
    static let isFoldable: Bool = ["iPhone19,4"].contains(identifier)
}

// MARK: - Panes

struct Pane: View {
    let title: String
    let color: Color
    var body: some View {
        GeometryReader { p in
            ZStack {
                color.opacity(0.35)
                VStack(spacing: 4) {
                    Text(title).font(.headline)
                    Text("\(Int(p.size.width.rounded())) × \(Int(p.size.height.rounded()))")
                        .font(.system(.title3, design: .monospaced))
                }
            }
        }
    }
}

struct SinglePane: View {
    let reason: String
    var body: some View {
        GeometryReader { p in
            ZStack {
                Color.orange.opacity(0.30)
                VStack(spacing: 4) {
                    Text("single column").font(.headline)
                    Text("\(Int(p.size.width.rounded())) × \(Int(p.size.height.rounded()))")
                        .font(.system(.title3, design: .monospaced))
                    Text(reason).font(.caption).multilineTextAlignment(.center).padding(.horizontal)
                }
            }
        }
    }
}

@available(iOS 27.1, *)
struct TwoPaneArrangement: View {
    var body: some View {
        ArrangementView {
            Pane(title: "Primary", color: .blue)
                .splitArrangementLayoutSize(minWidth: 240)
        } secondary: {
            Pane(title: "Secondary", color: .green)
                .splitArrangementLayoutSize(minWidth: 240)
        }
        .arrangementViewStyle(.split)
    }
}

struct SplitViewBaseline: View {
    @State private var selection: Int? = 1
    var body: some View {
        NavigationSplitView {
            List(1..<6, selection: $selection) { Text("Row \($0)").tag($0) }
                .navigationTitle("Sidebar")
        } detail: {
            Pane(title: "Detail", color: .purple)
        }
    }
}

// MARK: - Root

struct RootView: View {
    // `xcrun simctl launch <udid> dev.local.DuoProbe -strategy C` selects one
    // without tapping, so a pose can be measured unattended.
    @State private var strategy: Strategy = {
        switch UserDefaults.standard.string(forKey: "strategy")?.uppercased() {
        case "A": .deviceCheck
        case "B": .displayCheck
        case "C": .always
        case "D": .splitView
        case "E": .primaryOnly
        case "F": .skillSnippet
        case "G": .greedy
        case "H": .snippetFixed
        case "I": .floor400
        case "J": .floor500
        default:  .deviceCheck
        }
    }()
    @Environment(\.horizontalSizeClass) private var h
    @Environment(\.verticalSizeClass) private var v

    var body: some View {
        VStack(spacing: 0) {
            Picker("Strategy", selection: $strategy) {
                ForEach(Strategy.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(6)

            Text("\(DeviceModel.identifier) · isFoldable=\(DeviceModel.isFoldable ? "yes" : "no") · h=\(name(h)) v=\(name(v))")
                .font(.system(.caption2, design: .monospaced))
                .padding(.bottom, 4)

            content
                .duoLayoutProbe(strategy.rawValue)
        }
        .onChange(of: strategy, initial: true) { _, s in
            log.notice("strategy=\(s.rawValue, privacy: .public) model=\(DeviceModel.identifier, privacy: .public) isFoldable=\(DeviceModel.isFoldable, privacy: .public)")
        }
    }

    @ViewBuilder private var content: some View {
        switch strategy {
        case .deviceCheck:
            // The comment's rule, exactly: the DEVICE decides, once, for every display.
            if DeviceModel.isFoldable, #available(iOS 27.1, *) {
                TwoPaneArrangement()
            } else {
                SplitViewBaseline()
            }

        case .displayCheck:
            // Ask THIS display whether it has a fold at all.
            GeometryReader { proxy in
                let folds: Int = {
                    if #available(iOS 27.1, *) {
                        return proxy.reservedRegions(kind: .division, options: .includeInactive).count
                    }
                    return 0
                }()
                if folds > 0, #available(iOS 27.1, *) {
                    TwoPaneArrangement()
                        .onAppear { log.notice("displayCheck: \(folds, privacy: .public) inactive division region(s) -> arrangement") }
                } else {
                    SplitViewBaseline()
                        .onAppear { log.notice("displayCheck: no division region -> split view") }
                }
            }

        case .always:
            if #available(iOS 27.1, *) {
                TwoPaneArrangement()
            } else {
                SinglePane(reason: "iOS < 27.1 fallback")
            }

        case .splitView:
            SplitViewBaseline()

        case .primaryOnly:
            // The skill's trap #2: a floor on the primary only.
            if #available(iOS 27.1, *) {
                ArrangementView {
                    Pane(title: "Primary", color: .blue)
                        .splitArrangementLayoutSize(minWidth: 240)
                } secondary: {
                    Pane(title: "Secondary", color: .red)   // no floor at all
                }
                .arrangementViewStyle(.split)
            } else {
                SinglePane(reason: "iOS < 27.1 fallback")
            }

        case .skillSnippet:
            if #available(iOS 27.1, *) {
                ArrangementView {
                    Pane(title: "Primary", color: .blue)
                        .splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)
                } secondary: {
                    Pane(title: "Secondary", color: .red)
                }
                .arrangementViewStyle(.split)
            } else { SinglePane(reason: "iOS < 27.1 fallback") }

        case .greedy:
            if #available(iOS 27.1, *) {
                ArrangementView {
                    Pane(title: "Primary", color: .blue)
                        .splitArrangementLayoutSize(minWidth: 700)
                } secondary: {
                    Pane(title: "Secondary", color: .red)
                }
                .arrangementViewStyle(.split)
            } else { SinglePane(reason: "iOS < 27.1 fallback") }

        case .snippetFixed:
            if #available(iOS 27.1, *) {
                ArrangementView {
                    Pane(title: "Primary", color: .blue)
                        .splitArrangementLayoutSize(minWidth: 280, idealWidth: 330, maxWidth: 440)
                } secondary: {
                    Pane(title: "Secondary", color: .green)
                        .splitArrangementLayoutSize(minWidth: 240)
                }
                .arrangementViewStyle(.split)
            } else { SinglePane(reason: "iOS < 27.1 fallback") }

        case .floor400, .floor500:
            if #available(iOS 27.1, *) {
                let floor: CGFloat = strategy == .floor400 ? 400 : 500
                ArrangementView {
                    Pane(title: "Primary min \(Int(floor))", color: .blue)
                        .splitArrangementLayoutSize(minWidth: floor)
                } secondary: {
                    Pane(title: "Secondary", color: .green)
                        .splitArrangementLayoutSize(minWidth: 240)
                }
                .arrangementViewStyle(.split)
            } else { SinglePane(reason: "iOS < 27.1 fallback") }
        }
    }

    private func name(_ c: UserInterfaceSizeClass?) -> String {
        switch c { case .compact: "compact"; case .regular: "regular"; default: "nil" }
    }
}

@main
struct DuoProbeApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
