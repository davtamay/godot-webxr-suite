@tool
@icon("res://addons/godot_webxr_scene_understanding/icons/light_estimation_manager.svg")
class_name LightEstimationManager
extends Node3D

## Drop-in real-world lighting manager (mirrors ARFoundation's light
## estimation).
##
## Add this node anywhere in your scene and, in AR, your virtual objects are lit
## by - and reflect - the real room: the WebXR light estimate drives an
## environment sky rebuilt from the room's spherical harmonics (ambient +
## reflections on every object) plus a primary directional light with the room's
## main light colour, intensity, and direction.
##
## Zero wiring: finds your WorldEnvironment automatically (or creates one) and
## builds the sky and light itself. Requests the 'light-estimation' session
## feature by itself. Platform note: Android XR / ARCore serve light estimates;
## Quest Browser does not implement the feature - [method get_status] reports
## this honestly per device. Inert outside a web export.

## Emitted after each smoothed estimate is applied - carries the same values
## driving the sky and light, for telemetry UIs (direction arrows, colour
## swatches, banners).
signal estimate_applied(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	spherical_harmonics: PackedVector3Array
)

const _BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd"
## Pre-baked SH sky material template (WebGPU-export safe; uniform updates
## reuse the baked shader).
const _SKY_TEMPLATE := preload("res://addons/godot_webxr_scene_understanding/runtime/light_estimation_sky_material.tres")

## Drive the scene's ambient light from the room's spherical harmonics.
@export var affect_ambient := true

## Drive reflections (metallic/glossy materials mirror the real room's light).
@export var affect_reflections := true

## Create and drive a DirectionalLight3D matching the room's main light
## (direction, colour, intensity). Casts your virtual shadows the right way.
@export var create_primary_light := true

## Shadows on the estimated primary light.
@export var primary_light_shadows := true

## Overall strength of the estimated sky lighting.
@export_range(0.0, 4.0, 0.05) var sky_intensity := 1.0:
	set(value):
		sky_intensity = value
		if _sky_material:
			_sky_material.set_shader_parameter("sky_energy", sky_intensity)

## How fast the scene follows lighting changes. The platform itself converges
## over ~0.8s (measured); this only adds smoothing on top.
@export_range(1.0, 30.0, 0.5) var responsiveness := 20.0

## The WorldEnvironment to drive. Leave empty to find one automatically (or
## create one if the scene has none).
@export var world_environment_path: NodePath:
	set(value):
		world_environment_path = value
		update_configuration_warnings()

var _bridge: Node
var _sky_material: ShaderMaterial
var _light: DirectionalLight3D
var _has_target := false
var _target_direction := Vector3.DOWN
var _target_intensity := Vector3.ZERO
var _target_sh := PackedVector3Array()
var _smoothed_direction := Vector3.DOWN
var _smoothed_intensity := Vector3.ZERO
var _smoothed_sh := PackedVector3Array()


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	# The sky + light are built on EVERY platform (the neutral sky keeps the
	# flat/native views lit consistently); only the acquisition bridge is
	# WebXR-specific.
	_setup_sky()
	if create_primary_light:
		_light = DirectionalLight3D.new()
		_light.name = "EstimatedLight"
		_light.shadow_enabled = primary_light_shadows
		_light.visible = false
		add_child(_light)
	if not OS.has_feature("web"):
		set_process(false)
		return  # No estimate source off-web; harmless no-op on desktop / OpenXR.
	var script := load(_BRIDGE_SCRIPT)
	_bridge = Node.new()
	_bridge.name = "LightEstimationBridge"
	_bridge.set_script(script)
	add_child(_bridge)
	_bridge.estimate_updated.connect(_on_estimate_updated)
	_bridge.estimate_lost.connect(_on_estimate_lost)
	set_process(true)


## The bridge's honest per-device availability line, for status displays.
func get_status() -> String:
	return str(_bridge.get_status()) if _bridge else "Light estimation: web export required."


## Raw state token ('live', 'not-granted', ...) for UI state machines.
func get_state() -> String:
	return str(_bridge.get_state()) if _bridge else "unavailable"


## True while real room-light data is flowing.
func has_live_estimate() -> bool:
	return _bridge.has_live_estimate() if _bridge else false


func _setup_sky() -> void:
	if not affect_ambient and not affect_reflections:
		return
	var world_env := _find_world_environment()
	if world_env == null:
		world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		world_env.environment = Environment.new()
		add_child(world_env)
	if world_env.environment == null:
		world_env.environment = Environment.new()
	var env := world_env.environment
	# NOTE: REALTIME sky mode is broken for custom sky shaders (renders objects
	# black); INCREMENTAL spreads the radiance update over frames instead.
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	_sky_material = _SKY_TEMPLATE.duplicate() as ShaderMaterial
	_sky_material.set_shader_parameter("sky_energy", sky_intensity)
	sky.sky_material = _sky_material
	env.sky = sky
	if affect_ambient:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	if affect_reflections:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


func _find_world_environment() -> WorldEnvironment:
	if not world_environment_path.is_empty():
		var explicit := get_node_or_null(world_environment_path)
		if explicit is WorldEnvironment:
			return explicit
	var scene := get_tree().current_scene if get_tree().current_scene else get_tree().root
	var found := scene.find_children("*", "WorldEnvironment", true, false)
	return found[0] as WorldEnvironment if not found.is_empty() else null


func _on_estimate_updated(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	spherical_harmonics: PackedVector3Array
) -> void:
	if not _is_estimate_usable(direction_to_light, primary_intensity, spherical_harmonics):
		return  # An empty/degenerate sample would flash the scene black.
	_target_direction = direction_to_light.normalized()
	_target_intensity = primary_intensity
	_target_sh = spherical_harmonics.duplicate()
	if not _has_target:
		_has_target = true
		_smoothed_direction = _target_direction
		_smoothed_intensity = _target_intensity
		_smoothed_sh = _target_sh.duplicate()
		_apply_estimate()


func _on_estimate_lost() -> void:
	_has_target = false
	if _light:
		_light.visible = false


## Guard from in-headset bring-up: platforms occasionally serve an all-zero /
## non-finite sample; applying it reads as a black flash.
func _is_estimate_usable(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	spherical_harmonics: PackedVector3Array
) -> bool:
	if not direction_to_light.is_finite() or not primary_intensity.is_finite():
		return false
	var intensity_peak := maxf(primary_intensity.x, maxf(primary_intensity.y, primary_intensity.z))
	var sh_energy := 0.0
	for coefficient in spherical_harmonics:
		if not coefficient.is_finite():
			return false
		sh_energy += coefficient.length_squared()
	return intensity_peak > 0.0001 or sh_energy > 0.000001


## Stop following the estimate while false: the sky and light HOLD their last
## values (a "frozen" comparison mode). Data keeps streaming, so re-enabling
## snaps back to live.
var enabled := true

func _process(delta: float) -> void:
	if not _has_target or not enabled:
		return
	var blend := 1.0 - exp(-delta * responsiveness)
	_smoothed_direction = _smoothed_direction.lerp(_target_direction, blend).normalized()
	_smoothed_intensity = _smoothed_intensity.lerp(_target_intensity, blend)
	if _smoothed_sh.size() != _target_sh.size():
		_smoothed_sh = _target_sh.duplicate()
	else:
		for index in _target_sh.size():
			_smoothed_sh[index] = _smoothed_sh[index].lerp(_target_sh[index], blend)
	_apply_estimate()
	estimate_applied.emit(_smoothed_direction, _smoothed_intensity, _smoothed_sh)


## Restore neutral lighting (the sky template's defaults, estimated light
## hidden) - a "no room estimate" comparison baseline. Pair with enabled=false
## or the next live sample re-applies.
func reset_to_neutral() -> void:
	if _sky_material:
		var neutral := _SKY_TEMPLATE as ShaderMaterial
		for index in 9:
			_sky_material.set_shader_parameter("sh%d" % index, neutral.get_shader_parameter("sh%d" % index))
	if _light:
		_light.visible = false


func _apply_estimate() -> void:
	if _sky_material:
		for index in mini(9, _smoothed_sh.size()):
			_sky_material.set_shader_parameter("sh%d" % index, _smoothed_sh[index])
	if _light == null:
		return
	_light.visible = true
	# Hue and brightness are separate quantities (dividing dim estimates by 1.0
	# would read nearly black).
	var peak := maxf(0.0, maxf(_smoothed_intensity.x, maxf(_smoothed_intensity.y, _smoothed_intensity.z)))
	var normalized := _smoothed_intensity / maxf(peak, 0.0001)
	_light.light_color = Color(
		clampf(normalized.x, 0.08, 1.0),
		clampf(normalized.y, 0.08, 1.0),
		clampf(normalized.z, 0.08, 1.0)
	)
	_light.light_energy = clampf(sqrt(peak), 0.3, 5.0)
	# Direction convention settled from in-headset ground truth (see
	# LIGHT_ESTIMATION_NOTES.md): the platform's primaryLightDirection is the
	# direction the light TRAVELS (source at -direction), so the light's -Z aims
	# along it.
	if _smoothed_direction.length_squared() > 0.000001:
		var up := Vector3.UP if absf(_smoothed_direction.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
		_light.global_transform.basis = Basis.looking_at(_smoothed_direction, up)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not Engine.is_editor_hint():
		return warnings
	var world_env := _find_world_environment()
	if world_env and world_env.environment and world_env.environment.sky != null:
		warnings.append("This scene's WorldEnvironment already has a Sky - it will be replaced at runtime by the room-light sky.")
	return warnings
