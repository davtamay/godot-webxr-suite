@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg")
class_name XRPokeable
extends Node3D

## Makes an object POKEABLE (Unity's XRPokeFilter equivalent): parent this
## inside anything with a CollisionObject3D and a fingertip pushing into the
## chosen face emits pressed / released. The XRPokeInteractor finds pokeables
## by PHYSICS (a sphere around the fingertip), so a scene can hold many poke
## targets and only the ones near a finger cost anything - Unity-style scaling.
##
## Self-wiring like the affordances: walks up to the collision body and marks
## it. Per-object poke direction + depth live here, so different buttons can
## face different ways.

## Which local face the finger approaches from (the outward normal). Default
## +Z = the front of a panel/button facing -Z.
enum Face { X_PLUS, X_MINUS, Y_PLUS, Y_MINUS, Z_PLUS, Z_MINUS }

signal pressed(hand: int)
signal released(hand: int)

@export var poke_face := Face.Z_PLUS
## Finger must come within this depth of the surface to press, and retract past
## the second to release (hysteresis stops flicker). Metres.
@export var press_depth := 0.012
@export var release_depth := 0.04
## Half-extents of the pokeable face (metres) - a poke outside this rectangle is
## ignored. Zero = no bounds (the whole plane pokes).
@export var half_size := Vector2(0.05, 0.05)

var _body: CollisionObject3D
var _down := {}  # hand -> bool


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	var cursor := get_parent()
	while cursor != null and not (cursor is CollisionObject3D):
		cursor = cursor.get_parent()
	_body = cursor as CollisionObject3D
	if _body:
		_body.set_meta("xr_pokeable", self)


func _exit_tree() -> void:
	if _body and is_instance_valid(_body) and _body.get_meta("xr_pokeable", null) == self:
		_body.remove_meta("xr_pokeable")


func _get_configuration_warnings() -> PackedStringArray:
	var cursor := get_parent()
	while cursor != null:
		if cursor is CollisionObject3D:
			return PackedStringArray()
		cursor = cursor.get_parent()
	return PackedStringArray(["Place this inside a body with a collider (StaticBody3D/Area3D)."])


## Driven by the interactor with the world-space fingertip. Emits pressed on
## entry past press_depth and released on retract past release_depth.
func poke_update(hand: int, world_point: Vector3) -> void:
	var local := global_transform.affine_inverse() * world_point
	# Distance in FRONT of the surface along the chosen face normal, and the
	# in-plane offset (for the bounds rectangle).
	var normal := _local_normal()
	var depth := local.dot(normal)
	var planar := local - normal * depth
	if half_size.x > 0.0 or half_size.y > 0.0:
		var u := absf(planar.dot(_plane_u(normal)))
		var v := absf(planar.dot(_plane_v(normal)))
		if u > half_size.x or v > half_size.y:
			poke_end(hand)
			return
	if depth < -release_depth or depth > release_depth * 6.0:
		poke_end(hand)
		return
	if _down.get(hand, false):
		if depth > release_depth:
			_down[hand] = false
			released.emit(hand)
	elif depth <= press_depth:
		_down[hand] = true
		pressed.emit(hand)


func poke_end(hand: int) -> void:
	if _down.get(hand, false):
		_down[hand] = false
		released.emit(hand)


func is_pressed() -> bool:
	return _down.values().has(true)


## Outward face normal in local space (the finger presses toward -normal).
func _local_normal() -> Vector3:
	match poke_face:
		Face.X_PLUS: return Vector3.RIGHT
		Face.X_MINUS: return Vector3.LEFT
		Face.Y_PLUS: return Vector3.UP
		Face.Y_MINUS: return Vector3.DOWN
		Face.Z_MINUS: return Vector3.BACK  # -Z
		_: return Vector3.BACK * -1.0      # Z_PLUS = +Z


func _plane_u(normal: Vector3) -> Vector3:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	return normal.cross(up).normalized()


func _plane_v(normal: Vector3) -> Vector3:
	return normal.cross(_plane_u(normal)).normalized()
