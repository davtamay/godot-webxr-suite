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
## Poke the CLEAR button to wipe the notepad. Any tool that ends up on the floor
## respawns where it started, so nothing gets lost.

var _tools: Array = []
var _homes: Array = []


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	var button := get_node_or_null("ClearButton")
	var notepad := get_node_or_null("Notepad")
	if button and notepad and button.has_signal("pressed"):
		button.pressed.connect(notepad.clear)
	for tool_name in ["Pen", "CoffeeCup", "Wand"]:
		var body := get_node_or_null(tool_name + "/Body") as RigidBody3D
		if body:
			_tools.append(body)
			_homes.append(body.global_transform)


func _process(_delta: float) -> void:
	for index in _tools.size():
		var body := _tools[index] as RigidBody3D
		if body and not body.freeze and body.global_position.y < 0.55:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			body.global_transform = _homes[index]
