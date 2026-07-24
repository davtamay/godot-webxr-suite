# Godot XR Scene Understanding

One set of scene-perception managers for browser WebXR and native OpenXR.
Managers own the public API; providers own platform-specific acquisition:

```text
godot_xr_scene_understanding/
  icons/
  runtime/
  shared/
  providers/
    openxr_common/
    openxr_meta/
    openxr_android_xr/
```

The router selects providers from runtime capabilities, never from device names.
Quest and Android XR extensions are both requested as optional OpenXR
extensions, following the same pattern proven by the universal Unreal APK.

## Building-block contract

This addon owns the runtime-neutral managers, icons, shaders, and materials.
It has no resource dependency on a browser-specific addon.

- `EnvironmentDepthManager` and `SceneMeshManager` are the public blocks.
- Native OpenXR providers are included here and selected by capability. The
  common hit-test provider raycasts their neutral room-mesh collision layer and
  creates session-local `XRAnchor3D` trackers.
- The WebXR provider is optional and lives entirely in
  `godot_webxr_scene_understanding`. When installed, the router discovers its
  provider adapter and bridge on web. Without it, the neutral managers still
  load and report `WebXR provider is not installed`.
- The former `godot_webxr_scene_understanding` manager paths remain thin
  compatibility wrappers, so existing scenes keep loading.

Use the canonical `godot_xr_scene_understanding/shared/` paths in new scenes.
Install `godot_webxr_scene_understanding` only when browser scene perception,
browser hit testing/anchors, or WebXR light estimation are needed.

## Native dependency

Native providers use `godotopenxrvendors` 5.1 or newer. The universal APK keeps
Godot's Khronos loader and packages only the vendor GDExtension library; it does
not enable a device-specific Android loader. Unsupported extensions remain
inactive and the router selects the provider exposed by the active runtime.
