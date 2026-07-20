@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRBlaster
extends Node

## Turns a grab interactable into a blaster: drop this inside a grabbable and,
## while it's held, the interactor's ACTIVATE action (trigger-while-held) fires
## a projectile from the muzzle. The same pattern works for any "grab it, then
## use it" tool - spray cans, flashlights, drills.
##
## It listens to the parent interactable's `activated` signal, so it fires with
## whatever button the rig maps to activate (grip by default; swap to trigger in
## the OpenXR action map / adapter for classic trigger-to-shoot).

## The Node3D projectiles launch from; they fly along its -Z (forward).
@export var muzzle_path: NodePath
## The projectile scene (a RigidBody3D bolt gets the muzzle velocity).
@export var projectile: PackedScene = preload("res://addons/godot_xr_interaction_toolkit/bolt.tscn")
## Launch speed (m/s).
@export var muzzle_speed := 16.0
## Minimum seconds between shots.
@export_range(0.0, 2.0, 0.01) var fire_cooldown := 0.12
## Optional kick pushed back into a RigidBody3D body on each shot.
@export var recoil := 0.0

## Fired on each shot (for muzzle flash / sound / haptics).
signal fired(muzzle: Node3D)

var _interactable: Node
var _muzzle: Node3D
var _cooldown := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	var cursor := get_parent()
	while cursor != null and not cursor.has_signal("activated"):
		cursor = cursor.get_parent()
	_interactable = cursor
	if _interactable and _interactable.has_signal("activated") \
			and not _interactable.activated.is_connected(_on_activated):
		_interactable.activated.connect(_on_activated)
	_muzzle = get_node_or_null(muzzle_path) as Node3D


func _get_configuration_warnings() -> PackedStringArray:
	var cursor := get_parent()
	while cursor != null:
		if cursor.has_signal("activated"):
			return PackedStringArray()
		cursor = cursor.get_parent()
	return PackedStringArray(["Place this INSIDE a grab interactable (any ancestor)."])


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func _on_activated(_interactor) -> void:
	if _cooldown > 0.0 or _muzzle == null or projectile == null:
		return
	var bolt := projectile.instantiate() as Node3D
	if bolt == null:
		return
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(bolt)
	bolt.global_transform = _muzzle.global_transform
	var direction := (-_muzzle.global_transform.basis.z).normalized()
	if bolt is RigidBody3D:
		(bolt as RigidBody3D).linear_velocity = direction * muzzle_speed
	if recoil > 0.0:
		var body := _interactable.get_target() as RigidBody3D if _interactable.has_method("get_target") else null
		if body:
			body.apply_central_impulse(-direction * recoil)
	_cooldown = fire_cooldown
	fired.emit(_muzzle)
