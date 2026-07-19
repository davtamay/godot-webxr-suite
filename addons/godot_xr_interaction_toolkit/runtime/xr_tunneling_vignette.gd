@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg")
class_name XRTunnelingVignette
extends Node

## Comfort tunneling vignette - darkens the edges of your view WHILE you move,
## which greatly reduces motion sickness during smooth locomotion. Unity XRI's
## Tunneling Vignette as a drop-in block.
##
## Self-contained: it watches the camera's own motion (translation speed + turn
## rate), so it works with ANY locomotion - continuous move, continuous turn,
## even a moving platform. Instant teleport jumps are ignored (no flash). Add
## it near a rig; it finds the camera and rides along, invisible until you move.

const _MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_vignette_material.tres")

@export var enabled := true

@export_group("Feel")
## How dark the edges get at full effect (0 = off, 1 = fully black ring).
@export_range(0.0, 1.0, 0.05) var strength := 0.9
## Speed (m/s) and turn rate (deg/s) above which the vignette fades IN.
@export_range(0.0, 3.0, 0.05) var move_threshold := 0.3
@export_range(0.0, 90.0, 1.0) var turn_threshold := 25.0
## How fast the vignette fades in/out (per second).
@export_range(1.0, 20.0, 0.5) var fade_speed := 8.0

@export_group("Geometry")
@export var camera_path: NodePath
## Distance in front of the eyes and quad size - sized to roughly fill the
## headset FOV (~100 deg on Quest) so the dark ring lands at your view edges.
## Enlarge quad_size if you see a hard edge on a wider-FOV headset.
@export_range(0.2, 1.0, 0.05) var distance := 0.5
@export var quad_size := Vector2(1.35, 1.1)

var _camera: Node3D
var _quad: MeshInstance3D
var _material: StandardMaterial3D
var _intensity := 0.0
var _last_position := Vector3.ZERO
var _last_forward := Vector3.FORWARD
var _has_last := false
# Above this speed the motion is a teleport jump, not smooth travel - ignore.
const _TELEPORT_SPEED := 15.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	_ensure_camera()  # may fail this frame - _process keeps trying (XR session
	# start / ready order can make the camera appear a few frames later).


## Resolve the camera and build the quad once; returns true when ready.
func _ensure_camera() -> bool:
	if _quad != null:
		return true
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_node_or_null(camera_path) as Node3D
		if _camera == null:
			_camera = XRRigResolver.find_camera(self)
	if _camera == null:
		return false
	_build_quad()
	return true


func _build_quad() -> void:
	_material = _MATERIAL.duplicate()
	var mesh := QuadMesh.new()
	mesh.size = quad_size
	_quad = MeshInstance3D.new()
	_quad.name = "TunnelingVignette"
	_quad.mesh = mesh
	_quad.material_override = _material
	_quad.position = Vector3(0.0, 0.0, -distance)
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Render in both eyes, never culled by frustum (it's head-locked).
	_quad.extra_cull_margin = 16.0
	_camera.add_child(_quad)


func _process(delta: float) -> void:
	if not _ensure_camera() or delta <= 0.0:
		return
	var position := _camera.global_position
	var forward := -_camera.global_transform.basis.z

	var target := 0.0
	if enabled:
		var moving := false
		var turning := false
		if _has_last:
			var speed := position.distance_to(_last_position) / delta
			if speed > move_threshold and speed < _TELEPORT_SPEED:
				moving = true
			var flat_now := Vector3(forward.x, 0.0, forward.z).normalized()
			var flat_last := Vector3(_last_forward.x, 0.0, _last_forward.z).normalized()
			if flat_now.length() > 0.001 and flat_last.length() > 0.001:
				var turn_rate := rad_to_deg(flat_last.angle_to(flat_now)) / delta
				if turn_rate > turn_threshold:
					turning = true
		if moving or turning:
			target = strength

	_last_position = position
	_last_forward = forward
	_has_last = true

	_intensity = move_toward(_intensity, target, fade_speed * delta)
	_material.albedo_color.a = _intensity
	_quad.visible = _intensity > 0.001
