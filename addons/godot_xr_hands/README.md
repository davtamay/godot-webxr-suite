# Godot XR Hands

A procedural hand-joint visualizer for XR: spheres at the tracked joints and
bones between them, driven by Godot's `XRHandTracker`. Presentation only — it
draws hands, it does not implement interaction. Pure GDScript.

**Requires** the `godot_xr_interaction_toolkit` addon (uses its `XRInputAdapter`
handedness enum and `XRHandTrackerResolver`). It does **not** require
`godot_webxr_kit`.

## Contents

```text
addons/godot_xr_hands/
  plugin.cfg / plugin.gd
  runtime/
    hand_visualizer.gd    # procedural joint spheres + bones from XRHandTracker
```

## Usage

Add a `Node3D` under your `XROrigin3D`, attach `hand_visualizer.gd`, and (if you
want the fallback pose when joints are briefly unproven) point its
`left_fallback_pose_path` / `right_fallback_pose_path` at your `XRController3D`
nodes. Joint data comes from `XRHandTracker` at `/user/hand_tracker/left|right`,
which any WebXR or native OpenXR runtime that supports hand tracking populates —
so this package works standalone, without WebXR.

## Optional WebXR acceleration

On Quest Browser, `XRHandTracker` joints arrive late/partial for the first
seconds of a session. If `godot_webxr_kit` (and its custom HTML shell) is also
installed, the visualizer feature-detects the shell's `window.CompanyWebXRHandBridge`
JS global and uses those raw WebXR joints for an immediate, stable startup. This
is a runtime feature-detection (a `JavaScriptBridge.eval` string), **not** a
load-time dependency — the package loads and runs fine without the WebXR kit,
degrading to `XRHandTracker`.

## Note

This visualizer is a diagnostic/placeholder hand. It is designed so a rigged
hand mesh can replace it later; the joint transforms it reads are the same data
a skinned hand model would bind to.
