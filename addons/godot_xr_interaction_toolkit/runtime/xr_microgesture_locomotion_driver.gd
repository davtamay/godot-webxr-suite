@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg")
class_name XRMicrogestureLocomotionDriver
extends Node

## Thumb-microgesture locomotion driving the SAME teleport arc, marker, and
## snap turn as the thumbsticks - one locomotion system, many inputs.
##
## Uses godot_xr_hands' thumb microgesture recognition when that addon is
## installed (inert otherwise), with its canonical mapping:
##   swipe LEFT / RIGHT  = snap turn
##   swipe FORWARD       = aim the teleport arc (hand ray)
##   swipe BACKWARD      = commit
##   thumb TAP           = aim / commit toggle
##
## Drop anywhere (built into WebXRRig): it finds the XRLocomotion by group.

const _RUNTIME_SCRIPT := "res://addons/godot_xr_hands/runtime/recognition/xr_gesture_runtime.gd"
const _RECOGNIZER_SCRIPT := "res://addons/godot_xr_hands/runtime/recognition/xr_thumb_microgesture_recognizer.gd"

@export var enabled := true

## Optional; empty resolves to the scene's XRLocomotion by group.
@export var locomotion_path: NodePath

var _locomotion: Node


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not ResourceLoader.exists(_RECOGNIZER_SCRIPT) or not ResourceLoader.exists(_RUNTIME_SCRIPT):
		return  # godot_xr_hands not installed; microgesture locomotion stays off.
	var runtime: Node = (load(_RUNTIME_SCRIPT) as GDScript).new()
	runtime.name = "GestureRuntime"
	add_child(runtime)
	var recognizer: Node = (load(_RECOGNIZER_SCRIPT) as GDScript).new()
	recognizer.name = "ThumbRecognizer"
	recognizer.set("hand", -1)
	recognizer.set("gesture_runtime_path", NodePath("../GestureRuntime"))
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
