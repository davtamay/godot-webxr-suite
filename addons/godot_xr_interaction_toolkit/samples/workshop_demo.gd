extends Node3D

## Workshop: one room that merges the four grab-and-use demos - throw blocks into
## a tray, draw with the pen on a notepad, shoot the blaster at cans, and spray
## the wall. Every tool is the SAME prefab used in its standalone demo; this
## scene just gathers them into stations and handles the resets/respawns. Proof
## the demos were really one room rebuilt four times.

# Bodies to stand back up if they fall, paired with their home transforms.
var _respawn: Array[RigidBody3D] = []
var _homes: Array[Transform3D] = []
var _cans: Array[RigidBody3D] = []
var _can_homes: Array[Transform3D] = []


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())

	# Guided navigation: teleport can ONLY land on the four station pads.
	for loco in get_tree().get_nodes_in_group("xr_locomotion"):
		if "anchors_only" in loco:
			loco.anchors_only = true

	# Throwable blocks + loose tools (pen / cup / spray can): Node3D grab roots
	# with a Body RigidBody. Cans: RigidBody roots. Track all for respawn.
	for block in $ThrowStation/Blocks.get_children():
		_track(block.get_node_or_null("Body"))
	for tool_root in [$DrawStation/Pen, $DrawStation/CoffeeCup, $SprayStation/SprayCan]:
		if tool_root:
			_track(tool_root.get_node_or_null("Body"))
	for can in $ShootStation/Cans.get_children():
		var body := can as RigidBody3D
		if body:
			_cans.append(body)
			_can_homes.append(body.global_transform)

	_setup_grab_lab.call_deferred()

	# Station reset buttons.
	_wire_button($ShootStation/ResetButton, _reset_cans)
	var notepad := $DrawStation/Notepad
	if notepad and notepad.has_method("clear"):
		_wire_button($DrawStation/ClearButton, notepad.clear)
	var wall := $SprayStation/Wall/Surface
	if wall and wall.has_method("clear"):
		_wire_button($SprayStation/WipeButton, wall.clear)


## The Grab Lab's red cube is on interaction layer 2, so only an interactor that
## includes layer 2 can grab it. Give the RIGHT hand's interactors layer 2 (they
## keep layer 1 too, so they still grab everything) - the left hand can't. If no
## right-hand interactor is found, drop the cube back to layer 1 so it never
## looks broken.
func _setup_grab_lab() -> void:
	var right_found := false
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if "hand" in node and "interaction_layers" in node and int(node.hand) == 1:
			node.interaction_layers = int(node.interaction_layers) | 2
			right_found = true
	if not right_found:
		var cube := get_node_or_null("GrabLabStation/LayerCube")
		if cube:
			cube.interaction_layers = 1


func _track(body: Node) -> void:
	var rb := body as RigidBody3D
	if rb:
		_respawn.append(rb)
		_homes.append(rb.global_transform)


func _wire_button(button: Node, callback: Callable) -> void:
	if button and button.has_signal("pressed"):
		button.pressed.connect(callback)


func _reset_cans() -> void:
	for i in _cans.size():
		_stand(_cans[i], _can_homes[i])


func _process(_delta: float) -> void:
	for i in _respawn.size():
		if _respawn[i].global_position.y < 0.2:
			_stand(_respawn[i], _homes[i])
	for i in _cans.size():
		if _cans[i].global_position.y < 0.5:
			_stand(_cans[i], _can_homes[i])


func _stand(body: RigidBody3D, home: Transform3D) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = home
