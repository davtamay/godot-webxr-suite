# Godot XR Scene Understanding

One set of scene-perception managers for browser WebXR and native OpenXR.
Managers own the public API; providers own platform-specific acquisition:

```text
godot_xr_scene_understanding/
  shared/
  providers/
    webxr/
    openxr_meta/
    openxr_android_xr/
```

The router selects providers from runtime capabilities, never from device names.
Quest and Android XR extensions are both requested as optional OpenXR
extensions, following the same pattern proven by the universal Unreal APK.

The former `godot_webxr_scene_understanding` paths remain compatibility
wrappers. Existing scenes keep loading while new scenes can use this addon's
canonical paths.

## Native dependency

Native providers use `godotopenxrvendors` 5.1 or newer. The universal APK keeps
Godot's Khronos loader and packages only the vendor GDExtension library; it does
not enable a device-specific Android loader. Unsupported extensions remain
inactive and the router selects the provider exposed by the active runtime.
