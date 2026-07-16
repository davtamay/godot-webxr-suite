@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_screen_ray_interactor.svg")
class_name XRScreenRayInteractor
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactor.gd"

## Mouse/touch ray interactor for desktop and mobile browser testing.
## It feeds the same hover/select pipeline as XRRayInteractor, so affordances,
## layer masks, and grab behavior stay shared across input sources.

@export var enabled := true
@export var active_in_xr := false
@export var camera_path: NodePath
@export var max_distance := 6.0
@export_flags_3d_physics var collision_mask := 1
@export var collide_with_areas := true
@export var min_grab_distance := 0.25
@export var ignore_ui_canvas_interactables := true
@export var activate_with_right_mouse_button := true

var _camera: Camera3D
var _screen_position := Vector2.ZERO
var _has_screen_position := false
var _ray_state := {"valid": false}
var _grab_distance := 0.0
var _hover_distance := 0.0
var _attach_pose := Transform3D.IDENTITY
var _touch_index := -1

func _ready() -> void:
    super()
    _camera = get_node_or_null(camera_path) as Camera3D

func _physics_process(_delta: float) -> void:
    if not _is_active():
        _set_ray_inactive()
        return

    if _touch_index < 0:
        _screen_position = get_viewport().get_mouse_position()
        _has_screen_position = true
    if _has_screen_position:
        update_from_screen(_screen_position)

func _unhandled_input(event: InputEvent) -> void:
    if not _is_active():
        return

    if event is InputEventMouseMotion:
        var motion := event as InputEventMouseMotion
        _screen_position = motion.position
        _has_screen_position = true
        update_from_screen(_screen_position)
    elif event is InputEventMouseButton:
        var button := event as InputEventMouseButton
        if button.button_index != MOUSE_BUTTON_LEFT and not (activate_with_right_mouse_button and button.button_index == MOUSE_BUTTON_RIGHT):
            return
        _screen_position = button.position
        _has_screen_position = true
        update_from_screen(_screen_position)
        if button.button_index == MOUSE_BUTTON_RIGHT:
            if button.pressed:
                _try_activate()
            else:
                _release_activate()
        else:
            if button.pressed:
                _try_select()
            else:
                _release_select()
        _mark_handled_if_over_interactable()
    elif event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            if _touch_index >= 0:
                return
            _touch_index = touch.index
            _screen_position = touch.position
            _has_screen_position = true
            update_from_screen(_screen_position)
            _try_select()
            _mark_handled_if_over_interactable()
        elif touch.index == _touch_index:
            _screen_position = touch.position
            update_from_screen(_screen_position)
            _release_select()
            _touch_index = -1
            _mark_handled_if_over_interactable()
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if drag.index == _touch_index:
            _screen_position = drag.position
            _has_screen_position = true
            update_from_screen(_screen_position)
            _mark_handled_if_over_interactable()

func update_from_screen(screen_position: Vector2) -> void:
    var camera := _get_camera()
    if camera == null:
        _set_ray_inactive()
        return

    update_from_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func update_from_ray(origin: Vector3, direction: Vector3) -> void:
    if direction.length_squared() < 0.000001:
        _set_ray_inactive()
        return

    direction = direction.normalized()
    var hit := _intersect(origin, direction)
    var hit_anything := not hit.is_empty()
    var end := origin + direction * max_distance
    if hit_anything:
        end = hit["position"]

    var hovered = null
    if hit_anything and _manager:
        var interactable = _manager.get_interactable_for_collider(hit["collider"])
        if _can_screen_hover(interactable):
            hovered = interactable

    _hover_distance = origin.distance_to(end)
    if _selected == null:
        _set_hovered(hovered)
        _attach_pose = Transform3D(Basis.looking_at(direction, Vector3.UP), end)
    else:
        _attach_pose = Transform3D(Basis.looking_at(direction, Vector3.UP), origin + direction * _grab_distance)

    _ray_state = {
        "valid": true,
        "origin": origin,
        "direction": direction,
        "end": end,
        "hit": hit_anything,
        "hovered": hovered,
    }

func get_ray_state() -> Dictionary:
    return _ray_state

func get_attach_pose() -> Transform3D:
    return _attach_pose

func _notify_select_granted(interactable) -> void:
    _grab_distance = clampf(_hover_distance, min_grab_distance, max_distance)
    super(interactable)

func _get_camera() -> Camera3D:
    if _camera != null:
        return _camera
    if not camera_path.is_empty():
        _camera = get_node_or_null(camera_path) as Camera3D
        if _camera != null:
            return _camera
    return get_viewport().get_camera_3d()

func _is_active() -> bool:
    if not enabled:
        return false
    if get_viewport().use_xr and not active_in_xr:
        return false
    return true

func _set_ray_inactive() -> void:
    _ray_state = {"valid": false}
    if _selected == null:
        _set_hovered(null)

func _intersect(origin: Vector3, direction: Vector3) -> Dictionary:
    var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance)
    query.collision_mask = collision_mask
    query.collide_with_areas = collide_with_areas
    query.collide_with_bodies = true
    return get_world_3d().direct_space_state.intersect_ray(query)

func _can_screen_hover(interactable) -> bool:
    if interactable == null:
        return false
    if ignore_ui_canvas_interactables and interactable.has_method("map_ray_to_viewport"):
        return false
    return interactable.can_hover(self)

func _mark_handled_if_over_interactable() -> void:
    if _hovered != null or _selected != null:
        get_viewport().set_input_as_handled()
