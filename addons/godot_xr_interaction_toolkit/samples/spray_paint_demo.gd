extends Node3D

## Grab the spray can off the table and paint the wall. The point of this demo is
## that the can is the SAME building blocks as the blaster - a grab interactable
## with a GRIP hold and an XRHandActivator - only configured differently: the
## activator is in CONTINUOUS mode (spray while held, not one shot) and the
## effect is an XRSprayer instead of an XRBlaster. It composes with a third block,
## XRDrawingSurface, to actually paint. Poke WIPE to clear.

var _can: Node3D
var _home := Transform3D.IDENTITY


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())
	var reset := get_node_or_null("ResetButton")
	var surface := get_node_or_null("Board/Surface")
	if reset and reset.has_signal("pressed") and surface and surface.has_method("clear"):
		reset.pressed.connect(surface.clear)
	_can = get_node_or_null("SprayCan")
	var body := _can.get_node_or_null("Body") as Node3D if _can else null
	if body:
		_home = body.global_transform


func _process(_delta: float) -> void:
	# If the can is knocked to the floor, stand it back on the table.
	var body := _can.get_node_or_null("Body") as RigidBody3D if _can else null
	if body and body.global_position.y < 0.3:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.global_transform = _home
