class_name FlatscreenCamera
extends Node

## Drop-in desktop/mobile camera control for the WebXR rig. Lets you look and move
## on a PC or phone browser WITHOUT entering an immersive session, so the scene is
## testable flat. Fully inert while an XR session is active — the headset drives the
## camera then, and this restores the camera's start pose on session entry so a flat
## preview offset never leaks into VR.
##
## Look:  drag (left mouse on desktop, one finger on mobile) to rotate the view.
## Move:  W/A/S/D or arrows to fly, Q/E (or Space/Shift) down/up. Hold Shift-equiv?
##        keep it simple — desktop-only movement; mobile gets look, which is the ask.

## The camera this controls. Defaults to the rig's XRCamera3D.
@export var camera_path := NodePath("../XROrigin3D/XRCamera3D")
## Degrees of rotation per screen pixel dragged.
@export var look_sensitivity := 0.25
## Metres per second for keyboard fly movement.
@export var move_speed := 2.0
## Clamp so you can't flip past straight up/down.
@export var max_pitch_degrees := 89.0
## Turn the whole thing off (e.g. a scene that supplies its own flat camera).
@export var enabled := true

var _camera: Camera3D
var _start_transform: Transform3D
var _has_start := false
var _yaw := 0.0
var _pitch := 0.0
var _dragging := false
var _drag_pointer := -1  # touch index, or -1 for mouse
var _was_xr := false

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera:
		_start_transform = _camera.transform
		_has_start = true
		# Seed yaw/pitch from wherever the camera starts so control is continuous.
		var e := _camera.transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	set_process(_camera != null)

func _process(delta: float) -> void:
	if not enabled or _camera == null:
		return
	var xr := get_viewport().use_xr
	if xr:
		# Session owns the camera. Restore the flat start pose once on entry so any
		# preview look/move offset does not carry into the headset view.
		if not _was_xr and _has_start:
			_camera.transform = _start_transform
		_was_xr = true
		return
	if _was_xr and _has_start:
		# Coming back from VR to flat: re-seed from the restored pose.
		var e := _camera.transform.basis.get_euler()
		_pitch = e.x
		_yaw = e.y
	_was_xr = false

	_apply_keyboard_move(delta)
	_camera.transform.basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))

func _apply_keyboard_move(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_SHIFT):
		dir.y -= 1.0
	if dir == Vector3.ZERO:
		return
	# Move relative to where we're looking, but keep vertical world-aligned.
	var basis := Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	var world := basis * Vector3(dir.x, 0.0, dir.z)
	world.y += dir.y
	_camera.position += world.normalized() * move_speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _camera == null or get_viewport().use_xr:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_pointer = -1
	elif event is InputEventMouseMotion and _dragging and _drag_pointer == -1:
		_rotate_by(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed and not _dragging:
			_dragging = true
			_drag_pointer = event.index
		elif not event.pressed and event.index == _drag_pointer:
			_dragging = false
			_drag_pointer = -1
	elif event is InputEventScreenDrag and _dragging and event.index == _drag_pointer:
		_rotate_by(event.relative)

func _rotate_by(relative: Vector2) -> void:
	_yaw -= deg_to_rad(relative.x * look_sensitivity)
	_pitch -= deg_to_rad(relative.y * look_sensitivity)
	var limit := deg_to_rad(max_pitch_degrees)
	_pitch = clampf(_pitch, -limit, limit)
