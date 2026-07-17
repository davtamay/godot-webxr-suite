@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRGestureGhostHand
extends Node3D

## A joints-and-bones ghost hand with two modes:
## - show_gesture(): displays a gesture's recorded joint snapshot, slowly
##   yaw-rotating, as LEFT, RIGHT, or BOTH hands - the snapshot is mirrored
##   for the hand that did not record it (a wrist-local x-flip swaps
##   chirality), so one recording represents the pose on either hand.
## - start_live(): mirrors the user's live tracked hand in real time - during
##   recording you watch exactly what is being captured.
## set_highlight(true) tints it green (e.g. while the user matches the pose).

enum HandMode { LEFT, RIGHT, BOTH }

const _LINE_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_line_material.tres")
const _FeatureExtractor := preload("res://addons/godot_xr_interaction_toolkit/runtime/gestures/xr_hand_feature_extractor.gd")

const _GHOST_COLOR := Color(0.45, 0.85, 1.0, 0.9)
const _MATCH_COLOR := Color(0.3, 1.0, 0.5, 0.95)
const _LIVE_COLOR := Color(1.0, 0.85, 0.4, 0.95)
const _BOTH_SPACING := 0.13

## Degrees per second of yaw spin while showing a static pose (0 = static).
@export_range(0.0, 180.0, 5.0) var rotate_speed := 40.0

## Uniform scale applied to the displayed hand (1 = life size).
@export_range(0.5, 3.0, 0.1) var display_scale := 1.4

## Which hand(s) the static display shows.
@export var hand_mode: HandMode = HandMode.BOTH:
	set(value):
		hand_mode = value
		if _gesture and _live_hand < 0:
			show_gesture(_gesture)

var _rigs: Array = []
var _material: StandardMaterial3D
var _gesture: XRHandGesture
var _live_hand := -1
var _highlight := false


func _ready() -> void:
	_material = _LINE_MATERIAL.duplicate() as StandardMaterial3D
	_material.albedo_color = _GHOST_COLOR
	_rigs = [_build_skeleton(), _build_skeleton()]
	visible = false


func _process(delta: float) -> void:
	if _live_hand >= 0:
		var tracker := XRServer.get_tracker("/user/hand_tracker/%s" % ("left" if _live_hand == 0 else "right")) as XRHandTracker
		if tracker and tracker.has_tracking_data:
			var wrist_inverse := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_WRIST).affine_inverse()
			var frame := PackedVector3Array()
			frame.resize(XRHandTracker.HAND_JOINT_MAX)
			for joint in XRHandTracker.HAND_JOINT_MAX:
				frame[joint] = wrist_inverse * tracker.get_hand_joint_transform(joint).origin
			_apply_positions(0, frame)
			(_rigs[0]["root"] as Node3D).visible = true
			(_rigs[1]["root"] as Node3D).visible = false
			visible = true
	elif visible:
		for rig in _rigs:
			(rig["root"] as Node3D).rotate_y(deg_to_rad(rotate_speed) * delta)


## Show a gesture's recorded snapshot per hand_mode (returns false and hides
## when the gesture has none - recognition-only presets).
func show_gesture(gesture: XRHandGesture) -> bool:
	_live_hand = -1
	_gesture = gesture
	if gesture == null or gesture.joint_snapshot.size() < XRHandTracker.HAND_JOINT_MAX:
		visible = false
		return false
	# The snapshot's native chirality; mirror (wrist-local x-flip) for the
	# other hand. Authored gestures without a recorded hand display as-is.
	var native_hand := gesture.recorded_hand if gesture.recorded_hand >= 0 else 1
	var shown := [hand_mode == HandMode.LEFT or hand_mode == HandMode.BOTH,
			hand_mode == HandMode.RIGHT or hand_mode == HandMode.BOTH]
	for hand in 2:
		var rig_root := _rigs[hand]["root"] as Node3D
		rig_root.visible = shown[hand]
		if not shown[hand]:
			continue
		var snapshot := gesture.joint_snapshot
		if hand != native_hand:
			snapshot = _mirrored(snapshot)
		_apply_positions(hand, snapshot)
		rig_root.rotation = Vector3.ZERO
		rig_root.position = Vector3.ZERO
	if hand_mode == HandMode.BOTH:
		(_rigs[0]["root"] as Node3D).position = Vector3(-_BOTH_SPACING, 0.0, 0.0)
		(_rigs[1]["root"] as Node3D).position = Vector3(_BOTH_SPACING, 0.0, 0.0)
	visible = true
	return true


## Mirror the live tracked hand (0 = left, 1 = right) until stop_live().
func start_live(hand: int) -> void:
	_live_hand = clampi(hand, 0, 1)
	var rig_root := _rigs[0]["root"] as Node3D
	rig_root.rotation = Vector3.ZERO
	rig_root.position = Vector3.ZERO
	_material.albedo_color = _LIVE_COLOR


func stop_live() -> void:
	_live_hand = -1
	_material.albedo_color = _MATCH_COLOR if _highlight else _GHOST_COLOR
	if _gesture:
		show_gesture(_gesture)


## Green tint while the user's hand matches the displayed pose.
func set_highlight(on: bool) -> void:
	_highlight = on
	if _live_hand < 0:
		_material.albedo_color = _MATCH_COLOR if on else _GHOST_COLOR


func _build_skeleton() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.007
	joint_mesh.height = 0.014
	var spheres: Array[MeshInstance3D] = []
	for joint in XRHandTracker.HAND_JOINT_MAX:
		var sphere := MeshInstance3D.new()
		sphere.mesh = joint_mesh
		sphere.material_override = _material
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sphere)
		spheres.append(sphere)
	var bone_mesh := ImmediateMesh.new()
	var bones := MeshInstance3D.new()
	bones.mesh = bone_mesh
	bones.material_override = _material
	bones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bones)
	return {"root": root, "spheres": spheres, "bone_mesh": bone_mesh}


func _apply_positions(rig_index: int, snapshot: PackedVector3Array) -> void:
	var rig: Dictionary = _rigs[rig_index]
	var spheres: Array[MeshInstance3D] = rig["spheres"]
	var bone_mesh: ImmediateMesh = rig["bone_mesh"]
	var center := Vector3.ZERO
	for point in snapshot:
		center += point
	center /= snapshot.size()
	for joint in XRHandTracker.HAND_JOINT_MAX:
		spheres[joint].position = (snapshot[joint] - center) * display_scale
	bone_mesh.clear_surfaces()
	bone_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for finger in _FeatureExtractor.FINGERS:
		var chain: Array = _FeatureExtractor.FINGERS[finger]
		bone_mesh.surface_add_vertex((snapshot[XRHandTracker.HAND_JOINT_WRIST] - center) * display_scale)
		bone_mesh.surface_add_vertex((snapshot[chain[0]] - center) * display_scale)
		for i in range(chain.size() - 1):
			bone_mesh.surface_add_vertex((snapshot[chain[i]] - center) * display_scale)
			bone_mesh.surface_add_vertex((snapshot[chain[i + 1]] - center) * display_scale)
	bone_mesh.surface_end()


func _mirrored(snapshot: PackedVector3Array) -> PackedVector3Array:
	var flipped := PackedVector3Array()
	flipped.resize(snapshot.size())
	for i in snapshot.size():
		var point := snapshot[i]
		flipped[i] = Vector3(-point.x, point.y, point.z)
	return flipped
