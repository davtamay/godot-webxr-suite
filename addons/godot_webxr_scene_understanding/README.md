# Godot WebXR Scene Understanding

Real-world awareness for WebXR sessions, as drop-in nodes:

| Node | Feature | WebXR API | Works out of the box on |
|---|---|---|---|
| `webxr_mesh_bridge.gd` | Room mesh + semantic scene labels | `mesh-detection` (`frame.detectedMeshes`) + `plane-detection` for labels on platforms whose meshes are untagged (Quest) | Quest (Space Setup). Android XR requires chrome://flags → WebXR Incubations. |
| `webxr_occluder.gd` | Real-world occlusion of rendered content | room mesh (static) today; live sensor depth upcoming | Quest; Android XR behind the same flag |
| `webxr_depth_bridge.gd` | Live depth sensing → world-anchored depth mesh | `depth-sensing` CPU path (`frame.getDepthInformation`) | Android XR (WebGL sessions). Quest grants **gpu-optimized only** — the node reports it honestly; GPU-path consumption is future work. |

Every node reports an honest `get_status()` for its path on the current
device, including "behind browser flags" and "upcoming browser feature"
cases — wire it to a status label.

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
