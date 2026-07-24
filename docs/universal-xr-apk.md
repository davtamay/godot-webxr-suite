# Universal XR APK export

## Decision

`godot-xr-suite` is the canonical source for native Android XR export
tooling. A consuming project keeps its existing Web/WebGPU presets and adds an
independent `UniversalXRAPK` preset through `godot_universal_xr_apk`.

The universal development APK uses:

- Godot 4.8's built-in OpenXR module and Khronos Android loader;
- one `arm64-v8a` binary;
- minimum Android API 34;
- Compatibility/OpenGL on Android while retaining the project's independent
  Web renderer override;
- standard `IMMERSIVE_HMD` launch metadata;
- Android XR's Google loader, OpenXR feature, controller, and hand declarations
  marked optional;
- no platform-vendor AAR loader;
- the official Godot OpenXR Vendors arm64 GDExtension, injected unchanged by
  the universal export layer so optional Meta and Android XR extensions can
  coexist behind capability providers.

The WebXR and OpenXR bootstrap nodes remain siblings in the same scene. Each is
inert off its platform, so this export layer does not fork gameplay,
interaction, input, or UI code.

Their shared policy lives in `XRRuntimeConfig`. APK setup changes only Android's
mobile renderer override and native OpenXR settings; it does not write the web
renderer override or mutate a Web export preset. Conversely, WebGPU/WebXR setup
changes only web settings and presets.

## Why the Google library must be optional

Android XR full-space applications advertise `libopenxr.google.so`. A normal
immersive export from Godot OpenXR Vendors 5.1 marks that native library
required. Android rejects installation when a required shared library is not
present, and Quest does not provide Google's loader.

For the portable baseline, the suite's export plugin emits the same Android XR
declaration with `android:required="false"`. On Galaxy XR the Google runtime is
discoverable; on Quest Godot's Khronos loader discovers Meta's active OpenXR
runtime.

This mirrors the proven `UniversalDev` packaging pattern in the companion
`AndroidXR_BugSlice` Unreal project: platform runtime declarations are optional
and vendor extensions are allowed to be absent.

## Preset boundaries

`UniversalXRAPK` is for sideloading and cross-device development. Do not
turn it into a union of store requirements.

Later store presets should derive from the same project:

- `AndroidXRPlay`: Google Play metadata, signing, Android XR vendor extension,
  and required store features.
- `QuestStore`: Meta Horizon metadata, signing, Meta vendor extension, and
  Quest device declarations.

Scene mesh and environment depth now sit behind the shared
`godot_xr_scene_understanding` API with WebXR, Meta OpenXR, and Android XR
providers. Anchors, light estimation, eye tracking, and additional vendor room
APIs should follow the same pattern. Their absence must not prevent the shared
scene from starting.

## Verification gate

Before installing an APK:

1. Run `addons/godot_universal_xr_apk/tools/validate_universal_xr_apk.ps1`.
2. Record the SHA-256.
3. Install that exact hash on both devices.
4. Verify session start, head pose, controllers, hands, locomotion, and exit.

This gate proves that both results came from one artifact rather than two
nominally similar builds.
