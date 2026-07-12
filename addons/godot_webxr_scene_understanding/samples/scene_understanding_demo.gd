extends Node3D
## Root of the scene-understanding sample. Adds the demo app's "back to menu"
## button when that script is present, loaded dynamically so this sample keeps
## no hard dependency on the demo (it runs standalone in any project).

func _ready() -> void:
	const MENU_BUTTON := "res://scripts/back_to_menu_button.gd"
	if ResourceLoader.exists(MENU_BUTTON):
		var menu_button = load(MENU_BUTTON)
		if menu_button:
			add_child(menu_button.new())
