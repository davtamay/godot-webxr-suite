class_name XRSocketInteractor
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactor.gd"

## Socket/snap-zone interactor. It watches a local sphere, hovers the closest
## compatible interactable, and can automatically select it so grab objects snap
## to the socket attach pose.

@export_group("Socket")
@export var socket_active := true
@export_range(0.01, 5.0, 0.01, "or_greater") var socket_radius := 0.35
@export_range(1, 128, 1, "or_greater") var max_results := 24
@export_flags_3d_physics var collision_mask := 1
@export var collide_with_areas := true

@export_group("Selection")
@export var auto_select := true
@export_range(0.0, 5.0, 0.01, "or_greater") var hover_select_delay := 0.0
@export var keep_selected := true
@export var release_when_disabled := true
@export var allow_takeover_by_other_interactors := true
@export var allow_takeover_by_socket_interactors := false
@export_range(0.0, 5.0, 0.01, "or_greater") var reselect_delay_after_takeover := 0.2
@export var attach_transform_path: NodePath

@export_group("Filters")
@export var require_snap_to_attach := false
@export var accepted_groups: Array[StringName] = []
@export var rejected_groups: Array[StringName] = []

var _shape := SphereShape3D.new()
var _socket_state := {"valid": false}
var _hover_candidate: Node
var _hover_time := 0.0
var _reselect_delay_remaining := 0.0

func _physics_process(delta: float) -> void:
	_update_socket(delta)

func get_socket_state() -> Dictionary:
	return _socket_state

func get_attach_pose() -> Transform3D:
	var attach_node := get_node_or_null(attach_transform_path) as Node3D
	return attach_node.global_transform if attach_node else global_transform

func release_selected() -> bool:
	if _selected == null:
		return false
	_release_select()
	_reselect_delay_remaining = reselect_delay_after_takeover
	return true

func eject_selected(linear_velocity := Vector3.ZERO, angular_velocity := Vector3.ZERO) -> bool:
	if _selected == null:
		return false

	var selected = _selected
	var target = selected.get_target() if selected.has_method("get_target") else selected
	var released := release_selected()
	if released and target is RigidBody3D:
		target.sleeping = false
		target.linear_velocity = linear_velocity
		target.angular_velocity = angular_velocity
	return released

func should_yield_selection_to(requesting_interactor, interactable) -> bool:
	if not allow_takeover_by_other_interactors:
		return false
	if interactable != _selected:
		return false
	if requesting_interactor == self:
		return false
	if requesting_interactor != null and requesting_interactor.has_method("get_socket_state") and not allow_takeover_by_socket_interactors:
		return false

	_reselect_delay_remaining = reselect_delay_after_takeover
	return true

func _update_socket(delta := 0.0) -> void:
	_reselect_delay_remaining = maxf(0.0, _reselect_delay_remaining - maxf(delta, 0.0))

	if not socket_active:
		if release_when_disabled:
			release_selected()
		_reset_hover_candidate()
		_set_hovered(null)
		_set_socket_state(&"disabled", null)
		return

	if _selected != null and keep_selected:
		_set_hovered(_selected)
		_reset_hover_candidate()
		_set_socket_state(&"occupied", _selected)
		return

	var hovered = _closest_interactable()
	_update_hover_candidate(hovered, delta)
	_set_hovered(hovered)
	if _can_auto_select_hovered():
		_try_select()

	var state := &"occupied" if _selected != null else (&"hovering" if _hovered != null else &"ready")
	_set_socket_state(state, _hovered)

func _closest_interactable():
	if _manager == null:
		_resolve_manager()
	if _manager == null:
		return null

	_shape.radius = socket_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = true

	var hits := get_world_3d().direct_space_state.intersect_shape(query, max_results)
	var best = null
	var best_distance := INF
	for hit in hits:
		var collider = hit.get("collider")
		var interactable = _manager.get_interactable_for_collider(collider)
		if not _accepts_interactable(interactable):
			continue

		var node_3d := collider as Node3D
		var distance := global_position.distance_squared_to(node_3d.global_position) if node_3d else 0.0
		if distance < best_distance:
			best_distance = distance
			best = interactable
	return best

func _accepts_interactable(interactable) -> bool:
	if interactable == null or not interactable.can_hover(self):
		return false
	if require_snap_to_attach and not bool(interactable.get("snap_to_attach")):
		return false
	if not rejected_groups.is_empty() and _is_in_any_group(interactable, rejected_groups):
		return false
	if not accepted_groups.is_empty() and not _is_in_any_group(interactable, accepted_groups):
		return false
	return true

func _is_in_any_group(node: Node, groups: Array[StringName]) -> bool:
	for group in groups:
		if node.is_in_group(group):
			return true
	return false

func _update_hover_candidate(hovered, delta: float) -> void:
	if hovered != _hover_candidate:
		_hover_candidate = hovered
		_hover_time = 0.0
	elif hovered != null:
		_hover_time += maxf(delta, 0.0)
	else:
		_hover_time = 0.0

func _reset_hover_candidate() -> void:
	_hover_candidate = null
	_hover_time = 0.0

func _can_auto_select_hovered() -> bool:
	if not auto_select or _selected != null or _hovered == null:
		return false
	if _reselect_delay_remaining > 0.0:
		return false
	return _hover_time >= hover_select_delay

func _set_socket_state(state: StringName, candidate) -> void:
	_socket_state = {
		"valid": socket_active,
		"state": state,
		"origin": global_position,
		"hovered": _hovered,
		"candidate": candidate,
		"selected": _selected,
		"radius": socket_radius,
		"hover_time": _hover_time,
		"hover_select_delay": hover_select_delay,
		"reselect_delay": _reselect_delay_remaining,
	}
