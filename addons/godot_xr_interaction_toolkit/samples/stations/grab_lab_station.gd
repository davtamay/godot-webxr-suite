extends "res://addons/godot_xr_interaction_toolkit/samples/stations/workshop_station.gd"

## Grab Lab: sockets, movement types, two-hand, snap-grip, and a layer-filtered
## cube. The grabbables here are kinematic (they stay where dropped), so there is
## nothing to respawn - the only wiring is the interaction-layer conditional.


func _ready() -> void:
	_setup_layers.call_deferred()


## The red cube is on interaction layer 2, so only an interactor that includes
## layer 2 can grab it. Give the RIGHT hand's interactors layer 2 (they keep
## layer 1 too, so they still grab everything) - the left hand can't. If no
## right-hand interactor is found, drop the cube back to layer 1 so it never
## looks broken.
func _setup_layers() -> void:
	var right_found := false
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if "hand" in node and "interaction_layers" in node and int(node.hand) == 1:
			node.interaction_layers = int(node.interaction_layers) | 2
			right_found = true
	if not right_found:
		var cube := get_node_or_null("LayerCube")
		if cube:
			cube.interaction_layers = 1
