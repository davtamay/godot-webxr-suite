extends Node3D

## Gesture playground: preset + recorded gestures as cards that light up when
## performed; a library PANEL to record new gestures (explicit buttons) and
## browse every saved pose; selecting one shows it on a rotating GHOST HAND.
## Gestures persist on-device as .tres under user://gestures - the modular
## representation: features for recognition + a joint snapshot for display.

const _CARD_IDLE := Color(0.75, 0.8, 0.9, 1.0)
const _CARD_ACTIVE := Color(0.3, 1.0, 0.55, 1.0)

@onready var _recognizer: XRGestureRecognizer = $GestureRecognizer
@onready var _recorder: XRGestureRecorder = $GestureRecorder
@onready var _record_label: Label3D = $RecordLabel
@onready var _ghost: XRGestureGhostHand = $GhostHand

var _cards := {}
var _active_hands := {}
var _custom_count := 0
var _library_box: VBoxContainer


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
	_recognizer.gesture_started.connect(_on_gesture_started)
	_recognizer.gesture_ended.connect(_on_gesture_ended)
	_recorder.recording_state_changed.connect(_on_recording_state)
	_recorder.recording_finished.connect(_on_recording_finished)
	_build_library_panel()
	_record_label.text = "Use the panel: RECORD, hold your pose through the countdown.\nSelect any saved pose to inspect it on the ghost hand."


## ---- library panel -----------------------------------------------------------

func _build_library_panel() -> void:
	var root: Control = $GestureLibraryPanel/Viewport/Root
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "GESTURE LIBRARY"
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)

	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 10)
	column.add_child(record_row)
	for hand in 2:
		var record := Button.new()
		record.text = "RECORD %s" % ("LEFT" if hand == 0 else "RIGHT")
		record.custom_minimum_size = Vector2(220, 64)
		record.pressed.connect(_on_record_pressed.bind(hand))
		record_row.add_child(record)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_library_box = VBoxContainer.new()
	_library_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_library_box)
	_refresh_library()


func _refresh_library() -> void:
	for child in _library_box.get_children():
		child.queue_free()
	for gesture in _recognizer.gestures:
		if gesture == null or gesture.gesture_name.is_empty():
			continue
		var entry := Button.new()
		var has_snapshot: bool = gesture.joint_snapshot.size() > 0
		entry.text = "%s%s" % [gesture.gesture_name.replace("_", " ").to_upper(), "" if has_snapshot else "  (no snapshot)"]
		entry.custom_minimum_size = Vector2(0, 52)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.pressed.connect(_on_library_selected.bind(gesture))
		_library_box.add_child(entry)


func _on_library_selected(gesture: XRHandGesture) -> void:
	if _ghost.show_gesture(gesture):
		_record_label.text = "'%s' on the ghost hand - walk around it, or watch it spin." % gesture.gesture_name
	else:
		_record_label.text = "'%s' has no recorded snapshot (hand-authored preset).\nRe-record it under a new name to get one." % gesture.gesture_name


## ---- recording ---------------------------------------------------------------

func _on_record_pressed(hand: int) -> void:
	if _recorder.is_recording():
		return
	_custom_count += 1
	while _cards.has("custom_%d" % _custom_count):
		_custom_count += 1
	_recorder.start_recording("custom_%d" % _custom_count, hand)


func _on_recording_state(state: String, seconds_left: float) -> void:
	match state:
		"countdown":
			_record_label.text = "RECORDING in %d...\nget your pose ready!" % ceili(seconds_left)
		"capturing":
			_record_label.text = "HOLD IT... %.1f" % seconds_left
		"failed":
			_record_label.text = "Recording failed - the hand was not tracked.\nKeep it in view and try again."
		"done":
			pass  # recording_finished handles the reveal.


func _on_recording_finished(gesture: XRHandGesture, _save_path: String) -> void:
	_add_card(gesture)
	_refresh_library()
	_ghost.show_gesture(gesture)
	_record_label.text = "Saved '%s' - perform it! Its card lights up.\nIt is on the ghost hand now, and saved for next session." % gesture.gesture_name


func _add_card(gesture: XRHandGesture) -> void:
	if _cards.has(gesture.gesture_name):
		return
	var card := ($Cards/fist as Label3D).duplicate() as Label3D
	card.name = gesture.gesture_name
	card.text = gesture.gesture_name.replace("_", " ").to_upper()
	card.modulate = _CARD_IDLE
	card.position = Vector3(-0.8 + 0.8 * ((_cards.size() - 4) % 3), 1.15, -1.9)
	$Cards.add_child(card)
	_cards[gesture.gesture_name] = card


## ---- cards -------------------------------------------------------------------

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
