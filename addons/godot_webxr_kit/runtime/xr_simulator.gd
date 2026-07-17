@icon("res://addons/godot_webxr_kit/icons/openxr_input_adapter.svg")
class_name XRSimulator
extends Node

## Desktop XR simulator: test grab, teleport, poke, and UI flat - no headset.
##
## Registers FAKE controller trackers into XRServer (only when the platform
## has none) and drives them from mouse + keyboard, so every input path in
## the suite lights up unmodified - the rig's XRController3D nodes, the input
## adapters, locomotion's thumbstick read, poke's controller tip, modality.
## The rig's FlatscreenCamera keeps head movement (WASD + drag-look).
##
## Bindings while flat:
##   Right Mouse (hold) . trigger/select on the RIGHT hand (grab, click UI)
##   F (hold) ........... grab/activate button on the RIGHT hand
##   T (hold, release) .. push right thumbstick forward = teleport aim; release commits
##   Z / C .............. snap turn left / right
##   Mouse cursor ....... aims the right controller ray
##
## Auto-inert the moment a real XR session starts (and restores everything),
## so it is SAFE TO LEAVE IN SHIPPED SCENES - on a headset it does nothing.
## Drop anywhere; it finds the rig itself.

## Master switch (runtime): off = never activates.
@export var enabled := true
## How far in front of the camera the simulated controllers sit.
@export var controller_distance := 0.35
## Snap-turn key pulse length (locomotion edge-detects the stick).
@export var snap_pulse_seconds := 0.2

var _origin: XROrigin3D
var _camera: Camera3D
var _openxr_adapter: Node
var _webxr_adapter: Node
var _trackers := {}          # hand -> XRControllerTracker WE registered
var _repointed: Array = []   # interactors we switched to the OpenXR adapter
var _screen_rays: Array = [] # ScreenRayInteractors we suspended
var _active := false
var _select_down := false
var _grab_down := false
var _snap_pulse := 0.0
var _snap_direction := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	_resolve_rig.call_deferred()


func _resolve_rig() -> void:
	var scene := get_tree().current_scene if get_tree() else null
	var search_root: Node = scene if scene else get_tree().root
	var origins := search_root.find_children("*", "XROrigin3D", true, false)
	_origin = origins[0] as XROrigin3D if not origins.is_empty() else null
	if _origin == null:
		push_warning("XRSimulator: no XROrigin3D found - drop a WebXR Prefab/Rig first.")
		set_process(false)
		return
	var cameras := _origin.find_children("*", "XRCamera3D", true, false)
	_camera = cameras[0] as Camera3D if not cameras.is_empty() else null
	var rig := _origin.get_parent()
	if rig:
		_openxr_adapter = rig.get_node_or_null("OpenXRInputAdapter")
		_webxr_adapter = rig.get_node_or_null("WebXRInputAdapter")


func _process(delta: float) -> void:
	if _origin == null:
		return
	var in_xr := get_viewport().use_xr
	if _active and (in_xr or not enabled):
		_deactivate()
	elif not _active and not in_xr and enabled:
		_activate()
	if not _active:
		return

	_update_poses()
	_update_inputs(delta)


## ---- activation ---------------------------------------------------------------

func _activate() -> void:
	# Never clobber real trackers (native editor Play with Link running).
	for hand in 2:
		var tracker_name := &"left_hand" if hand == 0 else &"right_hand"
		if XRServer.get_tracker(tracker_name) != null:
			continue
		var tracker := XRControllerTracker.new()
		tracker.name = tracker_name
		XRServer.add_tracker(tracker)
		_trackers[hand] = tracker
	if _trackers.is_empty():
		return  # a real platform owns the controllers - stay passive

	# On the web flat page the interactors point at the WebXR adapter, which
	# only emits selects inside a browser session - route them to the OpenXR
	# adapter, which listens to controller button signals (our fake inputs).
	if _openxr_adapter:
		for interactor in _find_adapter_interactors(_origin.get_parent()):
			interactor.set_input_adapter(_openxr_adapter)
			_repointed.append(interactor)

	# The mouse ScreenRayInteractor duplicates our simulated ray - suspend it.
	for node in _find_screen_rays(_origin.get_parent()):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		_screen_rays.append(node)

	_active = true
	print("XRSimulator: flat-testing active (RMB=trigger, F=grab, T=teleport, Z/C=snap turn).")


func _deactivate() -> void:
	for hand in _trackers:
		XRServer.remove_tracker(_trackers[hand])
	_trackers.clear()
	if _webxr_adapter:
		for interactor in _repointed:
			if is_instance_valid(interactor):
				interactor.set_input_adapter(_webxr_adapter)
	_repointed.clear()
	for node in _screen_rays:
		if is_instance_valid(node):
			node.process_mode = Node.PROCESS_MODE_INHERIT
	_screen_rays.clear()
	_select_down = false
	_grab_down = false
	_active = false


func _find_adapter_interactors(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for child in root.get_children():
		if child.has_method("set_input_adapter"):
			var path: Variant = child.get("input_adapter_path")
			if path is NodePath and not (path as NodePath).is_empty():
				out.append(child)
		out.append_array(_find_adapter_interactors(child))
	return out


func _find_screen_rays(root: Node) -> Array:
	var out: Array = []
	if root == null:
		return out
	for child in root.get_children():
		var script: Script = child.get_script()
		if script and script.resource_path.contains("xr_screen_ray_interactor"):
			out.append(child)
		out.append_array(_find_screen_rays(child))
	return out


## ---- per-frame simulation ------------------------------------------------------

func _update_poses() -> void:
	if _camera == null:
		return
	var to_origin := _origin.global_transform.affine_inverse()
	var cam := _camera.global_transform

	# RIGHT controller: sits at the camera's lower right, aiming at the point
	# the mouse cursor is over - the ray interactor becomes mouse-driven.
	var right_pos := cam * Vector3(0.25, -0.2, -controller_distance)
	var target := _mouse_target(right_pos)
	var right_xf := Transform3D(_basis_looking(right_pos, target), right_pos)
	_set_hand_pose(1, to_origin * right_xf)

	# LEFT controller: passive companion at the lower left, aiming forward.
	var left_pos := cam * Vector3(-0.25, -0.2, -controller_distance)
	var left_xf := Transform3D(cam.basis, left_pos)
	_set_hand_pose(0, to_origin * left_xf)


func _mouse_target(from_position: Vector3) -> Vector3:
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse)
	var ray_direction := _camera.project_ray_normal(mouse)
	return ray_origin + ray_direction * 5.0


func _basis_looking(from_position: Vector3, at: Vector3) -> Basis:
	var forward := (at - from_position).normalized()
	if forward.length_squared() < 0.000001:
		return _camera.global_transform.basis
	var up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(forward, up)


func _set_hand_pose(hand: int, pose: Transform3D) -> void:
	var tracker: XRControllerTracker = _trackers.get(hand)
	if tracker == null:
		return
	for pose_name in [&"aim", &"grip", &"default"]:
		tracker.set_pose(pose_name, pose, Vector3.ZERO, Vector3.ZERO,
				XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _update_inputs(delta: float) -> void:
	var right: XRControllerTracker = _trackers.get(1)
	if right == null:
		return

	var select_now := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if select_now != _select_down:
		_select_down = select_now
		right.set_input(&"select", select_now)

	var grab_now := Input.is_physical_key_pressed(KEY_F)
	if grab_now != _grab_down:
		_grab_down = grab_now
		right.set_input(&"grab", grab_now)

	# Thumbstick: T holds forward (teleport aim; releasing commits), Z/C pulse
	# sideways (snap turn - locomotion edge-detects the deflection).
	var stick := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_T):
		stick.y = 1.0
	if _snap_pulse > 0.0:
		_snap_pulse -= delta
		stick.x = _snap_direction
	elif Input.is_physical_key_pressed(KEY_Z):
		_snap_pulse = snap_pulse_seconds
		_snap_direction = -1.0
	elif Input.is_physical_key_pressed(KEY_C):
		_snap_pulse = snap_pulse_seconds
		_snap_direction = 1.0
	right.set_input(&"thumbstick", stick)


func _exit_tree() -> void:
	if _active:
		_deactivate()
