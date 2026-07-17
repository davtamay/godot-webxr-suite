@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRGestureGhostHand
extends Node3D

## Displays an XRHandGesture's recorded joint snapshot as a ghost hand -
## joints as spheres, bones as lines - slowly rotating on its yaw so the full
## pose can be inspected from every side. Place it on a pedestal next to a
## gesture library UI; call show_gesture() on selection.
##
## Gestures without a snapshot (hand-authored .tres presets) show nothing -
## recognition uses the feature conditions, the snapshot exists purely for
## representation.

const _LINE_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_line_material.tres")
const _FeatureExtractor := preload("res://addons/godot_xr_interaction_toolkit/runtime/gestures/xr_hand_feature_extractor.gd")

const _GHOST_COLOR := Color(0.45, 0.85, 1.0, 0.9)

## Degrees per second of yaw spin (0 = static).
@export_range(0.0, 180.0, 5.0) var rotate_speed := 40.0

## Uniform scale applied to the snapshot (1 = life size).
@export_range(0.5, 3.0, 0.1) var display_scale := 1.4

var _display: Node3D
var _bone_mesh := ImmediateMesh.new()


func _ready() -> void:
	set_process(rotate_speed > 0.0)


func _process(delta: float) -> void:
	if _display:
		_display.rotate_y(deg_to_rad(rotate_speed) * delta)


## Show a gesture's snapshot (clears when null or snapshot-less).
func show_gesture(gesture: XRHandGesture) -> bool:
	if _display:
		_display.queue_free()
		_display = null
	if gesture == null or gesture.joint_snapshot.size() < XRHandTracker.HAND_JOINT_MAX:
		return false

	_display = Node3D.new()
	add_child(_display)
	var snapshot := gesture.joint_snapshot
	# Center the wrist-local cloud so it spins around its own middle.
	var center := Vector3.ZERO
	for point in snapshot:
		center += point
	center /= snapshot.size()

	var joint_mesh := SphereMesh.new()
	joint_mesh.radius = 0.007
	joint_mesh.height = 0.014
	var material := _LINE_MATERIAL.duplicate() as StandardMaterial3D
	material.albedo_color = _GHOST_COLOR
	for joint in XRHandTracker.HAND_JOINT_MAX:
		var sphere := MeshInstance3D.new()
		sphere.mesh = joint_mesh
		sphere.material_override = material
		sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sphere.position = (snapshot[joint] - center) * display_scale
		_display.add_child(sphere)

	var bones := MeshInstance3D.new()
	bones.mesh = _bone_mesh
	bones.material_override = material
	bones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_display.add_child(bones)
	return true
