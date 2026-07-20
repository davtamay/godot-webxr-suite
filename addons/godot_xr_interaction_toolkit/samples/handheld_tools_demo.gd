extends Node3D

## Handheld tools - how to customize WHERE and HOW an object sits in the hand,
## with an authored XRGrabPoint on each:
##   - Wand: long axis is its own +Y, so an identity grab point makes it stand
##     up out of the fist.
##   - Coffee cup: the grab point is on the HANDLE, so grabbing snaps the mug
##     into your hand by its handle, upright, however you reached for it.
##   - Pen: the grab point is pitched forward-down into a natural writing pose;
##     its tip draws on the notepad (XRDrawingSurface) when it touches.
##
## Poke the CLEAR button to wipe the notepad.


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	var button := get_node_or_null("ClearButton")
	var notepad := get_node_or_null("Notepad")
	if button and notepad and button.has_signal("pressed"):
		button.pressed.connect(notepad.clear)
