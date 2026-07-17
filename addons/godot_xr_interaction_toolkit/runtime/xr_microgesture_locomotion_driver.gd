@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg")
class_name XRMicrogestureLocomotionDriver
extends Node

## Thumb-microgesture locomotion driving the SAME teleport arc, marker, and
## snap turn as the thumbsticks - one locomotion system, many inputs.
##
## Powered by the hands addon's sequence recognition (godot_xr_hands
## gesture_studio; soft dependency - inert when that addon is absent):
##   thumb swipe LEFT / RIGHT  = snap turn
##   thumb swipe FORWARD       = aim the teleport arc (hand ray)
##   thumb swipe BACKWARD      = commit
##   thumb TAP                 = aim / commit toggle
## Rest your thumb on the side of your index finger and swipe - the Meta
## microgesture vocabulary, recognized from joints, working in the browser.

## The PROVEN thumb recognizer (phase state machine with posture gating -
## refined on-headset over many sessions) stays the microgesture engine;
## the gesture_studio sequence framework serves authored motion gestures
## and replaces this only when it matches this reliability on-device.
const _RUNTIME_SCRIPT := "res://addons/godot_xr_hands/runtime/recognition/xr_gesture_runtime.gd"
const _RECOGNIZER_SCRIPT := "res://addons/godot_xr_hands/runtime/recognition/xr_thumb_microgesture_recognizer.gd"

@export var enabled := true

## Optional; empty resolves to the scene's XRLocomotion by group.
@export var locomotion_path: NodePath

@export_group("Detection")
## The recognizer is built at runtime; these forward its most-tuned reliability
## knobs so you can adjust feel without reaching an internal node. Contact =
## how close the thumb must come to arm a swipe (lower = easier); release above
## the second value.
@export_range(0.05, 1.5, 0.01) var contact_threshold := 0.40
@export_range(0.05, 2.0, 0.01) var release_threshold := 0.46
## Fingers must be at least this curled (fist gate) to count as a microgesture.
@export_range(0.0, 1.0, 0.01) var minimum_finger_curl := 0.28
## Hand-tracking confidence floor; raise if false swipes fire on poor tracking.
@export_range(0.0, 1.0, 0.01) var minimum_tracking_quality := 0.36
## Seconds between recognized gestures.
@export_range(0.0, 2.0, 0.01) var cooldown := 0.18

const _FORWARDED := ["contact_threshold", "release_threshold", "minimum_finger_curl",
	"minimum_tracking_quality", "cooldown"]

var _locomotion: Node


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ResourceLoader.exists(_RECOGNIZER_SCRIPT) or not ResourceLoader.exists(_RUNTIME_SCRIPT):
		return  # Hands addon not installed; microgesture locomotion stays off.
	var runtime: Node = (load(_RUNTIME_SCRIPT) as GDScript).new()
	runtime.name = "GestureRuntime"
	add_child(runtime)
	var recognizer: Node = (load(_RECOGNIZER_SCRIPT) as GDScript).new()
	recognizer.name = "ThumbRecognizer"
	recognizer.set("hand", -1)
	recognizer.set("gesture_runtime_path", NodePath("../GestureRuntime"))
	for prop in _FORWARDED:
		recognizer.set(prop, get(prop))
	add_child(recognizer)
	if recognizer.has_signal("gesture_performed"):
		recognizer.connect("gesture_performed", _on_gesture)


func _on_gesture(gesture: int, hand: int, _confidence: float) -> void:
	if not enabled or not _resolve_locomotion():
		return
	# Gesture order matches XRMicrogestureSource.Gesture:
	# LEFT, RIGHT, FORWARD, BACKWARD, TAP.
	match gesture:
		0:
			_locomotion.do_snap_turn(1.0)
		1:
			_locomotion.do_snap_turn(-1.0)
		2:
			_locomotion.begin_teleport_aim(hand)
		3:
			_locomotion.commit_teleport(hand)
		4:
			if _locomotion.is_aiming(hand):
				_locomotion.commit_teleport(hand)
			else:
				_locomotion.begin_teleport_aim(hand)


func _resolve_locomotion() -> bool:
	if _locomotion and is_instance_valid(_locomotion):
		return true
	_locomotion = get_node_or_null(locomotion_path)
	if _locomotion == null:
		_locomotion = get_tree().get_first_node_in_group(XRLocomotion.GROUP)
	return _locomotion != null
