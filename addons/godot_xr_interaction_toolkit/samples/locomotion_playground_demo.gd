extends Node3D

## Locomotion playground: teleport around with the thumbstick (free arc lands
## anywhere on the floor), or aim at a glowing TELEPORT ANCHOR to snap to that
## exact spot - most anchors also turn you to FACE the centre sculpture (the
## bold arrow shows the facing you'll get). The far selection ray hides while
## you teleport - the two are exclusive.
##
## This scene turns DIRECTIONAL TELEPORT on (an authoring toggle on the rig's
## XRLocomotion): while aiming a free-floor teleport, the thumbstick ANGLE
## chooses which way you'll face when you land (the reticle shows a facing
## arrow). It's an opt-in behaviour - off by default, where left/right snap
## turns instead.
##
## The debug panel logs every teleport / snap turn. (Continuous move +
## climbing land in this same scene next.)

func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	# Demonstrate the directional-teleport authoring toggle on the rig's
	# locomotion (found by group; the rig lives inside the prefab).
	_enable_directional_teleport.call_deferred()


func _enable_directional_teleport() -> void:
	var locomotion := get_tree().get_first_node_in_group("xr_locomotion")
	if locomotion:
		locomotion.directional_teleport = true
