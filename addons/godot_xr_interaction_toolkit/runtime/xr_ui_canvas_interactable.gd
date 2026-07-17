@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_ui_canvas_interactable.svg")
class_name XRUICanvasInteractable
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactable.gd"

## 3D interactable surface that forwards XR ray hover/select to a SubViewport
## as mouse input, letting ordinary Godot Control buttons/sliders work in XR.

## Preloaded so the shader baker can precompile it for web/WebGPU exports.
const PANEL_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_ui_panel_material.tres")

@export_group("Panel")
@export var viewport_path: NodePath
@export var panel_mesh_path: NodePath
@export var camera_path: NodePath
@export var panel_size := Vector2(1.6, 0.9)
@export var viewport_pixel_size := Vector2i(1024, 640)

## EXPERIMENTAL A/B (headset-gated optimization): render the SubViewport only
## while its texture is on screen, skipping renders when the panel mesh is
## frustum-culled. Zero visual change is expected but 3D-mesh visibility
## detection is unverified on-device - flip ON during a headset pass to A/B.
## Default OFF ships today's always-render behavior.
@export var render_only_when_visible := false

@export_group("Screen Pointer")
@export var screen_pointer_enabled := true
@export var consume_screen_pointer_events := true

var _viewport: SubViewport
var _panel_mesh: MeshInstance3D
var _hovering_interactor: Node
var _pressing_interactor: Node
var _pointer_down := false
var _screen_pointer_down := false
var _screen_pointer_index := -1
var _last_pointer_position := Vector2.ZERO
var _last_motion_position := Vector2.ZERO
var _has_motion_position := false

func _ready() -> void:
    super()
    add_to_group("xr_ui_canvas")  # Poke sources find panels through this.
    _viewport = get_node_or_null(viewport_path) as SubViewport
    _panel_mesh = get_node_or_null(panel_mesh_path) as MeshInstance3D
    if _viewport:
        _viewport.size = viewport_pixel_size
        if render_only_when_visible:
            _viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    _apply_viewport_material()

    hover_entered.connect(_on_hover_entered)
    hover_exited.connect(_on_hover_exited)
    select_entered.connect(_on_select_entered)
    select_exited.connect(_on_select_exited)

func _process(_delta: float) -> void:
    var interactor: Node = _pressing_interactor if _pressing_interactor != null else _hovering_interactor
    if interactor != null:
        _update_pointer(interactor)

## ---- poke (fingertip) input ---------------------------------------------------
## Driven by XRPokeInteractor: the fingertip presses the panel DIRECTLY -
## crossing the press plane presses at the projected pixel, staying pressed
## while touching (drag = sliders work by touch), retracting releases.

const POKE_PRESS_Z := 0.012
const POKE_RELEASE_Z := 0.04
const POKE_RANGE_Z := 0.09

var _poke_pressed := {}

## World-space fingertip update from a poke source (source_id per hand).
func poke_update(source_id: int, world_point: Vector3) -> void:
    if _viewport == null:
        return
    var local := global_transform.affine_inverse() * world_point
    var inside := absf(local.x) <= panel_size.x * 0.5 and absf(local.y) <= panel_size.y * 0.5
    if not inside or local.z > POKE_RANGE_Z or local.z < -0.06:
        poke_end(source_id)
        return
    var pixels := map_local_point_to_viewport(local)
    if _poke_pressed.get(source_id, false):
        _push_mouse_motion(pixels)
        if local.z > POKE_RELEASE_Z:
            _poke_pressed[source_id] = false
            _push_mouse_button(pixels, false)
    elif local.z <= POKE_PRESS_Z:
        _poke_pressed[source_id] = true
        _push_mouse_motion(pixels)
        _push_mouse_button(pixels, true)
    _last_pointer_position = pixels


## The poke source lost its point (hand untracked / moved away).
func poke_end(source_id: int) -> void:
    if _poke_pressed.get(source_id, false):
        _poke_pressed[source_id] = false
        _push_mouse_button(_last_pointer_position, false)


func _unhandled_input(event: InputEvent) -> void:
    if not screen_pointer_enabled or _viewport == null:
        return

    if event is InputEventMouseMotion:
        _handle_screen_motion(event.position, _screen_pointer_down)
    elif event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT:
            _handle_screen_button(mouse_event.position, mouse_event.pressed)
    elif event is InputEventScreenTouch:
        var touch_event := event as InputEventScreenTouch
        _handle_screen_touch(touch_event.index, touch_event.position, touch_event.pressed)
    elif event is InputEventScreenDrag:
        var drag_event := event as InputEventScreenDrag
        if _screen_pointer_down and drag_event.index == _screen_pointer_index:
            _handle_screen_motion(drag_event.position, true)

func map_local_point_to_viewport(local_point: Vector3) -> Vector2:
    var u := clampf(local_point.x / panel_size.x + 0.5, 0.0, 1.0)
    var v := clampf(0.5 - local_point.y / panel_size.y, 0.0, 1.0)
    return Vector2(u * viewport_pixel_size.x, v * viewport_pixel_size.y)

func map_screen_point_to_viewport(screen_position: Vector2) -> Dictionary:
    var camera := _get_pointer_camera()
    if camera == null:
        return {}

    return map_ray_to_viewport(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))

func map_ray_to_viewport(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
    var inv := global_transform.affine_inverse()
    var local_origin: Vector3 = inv * ray_origin
    var local_direction := (global_transform.basis.inverse() * ray_direction).normalized()
    if absf(local_direction.z) < 0.00001:
        return {}

    var distance := -local_origin.z / local_direction.z
    if distance < 0.0:
        return {}

    var local_point := local_origin + local_direction * distance
    var inside := absf(local_point.x) <= panel_size.x * 0.5 and absf(local_point.y) <= panel_size.y * 0.5
    return {
        "position": map_local_point_to_viewport(local_point),
        "inside": inside,
    }

func _apply_viewport_material() -> void:
    if _viewport == null or _panel_mesh == null:
        return

    # Preloaded so the shader baker can precompile it for web/WebGPU exports;
    # the viewport texture is a uniform, so assigning it keeps the baked hash.
    var material := PANEL_MATERIAL.duplicate() as StandardMaterial3D
    material.albedo_texture = _viewport.get_texture()
    _panel_mesh.set_surface_override_material(0, material)

func _get_pointer_camera() -> Camera3D:
    if not camera_path.is_empty():
        var configured_camera := get_node_or_null(camera_path) as Camera3D
        if configured_camera != null:
            return configured_camera
    return get_viewport().get_camera_3d()

func _on_hover_entered(interactor) -> void:
    _hovering_interactor = interactor
    _update_pointer(interactor)

func _on_hover_exited(interactor) -> void:
    if interactor == _hovering_interactor:
        _hovering_interactor = null

func _on_select_entered(interactor) -> void:
    _pressing_interactor = interactor
    if _update_pointer(interactor):
        _push_mouse_button(_last_pointer_position, true)
        _push_mouse_motion(_last_pointer_position)

func _on_select_exited(interactor) -> void:
    if interactor == _pressing_interactor:
        _update_pointer(interactor)
        _push_mouse_button(_last_pointer_position, false)
        _pressing_interactor = null

func _update_pointer(interactor: Node) -> bool:
    if _viewport == null or interactor == null or not interactor.has_method("get_ray_state"):
        return false

    var ray_state: Dictionary = interactor.get_ray_state()
    if not ray_state.get("valid", false):
        return false

    var mapped := map_ray_to_viewport(ray_state["origin"], ray_state["direction"])
    if mapped.is_empty():
        return false

    _last_pointer_position = mapped["position"]
    _push_mouse_motion(_last_pointer_position)
    return true

func _handle_screen_motion(screen_position: Vector2, dragging: bool) -> void:
    var mapped := map_screen_point_to_viewport(screen_position)
    if mapped.is_empty():
        return
    if not dragging and not mapped.get("inside", false):
        return

    _last_pointer_position = mapped["position"]
    _push_mouse_motion(_last_pointer_position)
    _mark_screen_input_handled()

func _handle_screen_button(screen_position: Vector2, pressed: bool) -> void:
    var mapped := map_screen_point_to_viewport(screen_position)
    if pressed:
        if mapped.is_empty() or not mapped.get("inside", false):
            return
        _screen_pointer_down = true
    elif not _screen_pointer_down:
        return

    if not mapped.is_empty():
        _last_pointer_position = mapped["position"]
        _push_mouse_motion(_last_pointer_position)
    _push_mouse_button(_last_pointer_position, pressed)
    if pressed:
        _push_mouse_motion(_last_pointer_position)
    _screen_pointer_down = pressed
    _mark_screen_input_handled()

func _handle_screen_touch(index: int, screen_position: Vector2, pressed: bool) -> void:
    if pressed:
        if _screen_pointer_down:
            return
        var mapped := map_screen_point_to_viewport(screen_position)
        if mapped.is_empty() or not mapped.get("inside", false):
            return
        _screen_pointer_down = true
        _screen_pointer_index = index
        _last_pointer_position = mapped["position"]
        _push_mouse_motion(_last_pointer_position)
        _push_mouse_button(_last_pointer_position, true)
        _push_mouse_motion(_last_pointer_position)
        _mark_screen_input_handled()
    elif _screen_pointer_down and index == _screen_pointer_index:
        var mapped := map_screen_point_to_viewport(screen_position)
        if not mapped.is_empty():
            _last_pointer_position = mapped["position"]
            _push_mouse_motion(_last_pointer_position)
        _push_mouse_button(_last_pointer_position, false)
        _screen_pointer_down = false
        _screen_pointer_index = -1
        _mark_screen_input_handled()

func _mark_screen_input_handled() -> void:
    if consume_screen_pointer_events:
        get_viewport().set_input_as_handled()

func _push_mouse_motion(position: Vector2) -> void:
    if _viewport == null:
        return

    var event := InputEventMouseMotion.new()
    event.position = position
    event.global_position = position
    event.relative = position - _last_motion_position if _has_motion_position else Vector2.ZERO
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if _pointer_down else 0
    _viewport.push_input(event, true)
    _last_motion_position = position
    _has_motion_position = true

func _push_mouse_button(position: Vector2, pressed: bool) -> void:
    if _viewport == null or _pointer_down == pressed:
        return

    _pointer_down = pressed
    var event := InputEventMouseButton.new()
    event.position = position
    event.global_position = position
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.pressed = pressed
    _viewport.push_input(event, true)
