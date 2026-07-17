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
## Bindings while flat (H shows them on screen):
##   Right Mouse (hold) . trigger/select on the RIGHT hand (grab, click UI)
##   F (hold) ........... grab/activate button on the RIGHT hand
##   T (hold, release) .. push right thumbstick forward = teleport aim; release commits
##   Z / C .............. snap turn left / right
##   Mouse cursor ....... aims the right controller ray
##   X .................. switch to SIMULATED HANDS (Unity XR Device
##                        Simulator-style): fake XRHandTracker joints from the
##                        gesture presets (soft-loaded from godot_xr_hands).
##                        RMB then morphs a real PINCH (thumb+index together),
##                        driving the adapter's actual synthetic pinch select -
##                        authors see exactly how hand grabs behave. F = fist.
##
## Auto-inert the moment a real XR session starts (and restores everything),
## so it is SAFE TO LEAVE IN SHIPPED SCENES - on a headset it does nothing.
## Drop anywhere; it finds the rig itself.

enum SimMode { CONTROLLER, HAND }

const _HAND_TRACKER_NAMES := [&"/user/hand_tracker/left", &"/user/hand_tracker/right"]
const _POSE_PATHS := {
	"open": "res://addons/godot_xr_hands/runtime/gesture_studio/presets/open_palm.tres",
	"fist": "res://addons/godot_xr_hands/runtime/gesture_studio/presets/fist.tres",
}
const _JOINT_FLAGS: int = XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID \
		| XRHandTracker.HAND_JOINT_FLAG_POSITION_TRACKED \
		| XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID \
		| XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_TRACKED

## Master switch (runtime): off = never activates.
@export var enabled := true
## Show the on-screen hotkey help while simulating (H toggles it live).
@export var show_help := true
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
var _help_layer: CanvasLayer
var _help_body: Label
var _help_key_down := false
var _mode := SimMode.CONTROLLER
var _mode_key_down := false
var _hand_trackers := {}      # hand -> XRHandTracker WE registered
var _poses := {}              # "open"/"fist" -> [left PackedVector3Array, right ...]
var _current_pose: Array = [PackedVector3Array(), PackedVector3Array()]
var _openxr_was_processing := true


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

	if _mode == SimMode.CONTROLLER:
		_update_poses()
		_update_inputs(delta)
	else:
		_update_hand_poses(delta)
	_update_common_keys()


## ---- activation ---------------------------------------------------------------

func _activate() -> void:
	_add_controller_trackers()
	if _trackers.is_empty():
		return  # a real platform owns the controllers - stay passive
	_mode = SimMode.CONTROLLER
	_load_hand_poses()

	# On the web flat page the interactors point at the WebXR adapter, which
	# only emits selects inside a browser session - route them to the OpenXR
	# adapter, which listens to controller button signals (our fake inputs)
	# and runs the shared synthetic-pinch detector for simulated hands. The
	# adapter may have disabled its processing off-platform - re-enable it
	# for the simulation and restore on deactivate.
	if _openxr_adapter:
		_openxr_was_processing = _openxr_adapter.is_processing()
		_openxr_adapter.set_process(true)
		for interactor in _find_adapter_interactors(_origin.get_parent()):
			interactor.set_input_adapter(_openxr_adapter)
			_repointed.append(interactor)

	# The mouse ScreenRayInteractor duplicates our simulated ray - suspend it.
	for node in _find_screen_rays(_origin.get_parent()):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		_screen_rays.append(node)

	_active = true
	if _help_layer == null:
		_build_help_overlay()
	_help_layer.visible = show_help
	print("XRSimulator: flat-testing active (RMB=trigger, F=grab, T=teleport, Z/C=snap turn, H=help).")


func _deactivate() -> void:
	_remove_controller_trackers()
	_remove_hand_trackers()
	_mode = SimMode.CONTROLLER
	if _openxr_adapter:
		_openxr_adapter.set_process(_openxr_was_processing)
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
	if _help_layer:
		_help_layer.visible = false


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


func _update_common_keys() -> void:
	var help_key := Input.is_physical_key_pressed(KEY_H)
	if help_key and not _help_key_down:
		show_help = not show_help
		if _help_layer:
			_help_layer.visible = show_help
	_help_key_down = help_key

	var mode_key := Input.is_physical_key_pressed(KEY_X)
	if mode_key and not _mode_key_down and _hands_available():
		_set_mode(SimMode.HAND if _mode == SimMode.CONTROLLER else SimMode.CONTROLLER)
	_mode_key_down = mode_key


## ---- simulated hands -----------------------------------------------------------

func _hands_available() -> bool:
	return _poses.has("open") and _poses.has("fist")


## Gesture presets carry a wrist-local joint SNAPSHOT (PackedVector3Array
## indexed by XRHandTracker joint, recorded_hand = native chirality; the other
## hand is a wrist-local x-flip - same convention as the gesture ghost hand).
## Soft-loaded so the kit never hard-depends on godot_xr_hands.
const _GHOST_HAND_PATH := "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_ghost_hand.gd"

func _load_hand_poses() -> void:
	if not _poses.is_empty():
		return
	# Shipped presets are condition-only (no recorded snapshot) - synthesize
	# the joint positions from their curl conditions exactly like the gesture
	# ghost hand's preview does (canonical right-hand skeleton, pure math).
	var synthesizer: Node = null
	for key in _POSE_PATHS:
		var path: String = _POSE_PATHS[key]
		if not ResourceLoader.exists(path):
			break  # hands addon absent - controller mode only
		var preset: Resource = load(path)
		var snapshot: PackedVector3Array = preset.get("joint_snapshot") if preset.get("joint_snapshot") is PackedVector3Array else PackedVector3Array()
		var native_hand: int = 1
		if snapshot.size() >= XRHandTracker.HAND_JOINT_MAX:
			var recorded: Variant = preset.get("recorded_hand")
			native_hand = recorded if recorded is int and recorded >= 0 else 1
		else:
			if synthesizer == null and ResourceLoader.exists(_GHOST_HAND_PATH):
				synthesizer = (load(_GHOST_HAND_PATH) as GDScript).new()
			if synthesizer == null:
				break
			snapshot = synthesizer._synthesize_snapshot(preset)
			native_hand = 1  # the synthesized skeleton is canonically right
		if snapshot.size() < XRHandTracker.HAND_JOINT_MAX:
			break
		var per_hand := [null, null]
		for hand in 2:
			per_hand[hand] = snapshot if hand == native_hand else _mirrored(snapshot)
		_poses[key] = per_hand
	if synthesizer:
		synthesizer.free()
	if not _hands_available():
		_poses.clear()


func _mirrored(snapshot: PackedVector3Array) -> PackedVector3Array:
	var flipped := PackedVector3Array()
	flipped.resize(snapshot.size())
	for i in snapshot.size():
		var p := snapshot[i]
		flipped[i] = Vector3(-p.x, p.y, p.z)
	return flipped


func _set_mode(mode: SimMode) -> void:
	if mode == _mode:
		return
	if mode == SimMode.HAND and not _hands_available():
		return  # godot_xr_hands absent - controller simulation only
	_mode = mode
	if _mode == SimMode.HAND:
		_remove_controller_trackers()
		_add_hand_trackers()
	else:
		_remove_hand_trackers()
		_add_controller_trackers()
	_update_help_text()
	print("XRSimulator: %s mode." % ("simulated HANDS (RMB=pinch, F=fist)" if _mode == SimMode.HAND else "simulated CONTROLLERS"))


func _add_controller_trackers() -> void:
	# Never clobber real trackers (native editor Play with Link running).
	for hand in 2:
		var tracker_name := &"left_hand" if hand == 0 else &"right_hand"
		if XRServer.get_tracker(tracker_name) != null:
			continue
		var tracker := XRControllerTracker.new()
		tracker.name = tracker_name
		XRServer.add_tracker(tracker)
		_trackers[hand] = tracker


func _remove_controller_trackers() -> void:
	for hand in _trackers:
		XRServer.remove_tracker(_trackers[hand])
	_trackers.clear()
	_select_down = false
	_grab_down = false


func _add_hand_trackers() -> void:
	for hand in 2:
		if XRServer.get_tracker(_HAND_TRACKER_NAMES[hand]) != null:
			continue
		var tracker := XRHandTracker.new()
		tracker.name = _HAND_TRACKER_NAMES[hand]
		tracker.hand = XRPositionalTracker.TRACKER_HAND_LEFT if hand == 0 else XRPositionalTracker.TRACKER_HAND_RIGHT
		# UNOBSTRUCTED = real hand tracking: keeps the adapter's synthetic
		# pinch select armed (it ignores controller-emulated joints).
		tracker.hand_tracking_source = XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED
		XRServer.add_tracker(tracker)
		_hand_trackers[hand] = tracker
		_current_pose[hand] = (_poses["open"][hand] as PackedVector3Array).duplicate()


func _remove_hand_trackers() -> void:
	for hand in _hand_trackers:
		XRServer.remove_tracker(_hand_trackers[hand])
	_hand_trackers.clear()


func _update_hand_poses(delta: float) -> void:
	if _camera == null:
		return
	var to_origin := _origin.global_transform.affine_inverse()
	var cam := _camera.global_transform
	var blend := clampf(delta * 12.0, 0.0, 1.0)
	for hand in 2:
		var tracker: XRHandTracker = _hand_trackers.get(hand)
		if tracker == null:
			continue
		# Pose target: open palm; F makes the RIGHT hand a fist (gesture tests).
		var target_key := "fist" if hand == 1 and Input.is_physical_key_pressed(KEY_F) else "open"
		var target: PackedVector3Array = _poses[target_key][hand]
		var current: PackedVector3Array = _current_pose[hand]
		for i in current.size():
			current[i] = current[i].lerp(target[i], blend)
		_current_pose[hand] = current  # write back: packed arrays are CoW

		var applied := current
		if hand == 1 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			# Pinch morph: thumb+index tips meet -> the ADAPTER's real
			# synthetic-pinch detector fires select, exactly like on-device.
			applied = current.duplicate()
			var thumb := applied[XRHandTracker.HAND_JOINT_THUMB_TIP]
			var index := applied[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP]
			var mid := (thumb + index) * 0.5
			applied[XRHandTracker.HAND_JOINT_THUMB_TIP] = mid + (thumb - mid).normalized() * 0.008
			applied[XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP] = mid + (index - mid).normalized() * 0.008

		# Wrist anchor mirrors the controller placement; the right hand aims
		# at the mouse cursor so the hand ray is mouse-driven.
		var anchor_pos := cam * Vector3(0.25 if hand == 1 else -0.25, -0.2, -controller_distance)
		var anchor_basis := _basis_looking(anchor_pos, _mouse_target(anchor_pos)) if hand == 1 else cam.basis
		var anchor := to_origin * Transform3D(anchor_basis, anchor_pos)
		for joint in applied.size():
			tracker.set_hand_joint_transform(joint, Transform3D(anchor.basis, anchor * applied[joint]))
			tracker.set_hand_joint_flags(joint, _JOINT_FLAGS)
		tracker.has_tracking_data = true


## Unity XR Device Simulator-style on-screen bindings help, so nobody has to
## remember the hotkeys. Built in code (no scene dep), bottom-left corner.
func _build_help_overlay() -> void:
	_help_layer = CanvasLayer.new()
	_help_layer.layer = 90
	add_child(_help_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 12.0
	panel.offset_bottom = -12.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.self_modulate = Color(1.0, 1.0, 1.0, 0.85)
	_help_layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.text = "XR SIMULATOR - flat testing"
	title.add_theme_font_size_override("font_size", 13)
	column.add_child(title)

	_help_body = Label.new()
	_help_body.add_theme_font_size_override("font_size", 12)
	_help_body.self_modulate = Color(0.85, 0.9, 1.0)
	column.add_child(_help_body)
	_update_help_text()


func _update_help_text() -> void:
	if _help_body == null:
		return
	var lines := [
		"Move  W A S D  +  Q / E up-down",
		"Look  hold Left Mouse + drag",
	]
	if _mode == SimMode.CONTROLLER:
		lines += [
			"Aim ray  move the mouse cursor",
			"Trigger / select  hold Right Mouse",
			"Grab button  hold F",
			"Teleport  hold T, release to go",
			"Snap turn  Z / C",
		]
		if _hands_available():
			lines.append("X  switch to simulated HANDS")
	else:
		lines += [
			"Aim hand ray  move the mouse cursor",
			"Pinch (select/grab)  hold Right Mouse",
			"Fist pose  hold F",
			"X  switch to controllers",
		]
	lines.append("H  hide this help")
	_help_body.text = "\n".join(lines)


func _exit_tree() -> void:
	if _active:
		_deactivate()
