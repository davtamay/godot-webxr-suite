class_name WebXRInputAdapter
extends "res://addons/godot_xr_interaction_toolkit/runtime/input/xr_input_adapter.gd"

const XRHandGestureProvider := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_gesture_provider.gd")
const XRHandTrackerResolver := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_tracker_resolver.gd")

const BROWSER_PALM_JOINT_NAMES := [
    "wrist",
    "index-finger-metacarpal",
    "middle-finger-metacarpal",
    "ring-finger-metacarpal",
    "pinky-finger-metacarpal",
]

## WebXR input source: interface-level selectstart/selectend signals resolved
## to handedness, controller aim poses from XRController3D, and the validated
## XRHandTracker hand-ray fallback. Inert outside web exports.

@export_group("Rig")
@export var xr_origin_path: NodePath
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath

@export_group("Ray Source")
## false: prefer the runtime target ray from XRController3D aim pose. On Quest
## hand tracking this is closer to the Meta OS cursor behavior. true: prefer
## the fallback ray computed from hand joints.
@export var prefer_hand_ray := false

@export_group("Pinch Select")
@export var synthesize_pinch_select := true
@export_range(0.001, 0.2, 0.001, "or_greater") var pinch_start_distance := 0.035
@export_range(0.001, 0.2, 0.001, "or_greater") var pinch_end_distance := 0.055

@export_group("Select Stabilization")
## Experimental: keeps a hand ray from jumping when thumb/index pinch geometry changes.
## While selected, the cached pre-select ray translates with the palm but keeps
## its aim direction stable until release.
@export var stabilize_hand_select := false

@export_group("Browser Bridge")
@export var prefer_browser_hand_bridge := true

var _webxr
var _js_bridge
var _browser_hand_snapshot := {}
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
var _activate_source := {
    Hand.LEFT: "",
    Hand.RIGHT: "",
}
var _last_free_hand_pose := {
    Hand.LEFT: {},
    Hand.RIGHT: {},
}
var _last_free_hand_anchor := {
    Hand.LEFT: null,
    Hand.RIGHT: null,
}
var _select_anchor_pose := {
    Hand.LEFT: {},
    Hand.RIGHT: {},
}
var _select_anchor_hand_anchor := {
    Hand.LEFT: null,
    Hand.RIGHT: null,
}

func _ready() -> void:
    _origin = get_node_or_null(xr_origin_path) as Node3D
    _controllers[Hand.LEFT] = get_node_or_null(left_controller_path) as XRController3D
    _controllers[Hand.RIGHT] = get_node_or_null(right_controller_path) as XRController3D
    if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
        _js_bridge = Engine.get_singleton("JavaScriptBridge")
    if not OS.has_feature("web"):
        return

    _webxr = XRServer.find_interface("WebXR")
    if _webxr == null:
        return

    _connect_interface_signal(&"selectstart", _on_selectstart)
    _connect_interface_signal(&"selectend", _on_selectend)
    _connect_interface_signal(&"squeezestart", _on_squeezestart)
    _connect_interface_signal(&"squeezeend", _on_squeezeend)

func _process(_delta: float) -> void:
    _refresh_browser_hand_snapshot()
    if synthesize_pinch_select:
        _update_synthetic_pinch_select(Hand.LEFT)
        _update_synthetic_pinch_select(Hand.RIGHT)

func get_aim_pose(hand_id: int) -> Dictionary:
    if not _valid_hand(hand_id):
        return {}

    var browser_pose := _browser_aim_pose(hand_id)
    if not browser_pose.is_empty():
        return _stabilized_hand_pose(hand_id, browser_pose)

    var hand_pose := _hand_aim_pose(hand_id)
    if not hand_pose.is_empty():
        hand_pose = _stabilized_hand_pose(hand_id, hand_pose)

    if prefer_hand_ray:
        return hand_pose if not hand_pose.is_empty() else _controller_aim_pose(hand_id)

    var controller_pose := _controller_aim_pose(hand_id)
    return controller_pose if not controller_pose.is_empty() else hand_pose

func get_grip_pose(hand_id: int) -> Dictionary:
    if not _valid_hand(hand_id):
        return {}

    var browser_pose := _browser_grip_pose(hand_id)
    if not browser_pose.is_empty():
        return browser_pose

    var hand_pose := _hand_grip_pose(hand_id)
    return hand_pose if not hand_pose.is_empty() else _controller_aim_pose(hand_id)

func get_source_kind(hand_id: int) -> int:
    if not _valid_hand(hand_id):
        return SourceKind.NONE

    var browser_tracked := not _browser_aim_pose(hand_id).is_empty() or not _browser_grip_pose(hand_id).is_empty()
    if browser_tracked:
        return SourceKind.HAND

    var hand_tracked := not _hand_aim_pose(hand_id).is_empty()
    var controller_tracked := not _controller_aim_pose(hand_id).is_empty()
    if prefer_hand_ray and hand_tracked:
        return SourceKind.HAND
    if controller_tracked:
        return SourceKind.CONTROLLER
    if hand_tracked:
        return SourceKind.HAND
    return SourceKind.NONE

func _connect_interface_signal(signal_name: StringName, callback: Callable) -> void:
    if not _webxr.has_signal(signal_name):
        push_warning("WebXR signal unavailable in this Godot build: %s" % signal_name)
        return
    if not _webxr.is_connected(signal_name, callback):
        _webxr.connect(signal_name, callback)

func _refresh_browser_hand_snapshot() -> void:
    if _js_bridge == null:
        _browser_hand_snapshot = {}
        return

    var json_text = _js_bridge.eval("JSON.stringify(window.CompanyWebXRHandBridge && window.CompanyWebXRHandBridge.latest || null)", true)
    var parsed = JSON.parse_string(str(json_text))
    if typeof(parsed) == TYPE_DICTIONARY:
        _browser_hand_snapshot = parsed
    else:
        _browser_hand_snapshot = {}

func _browser_hand_snapshot_for(hand_id: int) -> Dictionary:
    if not prefer_browser_hand_bridge or _browser_hand_snapshot.is_empty():
        return {}

    var hands = _browser_hand_snapshot.get("hands", {})
    if typeof(hands) != TYPE_DICTIONARY:
        return {}

    var side := "right" if hand_id == Hand.RIGHT else "left"
    var hand = hands.get(side, {})
    return hand if typeof(hand) == TYPE_DICTIONARY else {}

func _browser_aim_pose(hand_id: int) -> Dictionary:
    var hand := _browser_hand_snapshot_for(hand_id)
    if hand.is_empty():
        return {}
    return _pose_from_browser_payload(hand.get("targetRay", {}))

func _browser_grip_pose(hand_id: int) -> Dictionary:
    var hand := _browser_hand_snapshot_for(hand_id)
    if hand.is_empty():
        return {}

    var grip_pose := _pose_from_browser_payload(hand.get("grip", {}))
    if not grip_pose.is_empty():
        return grip_pose

    var palm = _browser_joint_average(hand, BROWSER_PALM_JOINT_NAMES)
    if palm == null:
        return {}

    var origin_xf := _origin.global_transform if _origin != null else Transform3D.IDENTITY
    return {
        "origin": origin_xf * (palm as Vector3),
        "basis": origin_xf.basis.orthonormalized(),
    }

func _pose_from_browser_payload(payload) -> Dictionary:
    if typeof(payload) != TYPE_DICTIONARY:
        return {}
    if payload.is_empty():
        return {}
    if not payload.has("x") or not payload.has("y") or not payload.has("z"):
        return {}

    var local_origin := Vector3(
        float(payload.get("x", 0.0)),
        float(payload.get("y", 0.0)),
        float(payload.get("z", 0.0))
    )
    var local_direction := Vector3(
        float(payload.get("dx", 0.0)),
        float(payload.get("dy", 0.0)),
        float(payload.get("dz", -1.0))
    )
    if local_direction.length_squared() < 0.000001:
        return {}

    var origin_xf := _origin.global_transform if _origin != null else Transform3D.IDENTITY
    var direction := (origin_xf.basis * local_direction).normalized()
    return {
        "origin": origin_xf * local_origin,
        "direction": direction,
        "basis": XRHandGestureProvider.basis_from_forward(direction),
    }

func _browser_joint_average(hand: Dictionary, joint_names: Array):
    var joints = hand.get("joints", {})
    if typeof(joints) != TYPE_DICTIONARY:
        return null

    var position := Vector3.ZERO
    var count := 0
    for joint_name in joint_names:
        var sample = joints.get(str(joint_name), {})
        if typeof(sample) != TYPE_DICTIONARY:
            continue
        position += Vector3(
            float(sample.get("x", 0.0)),
            float(sample.get("y", 0.0)),
            float(sample.get("z", 0.0))
        )
        count += 1

    if count == 0:
        return null
    return position / float(count)

func _browser_joint_position(hand: Dictionary, joint_name: String):
    var joints = hand.get("joints", {})
    if typeof(joints) != TYPE_DICTIONARY:
        return null

    var sample = joints.get(joint_name, {})
    if typeof(sample) != TYPE_DICTIONARY:
        return null

    return Vector3(
        float(sample.get("x", 0.0)),
        float(sample.get("y", 0.0)),
        float(sample.get("z", 0.0))
    )

func _browser_pinch_distance(hand_id: int) -> float:
    var hand := _browser_hand_snapshot_for(hand_id)
    if hand.is_empty():
        return -1.0

    var thumb = _browser_joint_position(hand, "thumb-tip")
    var index = _browser_joint_position(hand, "index-finger-tip")
    if thumb == null or index == null:
        return -1.0

    return (thumb as Vector3).distance_to(index as Vector3)

func _on_selectstart(input_source_id: int) -> void:
    var hand_id := _hand_for_input_source(input_source_id)
    if hand_id >= 0:
        _emit_select_started(hand_id, "webxr")
    else:
        _broadcast_select_started("webxr")

func _on_selectend(input_source_id: int) -> void:
    var hand_id := _hand_for_input_source(input_source_id)
    if hand_id >= 0:
        _emit_select_ended(hand_id, "webxr")
    else:
        _broadcast_select_ended("webxr")

func _on_squeezestart(input_source_id: int) -> void:
    var hand_id := _hand_for_input_source(input_source_id)
    if hand_id >= 0:
        _emit_activate_started(hand_id, "webxr")
    else:
        _broadcast_activate_started("webxr")

func _on_squeezeend(input_source_id: int) -> void:
    var hand_id := _hand_for_input_source(input_source_id)
    if hand_id >= 0:
        _emit_activate_ended(hand_id, "webxr")
    else:
        _broadcast_activate_ended("webxr")

func _hand_for_input_source(input_source_id: int) -> int:
    if _webxr == null:
        return -1

    var tracker = _webxr.get_input_source_tracker(input_source_id)
    if tracker == null:
        return -1

    var tracker_hand = tracker.hand
    var tracker_hand_text := str(tracker_hand).to_lower()
    match tracker_hand:
        XRPositionalTracker.TRACKER_HAND_LEFT:
            return Hand.LEFT
        XRPositionalTracker.TRACKER_HAND_RIGHT:
            return Hand.RIGHT
    if tracker_hand_text.find("left") >= 0:
        return Hand.LEFT
    if tracker_hand_text.find("right") >= 0:
        return Hand.RIGHT
    return -1

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

func _stabilized_hand_pose(hand_id: int, raw_pose: Dictionary) -> Dictionary:
    if not stabilize_hand_select:
        _remember_free_hand_pose(hand_id, raw_pose)
        return raw_pose

    if not _select_down.get(hand_id, false):
        _remember_free_hand_pose(hand_id, raw_pose)
        return raw_pose

    var anchor_pose: Dictionary = _select_anchor_pose.get(hand_id, {})
    if anchor_pose.is_empty():
        _begin_select_stabilization(hand_id, raw_pose)
        anchor_pose = _select_anchor_pose.get(hand_id, {})
    if anchor_pose.is_empty():
        return raw_pose

    var start_anchor = _select_anchor_hand_anchor.get(hand_id)
    var current_anchor = _hand_anchor_global(hand_id)
    if start_anchor == null or current_anchor == null:
        return anchor_pose
    return _offset_pose_by_anchor_delta(anchor_pose, start_anchor, current_anchor)

func _remember_free_hand_pose(hand_id: int, pose: Dictionary) -> void:
    _last_free_hand_pose[hand_id] = pose.duplicate()
    _last_free_hand_anchor[hand_id] = _hand_anchor_global(hand_id)

func _begin_select_stabilization(hand_id: int, fallback_pose := {}) -> void:
    if not stabilize_hand_select or not _valid_hand(hand_id):
        return

    var pose: Dictionary = _last_free_hand_pose.get(hand_id, {})
    if pose.is_empty() and not fallback_pose.is_empty():
        pose = fallback_pose
    if pose.is_empty():
        pose = _browser_aim_pose(hand_id)
    if pose.is_empty():
        pose = _hand_aim_pose(hand_id)

    _select_anchor_pose[hand_id] = pose.duplicate() if not pose.is_empty() else {}
    var anchor = _last_free_hand_anchor.get(hand_id)
    _select_anchor_hand_anchor[hand_id] = anchor if anchor != null else _hand_anchor_global(hand_id)

func _end_select_stabilization(hand_id: int) -> void:
    if not _valid_hand(hand_id):
        return
    _select_anchor_pose[hand_id] = {}
    _select_anchor_hand_anchor[hand_id] = null

func _hand_anchor_global(hand_id: int):
    if not _valid_hand(hand_id):
        return null

    var browser_hand := _browser_hand_snapshot_for(hand_id)
    if not browser_hand.is_empty():
        var browser_anchor = _browser_joint_average(browser_hand, BROWSER_PALM_JOINT_NAMES)
        if browser_anchor != null:
            var origin_xf := _origin.global_transform if _origin != null else Transform3D.IDENTITY
            return origin_xf * (browser_anchor as Vector3)

    if _origin == null:
        return null

    var tracker := XRHandTrackerResolver.get_tracker(hand_id)
    if tracker == null:
        return null

    var anchor_joint := XRHandTracker.HAND_JOINT_PALM
    if not XRHandGestureProvider.joint_position_valid(tracker, anchor_joint):
        anchor_joint = XRHandTracker.HAND_JOINT_WRIST
    if not XRHandGestureProvider.joint_position_valid(tracker, anchor_joint):
        return null

    return _origin.global_transform * tracker.get_hand_joint_transform(anchor_joint).origin

func _offset_pose_by_anchor_delta(pose: Dictionary, start_anchor: Vector3, current_anchor: Vector3) -> Dictionary:
    var translated_pose := pose.duplicate()
    translated_pose["origin"] = (pose["origin"] as Vector3) + (current_anchor - start_anchor)
    return translated_pose

func _valid_hand(hand_id: int) -> bool:
    return hand_id == Hand.LEFT or hand_id == Hand.RIGHT

func _update_synthetic_pinch_select(hand_id: int) -> void:
    if not _valid_hand(hand_id):
        return
    if _select_source.get(hand_id, "") == "webxr":
        return

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

    var browser_distance := _browser_pinch_distance(hand_id)
    if browser_distance >= 0.0:
        return browser_distance

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
    _begin_select_stabilization(hand_id)
    _select_down[hand_id] = true
    _select_source[hand_id] = source
    select_started.emit(hand_id)

func _emit_select_ended(hand_id: int, source: String) -> void:
    if not _valid_hand(hand_id) or not _select_down.get(hand_id, false):
        return
    if source == "synthetic" and _select_source.get(hand_id, "") == "webxr":
        return
    _select_down[hand_id] = false
    _select_source[hand_id] = ""
    _end_select_stabilization(hand_id)
    select_ended.emit(hand_id)

func _broadcast_select_started(source: String) -> void:
    _emit_select_started(Hand.LEFT, source)
    _emit_select_started(Hand.RIGHT, source)

func _broadcast_select_ended(source: String) -> void:
    _emit_select_ended(Hand.LEFT, source)
    _emit_select_ended(Hand.RIGHT, source)

func _emit_activate_started(hand_id: int, source: String) -> void:
    if not _valid_hand(hand_id) or _activate_down.get(hand_id, false):
        return
    _activate_down[hand_id] = true
    _activate_source[hand_id] = source
    activate_started.emit(hand_id)

func _emit_activate_ended(hand_id: int, source: String) -> void:
    if not _valid_hand(hand_id) or not _activate_down.get(hand_id, false):
        return
    if source != _activate_source.get(hand_id, ""):
        return
    _activate_down[hand_id] = false
    _activate_source[hand_id] = ""
    activate_ended.emit(hand_id)

func _broadcast_activate_started(source: String) -> void:
    _emit_activate_started(Hand.LEFT, source)
    _emit_activate_started(Hand.RIGHT, source)

func _broadcast_activate_ended(source: String) -> void:
    _emit_activate_ended(Hand.LEFT, source)
    _emit_activate_ended(Hand.RIGHT, source)
