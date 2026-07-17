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
var _help_grid: GridContainer
var _help_footer: Label
var _help_key_down := false
var _mode := SimMode.CONTROLLER
var _mode_key_down := false
var _hand_trackers := {}      # hand -> XRHandTracker WE registered
var _poses := {}              # "open"/"fist" -> [left PackedVector3Array, right ...]
var _pose_library: Array = [] # [{name, per_hand}] - open + presets + user recordings
var _active_pose := 0         # library index applied to the RIGHT hand (0 = open)
var _pose_key_down := -1
var _current_pose: Array = [PackedVector3Array(), PackedVector3Array()]
var _hand_visual: Node3D
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

	# Number keys apply library gesture poses to the right hand (hand mode).
	if _mode == SimMode.HAND:
		var pressed := -1
		for i in range(0, mini(_pose_library.size(), 10)):
			if Input.is_physical_key_pressed(KEY_0 + i):
				pressed = i
				break
		if pressed >= 0 and pressed != _pose_key_down:
			_active_pose = 0 if pressed == _active_pose else pressed
			_update_help_text()
			print("XRSimulator: right hand pose -> %s" % _pose_library[_active_pose]["name"])
		_pose_key_down = pressed


## ---- simulated hands -----------------------------------------------------------

func _hands_available() -> bool:
	return _poses.has("open") and _poses.has("fist")


## Gesture presets carry a wrist-local joint SNAPSHOT (PackedVector3Array
## indexed by XRHandTracker joint, recorded_hand = native chirality; the other
## hand is a wrist-local x-flip - same convention as the gesture ghost hand).
## Soft-loaded so the kit never hard-depends on godot_xr_hands.
const _GHOST_HAND_PATH := "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_ghost_hand.gd"
const _HAND_MESH_PATH := "res://addons/godot_xr_hands/runtime/xr_hand_mesh_visualizer.gd"

## Finger chains (XRHandTracker joint ids) for deriving per-joint
## orientations from the position snapshot: each joint aims +Y at its
## successor (Godot's Humanoid hand convention - the engine maps OpenXR
## Z+ back-along-bone to Godot Y-), so the realistic hand mesh skins
## simulated poses with proper curl instead of uniform-orientation smear.
const _FINGER_CHAINS := [
	[XRHandTracker.HAND_JOINT_THUMB_METACARPAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_THUMB_TIP],
	[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP],
	[XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
]

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
	if _hands_available():
		_build_pose_library(synthesizer)
	else:
		_poses.clear()
	if synthesizer:
		synthesizer.free()


## The Unity-style editor gesture bench: number keys apply ANY authored
## gesture to the simulated right hand - the shipped presets plus your own
## Gesture Studio recordings (user://gestures) - so the scene's REAL
## recognizers react while you test flat. Slot 0 = open palm; capped at 9.
func _build_pose_library(synthesizer: Node) -> void:
	_pose_library = [{"name": "open palm", "per_hand": _poses["open"]}]
	var sources: Array = []
	var preset_dir := DirAccess.open(_POSE_PATHS["open"].get_base_dir())
	if preset_dir:
		for file in preset_dir.get_files():
			if file.ends_with(".tres") and file != "open_palm.tres":
				sources.append(_POSE_PATHS["open"].get_base_dir().path_join(file))
	var user_dir := DirAccess.open("user://gestures")
	if user_dir:
		for file in user_dir.get_files():
			if file.ends_with(".tres"):
				sources.append("user://gestures".path_join(file))
	for path in sources:
		if _pose_library.size() > 9:
			break
		var preset: Resource = load(path)
		if preset == null or preset.get("stages") != null:
			continue  # sequences (motion gestures) have no static pose
		var snapshot: PackedVector3Array = preset.get("joint_snapshot") if preset.get("joint_snapshot") is PackedVector3Array else PackedVector3Array()
		var native_hand := 1
		if snapshot.size() >= XRHandTracker.HAND_JOINT_MAX:
			var recorded: Variant = preset.get("recorded_hand")
			native_hand = recorded if recorded is int and recorded >= 0 else 1
		elif synthesizer and preset.get("conditions") is Dictionary:
			snapshot = synthesizer._synthesize_snapshot(preset)
		if snapshot.size() < XRHandTracker.HAND_JOINT_MAX:
			continue
		var per_hand := [null, null]
		for hand in 2:
			per_hand[hand] = snapshot if hand == native_hand else _mirrored(snapshot)
		var pose_name: String = preset.get("gesture_name") if preset.get("gesture_name") else str(path.get_file().get_basename()).replace("_", " ")
		_pose_library.append({"name": pose_name, "per_hand": per_hand})


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
		_active_pose = 0
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
	# The procedural hand visualizer is XR-session-gated (hard-hides flat),
	# so the simulator shows the REALISTIC hand mesh - the same visual real
	# scenes use - driven by these fake trackers. Soft-loaded; without the
	# hands addon the simulated hands are input-only.
	if _hand_visual == null and _origin and ResourceLoader.exists(_HAND_MESH_PATH):
		_hand_visual = (load(_HAND_MESH_PATH) as GDScript).new()
		_hand_visual.name = "SimulatedHandMesh"
		_origin.add_child(_hand_visual)


func _remove_hand_trackers() -> void:
	for hand in _hand_trackers:
		XRServer.remove_tracker(_hand_trackers[hand])
	_hand_trackers.clear()
	if _hand_visual:
		_hand_visual.queue_free()
		_hand_visual = null


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
		# Pose target: the library pose selected by number key (0 = open palm);
		# F momentarily overrides the RIGHT hand with a fist.
		var target: PackedVector3Array
		if hand == 1 and Input.is_physical_key_pressed(KEY_F):
			target = _poses["fist"][hand]
		elif hand == 1 and _active_pose > 0 and _active_pose < _pose_library.size():
			target = _pose_library[_active_pose]["per_hand"][hand]
		else:
			target = _poses["open"][hand]
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
		# at the mouse cursor so the hand ray is mouse-driven. The sub-mm sway
		# mimics real tracking jitter - without it the hand visualizer's
		# frozen-hand watchdog (built for Quest's stale-pose bug) classifies
		# bit-identical simulated joints as frozen and hides the hand.
		var sway_time := Time.get_ticks_msec() * 0.001
		var sway := Vector3(sin(sway_time * 1.3 + hand), sin(sway_time * 1.7), sin(sway_time * 2.1)) * 0.0006
		var anchor_pos := cam * Vector3(0.25 if hand == 1 else -0.25, -0.2, -controller_distance) + sway
		var anchor_basis := _basis_looking(anchor_pos, _mouse_target(anchor_pos)) if hand == 1 else cam.basis
		var anchor := to_origin * Transform3D(anchor_basis, anchor_pos)
		var joint_bases := _derive_joint_bases(applied, hand)
		for joint in applied.size():
			tracker.set_hand_joint_transform(joint,
					Transform3D(anchor.basis * joint_bases[joint], anchor * applied[joint]))
			tracker.set_hand_joint_flags(joint, _JOINT_FLAGS)
		tracker.has_tracking_data = true


## Per-joint orientations from the position snapshot, in Godot's Humanoid
## hand convention: +Y aims at the next joint along the finger (tip-ward),
## Z built from the palm normal (chirality-corrected). Consumers that read
## orientations - most importantly the realistic hand mesh, whose driver
## un-rebases back to the WebXR frame - get proper curl instead of a
## uniform-orientation smear.
func _derive_joint_bases(pose: PackedVector3Array, hand: int) -> Array:
	var bases := []
	bases.resize(pose.size())
	var wrist := pose[XRHandTracker.HAND_JOINT_WRIST]
	var palm_normal := (pose[XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL] - wrist).cross(
			pose[XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL] - wrist).normalized()
	if hand == 0:
		palm_normal = -palm_normal
	var wrist_basis := _basis_from_bone(
			(pose[XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL] - wrist).normalized(), palm_normal)
	for joint in pose.size():
		bases[joint] = wrist_basis
	for chain in _FINGER_CHAINS:
		for i in chain.size():
			var joint: int = chain[i]
			var bone_dir: Vector3
			if i < chain.size() - 1:
				bone_dir = pose[chain[i + 1]] - pose[joint]
			else:
				bone_dir = pose[joint] - pose[chain[i - 1]]  # tip keeps its bone's aim
			bases[joint] = _basis_from_bone(bone_dir.normalized(), palm_normal)
	return bases


func _basis_from_bone(y_dir: Vector3, reference_normal: Vector3) -> Basis:
	if y_dir.length_squared() < 0.000001:
		return Basis.IDENTITY
	var x_axis := reference_normal.cross(y_dir)
	if x_axis.length_squared() < 0.000001:
		x_axis = y_dir.cross(Vector3.UP)
		if x_axis.length_squared() < 0.000001:
			x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_dir).normalized()
	return Basis(x_axis, y_dir, z_axis)


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
	title.text = "XR SIMULATOR"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "flat testing - no headset"
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	column.add_child(subtitle)

	_help_grid = GridContainer.new()
	_help_grid.columns = 2
	_help_grid.add_theme_constant_override("h_separation", 14)
	_help_grid.add_theme_constant_override("v_separation", 3)
	column.add_child(_help_grid)

	_help_footer = Label.new()
	_help_footer.add_theme_font_size_override("font_size", 12)
	_help_footer.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	column.add_child(_help_footer)
	_update_help_text()


func _update_help_text() -> void:
	if _help_grid == null:
		return
	for child in _help_grid.get_children():
		child.queue_free()
	var rows := [
		["W A S D · Q E", "move / fly"],
		["Left Mouse", "hold + drag to look"],
		["Mouse cursor", "aims the ray"],
	]
	if _mode == SimMode.CONTROLLER:
		rows += [
			["Right Mouse", "trigger — select / grab"],
			["F", "grab button"],
			["T", "hold to aim teleport, release to go"],
			["Z / C", "snap turn"],
		]
		if _hands_available():
			rows.append(["X", "switch to simulated hands"])
	else:
		rows += [
			["Right Mouse", "pinch — select / grab"],
			["F", "fist (hold)"],
			["X", "switch to controllers"],
		]
		for i in range(1, _pose_library.size()):
			rows.append([str(i), "pose: %s (again = open)" % _pose_library[i]["name"]])
	rows.append(["H", "hide this help"])
	for row in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(0.55, 0.82, 1.0))
		key.custom_minimum_size = Vector2(104, 0)
		_help_grid.add_child(key)
		var action := Label.new()
		action.text = row[1]
		action.add_theme_font_size_override("font_size", 12)
		action.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
		_help_grid.add_child(action)
	var holding := _mode == SimMode.HAND and _active_pose > 0 and _active_pose < _pose_library.size()
	_help_footer.visible = holding
	_help_footer.text = "holding: %s" % _pose_library[_active_pose]["name"] if holding else ""


func _exit_tree() -> void:
	if _active:
		_deactivate()
