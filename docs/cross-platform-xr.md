# One project, two XR export pipelines

## Contract

Gameplay scenes contain one `XR Prefab` (`godot_webxr_kit/xr_prefab.tscn`) and
one set of XR blocks. Both session adapters ship in the scene:

- `WebXRBootstrap` runs only when `OS.has_feature("web")`;
- `OpenXRBootstrap` runs only in native builds;
- the XR simulator runs only while the viewport is not presenting XR.

The platform boundary ends at session/input providers. Interaction consumers
use the same `XROrigin3D`, tracker poses, action names, hand joints, signals,
and interaction state on both paths.

## User configuration

Select the `XR Prefab` root and edit `runtime_config`.

The default resource is
`addons/godot_webxr_kit/runtime/default_xr_runtime_config.tres`. It provides a
safe project-wide baseline:

- WebXR enabled, with hand tracking optional;
- native OpenXR enabled;
- Meta simultaneous hands/controllers disabled;
- 2.5 second native headset-present timeout.

Edit that resource for a project-wide policy. To override one scene, make the
resource unique in the Inspector and change only that instance. Disabling an
adapter never removes it from the scene or forks gameplay code.

## Export boundaries

| Concern | Web / WebXR | Universal XR APK |
|---|---|---|
| Session API | `WebXRInterface` | OpenXR |
| Floor/reference space | `local-floor` | OpenXR `Local Floor` |
| Renderer setting | `rendering_method.web` + Web preset | `rendering_method.mobile=gl_compatibility` |
| Export tooling | WebXR shell and optional WebGPU toggle | `UniversalXRAPK` Android preset |
| Entry UI | Browser VR/AR buttons | Runtime launches full-space directly |
| Platform extensions | Browser feature detection / JavaScript bridges | Optional OpenXR extensions |

Neither setup path may overwrite the other path's renderer override, export
preset, or runtime policy.

The consuming demo's `tools/export-xr.ps1` selects an editor by target and
requires templates matching that editor's exact version tag. Today the custom
WebGPU editor owns the Web export and the official 4.8-dev2 editor owns the APK
because only those matching template sets are installed. After Android
debug/release/source templates are built from the custom engine commit and
installed under its `4.8.dev` template directory, the same script will
automatically use that editor for APKs too.

## Block portability

The following are shared without scene forks:

- ray, direct, poke, and socket interaction;
- grab, throw, activate, drawing, tools, mechanisms, and affordances;
- teleport, snap turn, continuous movement, climbing, and comfort;
- in-world Godot UI;
- controller models and per-hand modality;
- standard tracked hands, gestures, and microgestures.

These work because they consume suite abstractions or Godot's standard XR
trackers rather than calling a platform session API directly.

Capability blocks may legitimately have different providers:

- WebGPU renderer selection and browser JavaScript bridges are web-only;
- `godot_xr_scene_understanding` routes room mesh and depth to WebXR,
  Meta OpenXR, or Android XR by runtime capability;
- hit-test, anchors, and light estimation still use the existing WebXR
  providers until native provider adapters are added.

A missing capability provider must disable that feature with an explicit status;
it must never prevent the shared scene, rig, or interactions from starting.

## Verification rule

Every runtime or block change must pass:

1. headless interaction tests;
2. a Web export and browser smoke test;
3. a validated Universal XR APK export;
4. on-device session, hands/controllers, interaction, and scene-handoff checks.

Fixes belong in the shared consumer when behavior is platform-neutral, or in
the relevant adapter/provider when platform-specific. Avoid platform checks in
gameplay scenes.
