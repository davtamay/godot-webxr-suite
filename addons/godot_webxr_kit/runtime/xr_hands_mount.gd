@icon("res://addons/godot_webxr_kit/icons/xr_hands_mount.svg")
class_name XRHandsMount
extends Node3D

## Drop-in procedural tracked hands with the AR-passthrough rule built in.
##
## Parent this node under an XROrigin3D and it soft-loads godot_xr_hands' hand
## visualizer (skipped cleanly when that addon isn't installed) and hides the
## virtual hand meshes during AR passthrough - in AR you see your REAL hands
## (virtual ones would draw on top of them); in VR the virtual hands return.
## Hand INPUT (pinch, rays, grab) is unaffected either way.
##
## This is THE one place that rule lives: WebXRPrefab uses it, and any
## rig-based scene adds one of these instead of hand-wiring the visualizer.

const HAND_VISUALIZER := "res://addons/godot_xr_hands/runtime/hand_visualizer.gd"

## Show the virtual hand meshes during AR passthrough too (off = real hands).
@export var virtual_hands_in_ar := false

## Forwarded to the visualizer; false = XRHandTracker joints on every platform.
@export var prefer_browser_hand_bridge := false

## The group WebXRBootstrap hides during AR passthrough.
@export var ar_hide_group := "ar_passthrough_hidden"


func _ready() -> void:
	if not ResourceLoader.exists(HAND_VISUALIZER):
		return  # godot_xr_hands not installed; nothing to mount.
	var hands: Node3D = load(HAND_VISUALIZER).new()
	hands.prefer_browser_hand_bridge = prefer_browser_hand_bridge
	# The visualizer manages its own visibility (tracking watchdog), so the AR
	# hide targets THIS mount - the two never fight.
	add_child(hands)
	if not virtual_hands_in_ar:
		add_to_group(ar_hide_group)
