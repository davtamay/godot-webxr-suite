@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg")
class_name XRPokeButton
extends Node3D

## A physical 3D push-button: the cap visibly DEPRESSES under any poke point
## (fingertip or controller tip via XRPokeInteractor) and fires at a travel
## threshold, with hysteresis so it cannot chatter at the boundary. Drop it
## anywhere - it builds its own base + cap meshes (bake-safe materials) and
## finds the scene's poke sources by group.
##
## Local +Y is the press axis (cap on top); tilt the node toward the user.

signal pressed
signal released

const _LINE_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_line_material.tres")

const _FINGER_RADIUS := 0.008
const _BASE_HEIGHT := 0.012

@export var enabled := true

## How far the cap travels to bottom out.
@export_range(0.005, 0.06, 0.001) var travel := 0.022

## Fraction of travel that fires `pressed` (releases at half of it).
@export_range(0.3, 1.0, 0.05) var press_fraction := 0.7

@export_range(0.015, 0.1, 0.005) var cap_radius := 0.035

@export var cap_color := Color(0.3, 0.75, 1.0, 1.0)
@export var pressed_color := Color(0.3, 1.0, 0.55, 1.0)

var _cap: MeshInstance3D
var _cap_material: StandardMaterial3D
var _cap_rest_y := 0.0
var _cap_height := 0.014
var _is_pressed := false


func _ready() -> void:
	_build_visuals()
	if Engine.is_editor_hint():
		set_physics_process(false)


func is_pressed() -> bool:
	return _is_pressed


func _physics_process(_delta: float) -> void:
	if not enabled or _cap == null:
		return
	var depth := 0.0
	for source in get_tree().get_nodes_in_group(XRPokeInteractor.GROUP):
		for hand in 2:
			var point: Vector3 = source.get_poke_point(hand)
			if point == Vector3.INF:
				continue
			var local := global_transform.affine_inverse() * point
			if Vector2(local.x, local.z).length() > cap_radius + _FINGER_RADIUS:
				continue
			var cap_rest_top := _cap_rest_y + _cap_height * 0.5
			var finger_bottom := local.y - _FINGER_RADIUS
			if finger_bottom > cap_rest_top + 0.05 or local.y < -0.01:
				continue
			depth = maxf(depth, clampf(cap_rest_top - finger_bottom, 0.0, travel))
	_cap.position.y = _cap_rest_y - depth

	# Hysteresis: fire at press_fraction, re-arm at half of it.
	if not _is_pressed and depth >= travel * press_fraction:
		_is_pressed = true
		_cap_material.albedo_color = pressed_color
		pressed.emit()
	elif _is_pressed and depth <= travel * press_fraction * 0.5:
		_is_pressed = false
		_cap_material.albedo_color = cap_color
		released.emit()


func _build_visuals() -> void:
	if _cap:
		return
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = cap_radius + 0.01
	base_mesh.bottom_radius = cap_radius + 0.012
	base_mesh.height = _BASE_HEIGHT
	base.mesh = base_mesh
	base.position.y = _BASE_HEIGHT * 0.5
	var base_material := _LINE_MATERIAL.duplicate() as StandardMaterial3D
	base_material.albedo_color = Color(0.2, 0.24, 0.3, 1.0)
	base.material_override = base_material
	add_child(base)

	_cap = MeshInstance3D.new()
	_cap.name = "Cap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = cap_radius
	cap_mesh.bottom_radius = cap_radius + 0.003
	cap_mesh.height = _cap_height
	_cap.mesh = cap_mesh
	_cap_rest_y = _BASE_HEIGHT + travel + _cap_height * 0.5
	_cap.position.y = _cap_rest_y
	_cap_material = _LINE_MATERIAL.duplicate() as StandardMaterial3D
	_cap_material.albedo_color = cap_color
	_cap.material_override = _cap_material
	add_child(_cap)
