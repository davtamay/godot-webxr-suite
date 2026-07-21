@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg")
class_name XRPokeStation
extends Node3D

## A self-contained fingertip-poke demo station: three physical 3D push-buttons
## (counter, momentary light, colour cycle) + a touch panel whose buttons and
## slider you press by TOUCH, all driving a demo orb. Packaged as one droppable
## block (like XRLightLab) so it can share a scene with other control blocks.
##
## Expected children (built into the scene): Stand/CounterButton,
## Stand/LightButton, Stand/ColorButton (XRPokeButton), Stand/CounterLabel,
## Orb (+ Orb/OrbLight), TouchPanel (an xr_ui_panel with Viewport/Root).

const _ORB_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/highlight_affordance_material.tres")
const _COLORS := [Color(0.3, 0.8, 1.0), Color(1.0, 0.55, 0.2), Color(0.5, 1.0, 0.5), Color(1.0, 0.4, 0.8)]

var _counter_button: XRPokeButton
var _light_button: XRPokeButton
var _color_button: XRPokeButton
var _counter_label: Label3D
var _orb: MeshInstance3D
var _orb_light: OmniLight3D

var _count := 0
var _color_index := 0
var _orb_material: StandardMaterial3D
var _slider_label: Label


func _ready() -> void:
	_counter_button = get_node_or_null("Stand/CounterButton")
	_light_button = get_node_or_null("Stand/LightButton")
	_color_button = get_node_or_null("Stand/ColorButton")
	_counter_label = get_node_or_null("Stand/CounterLabel")
	_orb = get_node_or_null("Orb")
	_orb_light = get_node_or_null("Orb/OrbLight")

	if _orb:
		_orb_material = _ORB_MATERIAL.duplicate() as StandardMaterial3D
		_orb_material.albedo_color = _COLORS[0]
		_orb.set_surface_override_material(0, _orb_material)

	if _counter_button:
		_counter_button.pressed.connect(func() -> void:
			_count += 1
			if _counter_label:
				_counter_label.text = "POKES: %d" % _count)
	if _light_button and _orb_light:
		_light_button.pressed.connect(func() -> void: _orb_light.visible = true)
		_light_button.released.connect(func() -> void: _orb_light.visible = false)
	if _color_button:
		_color_button.pressed.connect(func() -> void:
			_color_index = (_color_index + 1) % _COLORS.size()
			if _orb_material:
				_orb_material.albedo_color = _COLORS[_color_index]
			if _orb_light:
				_orb_light.light_color = _COLORS[_color_index])

	_build_panel_ui()


func _build_panel_ui() -> void:
	var root: Control = get_node_or_null("TouchPanel/Viewport/Root")
	if root == null or _orb == null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var title := Label.new()
	title.text = "TOUCH PANEL - poke the buttons, DRAG the slider with your fingertip"
	title.add_theme_font_size_override("font_size", 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for entry in [["BIGGER", 1.25], ["SMALLER", 0.8]]:
		var button := Button.new()
		button.text = entry[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 72)
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(func() -> void:
			_orb.scale = (_orb.scale * (entry[1] as float)).clamp(Vector3.ONE * 0.4, Vector3.ONE * 2.5))
		row.add_child(button)

	_slider_label = Label.new()
	_slider_label.text = "ORB HEIGHT: 50%"
	_slider_label.add_theme_font_size_override("font_size", 24)
	column.add_child(_slider_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.value = 50.0
	slider.custom_minimum_size = Vector2(0, 64)
	slider.value_changed.connect(func(value: float) -> void:
		_slider_label.text = "ORB HEIGHT: %d%%" % int(value)
		_orb.position.y = 1.0 + value * 0.012)
	column.add_child(slider)
