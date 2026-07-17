# godot-webxr-suite

**XR building blocks for Godot 4.x** — browser-first (WebXR), editor-testable
on a headset (Quest Link / SteamVR), drag-and-drop by design. Think Meta's
Building Blocks or Unity's XRI + XR Hands, but easier: most blocks wire
themselves the moment you drop them in.

## Quick start: a working XR scene in three clicks

1. Enable the `godot_xr_interaction_toolkit` plugin → the **XR Blocks** dock
   appears with the full catalog (double-click adds to the scene, undo-aware).
2. Click **Set Up XR Project** in the dock — it writes the project settings
   and Web export preset an XR project needs (OpenXR + the kit's action map +
   renderer + WebXR-ready export) and reports every change. Restart the
   editor if it switched the renderer.
3. Drop **WebXR Prefab** (rig + sessions + hands + auto VR/AR UI) and
   **Floor (teleportable)**. Add a light (or let the Scene Doctor do it) and
   a **Grabbable** to have something to pick up.

That's a working scene: look around, teleport, grab, poke, pinch — in the
browser via WebXR, or press Play straight to a headset over Quest Link (the
same scene carries both). When something doesn't behave on the headset, open
the **Scene Doctor** (also in the dock): it checks the scene + project for
everything that fails silently at runtime, with one-click fixes.

## Addons

| Addon | Layer | Purpose |
|---|---|---|
| `godot_webxr_kit` | Platform & embodiment | Session bootstraps (WebXR browser + OpenXR editor/native), the pre-wired rig, input adapters, per-hand input modality, profile-matched controller models, export shell. |
| `godot_xr_hands` | Hands provider | Hand visualization, the **Gesture Studio** (data-driven poses, record-first authoring, ghost-hand preview), thumb microgesture recognition. |
| `godot_xr_interaction_toolkit` | Interaction (consumer) | Interactors (ray, direct, poke, socket), interactables + affordances, locomotion, in-world UI panels + keyboard, the XR Blocks dock. |
| `godot_webxr_scene_understanding` | Perception | Room mesh, live depth occlusion, scene labels, light estimation, hit-test + anchors — as drag-drop managers. |
| `godot_blender_principled` | Materials | Blender Principled BSDF parity helpers + benchmark sample. |
| `godot_webgpu` | Export | WebGPU web-export toggle + shader bake anchors (see Renderers below). |

**Layering rule:** providers produce input data (hands, platform events);
consumers turn input into interaction. Consumers may depend softly downward
(soft-loaded, inert when absent); providers never know consumers exist.

## The block catalog

Everything below is in the **XR Blocks dock**. "Self-wiring" means drop it
anywhere — under the rig, under a hands mount, at the scene root — and it
finds the rig by itself (NodePath exports are overrides, not setup).

### Sessions & rig (`godot_webxr_kit`)
| Block | What you get |
|---|---|
| **WebXR Prefab** | Everything XR in one drop: rig + both session bootstraps + hands + auto-built VR/AR entry UI. |
| **WebXR Rig** | The rig alone (origin, camera, controllers, interactors, modality, locomotion, poke) — for scenes with their own HUD. |
| **Session UI** | Enter VR/AR buttons + status HUD; the WebXR bootstrap adopts it automatically. |
| **WebXR / OpenXR Bootstrap** | Session lifecycle per platform; each is inert on the other's platform, so ship both. |
| **Hands Mount** | Procedural tracked hands; virtual meshes hide per hand while it drives a controller. |
| **Input Modality** (self-wiring, rig-default) | Per-hand controller↔hands switching + profile-matched controller models (bundled generic, device models fetched + cached at runtime). |

### Interaction (`godot_xr_interaction_toolkit`)
| Block | What you get |
|---|---|
| **Locomotion** (self-wiring, rig-default) | Teleport arc + snap turn on the thumbsticks. External drivers (microgestures, your own gestures) steer the **same** arc via its intent API. |
| **Microgesture Locomotion** (opt-in) | Thumb swipes drive that same teleport/turn. Needs `godot_xr_hands`; inert without. |
| **Poke Interactor** (self-wiring, rig-default) | Fingertip touch: press panels, **drag sliders by touch**, push 3D buttons. Controller tips poke too. |
| **Poke Button (3D)** | A physical push-button that visibly depresses and fires with hysteresis. |
| **Floor (teleportable)** | Ground in one drop: visible floor + teleport collision; in AR passthrough the solid floor hides and a translucent grid marks the teleportable area. |
| **Grabbable** | Ready grabbable: swap the mesh, collision auto-fits, highlight included. |
| **Grab Point** | Authored grip: parent INSIDE a grabbable where the hand should hold it — grabbing anywhere snaps the object into the palm, position *and* orientation (Unity attach transforms / Meta grab poses). Per-hand filter + priority; multiple points, nearest wins. |
| **Highlight / Socket Affordance** | Self-wiring child components: parent INSIDE the object, they find their interactable and mesh. |
| **Socket Interactor** | Snap-zone that grabs and holds interactables. |
| **UI Panel (3D)** | In-world panel: ordinary Godot Controls, usable by ray *and* by touch. |
| **Keyboard (XR)** | In-world keyboard: `open(initial, prompt)` → `text_submitted` / `cancelled`. |

### Hands & gestures (`godot_xr_hands`)
| Block | What you get |
|---|---|
| **Gesture Recognizer** | Hand poses as data (`.tres`): per-hand start/end signals, hysteresis + hold built in, live tuning HUD (`show_debug`). Presets included. |
| **Gesture Recorder** | Hold a pose, get a gesture — targets from your recorded means, tolerances from your own jitter. See persistence below. |
| Sequences (`XRHandSequence`) | Motion gestures as staged data (conditions + feature deltas + time windows) — the authored-swipe framework. |

### Perception (`godot_webxr_scene_understanding`)
| Block | What you get |
|---|---|
| **Occlusion / Depth** | Real-world occlusion (hard/soft) with a drag-in occludees list. |
| **Scene Mesh** | The device's room geometry: visualize, occlude, label, collide. |
| **Light Estimation** | Objects lit by (and reflecting) the real room (Android XR). |
| **Hit Test + Anchors** | Surface reticle + pinch-to-place spatial anchors. |

### WebGPU export (`godot_webgpu`)
| Block | What you get |
|---|---|
| **WebGPU toggle** | One checkbox on the web export preset produces the adaptive build. |
| **Bake / Font Bake Anchor** | Declare runtime-built materials / Label3D text so their shaders bake. |

## Authoring pipelines worth knowing

- **Record gestures like Unity's XR Hands strategy, one step shorter**: run
  the Gesture Studio over Quest Link from the editor — recordings land as
  plain `.tres` files on disk (`user://gestures`) — copy them into your
  project as shipped presets. In the **browser**, recordings persist in that
  browser's site data only (cleared with browsing data): great for per-user
  personalization, not for authoring. The Studio says this to users.
- **Controller models** follow the WebXR Input Profiles registry: the generic
  model ships bundled; device-specific models download once per device and
  cache. Runtime-parsed glTF materials are remapped onto pre-baked templates
  so they render on WebGPU exports.

## Bake-safety rules (web/WebGPU exports)

Shaders compile at export, not at runtime, on the WebGPU path:
1. No `StandardMaterial3D.new()` for rendered materials — duplicate a baked
   `.tres` and change uniforms (colors, texture-swaps, roughness).
2. Texture *presence* is codegen: swapping a texture on an already-textured
   template is safe; adding one to a textureless material is not.
3. Never VRAM-compress textures destined for WebGPU exports (import lossless).
4. Runtime-internal engine materials (Label3D…) need a bake anchor.

## Renderers

WebGL is the **recommended default** (full features, smooth XR everywhere).
The WebGPU build is the experimental opt-in chip on the launcher: Godot's
modern Mobile renderer running in XR — currently held back by the browsers'
WebXR-WebGPU bridge (an extra full-res copy per frame), not by the engine.
It lights up as browsers optimize; nothing you build against the suite cares
which renderer is active.

## Consuming the suite

**Locally (Windows, several projects on one machine)** — directory junctions
so every project sees edits instantly:

```powershell
foreach ($a in @("godot_webxr_kit","godot_xr_hands","godot_xr_interaction_toolkit","godot_webxr_scene_understanding","godot_webgpu","godot_blender_principled")) {
  New-Item -ItemType Junction -Path "<project>\addons\$a" -Target "<this repo>\addons\$a"
}
```

**Portably (team/CI)** — add this repo as a git submodule, or vendor a tagged
snapshot of `addons/*`.

Design docs and standing decisions live in [`docs/`](docs/) — start with
`architecture-decision-2026-07-17.md` and `gesture-authoring-design.md`.
