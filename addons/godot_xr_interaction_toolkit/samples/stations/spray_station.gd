extends "res://addons/godot_xr_interaction_toolkit/samples/stations/workshop_station.gd"

## Spray station: grab the can and paint the wall; the Wipe button clears it.
## The can respawns if it falls.


func _ready() -> void:
	if $SprayCan:
		_track($SprayCan.get_node_or_null("Body"))
	var surface := $Wall/Surface
	if surface and surface.has_method("clear"):
		_wire_button($WipeButton, surface.clear)
