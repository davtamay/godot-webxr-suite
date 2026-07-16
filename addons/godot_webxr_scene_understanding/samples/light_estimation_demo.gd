extends Node3D

## Light-estimation demo scene. All the actual lighting work - SH environment
## sky (ambient + reflections), the estimated primary light, smoothing, the
## direction convention (see LIGHT_ESTIMATION_NOTES.md) - lives in the drop-in
## LightEstimationManager node. This script owns only the demo dressing: the
## grabbable hero material lab, the telemetry (arrow + colour swatch + status
## banner), and the LIVE / FROZEN / NEUTRAL comparison modes.

const LIGHT_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/light_estimation_material.tres")
const XR_GRAB_INTERACTABLE := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_grab_interactable.gd")

enum DisplayMode { LIVE, FROZEN, NEUTRAL }

@onready var _manager = $LightEstimationManager
@onready var _fallback_light: DirectionalLight3D = $FallbackLight
@onready var _hero_mount: Node3D = $LightLab/HeroMount
@onready var _light_arrow: Node3D = $LightLab/LightDirectionArrow
@onready var _world_status: Label3D = $LightLab/StatusLabel
@onready var _screen_status: Label = %DemoStatus
@onready var _mode_label: Label3D = $LightLab/ModeLabel
@onready var _controls = $XRUIPanel/Viewport/Root
@onready var _color_swatch: MeshInstance3D = $LightLab/LightMeter/Swatch

var _material: ShaderMaterial
var _status_accum := 0.0
var _display_mode := DisplayMode.LIVE
var _swatch_material: StandardMaterial3D
var _hero_mesh: MeshInstance3D
var _was_live := false
var _last_source_direction := Vector3.ZERO  # points AT the light source (-travel dir)


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
	_build_renderer_toggle()


func _process(delta: float) -> void:
	_status_accum += delta
	if _status_accum < 0.2:
		return
	_status_accum = 0.0
	# Estimate lost (session end, tracking drop): bring the readable fallback
	# lighting back. The manager hides its own light; the demo owns this one.
	var live: bool = _manager.has_live_estimate()
	if _was_live and not live and _display_mode == DisplayMode.LIVE:
		_apply_fallback()
	_was_live = live
	_update_status_banner()


func _update_status_banner() -> void:
	# ONE unmistakable state - you should never have to hunt for the word "live".
	# Also carries the per-feature "not supported on this headset" message.
	var text := ""
	var color := Color(0.78, 0.94, 1.0)
	var font_size := 28
	if _manager.has_live_estimate():
		text = "READING YOUR ROOM'S LIGHT\nThese objects are lit by your real room."
		# The numeric source direction (world space, unit vector) - handy for
		# checking the arrow against where the real light actually is.
		if _last_source_direction.length_squared() > 0.000001:
			text += "\nlight from: (%+.2f, %+.2f, %+.2f)" % [
				_last_source_direction.x, _last_source_direction.y, _last_source_direction.z]
		color = Color(0.45, 1.0, 0.55)
	else:
		match str(_manager.get_state()):
			"not-granted", "api-unavailable", "unavailable", "no-bridge":
				# Unmissable: bigger + red - this is the demo's whole answer on
				# devices without the feature.
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
	_screen_status.text = text
	_screen_status.modulate = color
	if _controls.has_method("set_runtime_status"):
		_controls.set_runtime_status("%s | %s" % [_mode_name(), str(_manager.get_status())])


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


## Telemetry follows the SAME smoothed values driving the sky and light: the
## arrow points at the real source (-direction; the platform reports the light's
## TRAVEL direction - see LIGHT_ESTIMATION_NOTES.md), the swatch shows its
## colour. Fires only while the manager is enabled, so FROZEN/NEUTRAL freeze the
## telemetry too.
func _on_estimate_applied(
	direction_to_light: Vector3,
	primary_intensity: Vector3,
	_spherical_harmonics: PackedVector3Array
) -> void:
	_fallback_light.visible = false
	if direction_to_light.length_squared() > 0.000001:
		_last_source_direction = -direction_to_light.normalized()
		_set_forward(_light_arrow, -direction_to_light)
	_update_telemetry(primary_intensity)


func _apply_fallback() -> void:
	_fallback_light.visible = true
	_last_source_direction = Vector3.ZERO
	_set_forward(_light_arrow, Vector3(0.35, 0.8, 0.45).normalized())
	_update_telemetry(Vector3.ZERO)


func _prepare_telemetry() -> void:
	# The "room light color" swatch gets its own material instance so we can recolor
	# it live (albedo is a uniform, so the WebGPU-baked shader is reused).
	var mat := _color_swatch.get_active_material(0)
	if mat is StandardMaterial3D:
		_swatch_material = (mat as StandardMaterial3D).duplicate()
		_color_swatch.material_override = _swatch_material


func _update_telemetry(primary_intensity: Vector3) -> void:
	# Show the room's light COLOR on the swatch (normalized hue of the primary
	# intensity) - something a user can actually read (warm lamp vs cool daylight).
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
	_manager.sky_intensity = float(values.get("gain", 1.0))
	var reflection := float(values.get("reflection", 0.5)) if bool(values.get("reflection_enabled", true)) else 0.0
	_hero_mesh.set_instance_shader_parameter("reflection_strength", reflection)


func _on_display_mode_changed(mode: int) -> void:
	_display_mode = clampi(mode, DisplayMode.LIVE, DisplayMode.NEUTRAL)
	match _display_mode:
		DisplayMode.LIVE:
			_manager.enabled = true
			if not _manager.has_live_estimate():
				_apply_fallback()
		DisplayMode.FROZEN:
			_manager.enabled = false  # sky + light + telemetry HOLD their last values
		DisplayMode.NEUTRAL:
			_manager.enabled = false
			_manager.reset_to_neutral()
			_apply_fallback()
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


func _build_renderer_toggle() -> void:
	# A GL <-> WebGPU switch on the flat page. The graphics backend is a boot
	# decision (a canvas is locked to its first context type), so switching saves a
	# localStorage preference and reloads. Shown only where this build can actually
	# run WebGPU-XR, so it never appears as a dead button (WebGL-only builds/browsers
	# get nothing). Lets you compare light estimation on both renderers.
	if not OS.has_feature("web") or not WebXRRenderer.webgpu_supported():
		return
	var layer := CanvasLayer.new()
	layer.name = "RendererToggle"
	layer.layer = 40
	add_child(layer)
	var btn := Button.new()
	btn.text = "Renderer: %s  -  tap to switch" % ("WebGPU" if WebXRRenderer.is_webgpu() else "WebGL")
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_left = -360.0
	btn.offset_top = 14.0
	btn.offset_right = -14.0
	btn.offset_bottom = 58.0
	btn.pressed.connect(func() -> void:
		WebXRRenderer.switch_to("webgl" if WebXRRenderer.is_webgpu() else "webgpu"))
	layer.add_child(btn)
