# Godot WebXR Scene Understanding

Real-world awareness for WebXR sessions, as drop-in nodes.

## Quick start: the three managers (recommended)

Drag-and-drop scene perception, mirroring the Unity / Meta component shape
(`EnvironmentDepthManager`, `ARMeshManager`, light estimation). Add a node,
set a property, done — each manager requests its own session feature, reports
per-device availability via `get_status()`, and shows editor configuration
warnings when something is mis-wired. `samples/perception_managers_demo.tscn`
is the whole thing working with **zero code**.

| Manager node | What you get | Key properties |
|---|---|---|
| `EnvironmentDepthManager` | Real-world **occlusion** (Meta parity): HARD = crisp depth-mesh punch over everything; SOFT = listed objects fade behind real surfaces (feathered, per-object). Occlusion materials are generated automatically from the pre-baked shader. Also the live depth debug view. | `occlusion_mode`, `occludees` (drag objects in; or mark objects with the `webxr_occludable` group; or `add_occludee()` at runtime), `edge_softness`, `debug_depth_visualization`, `depth_resolution` |
| `SceneMeshManager` | The device's **room geometry**, device-adaptive: stored Space-Setup mesh on Quest, live reconstruction on Android XR. | `visualize`, `occlude` (static room occlusion), `scene_labels`, `generate_collision`, `mesh_color` |
| `LightEstimationManager` | Virtual objects **lit by the real room**: SH environment sky (ambient + reflections) + a primary directional light with the room's colour/intensity/direction. Finds your WorldEnvironment automatically. | `affect_ambient`, `affect_reflections`, `create_primary_light`, `sky_intensity`, `responsiveness` |
| `HitTestAnchorManager` | **Surface placement + spatial anchors** (ARRaycastManager/ARAnchorManager): a reticle tracks real surfaces along the viewer ray; pinch/select places a platform-tracked anchor there, and your scene is instanced at it automatically. Anchors are standard `XRAnchor3D` trackers. | `show_reticle`, `reticle_scene`, `place_on_select`, `placed_scene`, `maximum_anchors`, `place_anchor()`, `clear_anchors()` |

Platform notes: depth + light estimation are Android XR strengths (Quest
serves gpu-only depth and no light estimation at all — see
`samples/LIGHT_ESTIMATION_NOTES.md`); room mesh is a Quest strength (Android
XR needs chrome://flags). The managers stay drop-in-safe everywhere —
unsupported features report themselves honestly instead of breaking, and
everything is inert outside a web export.

## The acquisition bridges (advanced)

The bridges are the layer the managers wrap — use them directly when you need
custom behavior:

| Node | Feature | WebXR API | Works out of the box on |
|---|---|---|---|
| `webxr_mesh_bridge.gd` | Room mesh + semantic scene labels + static room-mesh occlusion | `mesh-detection` (`frame.detectedMeshes`) + `plane-detection` for labels on platforms whose meshes are untagged (Quest) | Quest (Space Setup). Android XR requires chrome://flags → WebXR Incubations. |
| `webxr_depth_bridge.gd` | Live depth sensing → world-anchored depth mesh + **real-world occlusion** (Hard: live depth-mesh punch; Soft: per-object feathered `occlusion_object.gdshader`) | `depth-sensing` CPU path (`frame.getDepthInformation`) | Android XR (WebGL sessions). Quest grants **gpu-optimized only**, decoded via a grid-sized readback shader. |

Every node reports an honest `get_status()` for its path on the current
device, including "behind browser flags" and "upcoming browser feature"
cases — wire it to a status label.

## Environmental light estimation

`webxr_light_estimation_bridge.gd` requests the optional `light-estimation`
feature and publishes the primary light direction/intensity plus all nine RGB
spherical-harmonic coefficients. `light_estimation_demo.tscn` applies the SH
field in a Godot shader and maps the primary estimate to a
`DirectionalLight3D`.

The demo presents one large XR Toolkit grabbable hero material instead of a
fixed swatch grid. Its in-world slider panel controls metallic, roughness,
color hue, SH estimate gain, and reflection/specular response, with material
presets and LIVE/FROZEN/NEUTRAL comparison modes. These controls alter only
the virtual material; the WebXR measurements remain read-only.

Browser-owned reflection cubemaps are detected and reported, but importing
their native GPU texture into Godot remains a separate renderer-interop slice.

## Hit testing and anchors

`webxr_hit_test_anchor_bridge.gd` publishes viewer-ray surface hits and stable
anchor transforms using the optional `hit-test` and `anchors` features. The
bridge owns the browser anchor objects and their deletion; consumers only
respond to hit/anchor lifecycle signals. `hit_test_anchors_demo.tscn` provides
the reference reticle, select-to-place flow, tracked beacons, and diagnostics.

**Anchors drive standard `XRAnchor3D` nodes.** Each anchor is registered as an
`XRServer` anchor tracker (`TRACKER_ANCHOR`, named `webxr_anchor_<id>`) and its
pose is fed every frame — so you place anchors with Godot's stock `XRAnchor3D`
node, exactly as you would on OpenXR. Two ways:

- **Zero wiring:** set the bridge's `anchor_node_root` to your `XROrigin3D`. It
  spawns an `XRAnchor3D` per anchor and emits `anchor_node_added(id, node)` —
  attach your visuals to `node`.
- **Your own nodes:** from `anchor_added(id, xf)`, add an `XRAnchor3D` under your
  `XROrigin3D` with `tracker = bridge.get_anchor_tracker_name(id)`, `pose = "default"`.

The lifecycle signals stay for non-node consumers.

## Session features: the `webxr_feature_provider` contract

Nodes in the `webxr_feature_provider` group declare the WebXR session
features they need:

```gdscript
func get_webxr_required_features(session_mode: String) -> PackedStringArray
func get_webxr_optional_features(session_mode: String) -> PackedStringArray
```

`webxr_bootstrap.gd` (godot_webxr_kit ≥ 1.5.0) collects these before
requesting the session, so scenes only request what the nodes they actually
contain need — leaner requests enter immersive mode faster (Android XR
charges startup ceremony per feature family).

## Dependencies

The runtime scripts are dependency-free (pure GDScript, renderer-agnostic —
verified on both the WebGL and WebGPU rendering paths). The sample demo
scene composes `godot_webxr_kit` (session bootstrap, input) and
`godot_xr_interaction_toolkit` (toggle panel, grabbable objects).

## Bake note (WebGPU exports)

All materials are `.tres` files with shader-codegen flags frozen in the
resource (transparency, cull, vertex color), so shader-baked web exports
keep their hashes. Scripts only `duplicate()` them and touch uniforms.
