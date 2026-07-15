extends Node3D

## Starter scene root. If godot_xr_hands is installed (soft dependency), drop its
## procedural hand visualizer under the rig's XR origin so tracked hands render on
## both WebXR and OpenXR (Quest Link / SteamVR / Android XR). Skipped gracefully
## when the addon isn't present, so the starter still runs kit-only.

const HAND_VISUALIZER := "res://addons/godot_xr_hands/runtime/hand_visualizer.gd"


func _ready() -> void:
	if not ResourceLoader.exists(HAND_VISUALIZER):
		return
	var origin := get_node_or_null("WebXRRig/XROrigin3D")
	if origin == null:
		return
	var hands: Node3D = load(HAND_VISUALIZER).new()
	# Use the standard XRHandTracker on every platform (no browser JS bridge),
	# so the same hands show on WebXR and native OpenXR.
	hands.prefer_browser_hand_bridge = false
	origin.add_child(hands)
