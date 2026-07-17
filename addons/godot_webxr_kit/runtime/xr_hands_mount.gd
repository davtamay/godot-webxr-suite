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
const HAND_MESH_VISUALIZER := "res://addons/godot_xr_hands/runtime/xr_hand_mesh_visualizer.gd"

enum HandStyle { PROCEDURAL, REALISTIC }

## Virtual hand look. PROCEDURAL = capsule joints/bones; REALISTIC = the
## bundled WebXR Input Profiles rigged hand mesh (MIT) skinned live to the
## tracked joints. Realistic falls back to procedural if unavailable.
@export var hand_style := HandStyle.PROCEDURAL

## Show the virtual hand meshes during AR passthrough too. Default ON: without
## real-hand depth occlusion, virtual objects draw OVER your passthrough hands,
## so hiding the virtual meshes leaves you handless exactly while interacting.
## Turn OFF for scenes that ship hand/depth occlusion (e.g. the scene-
## understanding EnvironmentDepthManager) - there your real hands stay visible.
@export var virtual_hands_in_ar := true

## Forwarded to the visualizer; false = XRHandTracker joints on every platform.
@export var prefer_browser_hand_bridge := false

## The group WebXRBootstrap hides during AR passthrough.
@export var ar_hide_group := "ar_passthrough_hidden"

## Hide a hand's virtual mesh while THAT hand is driving a controller (the
## Unity-XRI visual swap: you see the controller model instead of the hand).
## With multimodal runtimes (simultaneous hands + controllers) hand joints keep
## tracking over a held controller, so without this the virtual hand draws
## wrapped around the controller model. Off = Meta-Home-style hands-over-
## controller presentation. Needs an XRInputModalityManager in the scene.
@export var hide_hand_while_using_controller := true

var _hands: Node3D


func _ready() -> void:
	var script_path := HAND_VISUALIZER
	if hand_style == HandStyle.REALISTIC and ResourceLoader.exists(HAND_MESH_VISUALIZER):
		script_path = HAND_MESH_VISUALIZER
	if not ResourceLoader.exists(script_path):
		return  # godot_xr_hands not installed; nothing to mount.
	_hands = load(script_path).new()
	if "prefer_browser_hand_bridge" in _hands:
		_hands.prefer_browser_hand_bridge = prefer_browser_hand_bridge
	# The visualizer manages its own visibility (tracking watchdog), so the AR
	# hide targets THIS mount - the two never fight.
	add_child(_hands)
	if not virtual_hands_in_ar:
		add_to_group(ar_hide_group)
	if hide_hand_while_using_controller:
		_connect_modality.call_deferred()


func _connect_modality() -> void:
	var manager := get_tree().get_first_node_in_group(XRInputModalityManager.GROUP)
	if manager == null or not manager.has_signal("modality_changed"):
		return  # No modality manager in the scene - hands stay always-on.
	manager.modality_changed.connect(_on_modality_changed)
	for hand in 2:
		_on_modality_changed(hand, manager.get_modality(hand))


func _on_modality_changed(hand: int, modality: int) -> void:
	if _hands == null:
		return
	var side := "Right" if hand == 1 else "Left"
	var hand_root := _hands.get_node_or_null("%sHandTracking" % side)
	if hand_root == null:
		return
	# Hide via render layers, not `visible` - the visualizer's own tracking
	# watchdog drives `visible` and would fight (and win) every frame.
	var shown := modality != XRInputModalityManager.Modality.CONTROLLER
	for mesh in hand_root.find_children("*", "VisualInstance3D", true, false):
		mesh.layers = 1 if shown else 0
