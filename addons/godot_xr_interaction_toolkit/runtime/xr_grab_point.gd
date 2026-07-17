@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRGrabPoint
extends Node3D

## An authored grip pose, as a self-wiring CHILD: parent this inside a grab
## interactable and place it where the HAND should hold the object - the
## handle of a mug, the hilt of a sword. Grabbing then SNAPS the object so
## this point lands in the hand (position AND orientation), instead of the
## object hanging wherever the ray touched it.
##
## Multiple grab points per object are fine - the nearest matching one wins
## at grab time. Orientation convention: the point's axes ARE the hand's axes
## when held - -Z = forward (aim direction), +Y = up out of the top of the
## clenched fist. A wand/torch whose long axis is its own +Y needs NO point
## rotation; rotate the point only to change how the object sits in the fist.
##
## In the editor the point draws a small palm bar + forward arrow so grips
## are authorable visually.

## Restrict this grip to one hand (-1 = either).
@export_enum("Any:-1", "Left:0", "Right:1") var hand := -1

## When several points match, higher priority wins before distance.
@export var priority := 0

var _interactable: Node


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	var cursor := get_parent()
	while cursor != null and not cursor.has_method("register_grab_point"):
		cursor = cursor.get_parent()
	_interactable = cursor
	if _interactable:
		_interactable.register_grab_point(self)


func _exit_tree() -> void:
	if _interactable and is_instance_valid(_interactable):
		_interactable.unregister_grab_point(self)
	_interactable = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_build_editor_marker()


func _get_configuration_warnings() -> PackedStringArray:
	var cursor := get_parent()
	while cursor != null:
		if cursor.has_method("register_grab_point"):
			return PackedStringArray()
		cursor = cursor.get_parent()
	return PackedStringArray(["Place this INSIDE a grab interactable (any ancestor)."])


func matches_hand(interactor_hand: int) -> bool:
	return hand < 0 or hand == interactor_hand


## Editor-only visual: a palm bar with a forward (-Z) arrow. Not saved into
## the scene (no owner), zero runtime cost.
func _build_editor_marker() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 1.0, 0.6, 0.9)

	var palm := MeshInstance3D.new()
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.05, 0.012, 0.03)
	palm.mesh = palm_mesh
	palm.material_override = material
	add_child(palm)

	var arrow := MeshInstance3D.new()
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.008
	arrow_mesh.height = 0.045
	arrow.mesh = arrow_mesh
	arrow.material_override = material
	arrow.position = Vector3(0.0, 0.0, -0.035)
	arrow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(arrow)
