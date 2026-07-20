extends Node3D

## Control panel: three grab-driven MECHANISMS wired to live effects -
## a DIAL sets a lamp's brightness + colour, a LEVER raises a piston, a DRAWER
## slides open to reveal a gem. Each is a constrained interactable that outputs
## a 0..1 value; the wiring below is all it takes to drive anything.

@onready var _dial: XRDial = $Console/Dial
@onready var _lever: XRLever = $Console/Lever
@onready var _drawer: XRDrawer = $Console/Drawer
@onready var _lamp: OmniLight3D = $Lamp/Light
@onready var _bulb: MeshInstance3D = $Lamp/Bulb
@onready var _piston: MeshInstance3D = $Piston
@onready var _gem: MeshInstance3D = $Console/Drawer/Gem
@onready var _dial_label: Label3D = $Console/DialLabel
@onready var _lever_label: Label3D = $Console/LeverLabel
@onready var _drawer_label: Label3D = $Console/DrawerLabel

var _bulb_material: StandardMaterial3D
var _gem_material: StandardMaterial3D
var _piston_base_y := 0.0


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())

	_bulb_material = _bulb.get_active_material(0).duplicate()
	_bulb.set_surface_override_material(0, _bulb_material)
	_gem_material = _gem.get_active_material(0).duplicate()
	_gem.set_surface_override_material(0, _gem_material)
	_piston_base_y = _piston.position.y

	# Checkerboard for the slide surface.
	var board_mesh := $Console/Board/BoardMesh as MeshInstance3D
	var board_mat := (board_mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	board_mat.albedo_texture = _make_checker()
	board_mesh.set_surface_override_material(0, board_mat)

	_dial.value_changed.connect(_on_dial)
	_lever.value_changed.connect(_on_lever)
	_drawer.value_changed.connect(_on_drawer)

	# Reflect the authored starting positions.
	_on_dial(_dial.value)
	_on_lever(_lever.value)
	_on_drawer(_drawer.value)


func _on_dial(value: float) -> void:
	var color := Color.from_hsv(value, 0.65, 1.0)
	_lamp.light_energy = 0.15 + value * 4.0
	_lamp.light_color = color
	_bulb_material.emission = color
	_bulb_material.emission_energy_multiplier = 0.3 + value * 3.0
	_dial_label.text = "BRIGHTNESS  %d%%" % roundi(value * 100.0)


func _on_lever(value: float) -> void:
	_piston.position.y = _piston_base_y + value * 0.45
	_lever_label.text = "LIFT  %d%%" % roundi(value * 100.0)


func _on_drawer(value: float) -> void:
	_gem.visible = value > 0.05
	_gem_material.emission_energy_multiplier = value * 4.0
	_drawer_label.text = "DRAWER  %d%%" % roundi(value * 100.0)


## An 8x8 checkerboard texture for the slide board.
func _make_checker() -> ImageTexture:
	var size := 256
	var tiles := 8
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var cell := (x * tiles / size + y * tiles / size) % 2
			image.set_pixel(x, y, Color(0.9, 0.9, 0.92) if cell == 0 else Color(0.12, 0.14, 0.2))
	return ImageTexture.create_from_image(image)
