@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRGestureRecognizer
extends Node

const XRHandFeatureExtractor := preload("res://addons/godot_xr_interaction_toolkit/runtime/gestures/xr_hand_feature_extractor.gd")

## Drop-in hand gesture recognition: assign XRHandGesture resources (or use
## the presets in runtime/gestures/presets/) and connect to the signals. Both
## hands are tracked independently; the same gesture resource matches either
## hand (features are chirality-corrected in the extractor).
##
## Reliability built in: entry tolerance + hysteresis on release (per
## gesture), hold-time debounce, and tracking-loss ends active gestures
## cleanly. show_debug displays every feature value live - the fastest way to
## tune a gesture's numbers on-headset.

## A gesture began / ended on a hand (0 = left, 1 = right).
signal gesture_started(gesture_name: String, hand: int)
signal gesture_ended(gesture_name: String, hand: int)

@export var enabled := true

## The gesture library this recognizer matches.
@export var gestures: Array[XRHandGesture] = []

## Camera (head) used for the palm_toward_head feature; found automatically
## when left empty.
@export var camera_path: NodePath

## Live per-feature readout on a head-anchored label - the tuning tool.
@export var show_debug := false

var _camera: Camera3D
var _origin: Node3D
var _active := [{}, {}]
var _hold := [{}, {}]
var _features := [{}, {}]
var _debug_label: Label3D
var _debug_accum := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return


func _process(delta: float) -> void:
	if not enabled:
		return
	_resolve_scene_refs()
	for hand in 2:
		var tracker := XRServer.get_tracker("/user/hand_tracker/%s" % ("left" if hand == 0 else "right")) as XRHandTracker
		var origin_xf := _origin.global_transform if _origin else Transform3D.IDENTITY
		var head: Variant = _camera.global_transform if _camera else null
		_features[hand] = XRHandFeatureExtractor.extract(tracker, hand, origin_xf, head)
		_update_hand(hand, delta)
	if show_debug:
		_update_debug(delta)
	elif _debug_label:
		_debug_label.visible = false


## The live feature dictionary for a hand ({} while untracked) - the recorder
## and debug tooling read this.
func get_features(hand: int) -> Dictionary:
	return _features[hand] if hand >= 0 and hand < 2 else {}


## Names of the gestures currently active on a hand.
func get_active_gestures(hand: int) -> Array:
	return _active[hand].keys() if hand >= 0 and hand < 2 else []


func _update_hand(hand: int, delta: float) -> void:
	var features: Dictionary = _features[hand]
	for gesture in gestures:
		if gesture == null or gesture.gesture_name.is_empty():
			continue
		var name := gesture.gesture_name
		var is_active: bool = _active[hand].has(name)
		if gesture.matches(features, is_active):
			if is_active:
				continue
			var held: float = _hold[hand].get(name, 0.0) + delta
			_hold[hand][name] = held
			if held >= gesture.min_hold_seconds:
				_active[hand][name] = true
				gesture_started.emit(name, hand)
		else:
			_hold[hand].erase(name)
			if is_active:
				_active[hand].erase(name)
				gesture_ended.emit(name, hand)


func _resolve_scene_refs() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_node_or_null(camera_path) as Camera3D
		if _camera == null:
			_camera = get_viewport().get_camera_3d()
	if _origin == null or not is_instance_valid(_origin):
		var cursor: Node = _camera
		while cursor != null and not (cursor is XROrigin3D):
			cursor = cursor.get_parent()
		_origin = cursor


## ---- debug HUD ----------------------------------------------------------------

func _update_debug(delta: float) -> void:
	if _camera == null:
		return
	if _debug_label == null:
		_debug_label = Label3D.new()
		_debug_label.top_level = true
		_debug_label.pixel_size = 0.0006
		_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_label.no_depth_test = true
		_debug_label.render_priority = 100
		_debug_label.font_size = 22
		_debug_label.outline_size = 6
		add_child(_debug_label)
	_debug_label.visible = true
	_debug_label.global_position = _camera.global_transform * Vector3(0.0, -0.12, -0.6)
	_debug_accum += delta
	if _debug_accum < 0.15:
		return
	_debug_accum = 0.0
	var lines := PackedStringArray()
	for hand in 2:
		var features: Dictionary = _features[hand]
		var side := "L" if hand == 0 else "R"
		if features.is_empty():
			lines.append("%s: no hand" % side)
			continue
		lines.append("%s active: %s" % [side, ", ".join(PackedStringArray(get_active_gestures(hand)))])
		var curls := PackedStringArray()
		for finger in ["thumb", "index", "middle", "ring", "pinky"]:
			curls.append("%s %.2f" % [finger.substr(0, 2), features.get("curl_%s" % finger, -1.0)])
		lines.append("%s curl: %s" % [side, " ".join(curls)])
		lines.append("%s pinch i %.2f | palm_up %.2f head %.2f" % [
			side, features.get("pinch_index", -1.0), features.get("palm_up", 0.0), features.get("palm_toward_head", 0.0)])
	_debug_label.text = "\n".join(lines)
