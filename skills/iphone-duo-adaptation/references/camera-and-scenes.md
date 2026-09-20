# Camera, second-display accessories and multiple scenes

**Contents:** [What changes for capture](#what-changes-for-capture) · [Checklist](#checklist-for-an-existing-camera-screen) · [Camera capture accessory](#camera-capture-accessory) · [Multiple windows](#multiple-windows) · [Split View multitasking](#split-view-multitasking)

## What changes for capture

iPhone Duo has two front cameras — one beside the outer display, one *under* the inner display — plus the rear cameras. Per Apple's Tech Talk 111465 both front cameras have square, ultra-wide sensors. That breaks three habits:

1. **`position == .front` no longer means "facing the person".** The displays face opposite ways, so which camera looks at the user depends on which display the app is on.
2. **The right camera changes while your session is running.** Opening or closing the device moves the app between displays. That is **not** a `scenePhase` change, so a session that starts and stops on scene activation keeps streaming from a camera that now points at the table.
3. **Preview orientation changes between displays**, not only on rotation.

In the SDK today (verified):

```swift
let front = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera],   // iOS 27.1
    mediaType: .video, position: .front
).devices
```

- `AVCaptureDevice.RotationCoordinator` — existing API; on iPhone Duo it also updates when the app moves between displays. If a capture pipeline still computes rotation from device or interface orientation, this is the moment to replace it. Anything downstream that assumes upright frames (OCR, barcode regions, ML crops) depends on it.
- `AVCaptureDevice.dynamicAspectRatio` and `AVCaptureDevice.Format.supportedDynamicAspectRatios` (iOS 26) — lets a square sensor deliver a landscape frame that fills the inner display.
- `AVCapturePhotoOutput.isCameraSensorOrientationCompensationEnabled` (iOS 26) — on by default for the Duo's front cameras; Apple suggests disabling it when you don't need it, for performance.
- `previewLayer.videoGravity` — with the rear camera on the inner display the preview has spare room around it; either offset the preview and group controls in the remainder, or fill the display.

**Announced but not in the SDK build this skill was verified against:** `AVCaptureDeviceDirectionCoordinator` (tells you which cameras are forward- or backward-facing relative to a given view, with a change handler), `AVCaptureDeviceDescriptor` (a `Sendable` stand-in you hand to your capture actor), and a *virtual front camera* device that switches between the two front cameras automatically at the cost of only the common feature set. They are described in Tech Talk 111465 and in the article *Choosing a camera by the direction it faces*. Run `scripts/check-sdk.sh`; if they are present, prefer the coordinator over any hand-rolled switching. If not, don't invent them — follow display changes yourself (the scene's `screen`, trait changes, `RotationCoordinator` updates) and reconfigure the session.

## Checklist for an existing camera screen

- [ ] Device selection uses a discovery session, not `AVCaptureDevice.default(…)` with a hard-coded type and position.
- [ ] The session is reconfigured when the app moves between displays — not only on `scenePhase` / `viewWillAppear`.
- [ ] Rotation comes from `RotationCoordinator`, for both the preview and the captured output.
- [ ] **Every optional setting is checked against the output first.** `capturePhoto` raises an *uncatchable* `NSInvalidArgumentException` for a flash mode that isn't in `photoOutput.supportedFlashModes`, and no front camera has a flash. A hard-coded `settings.flashMode = .auto` that has worked for years on the rear camera crashes here.
- [ ] Mirroring is set by which way the active camera faces, not by `position`.
- [ ] The shutter and mode controls are not on the fold. If the screen is "viewfinder + controls", an `ArrangementView` with `.overlay` (or `.split`) puts the preview on one half and the controls on the other when the device is propped half-open — exactly the table-top pose people use to take a photo hands-free.
- [ ] Tested: start capture closed → open the device; start open → close; rotate in each; half-fold.

## Camera capture accessory

While an app is **full screen on the fully open inner display with an active camera session**, it can show a second view on the *outer* display — a teleprompter, a preview for the person being photographed, a countdown.

```swift
CameraView()
    .sceneAccessory {
        CameraCaptureAccessory(isEnabled: $isEnabled) {
            TeleprompterView()
        }
        .onAvailabilityChange { isAvailable = $0 }
    }
    .toolbar {
        ToolbarItem {
            Toggle("Teleprompter", systemImage: "text.bubble", isOn: $isEnabled)
                .disabled(!isAvailable)
        }
    }
```

UIKit: `UISceneAccessory.cameraCapture(sceneConfiguration:)`. Availability is controlled by the system and changes at any time (the person folds the device, leaves full screen, the session stops) — observe it and keep the UI honest rather than assuming the accessory is showing.

## Multiple windows

iPhone Duo is the first iPhone that supports **several instances of an app's UI**. An app that already supports multiple windows on iPad supports them here.

- **New windows can only be created on the inner display.** On the outer display the request fails. `UIWindowSceneActivationAction` hides itself when a new window isn't possible, which makes it the right way to offer "Open in New Window"; if you request scenes manually, handle the error.
- Anything that reaches for "the" window or scene is now wrong in a new way: `UIApplication.shared.connectedScenes.first`, `windows.first`, `keyWindow`. Start from the view you have — `view.window?.windowScene` — and only fall back to the `foregroundActive` scene.
- Per-scene state (navigation path, selection, scroll position) belongs to the scene, not to a singleton.

## Split View multitasking

Every app takes part in Split View on the inner display: two apps side by side, or an app under a pinned video that resizes it vertically in real time.

- An app that resizes on iPad, or works in iPhone Mirroring, is most of the way there. `UIRequiresFullScreen` is the opposite of what this device needs.
- In Split View each app's vertical bar sits on its **outer** edge — for the left-hand app, the *leading* edge. Layout that assumes a trailing bar is wrong half the time; read `toolbarVerticalEdge` / `verticalBarEdge` or, better, just respect the safe area.
- Decide from size classes and scene geometry, and don't assume the inner display means regular width: in Split View your app has roughly half of it. Read the size class you are given.
