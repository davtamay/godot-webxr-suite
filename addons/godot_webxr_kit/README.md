# Godot WebXR Kit

The WebXR platform layer for `godot_xr_interaction_toolkit`. Turns a browser
WebXR session into the poses and select/activate events the interaction toolkit
consumes, and provides the browser-side plumbing (custom HTML shell, capability
probe, depth preview) that WebXR needs. Pure GDScript — no engine builds, no
export-template changes.

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
    webxr_depth_mesh_visualizer.gd  # AR depth-mesh preview (see platform notes)
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
| `CompanyWebXRDepthBridge` | shell | `webxr_depth_mesh_visualizer.gd` |
| `CompanyWebXRFailure` | `webxr_bootstrap.gd` writes it | surfaced to the page on session failure |

If you also install `godot_xr_hands`, its hand visualizer will use
`CompanyWebXRHandBridge` from this kit's shell for faster startup; without the
shell it falls back to `XRHandTracker`.

## Session lifecycle stays in your project

`webxr_bootstrap.gd` is a working example of requesting the session and setting
`viewport.use_xr`; wire its VR/AR buttons and status label in your scene. It
requests `layers` (required) and `hand-tracking` optional by default
(`require_hand_tracking = false`), so controller-only devices still start.

## Platform notes

- **Quest 3 / Quest Browser:** the proven path — controllers, hands, pinch
  select, VR and AR sessions all work.
- **Samsung Galaxy XR / tested Android XR browsers:** WebXR + WebGL2 present but
  no `OVR_multiview2` / `OCULUS_multiview`, so Godot WebXR stereo fails. Browser
  capability gap, not a kit/export issue.
- **AR depth mesh:** Quest Browser (Horizon 146.0) grants **gpu-optimized depth
  only**, while this preview reads CPU depth (`XRFrame.getDepthInformation`),
  which the WebXR spec requires to throw in gpu mode. So the depth-mesh preview
  is non-functional on Quest today; the code + a clean guard remain for future
  cpu-optimized support. See `docs/DECISION_LOG.md` (2026-07-06).
- **Desktop / no XR session:** the adapter reports no poses and interactors idle;
  the scene stays usable as a flat preview.
