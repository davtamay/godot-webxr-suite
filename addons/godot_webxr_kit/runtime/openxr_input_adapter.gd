class_name OpenXRInputAdapter
extends "res://addons/godot_xr_interaction_toolkit/runtime/input/xr_input_adapter.gd"

const XRHandGestureProvider := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_gesture_provider.gd")
const XRHandTrackerResolver := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_tracker_resolver.gd")

## Native (OpenXR) input source - the platform twin of WebXRInputAdapter for
## editor-time / native testing via Meta Quest Link, SteamVR, or Android XR.
##
## Feeds the SAME abstract XRInputAdapter the whole interaction toolkit consumes,
## so the manager, interactors, grab, and UI reuse unchanged. Poses come from the
## standard XRController3D nodes (driven by the OpenXR action map) and the standard
## XRHandTracker hand ray/pinch - identical to the WebXR adapter. The only
## difference is where select/activate come from: the controllers' action-map
## button signals (trigger -> select, grip -> activate) instead of browser events.
## Bare-hand pinch is still synthesized from XRHandTracker joints, so hand tracking
## grabs work too.
##
## Inert on web exports (the WebXR adapter owns that path). Requires an OpenXR
## action map exposing an "aim" pose action plus the boolean actions named below;
## godot_webxr_kit ships one at openxr/default_action_map.tres.

@export_group("Rig")
@export var xr_origin_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath

@export_group("Actions")
## Boolean action name (from the OpenXR action map) that fires select (grab).
@export var select_action := "select"
## Boolean action name that fires activate (use/trigger-while-held).
@export var activate_action := "grab"

@export_group("Ray Source")
## false: prefer the controller aim ray. true: prefer the hand-joint ray.
@export var prefer_hand_ray := false

@export_group("Pinch Select")
@export var synthesize_pinch_select := true
@export_range(0.001, 0.2, 0.001, "or_greater") var pinch_start_distance := 0.035
@export_range(0.001, 0.2, 0.001, "or_greater") var pinch_end_distance := 0.055

var _origin: Node3D
var _controllers := {}
var _select_down := {
	Hand.LEFT: false,
	Hand.RIGHT: false,
}
var _select_source := {
	Hand.LEFT: "",
	Hand.RIGHT: "",
}
var _activate_down := {
	Hand.LEFT: false,
	Hand.RIGHT: false,
}


func _ready() -> void:
	_origin = get_node_or_null(xr_origin_path) as Node3D
	_controllers[Hand.LEFT] = get_node_or_null(left_controller_path) as XRController3D
	_controllers[Hand.RIGHT] = get_node_or_null(right_controller_path) as XRController3D
	if OS.has_feature("web"):
		return  # WebXR adapter owns the browser path.

	_connect_controller(Hand.LEFT)
	_connect_controller(Hand.RIGHT)


func _process(_delta: float) -> void:
	if synthesize_pinch_select:
		_update_synthetic_pinch_select(Hand.LEFT)
		_update_synthetic_pinch_select(Hand.RIGHT)


func get_aim_pose(hand_id: int) -> Dictionary:
	if not _valid_hand(hand_id):
		return {}

	var hand_pose := _hand_aim_pose(hand_id)
	if prefer_hand_ray:
		return hand_pose if not hand_pose.is_empty() else _controller_aim_pose(hand_id)

	var controller_pose := _controller_aim_pose(hand_id)
	return controller_pose if not controller_pose.is_empty() else hand_pose


func get_grip_pose(hand_id: int) -> Dictionary:
	if not _valid_hand(hand_id):
		return {}

	var hand_pose := _hand_grip_pose(hand_id)
	return hand_pose if not hand_pose.is_empty() else _controller_aim_pose(hand_id)


func get_source_kind(hand_id: int) -> int:
	if not _valid_hand(hand_id):
		return SourceKind.NONE

	var hand_tracked := not _hand_aim_pose(hand_id).is_empty()
	var controller_tracked := not _controller_aim_pose(hand_id).is_empty()
	if prefer_hand_ray and hand_tracked:
		return SourceKind.HAND
	if controller_tracked:
		return SourceKind.CONTROLLER
	if hand_tracked:
		return SourceKind.HAND
	return SourceKind.NONE


func _connect_controller(hand_id: int) -> void:
	var controller := _controllers.get(hand_id) as XRController3D
	if controller == null:
		return
	controller.button_pressed.connect(_on_button_pressed.bind(hand_id))
	controller.button_released.connect(_on_button_released.bind(hand_id))


func _on_button_pressed(action_name: String, hand_id: int) -> void:
	if action_name == select_action:
		_emit_select_started(hand_id, "controller")
	elif action_name == activate_action:
		_emit_activate_started(hand_id, "controller")


func _on_button_released(action_name: String, hand_id: int) -> void:
	if action_name == select_action:
		_emit_select_ended(hand_id, "controller")
	elif action_name == activate_action:
		_emit_activate_ended(hand_id, "controller")


func _controller_aim_pose(hand_id: int) -> Dictionary:
	if not _valid_hand(hand_id):
		return {}

	var controller := _controllers.get(hand_id) as XRController3D
	if controller == null or not controller.get_is_active() or not controller.get_has_tracking_data():
		return {}

	var xf := controller.global_transform
	return {
		"origin": xf.origin,
		"direction": (-xf.basis.z).normalized(),
		"basis": xf.basis.orthonormalized(),
	}


func _hand_aim_pose(hand_id: int) -> Dictionary:
	if not _valid_hand(hand_id) or _origin == null:
		return {}

	var tracker := XRHandTrackerResolver.get_tracker(hand_id)
	var local_pose := XRHandGestureProvider.get_hand_ray_pose(tracker)
	if local_pose.is_empty():
		return {}

	var origin_xf := _origin.global_transform
	var direction := (origin_xf.basis * (local_pose["direction"] as Vector3)).normalized()
	return {
		"origin": origin_xf * (local_pose["origin"] as Vector3),
		"direction": direction,
		"basis": XRHandGestureProvider.basis_from_forward(direction),
	}


func _hand_grip_pose(hand_id: int) -> Dictionary:
	if not _valid_hand(hand_id) or _origin == null:
		return {}

	var tracker := XRHandTrackerResolver.get_tracker(hand_id)
	if tracker == null:
		return {}

	var grip_joint := XRHandTracker.HAND_JOINT_PALM
	if not XRHandGestureProvider.joint_position_valid(tracker, grip_joint):
		grip_joint = XRHandTracker.HAND_JOINT_WRIST
	if not XRHandGestureProvider.joint_position_valid(tracker, grip_joint):
		return {}

	var grip_transform := _origin.global_transform * tracker.get_hand_joint_transform(grip_joint)
	return {
		"origin": grip_transform.origin,
		"basis": grip_transform.basis.orthonormalized(),
	}


func _valid_hand(hand_id: int) -> bool:
	return hand_id == Hand.LEFT or hand_id == Hand.RIGHT


func _update_synthetic_pinch_select(hand_id: int) -> void:
	if not _valid_hand(hand_id):
		return
	if _select_source.get(hand_id, "") == "controller":
		return  # a real controller select is down; don't also synthesize a pinch.

	var distance := _pinch_distance(hand_id)
	if distance < 0.0:
		if _select_source.get(hand_id, "") == "synthetic":
			_emit_select_ended(hand_id, "synthetic")
		return

	if not _select_down.get(hand_id, false) and distance <= pinch_start_distance:
		_emit_select_started(hand_id, "synthetic")
	elif _select_source.get(hand_id, "") == "synthetic" and distance >= pinch_end_distance:
		_emit_select_ended(hand_id, "synthetic")


func _pinch_distance(hand_id: int) -> float:
	if not _valid_hand(hand_id):
		return -1.0

	var tracker := XRHandTrackerResolver.get_tracker(hand_id)
	if tracker == null:
		return -1.0

	var index_tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
	var thumb_tip := XRHandTracker.HAND_JOINT_THUMB_TIP
	if not XRHandGestureProvider.joint_position_valid(tracker, index_tip):
		return -1.0
	if not XRHandGestureProvider.joint_position_valid(tracker, thumb_tip):
		return -1.0

	var index_position := tracker.get_hand_joint_transform(index_tip).origin
	var thumb_position := tracker.get_hand_joint_transform(thumb_tip).origin
	return index_position.distance_to(thumb_position)


func _emit_select_started(hand_id: int, source: String) -> void:
	if not _valid_hand(hand_id) or _select_down.get(hand_id, false):
		return
	_select_down[hand_id] = true
	_select_source[hand_id] = source
	select_started.emit(hand_id)


func _emit_select_ended(hand_id: int, source: String) -> void:
	if not _valid_hand(hand_id) or not _select_down.get(hand_id, false):
		return
	if source == "synthetic" and _select_source.get(hand_id, "") == "controller":
		return
	_select_down[hand_id] = false
	_select_source[hand_id] = ""
	select_ended.emit(hand_id)


func _emit_activate_started(hand_id: int, source: String) -> void:
	if not _valid_hand(hand_id) or _activate_down.get(hand_id, false):
		return
	_activate_down[hand_id] = true
	activate_started.emit(hand_id)


func _emit_activate_ended(hand_id: int, source: String) -> void:
	if not _valid_hand(hand_id) or not _activate_down.get(hand_id, false):
		return
	_activate_down[hand_id] = false
	activate_ended.emit(hand_id)
