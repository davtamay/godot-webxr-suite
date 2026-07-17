extends Node3D

## Gesture playground: the four preset gestures as cards that light up when
## you perform them (either hand), plus the recognizer's live feature HUD -
## the tuning tool. Bare hands only; put the controllers down.

const _CARD_IDLE := Color(0.75, 0.8, 0.9, 1.0)
const _CARD_ACTIVE := Color(0.3, 1.0, 0.55, 1.0)
## Hold THUMBS UP this long to arm the recorder for that hand.
const _RECORD_ARM_SECONDS := 2.0

@onready var _recognizer: XRGestureRecognizer = $GestureRecognizer
@onready var _recorder: XRGestureRecorder = $GestureRecorder
@onready var _record_label: Label3D = $RecordLabel

var _cards := {}
var _active_hands := {}
var _arm_time := [0.0, 0.0]
var _custom_count := 0


func _ready() -> void:
	# Menu back button when running inside the demo app (dependency-free).
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	# Presets loaded here (not stored in the .tscn): script-class typed arrays
	# in hand-written scenes are serialization-fragile.
	for preset in ["point", "fist", "open_palm", "thumbs_up"]:
		var gesture := load("res://addons/godot_xr_interaction_toolkit/runtime/gestures/presets/%s.tres" % preset) as XRHandGesture
		if gesture:
			_recognizer.gestures.append(gesture)
	for card in $Cards.get_children():
		if card is Label3D:
			_cards[card.name] = card
			card.modulate = _CARD_IDLE
	_recognizer.gesture_started.connect(_on_gesture_started)
	_recognizer.gesture_ended.connect(_on_gesture_ended)
	_recorder.recording_state_changed.connect(_on_recording_state)
	_recorder.recording_finished.connect(_on_recording_finished)
	_record_label.text = "Record your own: hold THUMBS UP for 2s,\nthen hold your NEW pose through the countdown"


func _process(delta: float) -> void:
	# Thumbs-up-hold arms the recorder for that hand (no UI needed in-headset).
	if _recorder.is_recording():
		return
	for hand in 2:
		if "thumbs_up" in _recognizer.get_active_gestures(hand):
			_arm_time[hand] += delta
			if _arm_time[hand] >= _RECORD_ARM_SECONDS:
				_arm_time = [0.0, 0.0]
				_custom_count += 1
				_recorder.start_recording("custom_%d" % _custom_count, hand)
				return
		else:
			_arm_time[hand] = 0.0


func _on_recording_state(state: String, seconds_left: float) -> void:
	match state:
		"countdown":
			_record_label.text = "RECORDING in %d...\nget your new pose ready!" % ceili(seconds_left)
		"capturing":
			_record_label.text = "HOLD IT... %.1f" % seconds_left
		"failed":
			_record_label.text = "Recording failed - hand was not tracked.\nHold THUMBS UP 2s to try again"
		"done":
			pass  # recording_finished handles the reveal.


func _on_recording_finished(gesture: XRHandGesture, _save_path: String) -> void:
	if _cards.has(gesture.gesture_name):
		return
	# The new gesture joins the card row, immediately performable.
	var card := ($Cards/fist as Label3D).duplicate() as Label3D
	card.name = gesture.gesture_name
	card.text = gesture.gesture_name.replace("_", " ").to_upper()
	card.modulate = _CARD_IDLE
	card.position = Vector3(-0.4 + 0.8 * ((_cards.size() - 4) % 3), 1.15, -1.9)
	$Cards.add_child(card)
	_cards[gesture.gesture_name] = card
	_record_label.text = "Saved '%s' - perform it! Its card lights up.\nHold THUMBS UP 2s to record another" % gesture.gesture_name


func _on_gesture_started(gesture_name: String, hand: int) -> void:
	var card: Label3D = _cards.get(gesture_name)
	if card == null:
		return
	_active_hands[gesture_name] = _active_hands.get(gesture_name, {})
	_active_hands[gesture_name][hand] = true
	card.modulate = _CARD_ACTIVE
	card.text = "%s\n< %s >" % [gesture_name.replace("_", " ").to_upper(), "LEFT" if hand == 0 else "RIGHT"]


func _on_gesture_ended(gesture_name: String, hand: int) -> void:
	var card: Label3D = _cards.get(gesture_name)
	if card == null:
		return
	var hands: Dictionary = _active_hands.get(gesture_name, {})
	hands.erase(hand)
	if hands.is_empty():
		card.modulate = _CARD_IDLE
		card.text = gesture_name.replace("_", " ").to_upper()
