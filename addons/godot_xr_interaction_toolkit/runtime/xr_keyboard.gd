@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_ui_canvas_interactable.svg")
class_name XRKeyboard
extends XRUICanvasInteractable

## Drop-in XR keyboard block: an in-world panel of ray/pinch-pressable keys
## (rides the toolkit's existing panel input - no new input tech). Call
## open() with an optional prompt and initial text; listen for
## text_submitted / cancelled. Hidden until opened.
##
## Lean by design: lowercase letters, digits, space, underscore, backspace.
## Enough for names, ids, and short labels - the common XR text needs.

signal text_submitted(text: String)
signal cancelled

const _ROWS := ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]

var _text := ""
var _prompt_label: Label
var _text_label: Label


func _ready() -> void:
	if Engine.is_editor_hint():
		# Editor preview: build the key layout so authors place the keyboard
		# seeing the real thing (it used to be a blank quad until runtime).
		_build_keys()
		return
	super()
	_build_keys()
	_set_active(false)


## Show the keyboard. Submitting emits text_submitted(text); CANCEL emits
## cancelled. The keyboard hides itself on both.
func open(initial_text := "", prompt_text := "") -> void:
	_text = initial_text
	if _prompt_label:
		_prompt_label.text = prompt_text if not prompt_text.is_empty() else "Enter text"
	_refresh_text()
	_set_active(true)


func close() -> void:
	_set_active(false)


## Visibility AND collision together: a hidden keyboard must not keep its
## collider parked in front of other panels, silently eating their rays.
## The SubViewport also stops rendering while closed - it was a full 840x480
## off-screen render every frame for an idle feature.
func _set_active(on: bool) -> void:
	visible = on
	var shape := get_node_or_null("InteractableBody/CollisionShape3D") as CollisionShape3D
	if shape:
		shape.disabled = not on
	var viewport := get_node_or_null("Viewport") as SubViewport
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _build_keys() -> void:
	var root: Control = get_node_or_null(viewport_path).get_node("Root")
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_prompt_label = Label.new()
	_prompt_label.text = "Enter text"
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_prompt_label)

	_text_label = Label.new()
	_text_label.add_theme_font_size_override("font_size", 34)
	column.add_child(_text_label)

	for row in _ROWS:
		var row_box := HBoxContainer.new()
		row_box.alignment = BoxContainer.ALIGNMENT_CENTER
		row_box.add_theme_constant_override("separation", 6)
		column.add_child(row_box)
		for character in row:
			row_box.add_child(_make_key(character, _on_character.bind(character)))

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 6)
	column.add_child(bottom)
	bottom.add_child(_make_key("CANCEL", _on_cancel, 130))
	bottom.add_child(_make_key("_", _on_character.bind("_"), 66))
	bottom.add_child(_make_key("SPACE", _on_character.bind(" "), 190))
	bottom.add_child(_make_key("<--", _on_backspace, 90))
	bottom.add_child(_make_key("DONE", _on_done, 130))


func _make_key(label: String, action: Callable, width := 66) -> Button:
	var key := Button.new()
	key.text = label
	key.custom_minimum_size = Vector2(width, 62)
	key.add_theme_font_size_override("font_size", 24)
	key.focus_mode = Control.FOCUS_NONE
	key.pressed.connect(action)
	return key


func _on_character(character: String) -> void:
	if _text.length() < 40:
		_text += character
		_refresh_text()


func _on_backspace() -> void:
	_text = _text.substr(0, maxi(_text.length() - 1, 0))
	_refresh_text()


func _on_done() -> void:
	close()
	text_submitted.emit(_text)


func _on_cancel() -> void:
	close()
	cancelled.emit()


func _refresh_text() -> void:
	if _text_label:
		_text_label.text = "%s_" % _text
