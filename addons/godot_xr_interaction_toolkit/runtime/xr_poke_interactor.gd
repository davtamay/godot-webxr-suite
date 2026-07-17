@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg")
class_name XRPokeInteractor
extends Node

## Fingertip poke input as one block: tracks each hand's INDEX TIP (falling
## back to the controller tip while a hand drives a controller) and feeds it
## to everything pokeable - UI panels (press buttons and DRAG SLIDERS by
## touch) and XRPokeButton 3D push-buttons. Optional fingertip markers show
## exactly where the poke point is.
##
## Built into WebXRRig, so every rig/prefab scene is pokeable by default.

const _RETICLE_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_reticle_material.tres")
const XRHandGestureProvider := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_gesture_provider.gd")

## Group other blocks use to find poke sources.
const GROUP := "xr_poke_interactor"
## How far in front of the controller's aim origin the poke tip sits.
const _CONTROLLER_TIP_FORWARD := 0.02

@export var enabled := true

@export_group("Rig")
## All optional: empty paths self-resolve (drop the node anywhere - under the
## rig, under a hands mount, or at the scene root - and it finds the rig).
@export var xr_origin_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath

## Small dot on each active poke point - the aiming affordance.
@export var show_markers := true

var _origin: Node3D
var _controllers: Array = [null, null]
var _points := [Vector3.INF, Vector3.INF]
var _markers: Array = [null, null]


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	add_to_group(GROUP)
	_origin = get_node_or_null(xr_origin_path) as Node3D
	if _origin == null:
		_origin = XRRigResolver.find_origin(self)
	_controllers[0] = get_node_or_null(left_controller_path) as XRController3D
	_controllers[1] = get_node_or_null(right_controller_path) as XRController3D
	for hand in 2:
		if _controllers[hand] == null:
			_controllers[hand] = XRRigResolver.find_controller(self, hand)


## World-space poke point for a hand; Vector3.INF when none is tracked.
func get_poke_point(hand: int) -> Vector3:
	return _points[hand] if hand >= 0 and hand < 2 else Vector3.INF


func _physics_process(_delta: float) -> void:
	if not enabled:
		_points = [Vector3.INF, Vector3.INF]
		_update_markers()
		_feed_panels()
		return
	for hand in 2:
		_points[hand] = _resolve_point(hand)
	_update_markers()
	_feed_panels()


func _resolve_point(hand: int) -> Vector3:
	# Bare hand: the index fingertip.
	var tracker := XRServer.get_tracker("/user/hand_tracker/%s" % ("left" if hand == 0 else "right")) as XRHandTracker
	if tracker and tracker.has_tracking_data and _origin:
		var tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
		if XRHandGestureProvider.joint_position_valid(tracker, tip):
			return _origin.global_transform * tracker.get_hand_joint_transform(tip).origin
	# Controller in hand: the controller's tip.
	var controller := _controllers[hand] as XRController3D
	if controller and controller.get_is_active() and controller.get_has_tracking_data():
		return controller.global_transform * Vector3(0.0, 0.0, -_CONTROLLER_TIP_FORWARD)
	return Vector3.INF


func _feed_panels() -> void:
	for panel in get_tree().get_nodes_in_group("xr_ui_canvas"):
		for hand in 2:
			if _points[hand] == Vector3.INF:
				panel.poke_end(hand)
			else:
				panel.poke_update(hand, _points[hand])


func _update_markers() -> void:
	for hand in 2:
		var has_point: bool = _points[hand] != Vector3.INF
		if not show_markers or not has_point:
			if _markers[hand]:
				(_markers[hand] as Node3D).visible = false
			continue
		if _markers[hand] == null:
			var marker := MeshInstance3D.new()
			marker.top_level = true
			var dot := SphereMesh.new()
			dot.radius = 0.005
			dot.height = 0.01
			marker.mesh = dot
			var material := _RETICLE_MATERIAL.duplicate() as StandardMaterial3D
			material.albedo_color = Color(0.5, 0.9, 1.0, 0.85)
			marker.material_override = material
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(marker)
			_markers[hand] = marker
		(_markers[hand] as Node3D).visible = true
		(_markers[hand] as Node3D).global_position = _points[hand]
