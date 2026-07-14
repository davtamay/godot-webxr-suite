@tool
extends EditorPlugin

## WebXR platform layer. Plain class_name scripts, so it works with the plugin
## disabled. Requires godot_xr_interaction_toolkit (the abstract XRInputAdapter
## and XRHandTracker helpers it builds on).
##
## WebGPU build tooling (the WebGPU export toggle and the BakeAnchor node) lives
## in the standalone godot_webgpu addon — this kit does not depend on it.
