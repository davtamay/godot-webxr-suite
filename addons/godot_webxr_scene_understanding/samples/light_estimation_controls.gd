extends Control

## Ordinary Godot controls rendered into an XR-interactable SubViewport.
## These values alter only the virtual material; environmental estimates stay
## read-only so the demo continues to represent what WebXR actually measured.

signal material_values_changed(values: Dictionary)
signal display_mode_changed(mode: int)

const PRESETS := {
	"Matte": {"metallic": 0.0, "roughness": 0.9, "hue": 0.58, "reflection": 0.2},
	"Plastic": {"metallic": 0.0, "roughness": 0.34, "hue": 0.04, "reflection": 0.5},
	"Glossy": {"metallic": 0.0, "roughness": 0.08, "hue": 0.57, "reflection": 0.9},
	"Chrome": {"metallic": 1.0, "roughness": 0.12, "hue": 0.58, "reflection": 1.0},
	"Gold": {"metallic": 1.0, "roughness": 0.22, "hue": 0.115, "reflection": 0.95},
}

var _sliders := {}
var _value_labels := {}
var _reflection_toggle: CheckButton
var _color_preview: ColorRect
var _state_label: Label
var _suppress := false


func _ready() -> void:
	_build_panel()
	_apply_preset("Glossy")


func _build_panel() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.055, 0.085, 0.13, 0.96)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.text = "LIGHT MATERIAL LAB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)

	_state_label = Label.new()
	_state_label.text = "Grab the hero object, then tune its material."
	_state_label.custom_minimum_size.y = 62
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_label.add_theme_font_size_override("font_size", 20)
	content.add_child(_state_label)

	_add_slider(content, "Metallic", "metallic", 0.0, 1.0, 0.01, 0.0)
	_add_slider(content, "Roughness", "roughness", 0.04, 1.0, 0.01, 0.08)
	_add_slider(content, "Color hue", "hue", 0.0, 1.0, 0.005, 0.57)
	_add_slider(content, "Estimate gain", "gain", 0.0, 3.0, 0.02, 1.0)
	_add_slider(content, "Reflection / specular", "reflection", 0.0, 1.0, 0.01, 0.9)

	var reflection_row := HBoxContainer.new()
	content.add_child(reflection_row)
	_reflection_toggle = CheckButton.new()
	_reflection_toggle.text = "Reflection response enabled"
	_reflection_toggle.button_pressed = true
	_reflection_toggle.add_theme_font_size_override("font_size", 22)
	_reflection_toggle.toggled.connect(_on_value_changed)
	reflection_row.add_child(_reflection_toggle)
	_color_preview = ColorRect.new()
	_color_preview.custom_minimum_size = Vector2(80, 38)
	_color_preview.color = _current_color()
	reflection_row.add_child(_color_preview)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	content.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "Lighting:"
	mode_label.add_theme_font_size_override("font_size", 22)
	mode_row.add_child(mode_label)
	# OptionButton opens a separate PopupMenu window. That window is not part
	# of this SubViewport's textured XR interaction surface, so an XR ray can
	# open it but cannot reliably select an item. Keep every choice in the
	# panel's Control tree as a segmented group instead.
	var mode_group := ButtonGroup.new()
	var mode_names := ["LIVE", "FROZEN", "NEUTRAL"]
	for mode_index in range(mode_names.size()):
		var mode_button := Button.new()
		mode_button.text = mode_names[mode_index]
		mode_button.toggle_mode = true
		mode_button.button_group = mode_group
		mode_button.button_pressed = mode_index == 0
		mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_button.custom_minimum_size.y = 46
		mode_button.add_theme_font_size_override("font_size", 20)
		mode_button.pressed.connect(_select_display_mode.bind(mode_index))
		mode_row.add_child(mode_button)

	var preset_label := Label.new()
	preset_label.text = "Material presets"
	preset_label.add_theme_font_size_override("font_size", 21)
	content.add_child(preset_label)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	content.add_child(presets)
	for preset_name in PRESETS.keys():
		var button := Button.new()
		button.text = preset_name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(_apply_preset.bind(preset_name))
		presets.add_child(button)

	var note := Label.new()
	note.text = "Controls change the virtual material only. WebXR direction, intensity, and SH measurements remain read-only."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 17)
	note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.82))
	content.add_child(note)


func _add_slider(
	parent: VBoxContainer,
	label_text: String,
	key: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 220
	label.add_theme_font_size_override("font_size", 21)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 38
	slider.value_changed.connect(func(_value: float) -> void: _on_slider_changed(key))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 68
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 20)
	row.add_child(value_label)
	_sliders[key] = slider
	_value_labels[key] = value_label
	_update_value_label(key)


func _on_slider_changed(key: String) -> void:
	_update_value_label(key)
	if key == "hue" and _color_preview:
		_color_preview.color = _current_color()
	_emit_values()


func _on_value_changed(_enabled: bool) -> void:
	_emit_values()


func _select_display_mode(mode: int) -> void:
	display_mode_changed.emit(mode)


func _apply_preset(preset_name: String) -> void:
	var preset: Dictionary = PRESETS.get(preset_name, {})
	if preset.is_empty():
		return
	_suppress = true
	for key in preset.keys():
		if _sliders.has(key):
			_sliders[key].value = float(preset[key])
			_update_value_label(key)
	_suppress = false
	if _color_preview:
		_color_preview.color = _current_color()
	_emit_values()


func _update_value_label(key: String) -> void:
	if _sliders.has(key) and _value_labels.has(key):
		_value_labels[key].text = "%.2f" % float(_sliders[key].value)


func _emit_values() -> void:
	if _suppress or _sliders.is_empty():
		return
	material_values_changed.emit({
		"metallic": float(_sliders["metallic"].value),
		"roughness": float(_sliders["roughness"].value),
		"base_color": _current_color(),
		"gain": float(_sliders["gain"].value),
		"reflection": float(_sliders["reflection"].value),
		"reflection_enabled": _reflection_toggle.button_pressed,
	})


func _current_color() -> Color:
	var hue := float(_sliders["hue"].value) if _sliders.has("hue") else 0.57
	return Color.from_hsv(hue, 0.72, 0.95)


func set_runtime_status(text: String) -> void:
	if _state_label:
		_state_label.text = text
