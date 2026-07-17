extends Node3D

## Gesture Studio: record poses with explicit buttons, browse every saved
## gesture on the center panel, and validate against a REFERENCE - selecting
## a gesture shows it on the ghost hand (right) and points the wrist bars at
## it; performing it turns the ghost green. While recording, the ghost
## mirrors your live hand so you see exactly what is being captured.
## Gestures persist on-device as .tres under user://gestures.

@onready var _recognizer: XRGestureRecognizer = $GestureRecognizer
@onready var _recorder: XRGestureRecorder = $GestureRecorder
@onready var _status_label: Label3D = $StatusLabel
@onready var _ghost: XRGestureGhostHand = $GhostHand
@onready var _ghost_label: Label3D = $GhostHand/GhostLabel

var _selected: XRHandGesture
var _custom_count := 0
var _library_box: VBoxContainer
var _authoring_box: VBoxContainer
var _strictness: HSlider
var _strictness_value: Label


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
	_status_label.text = "RECORD a pose, or select one below to practice it:\nthe ghost hand shows the target, your wrist bars show what blocks it."


## ---- library panel -----------------------------------------------------------

func _build_library_panel() -> void:
	var root: Control = $GestureLibraryPanel/Viewport/Root
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 20)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 12)
	column.add_child(record_row)
	var title := Label.new()
	title.text = "GESTURES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	record_row.add_child(title)
	for hand in 2:
		var record := Button.new()
		record.text = "REC %s" % ("LEFT" if hand == 0 else "RIGHT")
		record.custom_minimum_size = Vector2(200, 72)
		record.add_theme_font_size_override("font_size", 28)
		record.pressed.connect(_on_record_pressed.bind(hand))
		record_row.add_child(record)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_library_box = VBoxContainer.new()
	_library_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_library_box)

	# Authoring section for the SELECTED gesture: display hands, strictness,
	# re-record, delete. Everything saves back to the gesture's .tres.
	_authoring_box = VBoxContainer.new()
	_authoring_box.add_theme_constant_override("separation", 8)
	_authoring_box.visible = false
	column.add_child(_authoring_box)

	var strict_row := HBoxContainer.new()
	strict_row.add_theme_constant_override("separation", 10)
	_authoring_box.add_child(strict_row)
	var strict_title := Label.new()
	strict_title.text = "STRICT"
	strict_title.add_theme_font_size_override("font_size", 26)
	strict_row.add_child(strict_title)
	_strictness = HSlider.new()
	_strictness.min_value = 0.4
	_strictness.max_value = 2.5
	_strictness.step = 0.05
	_strictness.value = 1.0
	_strictness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strictness.custom_minimum_size = Vector2(0, 56)
	_strictness.value_changed.connect(_on_strictness_changed)
	strict_row.add_child(_strictness)
	_strictness_value = Label.new()
	_strictness_value.text = "1.00"
	_strictness_value.add_theme_font_size_override("font_size", 26)
	strict_row.add_child(_strictness_value)
	var strict_hint := Label.new()
	strict_hint.text = "left = stricter match, right = more forgiving (saves live)"
	strict_hint.add_theme_font_size_override("font_size", 18)
	strict_hint.modulate = Color(1, 1, 1, 0.6)
	_authoring_box.add_child(strict_hint)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 10)
	_authoring_box.add_child(actions_row)
	var rerecord := Button.new()
	rerecord.text = "RE-RECORD"
	rerecord.custom_minimum_size = Vector2(220, 56)
	rerecord.add_theme_font_size_override("font_size", 24)
	rerecord.pressed.connect(_on_rerecord_pressed)
	actions_row.add_child(rerecord)
	var delete := Button.new()
	delete.text = "DELETE"
	delete.custom_minimum_size = Vector2(180, 56)
	delete.add_theme_font_size_override("font_size", 24)
	delete.pressed.connect(_on_delete_pressed)
	actions_row.add_child(delete)

	_refresh_library()


func _refresh_library() -> void:
	for child in _library_box.get_children():
		child.queue_free()
	for gesture in _recognizer.gestures:
		if gesture == null or gesture.gesture_name.is_empty():
			continue
		var entry := Button.new()
		var has_snapshot: bool = gesture.joint_snapshot.size() > 0
		entry.text = "  %s%s" % [gesture.gesture_name.replace("_", " ").to_upper(), "" if has_snapshot else "   (recognition only)"]
		entry.custom_minimum_size = Vector2(0, 64)
		entry.add_theme_font_size_override("font_size", 30)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.toggle_mode = true
		entry.button_pressed = _selected != null and _selected.gesture_name == gesture.gesture_name
		entry.pressed.connect(_on_library_selected.bind(gesture))
		_library_box.add_child(entry)


func _on_library_selected(gesture: XRHandGesture) -> void:
	_selected = gesture
	_recognizer.focus_gesture_name = gesture.gesture_name
	_refresh_library()
	_authoring_box.visible = true
	_strictness.set_value_no_signal(gesture.tolerance_scale)
	_strictness_value.text = "%.2f" % gesture.tolerance_scale
	_ghost.show_gesture(gesture)
	_ghost.set_highlight(false)
	var approx := gesture.joint_snapshot.size() == 0
	_ghost_label.text = "TARGET: %s%s\nmatch it with your hands" % [gesture.gesture_name.replace("_", " ").to_upper(), "  (approx.)" if approx else ""]
	_status_label.text = "Practice '%s': red wrist bars show which finger blocks it." % gesture.gesture_name


func _on_strictness_changed(value: float) -> void:
	if _selected == null:
		return
	_selected.tolerance_scale = value
	_strictness_value.text = "%.2f" % value
	_save_selected()


func _on_rerecord_pressed() -> void:
	if _selected == null or _recorder.is_recording():
		return
	var hand := _selected.recorded_hand if _selected.recorded_hand >= 0 else 1
	_ghost.start_live(hand)
	_recorder.start_recording(_selected.gesture_name, hand)


func _on_delete_pressed() -> void:
	if _selected == null:
		return
	var path := "user://gestures/%s.tres" % _selected.gesture_name
	if not FileAccess.file_exists(path):
		_status_label.text = "'%s' is a built-in preset - it cannot be deleted." % _selected.gesture_name
		return
	DirAccess.remove_absolute(path)
	_recognizer.gestures.erase(_selected)
	_recognizer.focus_gesture_name = ""
	_selected = null
	_authoring_box.visible = false
	_ghost.show_gesture(null)
	_ghost_label.text = "GHOST HAND\nselect a pose on the panel"
	_refresh_library()
	_status_label.text = "Deleted. Select or record another pose."


func _save_selected() -> void:
	# Custom gestures persist edits immediately; presets tune in-memory only
	# (their .tres ships read-only inside the app).
	if _selected and FileAccess.file_exists("user://gestures/%s.tres" % _selected.gesture_name):
		ResourceSaver.save(_selected, "user://gestures/%s.tres" % _selected.gesture_name)


## ---- recording ---------------------------------------------------------------

func _on_record_pressed(hand: int) -> void:
	if _recorder.is_recording():
		return
	_custom_count += 1
	while _has_gesture("custom_%d" % _custom_count):
		_custom_count += 1
	_ghost.start_live(hand)
	_ghost_label.text = "LIVE: your %s hand" % ("LEFT" if hand == 0 else "RIGHT")
	_recorder.start_recording("custom_%d" % _custom_count, hand)


func _on_recording_state(state: String, seconds_left: float) -> void:
	match state:
		"countdown":
			_status_label.text = "RECORDING in %d...\nget your pose ready - the ghost hand mirrors you!" % ceili(seconds_left)
		"capturing":
			_status_label.text = "HOLD IT... %.1f" % seconds_left
		"failed":
			_ghost.stop_live()
			_status_label.text = "Recording failed - the hand was not tracked.\nKeep it in view and try again."


func _on_recording_finished(gesture: XRHandGesture, _save_path: String) -> void:
	_ghost.stop_live()
	_refresh_library()
	_on_library_selected(gesture)
	_status_label.text = "Saved '%s' - now perform it: the ghost turns green on a match.\nIt stays saved for your next session." % gesture.gesture_name


## ---- reference validation ------------------------------------------------------

func _on_gesture_started(gesture_name: String, hand: int) -> void:
	if _selected and gesture_name == _selected.gesture_name:
		_ghost.set_highlight(true)
		_ghost_label.text = "MATCHED: %s (%s hand)" % [gesture_name.replace("_", " ").to_upper(), "left" if hand == 0 else "right"]


func _on_gesture_ended(gesture_name: String, _hand: int) -> void:
	if _selected and gesture_name == _selected.gesture_name:
		_ghost.set_highlight(false)
		_ghost_label.text = "TARGET: %s\nmatch it with your hand" % gesture_name.replace("_", " ").to_upper()


func _has_gesture(gesture_name: String) -> bool:
	for gesture in _recognizer.gestures:
		if gesture and gesture.gesture_name == gesture_name:
			return true
	return false
