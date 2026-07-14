extends Node3D

## Demonstrates the rendering-side use of WebXR light estimates. Acquisition
## stays in webxr_light_estimation_bridge.gd; this scene owns the subjective
## mapping from standardized data to Godot lights, materials, and diagnostics.

const LIGHT_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/light_estimation_material.tres")
const XR_GRAB_INTERACTABLE := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_grab_interactable.gd")

enum DisplayMode { LIVE, FROZEN, NEUTRAL }

@onready var _bridge: Node = $XROrigin3D/LightEstimationBridge
@onready var _fallback_light: DirectionalLight3D = $FallbackLight
@onready var _estimated_light: DirectionalLight3D = $EstimatedLight
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _hero_mount: Node3D = $LightLab/HeroMount
@onready var _light_arrow: Node3D = $LightLab/LightDirectionArrow
@onready var _world_status: Label3D = $LightLab/StatusLabel
@onready var _screen_status: Label = %DemoStatus
@onready var _mode_label: Label3D = $LightLab/ModeLabel
@onready var _controls = $XRUIPanel/Viewport/Root
@onready var _rgb_bars: Array[MeshInstance3D] = [
	$LightLab/LightMeter/Red,
	$LightLab/LightMeter/Green,
	$LightLab/LightMeter/Blue,
]

var _material: ShaderMaterial
var _status_accum := 0.0
var _display_mode := DisplayMode.LIVE
var _has_target := false
var _target_direction := Vector3.UP
var _target_intensity := Vector3.ZERO
var _target_sh := PackedVector3Array()
var _smoothed_direction := Vector3.UP
var _smoothed_intensity := Vector3.ZERO
var _smoothed_sh := PackedVector3Array()
var _sh_pips: Array[MeshInstance3D] = []
var _hero_mesh: MeshInstance3D
var _estimate_degraded := false


func _ready() -> void:
	const MENU_BUTTON := "res://scripts/back_to_menu_button.gd"
	if ResourceLoader.exists(MENU_BUTTON):
		var menu_button = load(MENU_BUTTON)
		if menu_button:
			add_child(menu_button.new())

	_material = LIGHT_MATERIAL.duplicate() as ShaderMaterial
	_build_hero_object()
	_prepare_telemetry()
	_controls.material_values_changed.connect(_on_material_values_changed)
	_controls.display_mode_changed.connect(_on_display_mode_changed)
	_bridge.estimate_updated.connect(_on_estimate_updated)
	_bridge.estimate_lost.connect(_on_estimate_lost)
	_on_material_values_changed({
		"metallic": 0.0,
		"roughness": 0.08,
		"base_color": Color.from_hsv(0.57, 0.72, 0.95),
		"gain": 1.0,
		"reflection": 0.9,
		"reflection_enabled": true,
	})
	_apply_fallback()
	_update_mode_label()


func _process(delta: float) -> void:
	if _display_mode == DisplayMode.LIVE and _has_target:
		_update_smoothed_estimate(delta)
	_status_accum += delta
	if _status_accum < 0.2:
		return
	_status_accum = 0.0
	var status := "Mode: %s - grab the hero object and tune its material on the XR panel.\n" % _mode_name()
	status += str(_bridge.get_status())
	if _bridge.has_live_estimate():
		var direction: Vector3 = _bridge.get_primary_direction()
		var intensity: Vector3 = _bridge.get_primary_intensity()
		status += "\nTo light: (%+.2f, %+.2f, %+.2f)  RGB: (%.2f, %.2f, %.2f)" % [
			direction.x, direction.y, direction.z,
			intensity.x, intensity.y, intensity.z,
		]
	status += "\n" + str(_bridge.get_reflection_status())
	if _estimate_degraded:
		status += "\nEstimate sample was empty or invalid; retaining the safe visible fallback."
	_world_status.text = status
	_screen_status.text = status
	if _controls.has_method("set_runtime_status"):
		_controls.set_runtime_status("%s | %s" % [_mode_name(), str(_bridge.get_status())])


func _build_hero_object() -> void:
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.31
	sphere_mesh.height = 0.62
	sphere_mesh.radial_segments = 48
	sphere_mesh.rings = 24
	var grab := XR_GRAB_INTERACTABLE.new()
	grab.name = "HeroMaterial"
	grab.movement_type = XR_GRAB_INTERACTABLE.MovementType.KINEMATIC_SMOOTH
	grab.smoothing_speed = 16.0
	grab.track_rotation = true
	grab.two_hand_grab_enabled = true
	grab.two_hand_scale = true
	_hero_mount.add_child(grab)

	_hero_mesh = MeshInstance3D.new()
	_hero_mesh.name = "Mesh"
	_hero_mesh.mesh = sphere_mesh
	_hero_mesh.material_override = _material
	_hero_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	grab.add_child(_hero_mesh)

	var body := StaticBody3D.new()
	body.name = "InteractableBody"
	grab.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.33
	collision.shape = shape
	body.add_child(collision)


func _on_estimate_updated(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	spherical_harmonics: PackedVector3Array
) -> void:
	# Some runtimes briefly expose a light estimate containing zeroed values
	# while the probe is warming up. Never let that transient packet disable
	# the readable fallback and turn the entire demonstration black.
	if not _is_estimate_usable(direction_to_light, primary_intensity, spherical_harmonics):
		_estimate_degraded = true
		if not _has_target:
			_apply_fallback()
		return
	_estimate_degraded = false
	_target_direction = direction_to_light.normalized()
	_target_intensity = primary_intensity
	_target_sh = spherical_harmonics.duplicate()
	if not _has_target:
		_has_target = true
		_smoothed_direction = _target_direction
		_smoothed_intensity = _target_intensity
		_smoothed_sh = _target_sh.duplicate()
		if _display_mode == DisplayMode.LIVE:
			_apply_estimate(_smoothed_direction, _smoothed_intensity, _smoothed_sh)


func _update_smoothed_estimate(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 5.5)
	_smoothed_direction = _smoothed_direction.lerp(_target_direction, blend).normalized()
	_smoothed_intensity = _smoothed_intensity.lerp(_target_intensity, blend)
	if _smoothed_sh.size() != _target_sh.size():
		_smoothed_sh = _target_sh.duplicate()
	else:
		for index in range(_smoothed_sh.size()):
			_smoothed_sh[index] = _smoothed_sh[index].lerp(_target_sh[index], blend)
	_apply_estimate(_smoothed_direction, _smoothed_intensity, _smoothed_sh)


func _apply_estimate(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	spherical_harmonics: PackedVector3Array
) -> void:
	_fallback_light.visible = false
	_estimated_light.visible = true

	# Hue and brightness are separate quantities. Dividing sub-1.0 intensity
	# values by 1.0 made otherwise valid dim-room estimates nearly black.
	var intensity_scalar := maxf(0.0, maxf(primary_intensity.x, maxf(primary_intensity.y, primary_intensity.z)))
	var normalized_color := primary_intensity / maxf(intensity_scalar, 0.0001)
	_estimated_light.light_color = Color(
		clampf(normalized_color.x, 0.08, 1.0),
		clampf(normalized_color.y, 0.08, 1.0),
		clampf(normalized_color.z, 0.08, 1.0),
		1.0
	)
	_estimated_light.light_energy = clampf(sqrt(intensity_scalar), 0.3, 5.0)

	# WebXR reports the vector pointing TO the real light. Godot's local -Z
	# is the direction the light rays travel, so those vectors are opposite.
	_set_forward(_estimated_light, -direction_to_light)
	_set_forward(_light_arrow, direction_to_light)

	for index in mini(9, spherical_harmonics.size()):
		_material.set_shader_parameter("sh%d" % index, spherical_harmonics[index])
	_update_telemetry(primary_intensity, spherical_harmonics)

	# The complete SH field is evaluated by the probe-sphere shader. A small
	# c0 approximation also keeps the non-probe stage readable.
	if not spherical_harmonics.is_empty() and _world_environment.environment:
		var c0 := Vector3(
			maxf(0.0, spherical_harmonics[0].x),
			maxf(0.0, spherical_harmonics[0].y),
			maxf(0.0, spherical_harmonics[0].z)
		)
		var ambient_scale := maxf(0.001, maxf(c0.x, maxf(c0.y, c0.z)))
		_world_environment.environment.ambient_light_color = Color(
			clampf(c0.x / ambient_scale, 0.08, 1.0),
			clampf(c0.y / ambient_scale, 0.08, 1.0),
			clampf(c0.z / ambient_scale, 0.08, 1.0)
		)
		_world_environment.environment.ambient_light_energy = clampf(sqrt(ambient_scale) * 0.22, 0.16, 0.7)


func _on_estimate_lost() -> void:
	_has_target = false
	_estimate_degraded = false
	_apply_fallback()


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


func _apply_fallback() -> void:
	_fallback_light.visible = true
	_estimated_light.visible = false
	_set_forward(_light_arrow, Vector3(0.35, 0.8, 0.45).normalized())
	for index in range(9):
		_material.set_shader_parameter("sh%d" % index, Vector3(0.7, 0.74, 0.82) if index == 0 else Vector3.ZERO)
	_update_telemetry(Vector3.ZERO, PackedVector3Array())
	if _world_environment.environment:
		_world_environment.environment.ambient_light_color = Color(0.66, 0.7, 0.78)
		_world_environment.environment.ambient_light_energy = 0.45


func _prepare_telemetry() -> void:
	var coefficient_root := get_node_or_null("LightLab/SHCoefficients")
	if coefficient_root:
		for child in coefficient_root.get_children():
			if child is MeshInstance3D:
				var pip := child as MeshInstance3D
				var source_material := pip.get_active_material(0)
				if source_material:
					pip.material_override = source_material.duplicate()
				_sh_pips.append(pip)


func _update_telemetry(primary_intensity: Vector3, spherical_harmonics: PackedVector3Array) -> void:
	var channels := [primary_intensity.x, primary_intensity.y, primary_intensity.z]
	for index in range(mini(_rgb_bars.size(), channels.size())):
		# Light-estimate intensities are unbounded. A square-root display keeps
		# dim rooms readable without allowing bright rooms to peg the meter.
		var amount := clampf(sqrt(maxf(0.0, channels[index])) / 2.2, 0.035, 1.0)
		_rgb_bars[index].scale.y = amount
		_rgb_bars[index].position.y = -0.46 + amount * 0.42

	for index in range(_sh_pips.size()):
		var coefficient := spherical_harmonics[index] if index < spherical_harmonics.size() else Vector3.ZERO
		var magnitude := coefficient.length()
		var color_vector := coefficient.abs()
		var color_peak := maxf(0.001, maxf(color_vector.x, maxf(color_vector.y, color_vector.z)))
		var color := Color(
			color_vector.x / color_peak,
			color_vector.y / color_peak,
			color_vector.z / color_peak,
			1.0
		)
		var size := 0.45 + clampf(sqrt(magnitude) * 0.42, 0.0, 0.8)
		_sh_pips[index].scale = Vector3.ONE * size
		var material := _sh_pips[index].material_override as StandardMaterial3D
		if material:
			material.albedo_color = color.darkened(0.18) if magnitude > 0.0001 else Color(0.08, 0.1, 0.13)
			material.emission = color if magnitude > 0.0001 else Color(0.015, 0.02, 0.025)
			material.emission_energy_multiplier = 0.7 + clampf(magnitude, 0.0, 2.5)


func _on_material_values_changed(values: Dictionary) -> void:
	if _hero_mesh == null:
		return
	_hero_mesh.set_instance_shader_parameter("base_color", values.get("base_color", Color.WHITE))
	_hero_mesh.set_instance_shader_parameter("material_metallic", float(values.get("metallic", 0.0)))
	_hero_mesh.set_instance_shader_parameter("material_roughness", float(values.get("roughness", 0.5)))
	_hero_mesh.set_instance_shader_parameter("sh_gain", float(values.get("gain", 1.0)))
	var reflection := float(values.get("reflection", 0.5)) if bool(values.get("reflection_enabled", true)) else 0.0
	_hero_mesh.set_instance_shader_parameter("reflection_strength", reflection)


func _on_display_mode_changed(mode: int) -> void:
	_display_mode = clampi(mode, DisplayMode.LIVE, DisplayMode.NEUTRAL)
	match _display_mode:
		DisplayMode.LIVE:
			if _has_target:
				_apply_estimate(_smoothed_direction, _smoothed_intensity, _smoothed_sh)
			else:
				_apply_fallback()
		DisplayMode.NEUTRAL:
			_apply_fallback()
		DisplayMode.FROZEN:
			pass
	_update_mode_label()


func _update_mode_label() -> void:
	match _display_mode:
		DisplayMode.LIVE:
			_mode_label.text = "LIVE ROOM LIGHT\nTune the hero material on the XR panel"
		DisplayMode.FROZEN:
			_mode_label.text = "FROZEN SNAPSHOT\nMaterial controls remain interactive"
		DisplayMode.NEUTRAL:
			_mode_label.text = "NEUTRAL BASELINE\nCompare without the room estimate"


func _mode_name() -> String:
	match _display_mode:
		DisplayMode.FROZEN:
			return "FROZEN"
		DisplayMode.NEUTRAL:
			return "NEUTRAL"
		_:
			return "LIVE"


func _set_forward(node: Node3D, forward: Vector3) -> void:
	if forward.length_squared() < 0.000001:
		return
	var normalized := forward.normalized()
	var up := Vector3.UP
	if absf(normalized.dot(up)) > 0.98:
		up = Vector3.FORWARD
	node.basis = Basis.looking_at(normalized, up)
