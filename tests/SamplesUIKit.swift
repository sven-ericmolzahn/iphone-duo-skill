//
//  SamplesUIKit.swift — every UIKit / AVFoundation snippet in the skill, in
//  compilable form. See Samples.swift for why this exists.
//

import UIKit
import AVFoundation

final class PlayerViewController: UIViewController {}
final class QueueViewController: UIViewController {}

// MARK: - Arrangement

@available(iOS 27.1, *)
@MainActor
func makePlayerArrangement() -> UIViewController {
    let arrangement = UIArrangementViewController()
    arrangement.setViewController(PlayerViewController(), for: .primary)
    arrangement.setViewController(QueueViewController(), for: .secondary)

    var split = UISplitArrangement.split.axes(.horizontal)

    // A size range for EACH pane. Without a floor on the secondary the fold
    // squeezes it into whatever the primary leaves over.
    var primary = split.defaultViewProperties
    primary.width.minimum = .absolute(280)
    primary.width.preferred = .absolute(330)
    primary.width.maximum = .absolute(440)
    split.setViewProperties(primary, for: .primary)

    var secondary = split.defaultViewProperties
    secondary.width.minimum = .absolute(360)
    split.setViewProperties(secondary, for: .secondary)

    arrangement.updateArrangement(split)

    // Navigation goes AROUND the arrangement, never inside it.
    return UINavigationController(rootViewController: arrangement)
}

@available(iOS 27.1, *)
@MainActor
func isLayeredOverTheOtherPane(_ arrangement: UIArrangementViewController) -> Bool {
    (arrangement.state(for: .primary)?.zIndex ?? 0) > 0
}

@available(iOS 27.1, *)
@MainActor
func useOverlay(_ arrangement: UIArrangementViewController) {
    arrangement.updateArrangement(UIOverlayArrangement.overlay, animated: true)
}

// MARK: - Reserved regions

@available(iOS 27.1, *)
final class HingeAwareView: UIView {
    private let banner = UILabel()

    override func layoutSubviews() {
        super.layoutSubviews()
        // Foreground in the safe area, inset as a rect: the insets are
        // asymmetric on this device, so never `width - inset.left * 2`.
        var area = bounds.inset(by: safeAreaInsets)

        // Active regions only — empty while the device is flat. `frame`
        // already includes the margins for interactive content.
        if let hinge = reservedRegions(kind: .division).first {
            area.size.width = min(area.maxX, hinge.frame.minX) - area.minX
        }
        banner.frame = CGRect(x: area.minX, y: area.minY, width: max(area.width, 0), height: 44)
    }

    var hasHingeEvenWhenFlat: Bool {
        !reservedRegions(kind: .division, options: .includeInactive).isEmpty
    }

    var cameraFrames: [CGRect] {
        reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
    }
}

// MARK: - Hinge

@available(iOS 27.1, *)
@MainActor
func observeHinge(on view: UIView, _ onAngle: @escaping (CGFloat?) -> Void) {
    let interaction = UIHingeInteraction { _, update in
        // A nil hinge means the device doesn't have one.
        guard let hinge = update.hinge, hinge.status == .partiallyOpen else { return onAngle(nil) }
        onAngle(hinge.angle)
    }
    view.addInteraction(interaction)
}

// MARK: - Vertical bars

@available(iOS 27.1, *)
final class MailboxViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Title AND image on every item.
        let compose = UIBarButtonItem(title: "Compose", image: UIImage(systemName: "square.and.pencil"), target: nil, action: nil)
        compose.visibilityPriority = .high          // last to overflow

        let archive = UIBarButtonItem(title: "Archive All", image: UIImage(systemName: "archivebox"), target: nil, action: nil)
        archive.visibilityPriority = .low           // first to overflow

        let select = UIBarButtonItem(title: "Select", style: .plain, target: nil, action: nil)
        select.axisBehavior = .horizontalOnly       // text that carries meaning stays horizontal

        navigationItem.rightBarButtonItems = [compose, archive, select]
        navigationItem.pinnedTrailingGroup = UIBarButtonItemGroup(
            barButtonItems: [UIBarButtonItem(systemItem: .done)], representativeItem: nil)
        navigationItem.additionalOverflowItems = UIDeferredMenuElement.uncached { provide in
            provide([UIAction(title: "Settings", image: UIImage(systemName: "gearshape")) { _ in }])
        }
        // Task-focused screen: keep the bar items, let the tab bar minimise.
        navigationItem.verticalBarCompressionBehavior = .prefersBarItems
    }

    private func observeBarEdge() {
        // Trait registration, not the deprecated traitCollectionDidChange.
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: Self, _) in
            switch self.traitCollection.verticalBarEdge {
            case .leading, .trailing: break         // items can sit in a vertical bar
            default: break                          // horizontal bars
            }
        }
    }
}

@available(iOS 26.0, *)
@MainActor
func badgedInboxItem() -> UIBarButtonItem {
    let item = UIBarButtonItem(title: "Inbox", image: UIImage(systemName: "tray"), target: nil, action: nil)
    item.badge = .count(7)                          // symbol + badge, not symbol + text
    return item
}

@available(iOS 27.1, *)
final class CalculatorLikeViewController: UIViewController {
    // Opt out only for bottom-heavy, full-width, non-scrolling UI.
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior { .disabled }
}

@available(iOS 27.0, *)
@MainActor
func preferSidebar(_ tabs: UITabBarController) {
    tabs.sidebar.preferredPlacement = .sidebar
}

// MARK: - Layout decisions: traits and the scene, never the device or the screen

@MainActor
func isWideLayout(_ viewController: UIViewController) -> Bool {
    viewController.traitCollection.horizontalSizeClass == .regular
}

@MainActor
func screen(for view: UIView) -> UIScreen? {
    view.window?.windowScene?.screen                // not UIScreen.main: there are two
}

// MARK: - Camera

@available(iOS 27.1, *)
func frontCameras() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera],
        mediaType: .video,
        position: .front
    ).devices
}

func configurePhoto(_ output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) {
    // Ask before setting: a mode the output doesn't list throws an
    // uncatchable NSInvalidArgumentException. No front camera has a flash.
    if output.supportedFlashModes.contains(.auto) {
        settings.flashMode = .auto
    }
}

@MainActor
func keepUpright(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) -> AVCaptureDevice.RotationCoordinator {
    // On iPhone Duo this also updates when the app moves between displays.
    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
    previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
    return coordinator
}
