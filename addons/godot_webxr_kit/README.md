# Godot WebXR Kit

The WebXR platform layer for `godot_xr_interaction_toolkit`. Turns a browser
WebXR session into the poses and select/activate events the interaction toolkit
consumes, and provides the browser-side plumbing (custom HTML shell, capability
probe) that WebXR needs. Pure GDScript — no engine builds, no
export-template changes. Room mesh, occlusion, and depth sensing live in the
`godot_webxr_scene_understanding` addon.

**Requires** the `godot_xr_interaction_toolkit` addon (this kit builds on its
abstract `XRInputAdapter` and `XRHandTracker` helpers). Install both.

## Quick start: drop in the rig (recommended)

You do **not** have to hand-wire the origin, controllers, manager, adapter, and
interactors. Instance the pre-wired rig scene once and add your grabbables:

```gdscript
const RIG := preload("res://addons/godot_webxr_kit/rig/xr_webxr_rig.tscn")

func _ready() -> void:
    add_child(RIG.instantiate())   # XR origin + camera + 2 controllers + manager
                                   # + WebXRInputAdapter + per-hand ray/direct
                                   # interactors (line + reticle) + screen ray.
    # Then add any XRGrabInteractable(s) anywhere in the scene — they register
    # with the rig's manager automatically (found by group).
```

Or, in the editor: **Instantiate Child Scene → `xr_webxr_rig.tscn`** under your
scene root, then add `XRGrabInteractable` nodes (each with a `CollisionObject3D`
child for the ray to hit). Session entry (requesting `immersive-vr`, setting
`viewport.use_xr`) stays in your project — see `runtime/webxr_bootstrap.gd` or
`../godot_blender_principled/samples/material_inspect_xr.gd` for a working
example. The rig has no scene-specific content, so it drops into any project.

## Contents

```text
addons/godot_webxr_kit/
  plugin.cfg / plugin.gd
  runtime/
    webxr_input_adapter.gd          # WebXRInputAdapter: WebXR session -> toolkit poses/events
    webxr_bootstrap.gd              # immersive-vr / immersive-ar session lifecycle
    browser_capabilities.gd         # WebGL2 / multiview / WebXR / WebGPU capability probe
    webxr_renderer.gd               # WebXRRenderer: read/switch the WebGL vs WebGPU backend
  web/
    company_webxr_shell.html        # custom HTML export shell + browser hand/depth JS bridges
```

## Required export wiring

The kit's WebXR hand tracking and depth preview ride on the custom HTML shell.
In your project's export preset (Web), set:

```
html/custom_html_shell="res://addons/godot_webxr_kit/web/company_webxr_shell.html"
```

The shell patches `navigator.xr.requestSession` / `requestAnimationFrame` and
publishes three `window` globals consumed by GDScript:

| JS global | Provided by | Consumed by |
|---|---|---|
| `CompanyWebXRHandBridge` | shell | `WebXRInputAdapter`; also `godot_xr_hands`' hand visualizer (optional) |
| `CompanyWebXRFailure` | `webxr_bootstrap.gd` writes it | surfaced to the page on session failure |

If you also install `godot_xr_hands`, its hand visualizer will use
`CompanyWebXRHandBridge` from this kit's shell for faster startup; without the
shell it falls back to `XRHandTracker`.

## Session lifecycle stays in your project

`webxr_bootstrap.gd` is a working example of requesting the session and setting
`viewport.use_xr`; wire its VR/AR buttons and status label in your scene. It
requests `hand-tracking` optional by default (`require_hand_tracking = false`),
so controller-only devices still start, and collects further session features
from nodes in the `webxr_feature_provider` group (see
`godot_webxr_scene_understanding`) — a scene only requests what it contains.

## WebGPU builds

`WebXRRenderer` (above) is the only WebGPU-aware piece here — it just reads or
switches the backend and works on any build. The WebGPU **build** tooling —
the one-checkbox WebGPU export toggle and the `BakeAnchor` node for baking
runtime-built materials — lives in the standalone **`godot_webgpu`** addon,
which this kit does not depend on. Install `godot_webgpu` if you want to ship
the WebGPU backend; see its README.

## Platform notes

- **Quest 3 / Quest Browser:** the proven path — controllers, hands, pinch
  select, VR and AR sessions all work.
- **Samsung Galaxy XR / tested Android XR browsers:** WebXR + WebGL2 present but
  no `OVR_multiview2` / `OCULUS_multiview`, so Godot WebXR stereo fails. Browser
  capability gap, not a kit/export issue.
- **AR depth / room mesh / occlusion:** moved to the
  `godot_webxr_scene_understanding` addon, which reports per-device status
  honestly (browser-flag-gated features, gpu-only depth grants, upcoming
  WebGPU paths).
- **Desktop / no XR session:** the adapter reports no poses and interactors idle;
  the scene stays usable as a flat preview.
