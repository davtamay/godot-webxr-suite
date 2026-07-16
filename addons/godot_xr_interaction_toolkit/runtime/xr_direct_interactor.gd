@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_direct_interactor.svg")
class_name XRDirectInteractor
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactor.gd"

## Near-field hand interactor. Uses an overlap sphere at the adapter's grip pose
## to hover/select nearby interactables. This is the Direct Interactor half of
## Unity XRI's near/far setup; XRRayInteractor remains the far interactor.

@export_group("Direct Hover")
@export_range(0.01, 2.0, 0.01, "or_greater") var hover_radius := 0.16
@export_range(1, 128, 1, "or_greater") var max_results := 16
@export_flags_3d_physics var collision_mask := 1
@export var collide_with_areas := true

var _shape := SphereShape3D.new()
var _direct_state := {"valid": false}
var _attach_pose := Transform3D.IDENTITY

func _physics_process(_delta: float) -> void:
    _update_direct()

func get_direct_state() -> Dictionary:
    return _direct_state

func get_attach_pose() -> Transform3D:
    return _attach_pose

func _update_direct() -> void:
    var pose := _get_grip_pose()
    if pose.is_empty():
        _direct_state = {"valid": false}
        if _selected == null:
            _set_hovered(null)
        return

    var origin: Vector3 = pose["origin"]
    var basis: Basis = pose.get("basis", Basis.IDENTITY)
    _attach_pose = Transform3D(basis, origin)

    var hovered = _closest_interactable(origin)
    if _selected == null:
        _set_hovered(hovered)

    _direct_state = {
        "valid": true,
        "origin": origin,
        "hovered": hovered,
        "radius": hover_radius,
    }

func _get_grip_pose() -> Dictionary:
    if _adapter == null:
        return {}
    if _adapter.has_method("get_grip_pose"):
        return _adapter.get_grip_pose(hand)
    if _adapter.has_method("get_aim_pose"):
        return _adapter.get_aim_pose(hand)
    return {}

func _closest_interactable(origin: Vector3):
    if _manager == null:
        _resolve_manager()
    if _manager == null:
        return null

    _shape.radius = hover_radius
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = _shape
    query.transform = Transform3D(Basis.IDENTITY, origin)
    query.collision_mask = collision_mask
    query.collide_with_areas = collide_with_areas
    query.collide_with_bodies = true

    var hits := get_world_3d().direct_space_state.intersect_shape(query, max_results)
    var best = null
    var best_distance := INF
    for hit in hits:
        var collider = hit.get("collider")
        var interactable = _manager.get_interactable_for_collider(collider)
        if interactable == null or not interactable.can_hover(self):
            continue

        var distance := origin.distance_squared_to((collider as Node3D).global_position)
        if distance < best_distance:
            best_distance = distance
            best = interactable
    return best
