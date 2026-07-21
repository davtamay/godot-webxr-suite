extends Node3D

## Perception showcase: room mesh + depth occlusion + light estimation + hit-test
## anchors, all via the drop-in manager blocks - like the Workshop, one room with
## a station for each perception feature (teleport between them). Adds the
## back-to-menu button when opened from the sample launcher (soft-loaded, so the
## addon stays standalone). The stations wire themselves; this script only adds
## the menu button.


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
