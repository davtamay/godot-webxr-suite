extends Node3D

## Locomotion playground: teleport around with the thumbstick (free arc lands
## anywhere on the floor), or aim at a glowing TELEPORT ANCHOR to snap to that
## exact spot - most anchors also turn you to FACE the centre sculpture. The
## blue arrow on each anchor shows the forward you'll be facing when you land.
##
## The debug panel logs every teleport / snap turn so you can see the system
## firing. (Continuous move + climbing land in this same scene next.)

func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
