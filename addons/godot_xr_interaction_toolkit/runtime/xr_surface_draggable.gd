@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRSurfaceDraggable
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactable.gd"

## Grab a piece and slide it along ONLY the axes you allow - a position
## constraint (Unity XRI / XR Hands transform constraints). Allow two axes and
## freeze the third = a magnet on a board / a piece on a checkerboard; allow one
## = a bead on a wire / an in-surface slider. Movement is in the PARENT's local
## space, so freezing the parent's up axis keeps the piece on a board tilted at
## any angle. Optional per-axis bounds. Near or far grab both drag it.
##
## Put it on a node with a collider, parented to the surface (the board); the
## frozen axis (default Y) is the surface normal, bounds are measured from where
## it started.

## Emitted as it moves; position is in the parent's local space.
signal moved(local_position: Vector3)

@export var target_path: NodePath

@export_group("Allowed movement")
## Which of the parent's LOCAL axes the piece may move along. A surface allows
## two and freezes the third (the surface normal); a slider allows one.
@export var allow_x := true
@export var allow_y := false
@export var allow_z := true

@export_group("Bounds")
## Half-range of travel per axis from the start position, in metres. 0 on an
## axis = unbounded there.
@export var limits := Vector3(0.2, 0.0, 0.2)

var _grabber: Node
var _rest := Vector3.ZERO
var _grab_offset := Vector3.ZERO


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	var piece := target()
	if piece:
		_rest = piece.position
	select_entered.connect(_on_grab)
	select_exited.connect(_on_release)


func target() -> Node3D:
	if target_path.is_empty():
		return self
	return get_node_or_null(target_path) as Node3D


func _on_grab(interactor) -> void:
	_grabber = interactor
	# Offset so the piece doesn't jump to the grab point on grab.
	_grab_offset = target().position - _parent_local(_grab_point())


func _on_release(interactor) -> void:
	if interactor == _grabber:
		_grabber = null


func _physics_process(_delta: float) -> void:
	if _grabber == null or not is_instance_valid(_grabber):
		return
	var want := _parent_local(_grab_point()) + _grab_offset
	# Only the allowed axes follow the hand; the frozen axes keep their value,
	# so the piece stays on its surface / wire. Each allowed axis is clamped to
	# its bounds around where the drag started.
	var piece := target()
	var pos := piece.position
	if allow_x:
		pos.x = _constrain(want.x, _rest.x, limits.x)
	if allow_y:
		pos.y = _constrain(want.y, _rest.y, limits.y)
	if allow_z:
		pos.z = _constrain(want.z, _rest.z, limits.z)
	piece.position = pos
	moved.emit(pos)


func _constrain(value: float, rest: float, half: float) -> float:
	return value if half <= 0.0 else clampf(value, rest - half, rest + half)


func _parent_local(world: Vector3) -> Vector3:
	var parent := target().get_parent() as Node3D
	return parent.to_local(world) if parent else world


## The grab point: the interactor's attach pose (ray hit on the piece for a far
## grab, the hand for a near grab).
func _grab_point() -> Vector3:
	if _grabber.has_method("get_attach_pose"):
		return (_grabber.get_attach_pose() as Transform3D).origin
	return (_grabber as Node3D).global_position
