extends Node3D

## Base for a self-contained Workshop station. Each station is its own prefab
## (edit once, every scene that instances it updates) and works standalone in its
## own test scene - so the wiring (respawns, reset buttons) lives HERE, in the
## station, not in the big Workshop root script. Subclasses register their
## physics bodies and wire their buttons in _ready().

## Objects below this height are stood back up at their home transform.
var _floor_y := 0.2

var _bodies: Array[RigidBody3D] = []
var _homes: Array[Transform3D] = []


## Track a RigidBody so it respawns at its current (home) transform if it falls.
func _track(body: Node) -> void:
	var rb := body as RigidBody3D
	if rb:
		_bodies.append(rb)
		_homes.append(rb.global_transform)


func _wire_button(button: Node, callback: Callable) -> void:
	if button and button.has_signal("pressed"):
		button.pressed.connect(callback)


func _process(_delta: float) -> void:
	for i in _bodies.size():
		if _bodies[i].global_position.y < _floor_y:
			_stand(i)


func _stand(i: int) -> void:
	_bodies[i].linear_velocity = Vector3.ZERO
	_bodies[i].angular_velocity = Vector3.ZERO
	_bodies[i].global_transform = _homes[i]


## Stand every tracked body back up (station reset buttons call this).
func _reset_all() -> void:
	for i in _bodies.size():
		_stand(i)
