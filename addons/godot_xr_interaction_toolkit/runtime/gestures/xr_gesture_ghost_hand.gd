@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRGestureGhostHand
extends Node3D

## A joints-and-bones ghost hand with two modes:
## - show_gesture(): displays a gesture's recorded joint snapshot, slowly
##   yaw-rotating so the pose reads from every side (the REFERENCE view).
## - start_live(): mirrors the user's live tracked hand in real time - during
##   recording you watch exactly what is being captured.
## set_highlight(true) tints it green (e.g. while the user's hand matches the
## displayed gesture).

const _LINE_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_line_material.tres")
const _FeatureExtractor := preload("res://addons/godot_xr_interaction_toolkit/runtime/gestures/xr_hand_feature_extractor.gd")

const _GHOST_COLOR := Color(0.45, 0.85, 1.0, 0.9)
const _MATCH_COLOR := Color(0.3, 1.0, 0.5, 0.95)
const _LIVE_COLOR := Color(1.0, 0.85, 0.4, 0.95)

## Degrees per second of yaw spin while showing a static pose (0 = static).
@export_range(0.0, 180.0, 5.0) var rotate_speed := 40.0

## Uniform scale applied to the displayed hand (1 = life size).
@export_range(0.5, 3.0, 0.1) var display_scale := 1.4

var _display: Node3D
var _spheres: Array[MeshInstance3D] = []
var _bone_mesh := ImmediateMesh.new()
var _material: StandardMaterial3D
var _live_hand := -1
var _highlight := false


func _ready() -> void:
	_build_skeleton()
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
			_apply_positions(frame)
			visible = true
	elif _display and visible:
		_display.rotate_y(deg_to_rad(rotate_speed) * delta)


## Show a gesture's recorded snapshot (returns false and hides when the
## gesture has none - recognition-only presets).
func show_gesture(gesture: XRHandGesture) -> bool:
	_live_hand = -1
	if gesture == null or gesture.joint_snapshot.size() < XRHandTracker.HAND_JOINT_MAX:
		visible = false
		return false
	_apply_positions(gesture.joint_snapshot)
	visible = true
	return true


## Mirror the live tracked hand (0 = left, 1 = right) until stop_live().
func start_live(hand: int) -> void:
	_live_hand = clampi(hand, 0, 1)
	_display.rotation = Vector3.ZERO
	_set_color(_LIVE_COLOR)


func stop_live() -> void:
	_live_hand = -1
	_set_color(_MATCH_COLOR if _highlight else _GHOST_COLOR)


## Green tint while the user's hand matches the displayed pose.
func set_highlight(on: bool) -> void:
	_highlight = on
	if _live_hand < 0:
		_set_color(_MATCH_COLOR if on else _GHOST_COLOR)


func _build_skeleton() -> void:
	_display = Node3D.new()
	add_child(_display)
	_material = _LINE_MATERIAL.duplicate() as StandardMaterial3D
	_material.albedo_color = _GHOST_COLOR
	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.007
	joint_mesh.height = 0.014
	for joint in XRHandTracker.HAND_JOINT_MAX:
		var sphere := MeshInstance3D.new()
		sphere.mesh = joint_mesh
		sphere.material_override = _material
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_display.add_child(sphere)
		_spheres.append(sphere)
	var bones := MeshInstance3D.new()
	bones.mesh = _bone_mesh
	bones.material_override = _material
	bones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_display.add_child(bones)


func _apply_positions(snapshot: PackedVector3Array) -> void:
	var center := Vector3.ZERO
	for point in snapshot:
		center += point
	center /= snapshot.size()
	for joint in XRHandTracker.HAND_JOINT_MAX:
		_spheres[joint].position = (snapshot[joint] - center) * display_scale
	_bone_mesh.clear_surfaces()
	_bone_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for finger in _FeatureExtractor.FINGERS:
		var chain: Array = _FeatureExtractor.FINGERS[finger]
		_bone_mesh.surface_add_vertex((snapshot[XRHandTracker.HAND_JOINT_WRIST] - center) * display_scale)
		_bone_mesh.surface_add_vertex((snapshot[chain[0]] - center) * display_scale)
		for i in range(chain.size() - 1):
			_bone_mesh.surface_add_vertex((snapshot[chain[i]] - center) * display_scale)
			_bone_mesh.surface_add_vertex((snapshot[chain[i + 1]] - center) * display_scale)
	_bone_mesh.surface_end()


func _set_color(color: Color) -> void:
	if _material:
		_material.albedo_color = color
