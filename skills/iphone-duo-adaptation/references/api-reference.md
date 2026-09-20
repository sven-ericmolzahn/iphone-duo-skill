# API reference

Every entry below was read from the SDK (`.swiftinterface` files and Objective-C headers) of **Xcode 27.1 (27A9269), iOS 27.1 SDK**, and the Swift forms are type-checked by `tests/typecheck.sh` in the skill's repository. Re-run `scripts/check-sdk.sh` against your own Xcode: these APIs shipped as beta and may move.

**Contents:** [Availability](#availability) · [SwiftUI layout](#swiftui--layout) · [SwiftUI bars, tabs, sheets](#swiftui--bars-tabs-sheets) · [SwiftUI scenes](#swiftui--scene-accessories) · [UIKit layout](#uikit--layout) · [UIKit bars](#uikit--bars-and-tabs) · [UIKit scenes](#uikit--scenes) · [AVFoundation](#avfoundation) · [Where docs and SDK disagree](#where-secondary-sources-and-the-sdk-disagree) · [Apple's sources](#apples-sources)

## Availability

- The SDK spells availability `@available(anyAppleOS 27.1, *)`. In your code write `#available(iOS 27.1, *)` / `@available(iOS 27.1, *)`.
- Several bar APIs are **27.0**, not 27.1: `visibilityPriority`, `ToolbarOverflowMenu`, `defaultTabBarPlacement`, `presentationPlacement`, `UITabBarController.sidebar.preferredPlacement`. `backgroundExtensionEffect()` and `UIBackgroundExtensionView` are **26.0**.
- The full-screen presentation and vertical bars come from *building* with the iOS 27.1 SDK. Apps built with older SDKs still run, in a compatibility presentation.
- **Module trap.** The SwiftUI layout symbols are declared in `SwiftUICore`; `SwiftUI` re-exports it, so `import SwiftUI` is all the code needs. When searching the SDK, search both interfaces.

## SwiftUI — layout

Declared in **SwiftUICore**, iOS 27.1.

| Symbol | Signature / values |
|---|---|
| `ArrangementView<Primary, Secondary>` | `init(primary: () -> Primary, secondary: () -> Secondary)` · `init(_ configuration: ArrangementViewStyleConfiguration)` (for custom styles) |
| `View.arrangementViewStyle(_:)` | `some ArrangementViewStyle`; built in: `.split`, `.overlay`. Default resolves to split. |
| `SplitArrangementViewStyle.axes(_:)` | `Axis.Set` — `.horizontal`, `.vertical`, or both (default) |
| `OverlayArrangementViewStyle.axes(_:)` | `Axis.Set` |
| `ArrangementViewStyle` (protocol) | `@MainActor func makeBody(configuration:) -> Body`; `configuration.primary`, `.secondary` |
| `View.splitArrangementLayoutSize(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)` | all `CGFloat?`, default `nil`. **Apply to a pane.** |
| `View.splitArrangementLayoutRatio(_:)` | `CGFloat?`. **Apply to a pane.** |
| `View.splitArrangementLayoutRatio(minHorizontal:idealHorizontal:maxHorizontal:minVertical:idealVertical:maxVertical:)` | all `CGFloat?`. **Apply to a pane.** |
| `View.splitArrangementFixedLayoutSize(horizontal:vertical:)` | `Bool`, default `true`. **Apply to a pane.** |
| `View.overlayArrangementEdge(_:)` | overloads for `VerticalEdge?` and `HorizontalEdge?` — write `VerticalEdge.bottom`, not `.bottom`, to disambiguate |
| `EnvironmentValues.overlayArrangementZIndex` | `Int` — `> 0` while this pane is layered above the other |
| `EnvironmentValues.splitArrangementAxis` | `Axis?` — `nil` outside a split arrangement |
| `ReservedRegion` | `id`, `kind`, `frame: CGRect` (includes margins), `margins: EdgeInsets`, `isActive: Bool`; `Identifiable`, `Hashable`, `Sendable` |
| `ReservedRegion.Kind` | `.division` (fold), `.occlusion` (cameras) |
| `ReservedRegion.QueryOptions` | `OptionSet`; `.includeInactive` |
| `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` | `options` default `[]` (active only); `layoutDirectionBehavior` default `.mirrors`, or `.fixed` |
| `View.onHingeChange(isEnabled:_:)` | `(_ old: DeviceHingeContext, _ new: DeviceHingeContext) -> Void` |
| `DeviceHingeContext` | `hinge: DeviceHinge?` — `nil` means the device has no hinge |
| `DeviceHinge` | `status: DeviceHinge.Status`, `angle: Angle` |
| `DeviceHinge.Status` | `.closed`, `.partiallyOpen`, `.fullyOpen` |

`onGeometryChange(for:of:action:)` hands you a `GeometryProxy` too, so `reservedRegions` works there without a `GeometryReader`.

## SwiftUI — bars, tabs, sheets

Declared in **SwiftUI** unless noted.

| Symbol | Values | Since |
|---|---|---|
| `ToolbarContent.axisBehavior(_:)` | `ToolbarItemAxisBehavior`: `.automatic`, `.horizontalOnly`, `.verticalPreferred` | 27.1 |
| `View.toolbarVerticalBehavior(_:)` | `ToolbarVerticalBehavior`: `.automatic`, `.disabled` | 27.1 |
| `View.toolbarVerticalCompressionBehavior(_:)` | `.automatic`, `.prefersToolbarItems`, `.prefersTabBar` | 27.1 |
| `EnvironmentValues.toolbarVerticalEdge` *(SwiftUICore)* | `HorizontalEdge?` — `.leading` / `.trailing`; `nil` with horizontal bars | 27.1 |
| `ToolbarContent.visibilityPriority(_:)` | `ToolbarItemVisibilityPriority`: `.automatic`, `.low`, `.high` | 27.0 |
| `ToolbarOverflowMenu { … }` | `ToolbarContent`; items placed straight into the system overflow menu | 27.0 |
| `ToolbarItemPlacement` | `.cancellationAction` (Back/Close, top), `.topBarPinnedTrailing` (Done), `.confirmationAction`, `.topBarTrailing`, `.bottomBar` | — |
| `View.defaultTabBarPlacement(_:)` | `AdaptableTabBarPlacement`: `.automatic`, `.tabBar`, `.sidebar` | 27.0 |
| `View.presentationPlacement(_:)` | `PresentationPlacement`: `.automatic`, `.leading`, `.trailing` | 27.0 |
| `View.backgroundExtensionEffect()` / `(isEnabled:)` | extends imagery under sidebars and the vertical bar | 26.0 |

Compression semantics, from the UIKit header: *automatic on iOS prefers the tab bar* — toolbar items overflow first and the tab bar stays. `.prefersToolbarItems` keeps the actions and minimises the tab bar instead.

## SwiftUI — scene accessories

| Symbol | Notes | Since |
|---|---|---|
| `View.sceneAccessory { … }` | content conforms to `SceneAccessoryContent` | 27.0 |
| `CameraCaptureAccessory(content:)` · `CameraCaptureAccessory(isEnabled:content:)` | shows a view on the *outer* display while the app uses the rear camera on the fully open inner display | 27.1 |
| `.onAvailabilityChange(perform:)` | `(Bool) -> Void`; the system controls availability dynamically | 27.1 |

## UIKit — layout

iOS 27.1. Many are `NS_REFINED_FOR_SWIFT`; the Swift names below are the ones to type.

| Symbol | Swift surface |
|---|---|
| `UIArrangementViewController` | `init()` · `setViewController(_:for:animated:)` · `viewController(for:)` · `placement(for:)` · `state(for:) -> ViewState?` · `updateArrangement(_:animated:)` |
| `UIArrangementViewController.ViewPlacement` | `.none`, `.primary`, `.secondary` |
| `UIArrangementViewController.ViewState` | `zIndex: Int`, `splitAxis`, `isHidden: Bool` |
| `UISplitArrangement` | `.split` · `.axes(_ : UIAxis)` · `defaultViewProperties` · `mutating setViewProperties(_:for:)` |
| `UISplitArrangement.ViewProperties` | `width`, `height`: `DimensionRange`; `layoutPriority: CGFloat` |
| `UISplitArrangement.DimensionRange` | `minimum`, `preferred`, `maximum`: `Dimension` |
| `UISplitArrangement.Dimension` | `.automatic`, `.intrinsic`, `.fractional(_:)`, `.absolute(_:)` |
| `UIOverlayArrangement` | `.overlay` · `.axes(_:)` · view properties with `edge: NSDirectionalRectEdge` |
| `UIView.reservedRegions(kind:options:)` | `[UIView.ReservedRegion]`; `options` default `[]` |
| `UIView.ReservedRegion` | `identifier`, `kind`, `frame` (includes margins), `margins: UIEdgeInsets`, `isActive` |
| `UIView.ReservedRegion.Kind` | `.division`, `.occlusion` · `QueryOptions.includeInactive` |
| `UIHingeInteraction(updateHandler:)` | `UIInteraction`; handler receives `(UIHingeInteraction, UIHingeInteractionUpdate)`; `isEnabled` |
| `UIHingeInteractionUpdate.hinge` | `UIHinge?` — `nil` means no hinge |
| `UIHinge` | `status: UIHingeStatus` (`.unknown`, `.closed`, `.partiallyOpen`, `.fullyOpen`), `angle: CGFloat` |

Note the asymmetry: SwiftUI's hinge angle is an `Angle`; UIKit's is a `CGFloat`.

## UIKit — bars and tabs

| Symbol | Values | Since |
|---|---|---|
| `UIBarButtonItem.axisBehavior` | `.automatic`, `.horizontalOnly`, `.verticalPreferred` | 27.1 |
| `UIBarButtonItem.visibilityPriority` | `.standard`, `.low`, `.high` (extensible `NSInteger`) | 27.0 |
| `UIViewController.preferredVerticalBarBehavior` | override; `.automatic`, `.disabled` | 27.1 |
| `UINavigationItem.verticalBarCompressionBehavior` | `.automatic` (prefers the tab bar), `.prefersBarItems`, `.prefersTabBar` | 27.1 |
| `UITraitCollection.verticalBarEdge` | `.unspecified`, `.leading`, `.trailing` | 27.1 |
| `UITraitCollection.systemTraitsAffectingVerticalBarEdge` | `[UITrait]` for `registerForTraitChanges` | 27.1 |
| `UINavigationItem.pinnedTrailingGroup` · `.leadingItemGroups` · `.additionalOverflowItems` | prominent item · Back/Close · items placed in the system overflow menu | 16.0 |
| `UITabBarController.sidebar.preferredPlacement` | `.automatic`, `.sidebar` | 27.0 |
| `UIBackgroundExtensionView` | extends imagery under sidebars and the vertical bar | 26.0 |

Content from a hand-instantiated `UIToolbar`, `UINavigationBar` or `UITabBar` is not considered for the vertical bar.

## UIKit — scenes

| Symbol | Notes |
|---|---|
| `UISceneAccessory.cameraCapture(sceneConfiguration:)` · `(…userInfo:)` | 27.1. The second-display accessory while capturing. |
| `UISceneAccessory.externalNonInteractive(sceneConfiguration:)` | 27.0 |
| `UIWindowSceneActivationAction` | iOS 15. Hides itself when a new window can't be created — which on iPhone Duo is whenever the app is on the **outer** display. |
| `view.window?.windowScene?.screen` | the screen this view is actually on |

## AVFoundation

| Symbol | Status in this SDK |
|---|---|
| `AVCaptureDevice.DeviceType.builtInOuterUltraWideCamera` | ✓ 27.1 |
| `AVCaptureDevice.DeviceType.builtInInnerUltraWideCamera` | ✓ 27.1 (the under-display camera) |
| `AVCaptureDevice.RotationCoordinator` | ✓ existing; on iPhone Duo it also updates when the app moves between displays |
| `AVCaptureDevice.dynamicAspectRatio` · `AVCaptureDevice.Format.supportedDynamicAspectRatios` | ✓ 26.0 |
| `AVCapturePhotoOutput.isCameraSensorOrientationCompensationEnabled` | ✓ 26.0 |
| `AVCaptureDeviceDirectionCoordinator`, `AVCaptureDeviceDescriptor`, a "virtual front camera" device | ✗ **announced in Tech Talk 111465, absent from the headers of this SDK build** (simulator and device). Don't write code against them until `scripts/check-sdk.sh` finds them. |

## Where secondary sources and the SDK disagree

Found while verifying; each of these was stated confidently somewhere.

| Claim | Reality in the SDK |
|---|---|
| Region kinds `.divisions` / `.occlusions`, option `.all`, behaviour `.mirrored` | `.division` / `.occlusion`, `.includeInactive`, `.mirrors` / `.fixed` |
| "`ArrangementView` isn't in the SwiftUI SDK yet" | It is — in `SwiftUICore` |
| "The default compression behaviour is `.prefersToolbarItems`" | Automatic on iOS *prefers the tab bar*; toolbar items overflow first |
| `.arrangementStyle(...)` | `.arrangementViewStyle(...)` |
| Hinge angle is an `Angle` everywhere | `Angle` in SwiftUI, `CGFloat` in UIKit |
| `sidebar.preferredPlacement` is an iOS 18 API | 27.0 |
| `AVCaptureDeviceDirectionCoordinator` is available | Not in this SDK build |

## Apple's sources

- HIG — [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- Overview — [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- Reference — [`ArrangementView`](https://developer.apple.com/documentation/swiftui/arrangementview)
- Tech Talks: [Prepare your app (111461)](https://developer.apple.com/videos/play/tech-talks/111461/) · [Raise the bar (111462)](https://developer.apple.com/videos/play/tech-talks/111462/) · [Strike a pose with adaptive layouts (111463)](https://developer.apple.com/videos/play/tech-talks/111463/) · [Multiple displays and scenes (111464)](https://developer.apple.com/videos/play/tech-talks/111464/) · [A great camera experience (111465)](https://developer.apple.com/videos/play/tech-talks/111465/) · [Design for iPhone Duo (111466)](https://developer.apple.com/videos/play/tech-talks/111466/)

Tip for agents: Apple's documentation pages are JavaScript-rendered and fetch as an empty shell. The same content is served as JSON at `https://developer.apple.com/tutorials/data/<path>.json` — for example `…/tutorials/data/documentation/swiftui/arrangementview.json` and `…/tutorials/data/design/human-interface-guidelines/designing-for-iphone-duo.json`.
