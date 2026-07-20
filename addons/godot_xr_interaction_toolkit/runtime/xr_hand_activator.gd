@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRHandActivator
extends Node
## Fires a held object's ACTIVATE with a bare-hand gesture, so hands do what a
## controller trigger does. Drop it inside a grab interactable: while the object
## is held bare-handed, curling the chosen TRIGGER FINGER (index by default)
## fires the object's activate - a blaster shoots, a spray can sprays. The effect
## stays separate (XRBlaster and friends listen for `activated`), so this one
## bridge powers any activatable hand tool.
##
## Authorable two ways: the simple default measures a single finger's curl (set
## `trigger_finger` + the thresholds - a gun uses the index, a spray can the
## thumb); or point `activate_gesture` at any XRHandGesture (a Gesture Studio
## recording or a preset) to fire on a whole authored pose instead.
##
## Emits `trigger_progress(hand, amount)` every frame the object is held so the
## tool can respond live (a trigger that visibly depresses as your finger curls),
## which is how the gesture teaches itself to the user.
##
## Controllers already fire activate from their trigger button, so this stays
## quiet unless a HAND is the one holding the object.

enum Finger { THUMB, INDEX, MIDDLE, RING, PINKY }

## Which finger's curl pulls the trigger. Ignored when activate_gesture is set.
@export var trigger_finger: Finger = Finger.INDEX
## Curl (0 = straight, 1 = fully curled) at which the trigger fires.
@export_range(0.05, 1.0, 0.01) var curl_to_fire := 0.55
## Curl the finger must fall back below before it can fire again (hysteresis, so
## one deliberate pull = one shot). Keep it below curl_to_fire.
@export_range(0.0, 1.0, 0.01) var curl_to_rearm := 0.3
## Optional: fire on a whole authored pose (a Gesture Studio recording or preset)
## instead of a single finger curl. When set, the finger settings are ignored.
@export var activate_gesture: XRHandGesture:
	set(value):
		activate_gesture = value
		_rebuild_recognizer()
## Only fire while the object is actually held by a hand (the normal case).
@export var require_held := true

## Emitted the frame the gesture fires. hand is XRPositionalTracker.TRACKER_HAND_*.
signal activated_by_gesture(hand: int)
## Emitted every frame a hand holds the object: amount is the trigger finger's
## curl 0..1 (or 1.0 when an authored gesture is matched). Drive live feedback.
signal trigger_progress(hand: int, amount: float)

const _RECOGNIZER_PATH := "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_recognizer.gd"

# base / knuckle / tip joints per finger - curl is the bend between the two bones.
const _FINGER_JOINTS := {
	Finger.THUMB: [
		XRHandTracker.HAND_JOINT_THUMB_METACARPAL,
		XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_THUMB_TIP,
	],
	Finger.INDEX: [
		XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP,
	],
	Finger.MIDDLE: [
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP,
	],
	Finger.RING: [
		XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_RING_FINGER_TIP,
	],
	Finger.PINKY: [
		XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL,
		XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP,
	],
}

var _interactable: XRBaseInteractable
var _recognizer: Node
# Per-hand armed state so one pull fires once (mirrors the pinch re-arm).
var _armed := {}


func _ready() -> void:
	_interactable = _find_interactable()
	if Engine.is_editor_hint():
		return
	_rebuild_recognizer()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# The recognizer path drives itself off its own signals; the finger path
	# polls the holding hand here.
	if activate_gesture != null:
		return
	_poll_finger(XRPositionalTracker.TRACKER_HAND_LEFT)
	_poll_finger(XRPositionalTracker.TRACKER_HAND_RIGHT)


func _find_interactable() -> XRBaseInteractable:
	var node := get_parent()
	while node != null:
		if node is XRBaseInteractable:
			return node
		node = node.get_parent()
	return null


func _poll_finger(hand: int) -> void:
	var interactor := _held_by(hand)
	if require_held and interactor == null:
		return
	var curl := _finger_curl(hand)
	if curl < 0.0:
		return  # no valid tracking this frame
	trigger_progress.emit(hand, curl)
	if not _armed.get(hand, true):
		if curl <= curl_to_rearm:
			_armed[hand] = true
		return
	if curl >= curl_to_fire:
		_armed[hand] = false
		_fire(hand, interactor)


## Curl of the trigger finger, 0 (straight) .. 1 (fully curled), or -1 if the
## hand isn't tracked this frame. Measured as the bend between the base bone
## (metacarpal -> knuckle) and the finger (knuckle -> tip) - pose-stable and
## independent of the hand's world orientation.
func _finger_curl(hand: int) -> float:
	var tracker := XRHandTrackerResolver.get_tracker(hand)
	if tracker == null:
		return -1.0
	var joints: Array = _FINGER_JOINTS[trigger_finger]
	for j in joints:
		if not XRHandGestureProvider.joint_position_valid(tracker, j):
			return -1.0
	var base_p: Vector3 = tracker.get_hand_joint_transform(joints[0]).origin
	var knuckle_p: Vector3 = tracker.get_hand_joint_transform(joints[1]).origin
	var tip_p: Vector3 = tracker.get_hand_joint_transform(joints[2]).origin
	var bone := knuckle_p - base_p
	var finger := tip_p - knuckle_p
	if bone.length_squared() < 0.000001 or finger.length_squared() < 0.000001:
		return -1.0
	# Angle between the two bones: straight ~0.2 rad, fully curled ~2.4 rad.
	var angle := bone.normalized().angle_to(finger.normalized())
	return clampf((angle - 0.2) / 2.0, 0.0, 1.0)


func _held_by(hand: int) -> Node:
	if _interactable == null:
		return null
	for interactor in _interactable.get_selecting_interactors():
		if interactor != null and interactor.get("hand") == hand:
			return interactor
	return null


func _fire(hand: int, interactor) -> void:
	activated_by_gesture.emit(hand)
	if _interactable != null:
		# Momentary fire - emit the activate signal the tool listens for without
		# leaving the interactable latched in an activated state.
		_interactable.activated.emit(interactor)


func _rebuild_recognizer() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	if _recognizer != null and is_instance_valid(_recognizer):
		_recognizer.queue_free()
		_recognizer = null
	if activate_gesture == null:
		return
	var script := load(_RECOGNIZER_PATH)
	if script == null:
		push_warning("XRHandActivator: gesture recognizer script not found; falling back to finger curl.")
		return
	_recognizer = script.new()
	_recognizer.name = "ActivatorRecognizer"
	_recognizer.gestures = [activate_gesture]
	_recognizer.focus_gesture_name = activate_gesture.gesture_name
	add_child(_recognizer)
	_recognizer.gesture_started.connect(_on_gesture_started)


func _on_gesture_started(gesture_name: String, hand: int) -> void:
	if activate_gesture == null or gesture_name != activate_gesture.gesture_name:
		return
	var interactor := _held_by(hand)
	if require_held and interactor == null:
		return
	trigger_progress.emit(hand, 1.0)
	_fire(hand, interactor)


func _get_configuration_warnings() -> PackedStringArray:
	if _find_interactable() == null:
		return PackedStringArray([
			"Place XRHandActivator inside a grab interactable (XRGrabInteractable) - "
			+ "it fires that object's activate from a bare-hand gesture."])
	return PackedStringArray()
