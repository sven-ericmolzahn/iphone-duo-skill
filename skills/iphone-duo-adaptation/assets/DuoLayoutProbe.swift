//
//  DuoLayoutProbe.swift
//
//  A drop-in, DEBUG-only probe for iPhone Duo layout work. Attach it to any
//  view and it logs what the system is *actually* giving that view — size,
//  safe-area insets, size classes, the vertical-bar edge, reserved regions
//  (hinge and cameras) and the hinge state — every time one of them changes.
//
//      SomeView().duoLayoutProbe("library")
//
//  Read it back from the simulator (or Console.app for a device):
//
//      xcrun simctl spawn booted log show --last 2m --style compact \
//          --predicate 'category == "DuoProbe"'
//
//  Why this exists: estimating layout from screenshots is unreliable (they are
//  scaled, and the two displays differ), and the interesting values — a
//  40-point hinge band that is only *active* when folded, a trailing inset
//  that is a whole toolbar wide — are invisible until you log them.
//
//  Remove the call sites before shipping. The file compiles to nothing in
//  release builds.
//

import SwiftUI
import OSLog

#if DEBUG

private let duoProbeLog = os.Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "app",
    category: "DuoProbe"
)

public extension View {
    /// Logs this view's geometry, insets, reserved regions and hinge state
    /// whenever any of them change. No-op before iOS 27.1 apart from size,
    /// insets and size classes.
    func duoLayoutProbe(_ label: String) -> some View {
        modifier(DuoLayoutProbe(label: label))
    }
}

private struct DuoLayoutProbe: ViewModifier {
    let label: String
    @Environment(\.horizontalSizeClass) private var horizontal
    @Environment(\.verticalSizeClass) private var vertical

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.modifier(DuoProbe271(label: label, classes: classes))
        } else {
            content.onGeometryChange(for: DuoSnapshot.self) { proxy in
                DuoSnapshot(size: proxy.size, insets: proxy.safeAreaInsets)
            } action: { snapshot in
                duoProbeLog.notice("[\(label, privacy: .public)] \(snapshot.summary, privacy: .public) classes=\(classes, privacy: .public)")
            }
        }
    }

    private var classes: String {
        "\(Self.name(horizontal))/\(Self.name(vertical))"
    }

    private static func name(_ sizeClass: UserInterfaceSizeClass?) -> String {
        switch sizeClass {
        case .compact: "compact"
        case .regular: "regular"
        default: "nil"
        }
    }
}

@available(iOS 27.1, *)
private struct DuoProbe271: ViewModifier {
    let label: String
    let classes: String
    /// `.leading` / `.trailing` while this view's toolbar items can sit in a
    /// vertical bar; `nil` when the bars are horizontal.
    @Environment(\.toolbarVerticalEdge) private var barEdge

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: DuoSnapshot.self) { proxy in
                // `.includeInactive` returns the hinge even while the device
                // is flat, flagged `isActive == false` — useful for deciding
                // things like an even column count ahead of a fold.
                DuoSnapshot(
                    size: proxy.size,
                    insets: proxy.safeAreaInsets,
                    divisions: proxy.reservedRegions(kind: .division, options: .includeInactive)
                        .map { DuoSnapshot.Region(frame: $0.frame, isActive: $0.isActive) },
                    occlusions: proxy.reservedRegions(kind: .occlusion, options: .includeInactive)
                        .map { DuoSnapshot.Region(frame: $0.frame, isActive: $0.isActive) }
                )
            } action: { snapshot in
                duoProbeLog.notice("[\(label, privacy: .public)] \(snapshot.summary, privacy: .public) classes=\(classes, privacy: .public) barEdge=\(edgeName, privacy: .public)")
            }
            .onHingeChange { _, context in
                // A nil hinge means the device has none.
                guard let hinge = context.hinge else { return }
                duoProbeLog.notice("[\(label, privacy: .public)] hinge=\(Self.name(hinge.status), privacy: .public) angle=\(hinge.angle.degrees, format: .fixed(precision: 1), privacy: .public)°")
            }
    }

    private var edgeName: String {
        switch barEdge {
        case .leading: "leading"
        case .trailing: "trailing"
        case nil: "none(horizontal bars)"
        }
    }

    private static func name(_ status: DeviceHinge.Status) -> String {
        switch status {
        case .closed: "closed"
        case .partiallyOpen: "partiallyOpen"
        case .fullyOpen: "fullyOpen"
        default: "unknown"
        }
    }
}

// `nonisolated` and `Sendable` on purpose. Projects created with recent Xcode
// templates set SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which makes a plain
// struct's synthesised `Equatable` conformance main-actor-isolated — and
// `onGeometryChange(for:)` needs a conformance it can use off the main actor.
// Without these two words this file compiles in a playground and fails in
// exactly the apps it is meant for.
nonisolated private struct DuoSnapshot: Equatable, Sendable {
    nonisolated struct Region: Equatable, Sendable {
        var frame: CGRect
        var isActive: Bool
    }

    var size: CGSize
    var insets: EdgeInsets
    var divisions: [Region] = []
    var occlusions: [Region] = []

    var summary: String {
        func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        func regions(_ list: [Region]) -> String {
            list.isEmpty ? "-" : list.map {
                "x\(f($0.frame.minX))…\(f($0.frame.maxX)) y\(f($0.frame.minY))…\(f($0.frame.maxY)) \($0.isActive ? "ACTIVE" : "inactive")"
            }.joined(separator: " | ")
        }
        return "size=\(f(size.width))x\(f(size.height))"
            + " insets(t/l/b/tr)=\(f(insets.top))/\(f(insets.leading))/\(f(insets.bottom))/\(f(insets.trailing))"
            + " division=[\(regions(divisions))] occlusion=[\(regions(occlusions))]"
    }
}

#endif
