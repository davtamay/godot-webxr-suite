extends Node3D

## Base for a self-contained Workshop station. Each station is its own prefab
## (edit once, every scene that instances it updates) - AND directly playable on
## its own: press Play (F6) on a station scene and it spawns a debug rig + floor
## so you can test just that station, no separate "demo" scene needed. Inside the
## Workshop it stays passive (the Workshop provides the rig). Subclasses put their
## wiring in _wire().

## The rig used when a station is played on its own.
const _DEBUG_RIG := preload("res://addons/godot_webxr_kit/webxr_prefab.tscn")

## Objects below this height are stood back up at their home transform.
var _floor_y := 0.2

var _bodies: Array[RigidBody3D] = []
var _homes: Array[Transform3D] = []


func _ready() -> void:
	# Played on its own (this station is the running scene's root)? Give it a rig
	# and floor so it's immediately testable. Deferred so the check sees the whole
	# tree; guarded so it never adds a second rig when embedded in a bigger scene.
	if get_tree().current_scene == self:
		_spawn_debug_env.call_deferred()
	_wire()


## Subclasses override this for their station wiring (respawns, buttons, etc.).
func _wire() -> void:
	pass


func _spawn_debug_env() -> void:
	if get_tree().get_first_node_in_group(&"xr_interaction_manager") != null:
		return  # a rig is already present - don't add another

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.74, 0.82)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 0.08, 12)
	floor_col.shape = box
	floor_col.position.y = -0.04
	floor_body.add_child(floor_col)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 12)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.19, 0.24)
	mat.roughness = 0.95
	floor_mesh.material_override = mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	add_child(_DEBUG_RIG.instantiate())


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
