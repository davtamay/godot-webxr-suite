extends Node3D

## Workshop: five grab stations in a row - Throw, Draw, Shoot, Spray, Grab Lab -
## each an INSTANCED prefab from samples/stations/ (edit a station once and it
## updates here and in its own test scene). Every station owns its wiring
## (respawns, reset buttons, the layer filter), so this root only adds the
## back-to-menu button and locks teleport to the station pads.


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())

	# Guided navigation: teleport can ONLY land on the station pads.
	for loco in get_tree().get_nodes_in_group("xr_locomotion"):
		if "anchors_only" in loco:
			loco.anchors_only = true
