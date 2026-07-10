# godot-webxr-suite

Source of truth for a set of reusable Godot 4.x XR addons, focused on
browser-delivered WebXR. Projects consume these addons from this repo —
never edit a project-local copy.

## Addons

| Addon | Purpose |
|---|---|
| `godot_xr_interaction_toolkit` | Engine-agnostic XR interaction layer: interactors (ray/direct/socket/screen-ray), interactables (grab/UI canvas), interaction manager, input adapter + hand tracker abstractions. |
| `godot_webxr_kit` | WebXR platform layer: session bootstrap (VR/AR), pre-wired XR rig scene, WebXR input adapter, browser capability probe, custom HTML export shell with hand/depth JS bridges. **Requires** `godot_xr_interaction_toolkit`. |
| `godot_xr_hands` | Hand-joint visualizer (WebXR hand bridge or `XRHandTracker` fallback). |
| `godot_blender_principled` | Blender Principled BSDF material parity helpers + XR sample scenes. |

## Consuming the suite

**Locally (Windows, several projects on one machine)** — create directory
junctions so every project sees edits instantly:

```powershell
foreach ($a in @("godot_webxr_kit","godot_xr_hands","godot_xr_interaction_toolkit","godot_blender_principled")) {
  New-Item -ItemType Junction -Path "<project>\addons\$a" -Target "<this repo>\addons\$a"
}
```

**Portably (team/CI)** — add this repo as a git submodule and junction/copy
the `addons/*` entries into the project's `addons/` folder, or vendor a
tagged snapshot.

## Quick start

Instance `addons/godot_webxr_kit/rig/xr_webxr_rig.tscn` in your scene, add
`XRGrabInteractable` nodes, and wire session entry via
`addons/godot_webxr_kit/runtime/webxr_bootstrap.gd`. See each addon's
README for details, including the required custom HTML shell export setting
for hand tracking (`html/custom_html_shell`).

## Renderer compatibility

The addons are pure GDScript and renderer-agnostic (WebXRInterface). Proven
on GL Compatibility web exports; also runs on the experimental WebGPU
backend (flat rendering — immersive sessions under WebGPU are pending
engine-side XRGPUBinding support).
