extends Node3D

## Grab the blaster off the counter and shoot the cans off the shelf. The
## blaster is an ordinary grab interactable with an XRBlaster inside - pulling
## the ACTIVATE action (trigger-while-held) fires a bolt from the muzzle. Cans
## are physics targets; poke RESET to stand them back up, and any can knocked
## to the floor respawns on the shelf.

const _COLORS := [
	Color(0.85, 0.3, 0.25), Color(0.3, 0.55, 0.85), Color(0.4, 0.75, 0.4),
	Color(0.9, 0.7, 0.25), Color(0.7, 0.4, 0.75), Color(0.35, 0.75, 0.75),
]

var _cans: Array = []
var _homes: Array = []


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	var index := 0
	for can in $Cans.get_children():
		var body := can as RigidBody3D
		if body == null:
			continue
		var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			material.albedo_color = _COLORS[index % _COLORS.size()]
			mesh.set_surface_override_material(0, material)
		_cans.append(body)
		_homes.append(body.global_transform)
		index += 1
	var reset := get_node_or_null("ResetButton")
	if reset and reset.has_signal("pressed"):
		reset.pressed.connect(_reset)


func _reset() -> void:
	for i in _cans.size():
		_stand(_cans[i], _homes[i])


func _process(_delta: float) -> void:
	# Cans that end up on the floor pop back onto the shelf.
	for i in _cans.size():
		var body := _cans[i] as RigidBody3D
		if body and body.global_position.y < 0.5:
			_stand(body, _homes[i])


func _stand(body: RigidBody3D, home: Transform3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = home
