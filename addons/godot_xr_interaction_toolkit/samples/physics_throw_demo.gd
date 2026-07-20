extends Node3D

## Grab-and-throw with real gravity: grab a block (near or far), move it, and
## let go while moving to THROW it - the release velocity carries it and it
## falls, bounces, and lands under physics. Try landing one in the tray.
##
## Each block is a Throwable prefab (a RigidBody3D driven by XRGrabInteractable,
## frozen while held so gravity doesn't fight the grab, thrown on release).

const _COLORS := [
	Color(0.4, 0.62, 0.95), Color(0.95, 0.4, 0.45),
	Color(0.5, 0.85, 0.45), Color(1.0, 0.8, 0.3),
]

var _blocks: Array = []
var _homes: Array = []


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	var i := 0
	for block in $Blocks.get_children():
		var body := block.get_node_or_null("Body") as RigidBody3D
		if body == null:
			continue
		var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			var material := (mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
			material.albedo_color = _COLORS[i % _COLORS.size()]
			mesh.set_surface_override_material(0, material)
		_blocks.append(body)
		_homes.append(body.global_transform)
		i += 1


func _process(_delta: float) -> void:
	# A block that falls off the world respawns at its home on the table.
	for index in _blocks.size():
		var body := _blocks[index] as RigidBody3D
		if body and body.global_position.y < -1.5:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.global_transform = _homes[index]
