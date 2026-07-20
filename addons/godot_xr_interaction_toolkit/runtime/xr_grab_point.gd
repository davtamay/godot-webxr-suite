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

## Which pose the preview hand makes, so you can place a grip against the
## HELD shape (a pinch for a pen, a relaxed grip for a mug/wand, ...).
@export_enum("Open", "Relaxed Grip", "Pinch", "Fist") var preview_pose := "Relaxed Grip": set = _set_preview_pose

const _HAND_MODEL_PATH := "res://addons/godot_xr_hands/models/generic_hand/right.glb"

## Finger chains (metacarpal -> tip) on the generic-hand skeleton.
const _CHAINS := {
	"thumb": ["thumb-metacarpal", "thumb-phalanx-proximal", "thumb-phalanx-distal", "thumb-tip"],
	"index": ["index-finger-metacarpal", "index-finger-phalanx-proximal", "index-finger-phalanx-intermediate", "index-finger-phalanx-distal", "index-finger-tip"],
	"middle": ["middle-finger-metacarpal", "middle-finger-phalanx-proximal", "middle-finger-phalanx-intermediate", "middle-finger-phalanx-distal", "middle-finger-tip"],
	"ring": ["ring-finger-metacarpal", "ring-finger-phalanx-proximal", "ring-finger-phalanx-intermediate", "ring-finger-phalanx-distal", "ring-finger-tip"],
	"pinky": ["pinky-finger-metacarpal", "pinky-finger-phalanx-proximal", "pinky-finger-phalanx-intermediate", "pinky-finger-phalanx-distal", "pinky-finger-tip"],
}

## Total curl (degrees) per finger for each pose; Open leaves the bind pose.
const _POSES := {
	"Open": {},
	"Relaxed Grip": {"thumb": 45.0, "index": 95.0, "middle": 100.0, "ring": 105.0, "pinky": 105.0},
	"Pinch": {"thumb": 55.0, "index": 80.0, "middle": 35.0, "ring": 30.0, "pinky": 30.0},
	"Fist": {"thumb": 60.0, "index": 150.0, "middle": 155.0, "ring": 160.0, "pinky": 160.0},
}

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


func _set_preview_pose(value: String) -> void:
	preview_pose = value
	if is_inside_tree() and Engine.is_editor_hint():
		_rebuild_hand_preview()


## Editor-only ghost hand whose GRIP coincides with this grab point (built from
## the model's bind-pose joints with the SAME basis the live grip uses), so what
## you see gripping the object here is what you get in-headset.
const _PREVIEW_META := "grab_point_hand_preview"

func _rebuild_hand_preview() -> void:
	# Remove any previous preview - including one orphaned by a @tool script
	# reload (which nulls _hand_preview but leaves the child), the case that made
	# toggling off do nothing.
	for child in get_children():
		if child.has_meta(_PREVIEW_META):
			remove_child(child)
			child.queue_free()
	_hand_preview = null
	if not preview_hand or not Engine.is_editor_hint():
		return
	var packed := load(_HAND_MODEL_PATH) as PackedScene
	if packed == null:
		return
	var ghost := packed.instantiate() as Node3D
	if ghost == null:
		return
	ghost.set_meta(_PREVIEW_META, true)
	add_child(ghost)
	_hand_preview = ghost
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
	# Place the ghost so its grip lands on this grab point (using the OPEN-hand
	# joints), then curl the fingers into the chosen pose - the grip origin
	# (wrist/palm) does not move, so the alignment holds.
	var grip_rel_hand := ghost.global_transform.affine_inverse() * grip_world
	ghost.global_transform = global_transform * grip_rel_hand.affine_inverse()
	_pose_skeleton(skeleton)


## Curl the fingers into the selected pose using the Gesture Studio's method:
## each finger bends around its OWN bind-measured hinge axis (palm_normal x bone;
## the thumb is opposition, across the palm), and the FK rotates positions AND
## orientations together, the step pivoting on the previous accumulated angle.
func _pose_skeleton(skeleton: Skeleton3D) -> void:
	var curls: Dictionary = _POSES.get(preview_pose, {})
	if curls.is_empty():
		return
	var wrist := _bone_pos(skeleton, "wrist")
	var index_mc := _bone_pos(skeleton, "index-finger-metacarpal") - wrist
	var pinky_mc := _bone_pos(skeleton, "pinky-finger-metacarpal") - wrist
	var thumb_mc := _bone_pos(skeleton, "thumb-metacarpal") - wrist
	# Palm normal, chirality-corrected by the thumb sitting palm-side of the
	# finger plane (same rule the pose studio uses).
	var normal := index_mc.cross(pinky_mc).normalized()
	if normal.length_squared() < 0.000001:
		return
	if normal.dot(thumb_mc - (index_mc + pinky_mc) * 0.5) > 0.0:
		normal = -normal
	for finger in _CHAINS:
		var total: float = curls.get(finger, 0.0)
		if total <= 0.0:
			continue
		var names: Array = _CHAINS[finger]
		var mc := _bone_pos(skeleton, names[0]) - wrist
		var proximal := _bone_pos(skeleton, names[1]) - wrist
		var bone := (proximal - mc).normalized()
		var axis: Vector3
		if finger == "thumb":
			axis = bone.cross((pinky_mc - mc).normalized()).normalized()
		else:
			axis = normal.cross(bone).normalized()
		if axis.length_squared() < 0.000001:
			continue
		_curl_chain(skeleton, names, axis, deg_to_rad(total))


func _bone_pos(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var idx := skeleton.find_bone(bone_name)
	return skeleton.get_bone_global_rest(idx).origin if idx >= 0 else Vector3.ZERO


func _curl_chain(skeleton: Skeleton3D, names: Array, axis: Vector3, total: float) -> void:
	var bones: Array = []
	for bone_name in names:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			return
		bones.append(idx)
	var per := total / float(bones.size() - 1)
	var angle := 0.0
	var prev_pos: Vector3 = skeleton.get_bone_global_rest(bones[0]).origin
	for i in range(1, bones.size()):
		var step: Vector3 = skeleton.get_bone_global_rest(bones[i]).origin - skeleton.get_bone_global_rest(bones[i - 1]).origin
		var new_pos := prev_pos + Basis(axis, angle) * step  # step uses the PREVIOUS angle
		angle += per
		skeleton.set_bone_pose_position(bones[i], new_pos)
		skeleton.set_bone_pose_rotation(bones[i], (Basis(axis, angle) * skeleton.get_bone_global_rest(bones[i]).basis).get_rotation_quaternion())
		prev_pos = new_pos


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
