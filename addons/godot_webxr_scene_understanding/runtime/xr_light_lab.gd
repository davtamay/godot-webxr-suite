@icon("res://addons/godot_webxr_scene_understanding/icons/light_estimation_manager.svg")
class_name XRLightLab
extends Node3D

## Drop-in environmental-light lab: a grabbable hero sphere whose material you
## tune live, a colour swatch of the estimated room light, and an arrow that
## points at the main light source - all driven by a LightEstimationManager.
##
## This is the light-estimation demo's dressing, packaged as ONE droppable block
## so it can share a scene with other perception blocks. Point it at a manager
## and (optionally) a material-controls panel; it builds the hero object under
## its HeroMount child and wires the telemetry itself. The actual lighting work
## (SH sky, primary light, smoothing, the -travel-direction convention) stays in
## the manager - see LIGHT_ESTIMATION_NOTES.md.
##
## Expected children (built into the scene): HeroMount, LightMeter/Swatch,
## LightDirectionArrow, StatusLabel, ModeLabel.

const LIGHT_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/light_estimation_material.tres")
const XR_GRAB_INTERACTABLE := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_grab_interactable.gd")

enum DisplayMode { LIVE, FROZEN, NEUTRAL }

## The LightEstimationManager driving this lab.
@export var manager_path: NodePath
## A material-controls panel (a Control emitting material_values_changed /
## display_mode_changed, e.g. light_estimation_controls.gd). Optional.
@export var controls_path: NodePath
## A directional light the lab shows when there is no live estimate (readable
## fallback). Optional.
@export var fallback_light_path: NodePath

var _manager: Node
var _controls: Node
var _fallback_light: DirectionalLight3D
var _hero_mount: Node3D
var _light_arrow: Node3D
var _world_status: Label3D
var _mode_label: Label3D
var _color_swatch: MeshInstance3D

var _material: ShaderMaterial
var _hero_mesh: MeshInstance3D
var _swatch_material: StandardMaterial3D
var _status_accum := 0.0
var _display_mode := DisplayMode.LIVE
var _was_live := false
var _last_source_direction := Vector3.ZERO  # points AT the source (-travel dir)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_manager = get_node_or_null(manager_path)
	_controls = get_node_or_null(controls_path)
	_fallback_light = get_node_or_null(fallback_light_path) as DirectionalLight3D
	_hero_mount = get_node_or_null("HeroMount")
	_light_arrow = get_node_or_null("LightDirectionArrow")
	_world_status = get_node_or_null("StatusLabel")
	_mode_label = get_node_or_null("ModeLabel")
	_color_swatch = get_node_or_null("LightMeter/Swatch")

	_material = LIGHT_MATERIAL.duplicate() as ShaderMaterial
	_build_hero_object()
	_prepare_telemetry()

	if _controls:
		if _controls.has_signal("material_values_changed"):
			_controls.material_values_changed.connect(_on_material_values_changed)
		if _controls.has_signal("display_mode_changed"):
			_controls.display_mode_changed.connect(_on_display_mode_changed)
	if _manager and _manager.has_signal("estimate_applied"):
		_manager.estimate_applied.connect(_on_estimate_applied)

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
	if _manager == null:
		return
	_status_accum += delta
	if _status_accum < 0.2:
		return
	_status_accum = 0.0
	var live: bool = _manager.has_live_estimate()
	if _was_live and not live and _display_mode == DisplayMode.LIVE:
		_apply_fallback()
	_was_live = live
	_update_status_banner()


func _update_status_banner() -> void:
	if _world_status == null:
		return
	var text := ""
	var color := Color(0.78, 0.94, 1.0)
	var font_size := 28
	if _manager.has_live_estimate():
		text = "READING YOUR ROOM'S LIGHT\nThese objects are lit by your real room."
		if _last_source_direction.length_squared() > 0.000001:
			text += "\nlight from: (%+.2f, %+.2f, %+.2f)" % [
				_last_source_direction.x, _last_source_direction.y, _last_source_direction.z]
		color = Color(0.45, 1.0, 0.55)
	else:
		match str(_manager.get_state()):
			"not-granted", "api-unavailable", "unavailable", "no-bridge":
				text = "✕ NOT AVAILABLE ON THIS HEADSET\nLight estimation is an Android XR / ARCore feature.\nQuest 3 does not support it - nothing here will react."
				color = Color(1.0, 0.4, 0.25)
				font_size = 36
			"requesting-probe", "probe-ready", "waiting-estimate", "live":
				text = "WARMING UP...\nWaiting for the first light estimate (about a second)."
			_:
				text = "ENTER AR\nStep into AR to light these objects with your real room."
	_world_status.text = text
	_world_status.modulate = color
	_world_status.font_size = font_size
	if _controls and _controls.has_method("set_runtime_status"):
		_controls.set_runtime_status("%s | %s" % [_mode_name(), str(_manager.get_status())])


func _build_hero_object() -> void:
	if _hero_mount == null:
		return
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


func _on_estimate_applied(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	_spherical_harmonics: PackedVector3Array
) -> void:
	if _fallback_light:
		_fallback_light.visible = false
	if direction_to_light.length_squared() > 0.000001:
		_last_source_direction = -direction_to_light.normalized()
		_set_forward(_light_arrow, -direction_to_light)
	_update_telemetry(primary_intensity)


func _apply_fallback() -> void:
	if _fallback_light:
		_fallback_light.visible = true
	_last_source_direction = Vector3.ZERO
	_set_forward(_light_arrow, Vector3(0.35, 0.8, 0.45).normalized())
	_update_telemetry(Vector3.ZERO)


func _prepare_telemetry() -> void:
	if _color_swatch == null:
		return
	var mat := _color_swatch.get_active_material(0)
	if mat is StandardMaterial3D:
		_swatch_material = (mat as StandardMaterial3D).duplicate()
		_color_swatch.material_override = _swatch_material


func _update_telemetry(primary_intensity: Vector3) -> void:
	if _swatch_material == null:
		return
	var peak := maxf(primary_intensity.x, maxf(primary_intensity.y, primary_intensity.z))
	if peak > 0.0001:
		_swatch_material.albedo_color = Color(
			primary_intensity.x / peak, primary_intensity.y / peak, primary_intensity.z / peak, 1.0)
	else:
		_swatch_material.albedo_color = Color(0.6, 0.6, 0.62, 1.0)


func _on_material_values_changed(values: Dictionary) -> void:
	if _hero_mesh == null:
		return
	_hero_mesh.set_instance_shader_parameter("base_color", values.get("base_color", Color.WHITE))
	_hero_mesh.set_instance_shader_parameter("material_metallic", float(values.get("metallic", 0.0)))
	_hero_mesh.set_instance_shader_parameter("material_roughness", float(values.get("roughness", 0.5)))
	if _manager:
		_manager.sky_intensity = float(values.get("gain", 1.0))
	var reflection := float(values.get("reflection", 0.5)) if bool(values.get("reflection_enabled", true)) else 0.0
	_hero_mesh.set_instance_shader_parameter("reflection_strength", reflection)


func _on_display_mode_changed(mode: int) -> void:
	_display_mode = clampi(mode, DisplayMode.LIVE, DisplayMode.NEUTRAL)
	if _manager:
		match _display_mode:
			DisplayMode.LIVE:
				_manager.enabled = true
				if not _manager.has_live_estimate():
					_apply_fallback()
			DisplayMode.FROZEN:
				_manager.enabled = false
			DisplayMode.NEUTRAL:
				_manager.enabled = false
				_manager.reset_to_neutral()
				_apply_fallback()
	_update_mode_label()


func _update_mode_label() -> void:
	if _mode_label == null:
		return
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
	if node == null or forward.length_squared() < 0.000001:
		return
	var normalized := forward.normalized()
	var up := Vector3.UP
	if absf(normalized.dot(up)) > 0.98:
		up = Vector3.FORWARD
	node.basis = Basis.looking_at(normalized, up)
