extends Node3D

## Poke playground: physical 3D push-buttons (counter, momentary light,
## color cycle) + a UI panel whose buttons and SLIDER are pressed by TOUCH -
## the same fingertip that pushes the 3D buttons drags the slider directly.
## Rays still work on the panel; poke and ray coexist.

@onready var _counter_button: XRPokeButton = $Stand/CounterButton
@onready var _light_button: XRPokeButton = $Stand/LightButton
@onready var _color_button: XRPokeButton = $Stand/ColorButton
@onready var _counter_label: Label3D = $Stand/CounterLabel
@onready var _orb: MeshInstance3D = $Orb
@onready var _orb_light: OmniLight3D = $Orb/OrbLight

const _ORB_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/highlight_affordance_material.tres")
const _COLORS := [Color(0.3, 0.8, 1.0), Color(1.0, 0.55, 0.2), Color(0.5, 1.0, 0.5), Color(1.0, 0.4, 0.8)]

var _count := 0
var _color_index := 0
var _orb_material: StandardMaterial3D
var _slider_label: Label


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	_orb_material = _ORB_MATERIAL.duplicate() as StandardMaterial3D
	_orb_material.albedo_color = _COLORS[0]
	_orb.set_surface_override_material(0, _orb_material)

	_counter_button.pressed.connect(func() -> void:
		_count += 1
		_counter_label.text = "POKES: %d" % _count)
	_light_button.pressed.connect(func() -> void: _orb_light.visible = true)
	_light_button.released.connect(func() -> void: _orb_light.visible = false)
	_color_button.pressed.connect(func() -> void:
		_color_index = (_color_index + 1) % _COLORS.size()
		_orb_material.albedo_color = _COLORS[_color_index]
		_orb_light.light_color = _COLORS[_color_index])
	_build_panel_ui()


func _build_panel_ui() -> void:
	var root: Control = $TouchPanel/Viewport/Root
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
