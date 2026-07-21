extends "res://addons/godot_xr_interaction_toolkit/samples/stations/workshop_station.gd"

## Shoot station: grab the blaster and knock the cans off the shelf; the Reset
## button (and falling off the world) stands them back up.


func _wire() -> void:
	_floor_y = 0.5
	for can in $Cans.get_children():
		_track(can)  # cans are RigidBody roots
	_wire_button($ResetButton, _reset_all)
