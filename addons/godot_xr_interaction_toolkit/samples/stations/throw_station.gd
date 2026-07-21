extends "res://addons/godot_xr_interaction_toolkit/samples/stations/workshop_station.gd"

## Throw station: grab the blocks and toss them into the tray; they respawn if
## they fall off the world.


func _wire() -> void:
	for block in $Blocks.get_children():
		_track(block.get_node_or_null("Body"))
