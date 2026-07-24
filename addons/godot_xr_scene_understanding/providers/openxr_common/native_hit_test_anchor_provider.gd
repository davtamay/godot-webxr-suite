extends Node3D

## Native OpenXR surface placement backed by the neutral room-mesh colliders.
## Quest uses its stored Scene Model; Android XR uses live scene reconstruction.
## Anchors are session-local XRAnchor3D trackers, so placed content remains
## world-locked without introducing a dependency on either vendor API.

signal hit_pose_updated(hit_transform: Transform3D)
signal hit_lost
signal anchor_node_added(anchor_id: int, anchor_node: XRAnchor3D)
signal anchor_removed(anchor_id: int)
signal anchor_failed(message: String)
signal select_pressed(hand: int)

const SURFACE_COLLISION_LAYER := 1 << 30
const MAX_HIT_DISTANCE := 12.0
const ANCHOR_TRACKER_PREFIX := "xr_surface_anchor_"

var maximum_anchors := 16
var anchor_node_root: NodePath

var _enabled := false
var _adapter: Node
var _camera: XRCamera3D
var _origin: XROrigin3D
var _preferred_hand := 1
var _has_hit := false
var _hit_transform := Transform3D.IDENTITY
var _aim_label := "head-view fallback"
var _next_anchor_id := 1
var _anchor_trackers := {}
var _anchor_nodes := {}


func _ready() -> void:
	_resolve_runtime_nodes()
	set_process(false)


func _exit_tree() -> void:
	clear_anchors()


func set_enabled(value: bool) -> void:
	_enabled = value
	set_process(value)
	if not value:
		_clear_hit()


func set_preferred_hand(hand: int) -> void:
	if hand == 0 or hand == 1:
		_preferred_hand = hand


func _process(_delta: float) -> void:
	if not _enabled:
		return
	if _origin == null or _camera == null or _adapter == null:
		_resolve_runtime_nodes()
	if not is_inside_tree() or get_world_3d() == null:
		_clear_hit()
		return

	var aim := _current_aim()
	if aim.is_empty():
		_clear_hit()
		return
	var origin: Vector3 = aim["origin"]
	var direction: Vector3 = aim["direction"]
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * MAX_HIT_DISTANCE,
		SURFACE_COLLISION_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		_clear_hit()
		return

	_has_hit = true
	_hit_transform = _surface_transform(
		result["position"],
		result["normal"],
		direction
	)
	hit_pose_updated.emit(_hit_transform)


func _current_aim() -> Dictionary:
	if _adapter != null and _adapter.has_method("get_aim_pose"):
		var hands := [_preferred_hand, 1 - _preferred_hand]
		for hand in hands:
			var pose: Dictionary = _adapter.call("get_aim_pose", hand)
			if not pose.is_empty():
				_aim_label = "%s-hand ray" % ("left" if hand == 0 else "right")
				return pose
	if _camera != null:
		var camera_xf := _camera.global_transform
		_aim_label = "head-view fallback"
		return {
			"origin": camera_xf.origin,
			"direction": (-camera_xf.basis.z).normalized(),
		}
	return {}


static func _surface_transform(
	position: Vector3,
	normal_value: Vector3,
	ray_direction: Vector3
) -> Transform3D:
	var normal := normal_value.normalized()
	var forward := ray_direction.slide(normal).normalized()
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD.slide(normal).normalized()
	if forward.length_squared() < 0.000001:
		forward = Vector3.RIGHT.slide(normal).normalized()
	var z_axis := -forward
	var x_axis := normal.cross(z_axis).normalized()
	return Transform3D(Basis(x_axis, normal, z_axis).orthonormalized(), position)


func has_hit() -> bool:
	return _has_hit


func get_hit_transform() -> Transform3D:
	return _hit_transform


func get_hit_aim_label() -> String:
	return _aim_label


func get_anchor_count() -> int:
	return _anchor_nodes.size()


func get_status() -> String:
	if not _enabled:
		return "Hit Test + Anchors: off."
	if _has_hit:
		return (
			"OpenXR room-surface hit LIVE via %s. Pinch or press select to place "
			+ "an in-session anchor. Anchors: %d/%d."
		) % [_aim_label, _anchor_nodes.size(), maximum_anchors]
	if _origin == null:
		return "Hit Test + Anchors: waiting for an OpenXR session."
	return (
		"Hit test ready (%s); aim at captured room geometry. "
		+ "Quest requires a Space Setup room scan."
	) % _aim_label


func request_anchor() -> bool:
	if not _enabled or not _has_hit or _origin == null:
		return false
	while _anchor_nodes.size() >= maximum_anchors:
		var oldest_id: int = _anchor_nodes.keys().min()
		_remove_anchor(oldest_id)

	var anchor_id := _next_anchor_id
	_next_anchor_id += 1
	var tracker := XRPositionalTracker.new()
	tracker.type = XRServer.TRACKER_ANCHOR
	tracker.name = StringName(ANCHOR_TRACKER_PREFIX + str(anchor_id))
	XRServer.add_tracker(tracker)
	_anchor_trackers[anchor_id] = tracker
	var local_pose := _origin.global_transform.affine_inverse() * _hit_transform
	tracker.set_pose(
		&"default",
		local_pose,
		Vector3.ZERO,
		Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH
	)

	var anchor := XRAnchor3D.new()
	anchor.name = "SurfaceAnchor%d" % anchor_id
	anchor.tracker = tracker.name
	anchor.pose = &"default"
	_origin.add_child(anchor)
	_anchor_nodes[anchor_id] = anchor
	anchor_node_added.emit(anchor_id, anchor)
	return true


func clear_anchors() -> void:
	for anchor_id in _anchor_nodes.keys().duplicate():
		_remove_anchor(int(anchor_id))


func _remove_anchor(anchor_id: int) -> void:
	var tracker = _anchor_trackers.get(anchor_id)
	if tracker != null:
		XRServer.remove_tracker(tracker)
		_anchor_trackers.erase(anchor_id)
	var anchor = _anchor_nodes.get(anchor_id)
	if anchor != null and is_instance_valid(anchor):
		anchor.queue_free()
	_anchor_nodes.erase(anchor_id)
	anchor_removed.emit(anchor_id)


func _clear_hit() -> void:
	if _has_hit:
		_has_hit = false
		hit_lost.emit()


func _resolve_runtime_nodes() -> void:
	_origin = _find_origin()
	_camera = _find_camera()
	var adapters := get_tree().get_nodes_in_group("xr_openxr_input_adapter")
	if not adapters.is_empty():
		_set_adapter(adapters[0])
	elif is_inside_tree():
		var root := _own_scene_root()
		var candidates := root.find_children("OpenXRInputAdapter", "", true, false)
		if not candidates.is_empty():
			_set_adapter(candidates[0])


func _set_adapter(adapter: Node) -> void:
	if adapter == _adapter:
		return
	if _adapter != null and _adapter.select_started.is_connected(_on_select_started):
		_adapter.select_started.disconnect(_on_select_started)
	_adapter = adapter
	if _adapter != null and not _adapter.select_started.is_connected(_on_select_started):
		_adapter.select_started.connect(_on_select_started)


func _on_select_started(hand: int) -> void:
	set_preferred_hand(hand)
	select_pressed.emit(hand)


func _find_origin() -> XROrigin3D:
	var root := _own_scene_root()
	if root is XROrigin3D:
		return root
	var origins := root.find_children("*", "XROrigin3D", true, false)
	return null if origins.is_empty() else origins[0] as XROrigin3D


func _find_camera() -> XRCamera3D:
	if _origin == null:
		return null
	var cameras := _origin.find_children("*", "XRCamera3D", true, false)
	return null if cameras.is_empty() else cameras[0] as XRCamera3D


func _own_scene_root() -> Node:
	var node: Node = self
	var tree_root := get_tree().root
	while node.get_parent() != null and node.get_parent() != tree_root:
		node = node.get_parent()
	return node
