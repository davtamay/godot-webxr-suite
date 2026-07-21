extends "res://addons/godot_xr_interaction_toolkit/samples/stations/workshop_station.gd"

## Draw station: write on the notepad with the pen; the Clear button wipes it.
## Pen and cup respawn on the desk if they fall.


func _ready() -> void:
	for tool_root in [$Pen, $CoffeeCup]:
		if tool_root:
			_track(tool_root.get_node_or_null("Body"))
	var notepad := $Notepad
	if notepad and notepad.has_method("clear"):
		_wire_button($ClearButton, notepad.clear)
