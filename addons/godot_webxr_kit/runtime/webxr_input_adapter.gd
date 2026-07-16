@icon("res://addons/godot_webxr_kit/icons/webxr_input_adapter.svg")
class_name WebXRInputAdapter
extends "res://addons/godot_xr_interaction_toolkit/runtime/input/xr_controller_hand_adapter.gd"

## WebXR select source. Resolves the browser interface's selectstart / selectend /
## squeezestart / squeezeend to handedness and feeds them into the shared
## controller + hand adapter base. Poses, hand ray, bare-hand pinch, and
## stabilization all live in the base (XRControllerHandAdapter) - this file only
## adds where select/activate come from on WebXR. Inert outside web exports.

var _webxr


func _ready() -> void:
	_resolve_rig()
	if not OS.has_feature("web"):
		# The OpenXR adapter owns the native path. Also stop the base's
		# _process, or BOTH adapters run the synthetic pinch detector in
		# parallel (duplicate events/compute).
		set_process(false)
		return

	_webxr = XRServer.find_interface("WebXR")
	if _webxr == null:
		return

	_connect_interface_signal(&"selectstart", _on_selectstart)
	_connect_interface_signal(&"selectend", _on_selectend)
	_connect_interface_signal(&"squeezestart", _on_squeezestart)
	_connect_interface_signal(&"squeezeend", _on_squeezeend)


func _connect_interface_signal(signal_name: StringName, callback: Callable) -> void:
	if not _webxr.has_signal(signal_name):
		push_warning("WebXR signal unavailable in this Godot build: %s" % signal_name)
		return
	if not _webxr.is_connected(signal_name, callback):
		_webxr.connect(signal_name, callback)


func _on_selectstart(input_source_id: int) -> void:
	var hand_id := _hand_for_input_source(input_source_id)
	if hand_id >= 0:
		_emit_select_started(hand_id, HARDWARE_SELECT)
	else:
		_broadcast_select_started(HARDWARE_SELECT)


func _on_selectend(input_source_id: int) -> void:
	var hand_id := _hand_for_input_source(input_source_id)
	if hand_id >= 0:
		_emit_select_ended(hand_id, HARDWARE_SELECT)
	else:
		_broadcast_select_ended(HARDWARE_SELECT)


func _on_squeezestart(input_source_id: int) -> void:
	var hand_id := _hand_for_input_source(input_source_id)
	if hand_id >= 0:
		_emit_activate_started(hand_id, HARDWARE_SELECT)
	else:
		_broadcast_activate_started(HARDWARE_SELECT)


func _on_squeezeend(input_source_id: int) -> void:
	var hand_id := _hand_for_input_source(input_source_id)
	if hand_id >= 0:
		_emit_activate_ended(hand_id, HARDWARE_SELECT)
	else:
		_broadcast_activate_ended(HARDWARE_SELECT)


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
