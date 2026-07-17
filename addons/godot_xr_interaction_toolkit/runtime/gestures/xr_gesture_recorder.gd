@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_gesture_recognizer.svg")
class_name XRGestureRecorder
extends Node

## Record-first gesture authoring: hold a pose, get a gesture. The recorder
## counts down, samples the hand's feature stream for a capture window, and
## derives an XRHandGesture whose targets are the observed means and whose
## tolerances come from YOUR OWN jitter - steadier hands make tighter
## gestures automatically. Recordings save as .tres under user://gestures and
## reload on the next run.
##
## Needs an XRGestureRecognizer in the scene (it supplies the live features -
## one extraction pass shared by recognition, debug HUD, and recording).

## state: "countdown" | "capturing" | "done" | "failed"; seconds_left counts
## the current stage down for UI display.
signal recording_state_changed(state: String, seconds_left: float)
## The derived gesture (already saved to save_path; "" if saving failed).
signal recording_finished(gesture: XRHandGesture, save_path: String)

## The recognizer supplying live features (found by class in the scene when
## left empty).
@export var recognizer_path: NodePath

@export_range(1.0, 10.0, 0.5) var countdown_seconds := 3.0
@export_range(0.5, 5.0, 0.5) var capture_seconds := 2.0

## Append the recorded gesture to the recognizer's library immediately - it
## is performable the moment recording ends.
@export var auto_add_to_recognizer := true

## Where recordings persist ("" = don't save).
@export var save_directory := "user://gestures"

## Reload previously saved recordings into the recognizer at startup.
@export var load_saved_on_ready := true

## Tolerances never go below this (raw jitter on a steady hand is optimistic).
@export_range(0.05, 0.4, 0.01) var min_tolerance := 0.12

## Pinch features join the gesture only when strongly expressed (mean above
## this) - a relaxed hand's incidental pinch values would over-constrain.
@export_range(0.0, 1.0, 0.05) var include_pinch_threshold := 0.7

var _recognizer: XRGestureRecognizer
var _state := ""
var _gesture_name := ""
var _hand := 0
var _time_left := 0.0
var _samples := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	set_process(false)
	if load_saved_on_ready:
		_load_saved.call_deferred()


func is_recording() -> bool:
	return _state == "countdown" or _state == "capturing"


## Begin the countdown-then-capture flow for one hand (0 = left, 1 = right).
func start_recording(gesture_name: String, hand: int) -> void:
	if is_recording() or not _resolve_recognizer():
		return
	_gesture_name = gesture_name
	_hand = clampi(hand, 0, 1)
	_samples = {}
	_state = "countdown"
	_time_left = countdown_seconds
	set_process(true)
	recording_state_changed.emit(_state, _time_left)


func _process(delta: float) -> void:
	if not is_recording():
		set_process(false)
		return
	_time_left -= delta
	if _state == "capturing":
		var features: Dictionary = _recognizer.get_features(_hand)
		for feature in features:
			if not _samples.has(feature):
				_samples[feature] = PackedFloat32Array()
			(_samples[feature] as PackedFloat32Array).append(features[feature])
	if _time_left > 0.0:
		recording_state_changed.emit(_state, _time_left)
		return
	if _state == "countdown":
		_state = "capturing"
		_time_left = capture_seconds
		recording_state_changed.emit(_state, _time_left)
		return
	_finish()


func _finish() -> void:
	set_process(false)
	var sample_count: int = _samples.get("curl_index", PackedFloat32Array()).size()
	if sample_count < 10:
		_state = "failed"
		recording_state_changed.emit(_state, 0.0)
		return

	var gesture := XRHandGesture.new()
	gesture.gesture_name = _gesture_name
	var conditions: Dictionary[String, Vector2] = {}
	for feature in _samples:
		var values: PackedFloat32Array = _samples[feature]
		var mean := 0.0
		var low := values[0]
		var high := values[0]
		for value in values:
			mean += value
			low = minf(low, value)
			high = maxf(high, value)
		mean /= values.size()
		# Curls define the pose; pinches join only when strongly expressed;
		# palm orientation is deliberately left out (poses should work at any
		# angle unless authored otherwise in the inspector).
		var include: bool = feature.begins_with("curl_")
		if feature.begins_with("pinch_") and mean >= include_pinch_threshold:
			include = true
		if not include:
			continue
		var tolerance := maxf(min_tolerance, (high - low) * 0.5 + 0.08)
		conditions[feature] = Vector2(snappedf(mean, 0.01), snappedf(tolerance, 0.01))
	gesture.conditions = conditions

	var save_path := ""
	if not save_directory.is_empty():
		DirAccess.make_dir_recursive_absolute(save_directory)
		save_path = "%s/%s.tres" % [save_directory, _gesture_name]
		if ResourceSaver.save(gesture, save_path) != OK:
			save_path = ""
	if auto_add_to_recognizer:
		_recognizer.gestures.append(gesture)

	_state = "done"
	recording_state_changed.emit(_state, 0.0)
	recording_finished.emit(gesture, save_path)


func _load_saved() -> void:
	if save_directory.is_empty() or not _resolve_recognizer():
		return
	var dir := DirAccess.open(save_directory)
	if dir == null:
		return
	var known := {}
	for existing in _recognizer.gestures:
		if existing:
			known[existing.gesture_name] = true
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var gesture := ResourceLoader.load("%s/%s" % [save_directory, file]) as XRHandGesture
		if gesture and not known.has(gesture.gesture_name):
			_recognizer.gestures.append(gesture)
			recording_finished.emit(gesture, "%s/%s" % [save_directory, file])


func _resolve_recognizer() -> bool:
	if _recognizer and is_instance_valid(_recognizer):
		return true
	_recognizer = get_node_or_null(recognizer_path) as XRGestureRecognizer
	if _recognizer == null:
		for node in get_tree().current_scene.find_children("*", "Node", true, false):
			if node is XRGestureRecognizer:
				_recognizer = node
				break
	return _recognizer != null
