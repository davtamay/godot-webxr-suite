extends Node3D

## WebXR-enabled material inspector. Drops in the packaged
## godot_webxr_kit rig (one scene = XR origin + ray/direct interactors + manager
## + WebXR adapter, fully wired), then just adds grabbable material balls. This
## is the "simple to integrate" path: a project instances the rig and adds its
## own XRGrabInteractables — no manual node wiring.
##
## Controls:
##   Desktop: LMB-drag = orbit, wheel = zoom, click a ball = grab (screen ray).
##   VR: point a controller/hand ray at a ball, pinch/trigger to grab; two hands to scale.
##   [Enter VR] starts the immersive session. [Tonemap] toggles parity/AgX.

const RIG := preload("res://addons/godot_webxr_kit/rig/webxr_rig.tscn")
const StrictParityEnvironment := preload("res://addons/godot_blender_principled/runtime/strict_parity_environment.gd")
const PrincipledMaterial := preload("res://addons/godot_blender_principled/runtime/principled_material.gd")
const XRGrabInteractable := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_grab_interactable.gd")
const HandVisualizer := preload("res://addons/godot_xr_hands/runtime/hand_visualizer.gd")

const COLLECTION := "res://addons/godot_blender_principled/samples/assets/MaterialCollection.glb"
const BALL_RADIUS := 0.14

var _pivot := Vector3(0, 1.1, -1.4)
var _yaw := 0.0
var _pitch := -0.15
var _distance := 2.2
var _dragging := false

var _origin: XROrigin3D
var _camera: XRCamera3D
var _world_env: WorldEnvironment
var _stand: MeshInstance3D
var _nice := false
var _status: Label
var _webxr: XRInterface
var _vr_supported := false
var _ar_supported := false
var _requested_mode := ""
var _base_clear_color := Color(0, 0, 0, 1)

func _ready() -> void:
	# Anti-alias the silhouettes so ball/edge outlines don't shimmer ("tweak") in XR.
	get_viewport().msaa_3d = Viewport.MSAA_4X

	_world_env = WorldEnvironment.new()
	_world_env.environment = StrictParityEnvironment.parity_environment()
	add_child(_world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.5
	add_child(sun)

	_build_stand()

	# The entire XR interaction setup — one instanced rig scene. The rig resets
	# the origin to this standing pose when a session starts (faces the stand).
	var rig := RIG.instantiate()
	rig.start_position = Vector3(0, 0, 0.5)
	add_child(rig)
	_origin = rig.get_node("XROrigin3D")
	_camera = rig.get_node("XROrigin3D/XRCamera3D")
	# This scene drives its own orbit camera (below); disable the rig's built-in
	# flatscreen fly-cam so the two don't fight over the same drag input.
	var flatcam := rig.get_node_or_null("FlatscreenCamera")
	if flatcam:
		flatcam.enabled = false

	# Procedural XR hands (auto-resolves the rig controllers).
	_origin.add_child(HandVisualizer.new())

	_spawn_material_balls()
	_build_ui()
	_add_menu_button()
	_setup_webxr()
	_update_camera()

## Optional "back to menu" button when running inside the demo app. Loaded
## dynamically so this sample keeps no hard dependency on the demo (works
## standalone if the addon is used in another project).
func _add_menu_button() -> void:
	var menu_button = load("res://scripts/back_to_menu_button.gd")
	if menu_button:
		add_child(menu_button.new())

func _build_stand() -> void:
	_stand = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.4, 0.08, 1.2)
	_stand.mesh = box
	_stand.position = Vector3(0, 0.9, -1.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	mat.roughness = 0.8
	_stand.material_override = mat
	add_child(_stand)

func _spawn_material_balls() -> void:
	var mats := _collect_materials()
	var per_row := 6
	var spacing := 0.4
	for i in mats.size():
		var col := i % per_row
		var row := i / per_row
		var x := (col - (per_row - 1) / 2.0) * spacing
		var z := -1.4 + (row - 0.5) * spacing
		_make_grabbable_ball(mats[i], Vector3(x, 1.1, z))

func _make_grabbable_ball(material: Material, pos: Vector3) -> void:
	var grab := XRGrabInteractable.new()
	grab.position = pos
	grab.track_rotation = true
	grab.movement_type = XRGrabInteractable.MovementType.KINEMATIC_SMOOTH
	grab.two_hand_grab_enabled = true
	grab.two_hand_scale = true
	add_child(grab)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	mesh.mesh = sphere
	# Keep the material's authentic UV tiling. The sparkle at high tile counts is
	# grazing-angle texture aliasing; the GLB textures import WITHOUT mipmaps, so
	# nothing minifies the detail. Fix = give the preview copy mipmapped textures +
	# anisotropic filtering, leaving the shared parity material untouched.
	mesh.material_override = _preview_material(material)
	grab.add_child(mesh)

	var body := StaticBody3D.new()
	body.name = "Body"
	grab.add_child(body)
	var shape := CollisionShape3D.new()
	var col := SphereShape3D.new()
	col.radius = BALL_RADIUS
	shape.shape = col
	body.add_child(shape)

	var label := Label3D.new()
	label.text = material.resource_name if material.resource_name != "" else "material"
	label.font_size = 28
	label.pixel_size = 0.0015
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, BALL_RADIUS + 0.08, 0)
	grab.add_child(label)

## Returns a preview copy of the material with mipmapped textures + anisotropic
## filtering, so the authentic (high) UV tiling no longer aliases into sparkle.
## The original (shared, lossless, mipmap-free) material is left untouched.
func _preview_material(source: Material) -> Material:
	if not (source is StandardMaterial3D):
		return source
	var m: StandardMaterial3D = source.duplicate()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for prop in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "ao_texture", "emission_texture"]:
		var tex = m.get(prop)
		if tex is Texture2D:
			var img: Image = tex.get_image()
			if img and not img.is_compressed() and not img.has_mipmaps():
				img.generate_mipmaps()
				m.set(prop, ImageTexture.create_from_image(img))
	return m

func _collect_materials() -> Array:
	var out := []
	var packed := load(COLLECTION) as PackedScene
	if packed:
		var root := packed.instantiate()
		var stack := [root]
		while not stack.is_empty():
			var n = stack.pop_back()
			if n is MeshInstance3D and n.mesh:
				for i in n.mesh.get_surface_count():
					var m: Material = n.mesh.surface_get_material(i)
					if m and not out.has(m):
						out.append(m)
			for c in n.get_children():
				stack.append(c)
		root.free()
	for pair in [[0.0, 0.2], [1.0, 0.35]]:
		var pm := PrincipledMaterial.new()
		pm.base_color = Color(0.8, 0.35, 0.2)
		pm.metallic = pair[0]
		pm.roughness = pair[1]
		pm.resource_name = "Principled M%.1f R%.2f" % [pair[0], pair[1]]
		out.append(pm)
	return out

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := VBoxContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_constant_override("separation", 8)
	layer.add_child(panel)

	var title := Label.new()
	title.text = "Material Inspector — grab a ball to inspect"
	panel.add_child(title)

	_status = Label.new()
	_status.text = "Desktop: drag orbit, wheel zoom, click a ball to grab."
	panel.add_child(_status)

	var enter := Button.new()
	enter.text = "Enter VR"
	enter.custom_minimum_size = Vector2(160, 44)
	enter.pressed.connect(_on_enter_vr)
	panel.add_child(enter)

	var enter_ar := Button.new()
	enter_ar.text = "Enter AR (passthrough)"
	enter_ar.custom_minimum_size = Vector2(200, 44)
	enter_ar.pressed.connect(_on_enter_ar)
	panel.add_child(enter_ar)

	var tonemap := Button.new()
	tonemap.text = "Toggle tonemap (parity / AgX)"
	tonemap.custom_minimum_size = Vector2(220, 44)
	tonemap.pressed.connect(_toggle_tonemap)
	panel.add_child(tonemap)

func _toggle_tonemap() -> void:
	_nice = not _nice
	_world_env.environment = StrictParityEnvironment.nice_environment() if _nice else StrictParityEnvironment.parity_environment()

func _setup_webxr() -> void:
	_base_clear_color = RenderingServer.get_default_clear_color()
	if not OS.has_feature("web"):
		return
	_webxr = XRServer.find_interface("WebXR")
	if _webxr == null:
		return
	_webxr.session_supported.connect(_on_session_supported)
	_webxr.session_started.connect(_on_session_started)
	_webxr.session_ended.connect(_on_session_ended)
	_webxr.is_session_supported("immersive-vr")
	_webxr.is_session_supported("immersive-ar")

func _on_session_supported(mode: String, supported: bool) -> void:
	if mode == "immersive-vr":
		_vr_supported = supported
	elif mode == "immersive-ar":
		_ar_supported = supported
	_set_status("VR %s | AR %s" % ["ok" if _vr_supported else "no", "ok" if _ar_supported else "no"])

func _on_enter_vr() -> void:
	_start_session("immersive-vr", _vr_supported)

func _on_enter_ar() -> void:
	_start_session("immersive-ar", _ar_supported)

func _start_session(mode: String, supported: bool) -> void:
	if _webxr == null or not supported:
		_set_status("WebXR %s not available here." % mode)
		return
	_requested_mode = mode
	_webxr.session_mode = mode
	_webxr.requested_reference_space_types = "local-floor, local" if mode == "immersive-ar" else "bounded-floor, local-floor, local"
	_webxr.required_features = "layers"
	_webxr.optional_features = "local-floor, bounded-floor, hand-tracking"
	if not _webxr.initialize():
		_requested_mode = ""
		_set_status("WebXR initialize() failed for %s." % mode)

func _on_session_started() -> void:
	get_viewport().use_xr = true
	# The rig self-heals the origin to its start pose on session start, so the
	# user faces the stand at floor height (no manual reset needed here).
	_apply_ar_mode(_requested_mode == "immersive-ar")
	_set_status("%s session started." % ("AR" if _requested_mode == "immersive-ar" else "VR"))

func _on_session_ended() -> void:
	get_viewport().use_xr = false
	_apply_ar_mode(false)
	_requested_mode = ""
	_set_status("session ended.")
	_update_camera()

func _apply_ar_mode(enabled: bool) -> void:
	# Passthrough: clear to transparent so the real world shows behind the
	# floating material balls; hide the solid stand so it doesn't occlude the room.
	get_viewport().transparent_bg = enabled
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0) if enabled else _base_clear_color)
	if _world_env:
		_world_env.environment.background_mode = Environment.BG_CLEAR_COLOR if enabled else Environment.BG_COLOR
	if _stand:
		_stand.visible = not enabled

func _set_status(text: String) -> void:
	if _status:
		_status.text = text
	print(text)

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(0.6, _distance - 0.15)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(6.0, _distance + 0.15)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.008, -1.3, 1.3)
		_update_camera()

func _update_camera() -> void:
	if _origin == null or _camera == null or get_viewport().use_xr:
		return
	# Place the (rig) XR camera at the orbit position looking at the stand, then
	# derive the origin transform that puts the camera there (camera has a local
	# eye-height offset in the rig).
	var dir := Vector3(cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw))
	var cam_pos := _pivot + dir * _distance
	var cam_global := Transform3D(Basis.IDENTITY, cam_pos).looking_at(_pivot, Vector3.UP)
	_origin.global_transform = cam_global * _camera.transform.affine_inverse()
