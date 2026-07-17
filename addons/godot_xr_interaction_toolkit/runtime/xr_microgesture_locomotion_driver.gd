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

const _RECOGNIZER_SCRIPT := "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_recognizer.gd"
const _PRESET_DIR := "res://addons/godot_xr_hands/runtime/gesture_studio/presets"
const _SEQUENCES := ["thumb_swipe_left", "thumb_swipe_right", "thumb_swipe_forward", "thumb_swipe_backward", "thumb_tap"]

@export var enabled := true

## Optional; empty resolves to the scene's XRLocomotion by group.
@export var locomotion_path: NodePath

var _locomotion: Node


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ResourceLoader.exists(_RECOGNIZER_SCRIPT):
		return  # Hands addon not installed; microgesture locomotion stays off.
	var recognizer: Node = (load(_RECOGNIZER_SCRIPT) as GDScript).new()
	recognizer.name = "MicrogestureRecognizer"
	for sequence_name in _SEQUENCES:
		var sequence := load("%s/%s.tres" % [_PRESET_DIR, sequence_name])
		if sequence:
			(recognizer.get("sequences") as Array).append(sequence)
	add_child(recognizer)
	if recognizer.has_signal("sequence_performed"):
		recognizer.connect("sequence_performed", _on_sequence)


func _on_sequence(sequence_name: String, hand: int) -> void:
	if not enabled or not _resolve_locomotion():
		return
	match sequence_name:
		"thumb_swipe_left":
			_locomotion.do_snap_turn(1.0)
		"thumb_swipe_right":
			_locomotion.do_snap_turn(-1.0)
		"thumb_swipe_forward":
			_locomotion.begin_teleport_aim(hand)
		"thumb_swipe_backward":
			_locomotion.commit_teleport(hand)
		"thumb_tap":
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
