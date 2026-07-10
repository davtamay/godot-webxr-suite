extends Node3D

## Interactive VR stress benchmark. Pick a content kind and toggle individual
## performance-hit types, then ramp (or step) the model count and watch where the
## frame rate drops below the VR target (72 Hz). A world-space HUD (follows your
## gaze) shows live FPS / frame-ms / draw calls / primitives / memory.
##
## Configure in the flat view, then Enter VR to read the real stereo ceiling.
## Controls (2D buttons, usable in the flat browser view):
##   Kind:    Unique mesh+material / Unique shared-material / MultiMesh instanced
##   Hits:    Transparency (overdraw), Dynamic shadows
##   Count:   Auto-ramp to 72 Hz, +512, -512, Clear

const RIG := preload("res://addons/godot_webxr_kit/rig/xr_webxr_rig.tscn")

## Preloaded so the shader baker can precompile it for web/WebGPU exports
## (the opaque combos below match the always-baked default material).
const TRANSPARENT_MATERIAL := preload("res://addons/godot_blender_principled/samples/stress_transparent_material.tres")

const TARGET_FPS := 72.0
const RAMP_STEP := 512
const STEP := 512
const RAMP_INTERVAL := 0.8
const MAX_N := 40000
const GRID_SPACING := 0.55

enum Kind { UNIQUE, SHARED, INSTANCED }

var _camera: XRCamera3D
var _hud: Label3D
var _status: Label
var _webxr: XRInterface
var _vr_supported := false

# config
var _kind := Kind.UNIQUE
var _transparent := false
var _shadows := false
var _auto_ramp := false

# state
var _current_n := 0
var _last_pass_n := 0
var _elapsed := 0.0
var _ceiling_text := ""

var _content_root: Node3D
var _sun: DirectionalLight3D
var _box := BoxMesh.new()
var _shared_material: StandardMaterial3D
var _multimesh: MultiMesh
var _multimesh_instance: MultiMeshInstance3D
var _kind_buttons := {}
var _transp_button: Button
var _shadow_button: Button
var _autoramp_button: Button

func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.4)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-55, -35, 0)
	_sun.light_energy = 1.4
	_sun.shadow_enabled = false
	add_child(_sun)

	_box.size = Vector3(0.28, 0.28, 0.28)
	_shared_material = StandardMaterial3D.new()
	_shared_material.albedo_color = Color(0.5, 0.7, 1.0)
	_shared_material.roughness = 0.5

	_content_root = Node3D.new()
	add_child(_content_root)

	var rig := RIG.instantiate()
	rig.start_yaw_degrees = 180.0
	add_child(rig)
	_camera = rig.get_node("XROrigin3D/XRCamera3D")

	_hud = Label3D.new()
	_hud.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_hud.font_size = 40
	_hud.outline_size = 8
	_hud.pixel_size = 0.0016
	_hud.modulate = Color(0.9, 1.0, 0.9)
	_hud.position = Vector3(0, -0.15, -1.4)
	_camera.add_child(_hud)

	_build_ui()
	var menu_button = load("res://scripts/back_to_menu_button.gd")
	if menu_button:
		add_child(menu_button.new())
	_setup_webxr()
	_update_button_states()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := VBoxContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_constant_override("separation", 6)
	layer.add_child(panel)

	var title := Label.new()
	title.text = "VR Stress Benchmark — pick hit types, then Enter VR"
	panel.add_child(title)
	_status = Label.new()
	_status.text = "target 72 Hz  ·  flat: drag to look, WASD/QE to move"
	panel.add_child(_status)

	_button(panel, "Enter VR", func() -> void: _on_enter_vr())

	panel.add_child(_section("Content kind"))
	_kind_buttons[Kind.UNIQUE] = _button(panel, "Unique mesh + material", func() -> void: _set_kind(Kind.UNIQUE))
	_kind_buttons[Kind.SHARED] = _button(panel, "Unique mesh, shared material", func() -> void: _set_kind(Kind.SHARED))
	_kind_buttons[Kind.INSTANCED] = _button(panel, "MultiMesh instanced", func() -> void: _set_kind(Kind.INSTANCED))

	panel.add_child(_section("Extra hit types"))
	_transp_button = _button(panel, "Transparency (overdraw)", func() -> void: _toggle_transparency())
	_shadow_button = _button(panel, "Dynamic shadows", func() -> void: _toggle_shadows())

	panel.add_child(_section("Count"))
	_autoramp_button = _button(panel, "Auto-ramp to 72 Hz", func() -> void: _toggle_autoramp())
	_button(panel, "+%d" % STEP, func() -> void: _add_batch(STEP))
	_button(panel, "-%d" % STEP, func() -> void: _remove_batch(STEP))
	_button(panel, "Clear", func() -> void: _clear())

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = "— %s —" % text
	return l

func _button(parent: Node, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 40)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b

# --------------------------------------------------------------- config -------

func _set_kind(kind: Kind) -> void:
	_kind = kind
	_clear()

func _toggle_transparency() -> void:
	_transparent = not _transparent
	_clear()

func _toggle_shadows() -> void:
	_shadows = not _shadows
	_sun.shadow_enabled = _shadows
	_update_button_states()

func _toggle_autoramp() -> void:
	_auto_ramp = not _auto_ramp
	_elapsed = 0.0
	if _auto_ramp:
		_ceiling_text = ""
		_last_pass_n = _current_n
	_update_button_states()

func _update_button_states() -> void:
	for k in _kind_buttons:
		_kind_buttons[k].button_pressed = false
		(_kind_buttons[k] as Button).modulate = Color(0.6, 1.0, 0.6) if k == _kind else Color.WHITE
	_transp_button.modulate = Color(0.6, 1.0, 0.6) if _transparent else Color.WHITE
	_shadow_button.modulate = Color(0.6, 1.0, 0.6) if _shadows else Color.WHITE
	_autoramp_button.modulate = Color(1.0, 0.8, 0.4) if _auto_ramp else Color.WHITE

# --------------------------------------------------------------- ramp ---------

func _process(delta: float) -> void:
	if _auto_ramp:
		_elapsed += delta
		if _elapsed >= RAMP_INTERVAL:
			_elapsed = 0.0
			var fps := Engine.get_frames_per_second()
			if fps < TARGET_FPS or _current_n >= MAX_N:
				_ceiling_text = "CEILING: spawned=%d, draws=%d (%.0f fps)" % [_last_pass_n, _draw_calls(), fps]
				print("[stress] " + _config_label() + " " + _ceiling_text)
				_js_log(_config_label() + " " + _ceiling_text)
				_auto_ramp = false
				_update_button_states()
			else:
				_last_pass_n = _current_n
				_add_batch(RAMP_STEP)
	_update_hud()

func _add_batch(count: int) -> void:
	if _kind == Kind.INSTANCED:
		_ensure_multimesh()
		var target := _current_n + count
		_multimesh.instance_count = target
		for i in range(target):
			_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, _position_for(i)))
		_current_n = target
	else:
		for j in range(count):
			var mi := MeshInstance3D.new()
			mi.mesh = _box
			mi.position = _position_for(_current_n + j)
			mi.material_override = _material_for(_current_n + j)
			_content_root.add_child(mi)
		_current_n += count

func _remove_batch(count: int) -> void:
	if _kind == Kind.INSTANCED:
		if _multimesh:
			_current_n = maxi(0, _current_n - count)
			_multimesh.instance_count = _current_n
	else:
		var kids := _content_root.get_children()
		var to_remove := mini(count, kids.size())
		for i in range(to_remove):
			kids[kids.size() - 1 - i].queue_free()
		_current_n = maxi(0, _current_n - to_remove)

func _material_for(index: int) -> StandardMaterial3D:
	if _kind == Kind.SHARED and not _transparent:
		return _shared_material
	var m := (TRANSPARENT_MATERIAL.duplicate() as StandardMaterial3D) if _transparent else StandardMaterial3D.new()
	m.albedo_color = Color.from_hsv(fmod(index * 0.011, 1.0), 0.55, 0.95)
	m.roughness = 0.5
	if _transparent:
		m.albedo_color.a = 0.55
	return m

func _ensure_multimesh() -> void:
	if _multimesh_instance != null:
		return
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = _box
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.material_override = _shared_material
	_content_root.add_child(_multimesh_instance)

func _clear() -> void:
	_auto_ramp = false
	for c in _content_root.get_children():
		c.queue_free()
	_multimesh = null
	_multimesh_instance = null
	_current_n = 0
	_last_pass_n = 0
	_ceiling_text = ""
	_update_button_states()

func _position_for(index: int) -> Vector3:
	var side := int(ceil(pow(maxf(1.0, float(index + 1)), 1.0 / 3.0)))
	var x := index % side
	var y := (index / side) % side
	var z := index / (side * side)
	return Vector3(
		(x - side * 0.5) * GRID_SPACING,
		0.6 + y * GRID_SPACING,
		-2.5 - z * GRID_SPACING)

func _draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))

func _config_label() -> String:
	var kind_names := ["Unique+mat", "Shared-mat", "Instanced"]
	var s: String = kind_names[_kind]
	if _transparent:
		s += "+transp"
	if _shadows:
		s += "+shadows"
	return s

func _update_hud() -> void:
	if _hud == null:
		return
	var fps := Engine.get_frames_per_second()
	var draws := _draw_calls()
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_hud.text = "VR STRESS  (target %.0f Hz)\nconfig: %s%s\nspawned: %d   draw calls: %d\nFPS: %.1f   frame: %.1f ms\nprimitives: %dk   mem: %.0f MB\n%s" % [
		TARGET_FPS, _config_label(), "   [AUTO-RAMP]" if _auto_ramp else "",
		_current_n, draws, fps, 1000.0 / maxf(1.0, fps), prims / 1000, mem, _ceiling_text]

# --------------------------------------------------------------- WebXR --------

func _setup_webxr() -> void:
	if not OS.has_feature("web"):
		return
	_webxr = XRServer.find_interface("WebXR")
	if _webxr == null:
		return
	_webxr.session_supported.connect(_on_session_supported)
	_webxr.session_started.connect(_on_session_started)
	_webxr.session_ended.connect(_on_session_ended)
	_webxr.is_session_supported("immersive-vr")

func _on_session_supported(mode: String, supported: bool) -> void:
	if mode == "immersive-vr":
		_vr_supported = supported

func _on_enter_vr() -> void:
	if _webxr == null or not _vr_supported:
		_set_status("WebXR immersive-vr not available.")
		return
	_webxr.session_mode = "immersive-vr"
	_webxr.requested_reference_space_types = "bounded-floor, local-floor, local"
	_webxr.required_features = "layers"
	_webxr.optional_features = "local-floor, bounded-floor"
	if not _webxr.initialize():
		_set_status("WebXR initialize() failed.")

func _on_session_started() -> void:
	get_viewport().use_xr = true
	_set_status("VR session — measuring in stereo")

func _on_session_ended() -> void:
	get_viewport().use_xr = false
	_set_status("VR ended")

func _set_status(text: String) -> void:
	if _status:
		_status.text = text
	print(text)

func _js_log(line: String) -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js = Engine.get_singleton("JavaScriptBridge")
		js.eval("console.log(%s);" % JSON.stringify("[GodotStress] " + line), true)
