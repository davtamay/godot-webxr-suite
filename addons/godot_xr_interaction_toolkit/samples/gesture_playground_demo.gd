extends Node3D

## Gesture playground: the four preset gestures as cards that light up when
## you perform them (either hand), plus the recognizer's live feature HUD -
## the tuning tool. Bare hands only; put the controllers down.

const _CARD_IDLE := Color(0.75, 0.8, 0.9, 1.0)
const _CARD_ACTIVE := Color(0.3, 1.0, 0.55, 1.0)

@onready var _recognizer: XRGestureRecognizer = $GestureRecognizer

var _cards := {}
var _active_hands := {}


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
