# Godot Universal XR APK

One Godot 4.8 project can keep its Web/WebGPU exports and also produce one
native arm64 OpenXR APK for both Meta Quest 3 and Android XR devices such as
Galaxy XR.

This addon is intentionally an **export layer**, not a second XR runtime. The
shared rig, action map, controller/hand input, interactions, and WebXR/OpenXR
session bootstraps remain in `godot_webxr_kit`.

## What it does

- Adds optional Android XR manifest entries without requiring
  `libopenxr.google.so`, so the same APK remains installable on Quest.
- Uses Godot 4.8's built-in Khronos OpenXR loader.
- Packages the official Godot OpenXR Vendors arm64 GDExtension without enabling
  a device-specific AAR loader. The vendor addon itself remains unchanged.
- Adds **Project > Tools > Set Up Universal XR APK Export**, which creates
  or repairs an idempotent `UniversalXRAPK` preset.
- Enforces arm64, Gradle, OpenXR, minimum Android API 34, and Godot's
  recommended Compatibility/OpenGL renderer override for standalone Android
  headsets.
- Leaves existing Web and WebGPU presets untouched.

## Use

1. Enable **Godot Universal XR APK** in Project Settings > Plugins.
2. Select **Project > Tools > Set Up Universal XR APK Export**.
3. Install Godot's Android build template if the editor requests it.
4. Export `UniversalXRAPK`.
5. Run `tools/validate_universal_xr_apk.ps1 -Apk <path>` before device testing.

The universal preset is a sideload/development baseline. Store submissions
should be separate presets because Google Play and Meta Horizon apply different
required features, signing, metadata, and validation rules.

## Vendor extensions

The portable preset deliberately disables the Android XR, Meta, Pico, and Magic
Leap vendor exporters. In Godot OpenXR Vendors 5.1, enabling the Android XR
exporter for an immersive app marks `libopenxr.google.so` required; a Quest
does not provide that Google library, so that setting cannot describe a truly
universal APK.

Generic OpenXR controllers and `XR_EXT_hand_tracking` remain available through
Godot's built-in OpenXR module. The companion
`godot_xr_scene_understanding` addon routes environment depth and scene meshes
to WebXR, Meta OpenXR, or Android XR providers by capability. Unsupported
extensions remain dormant. Native anchors, native light estimation, eye
tracking, and store packaging remain separate capability adapters or
store-specific presets.
