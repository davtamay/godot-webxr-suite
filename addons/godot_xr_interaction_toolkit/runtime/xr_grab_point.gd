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

## AUTHORING AID (editor only): show a translucent reference HAND gripping the
## object exactly as it will at runtime (same grip convention). Move/rotate this
## grab point until the hand holds the object naturally - then it's correct
## in-headset, no guessing. The preview is never saved and never appears in-game.
@export var preview_hand := false: set = _set_preview_hand

const _HAND_MODEL_PATH := "res://addons/godot_xr_hands/models/generic_hand/right.glb"

var _interactable: Node
var _hand_preview: Node3D


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
		if preview_hand:
			_rebuild_hand_preview()


func _set_preview_hand(value: bool) -> void:
	preview_hand = value
	if is_inside_tree() and Engine.is_editor_hint():
		_rebuild_hand_preview()


## Editor-only ghost hand whose GRIP coincides with this grab point (built from
## the model's bind-pose joints with the SAME basis the live grip uses), so what
## you see gripping the object here is what you get in-headset.
func _rebuild_hand_preview() -> void:
	if _hand_preview and is_instance_valid(_hand_preview):
		_hand_preview.queue_free()
	_hand_preview = null
	if not preview_hand or not Engine.is_editor_hint():
		return
	var packed := load(_HAND_MODEL_PATH) as PackedScene
	if packed == null:
		return
	var ghost := packed.instantiate() as Node3D
	if ghost == null:
		return
	add_child(ghost)
	var skeleton := _find_skeleton(ghost)
	if skeleton == null:
		return
	var wrist := skeleton.find_bone("wrist")
	var index := skeleton.find_bone("index-finger-phalanx-proximal")
	var pinky := skeleton.find_bone("pinky-finger-phalanx-proximal")
	# No "palm" bone in the model; the middle metacarpal sits nearest the
	# tracker's palm joint (the runtime grip origin), so use it as the proxy.
	var palm := skeleton.find_bone("middle-finger-metacarpal")
	if wrist < 0 or index < 0 or pinky < 0:
		return
	var s2w := skeleton.global_transform
	var wrist_p: Vector3 = s2w * skeleton.get_bone_global_rest(wrist).origin
	var index_p: Vector3 = s2w * skeleton.get_bone_global_rest(index).origin
	var pinky_p: Vector3 = s2w * skeleton.get_bone_global_rest(pinky).origin
	var origin_p := s2w * skeleton.get_bone_global_rest(palm).origin if palm >= 0 else wrist_p
	var forward := (index_p - wrist_p).normalized()
	var across := pinky_p - index_p
	if forward.length_squared() < 0.000001 or across.length_squared() < 0.000001:
		return
	var up := forward.cross(across.normalized()).normalized()
	var grip_world := Transform3D(Basis(up.cross(-forward).normalized(), up, -forward).orthonormalized(), origin_p)
	# Place the ghost so its grip lands on this grab point.
	var grip_rel_hand := ghost.global_transform.affine_inverse() * grip_world
	ghost.global_transform = global_transform * grip_rel_hand.affine_inverse()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


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
