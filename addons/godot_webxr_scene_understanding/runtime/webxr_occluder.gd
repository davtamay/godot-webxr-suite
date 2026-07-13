extends MeshInstance3D

## Experimental real-world occlusion for AR on the WebGPU backend: feeds the
## headset's depth-sensing texture (exposed by the engine through
## WebXRInterface.get_system_info()) into a fullscreen punch shader that
## reveals passthrough where the real world is closer than virtual content.
##
## Attach under XRCamera3D. Toggle with set_occlusion(); get_status() gives
## honest feedback. The live-sensor path needs the WebGPU renderer AND a
## browser whose XRGPUBinding exposes getDepthInformation() - an upcoming
## feature (Quest Browser 148 does not ship it yet). Until then occlusion
## falls back to the static room mesh. Detection runs only when the button
## is pressed (zero per-frame cost while idle); re-toggle after a browser
## update ships the sensor and this switches to it automatically.

const OCCLUSION_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/occlusion_material.tres")

var occlusion_enabled := false

var _webxr: XRInterface
var _material: ShaderMaterial
var _depth_rd: Texture2DRD
var _sensor_active := false
## Whether we routed a depth bridge into live-depth punch occlusion (dynamic).
var _depth_occluding := false

func _ready() -> void:
	add_to_group("webxr_occluder")
	add_to_group("webxr_feature_provider")

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	# Keep the sort origin at the camera and never let culling drop it.
	extra_cull_margin = 16384.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Duplicate of a baked .tres so the shader is precompiled for web.
	_material = OCCLUSION_MATERIAL.duplicate() as ShaderMaterial
	material_override = _material

	_depth_rd = Texture2DRD.new()
	_material.set_shader_parameter("depth_map", _depth_rd)

	_webxr = XRServer.find_interface("WebXR")
	# Per-frame work only happens while sensor occlusion is actually live.
	set_process(false)
	# Hidden unless sensor occlusion runs: the punch shader samples the scene
	# depth buffer (hint_depth_texture), which the WebGPU driver cannot bind
	# yet - an always-on quad would invalidate every frame there.
	visible = false

func _process(_delta: float) -> void:
	if not occlusion_enabled or not _sensor_active or not _webxr or not _webxr.is_initialized():
		set_process(false)
		visible = false
		return
	# Sensor mode: the depth texture is per-frame data, so refresh the RID.
	var info := _webxr.get_system_info()
	if info.has("webxr_depth_texture_rd"):
		var rid: RID = info["webxr_depth_texture_rd"]
		if _depth_rd.texture_rd_rid != rid:
			_depth_rd.texture_rd_rid = rid
		_material.set_shader_parameter("raw_to_meters", float(info.get("webxr_depth_raw_to_meters", 1.0)))

func set_occlusion(p_enabled: bool) -> void:
	occlusion_enabled = p_enabled
	_sensor_active = false
	visible = false
	if not p_enabled:
		_material.set_shader_parameter("occlusion_enabled", 0.0)
		set_process(false)
		if _depth_occluding:
			_depth_occluding = false
			for b in get_tree().get_nodes_in_group("webxr_depth_bridge"):
				b.set_occlude(false)
		for bridge in get_tree().get_nodes_in_group("webxr_mesh_bridge"):
			bridge.set_occlusion(false)
		return
	# Best path: the engine binds the sensor depth texture -> one fullscreen
	# punch does everything. (Browsers withhold it today, so this rarely wins.)
	if _has_sensor_depth():
		_sensor_active = true
		visible = true
		_material.set_shader_parameter("occlusion_enabled", 1.0)
		set_process(true)
		return
	_material.set_shader_parameter("occlusion_enabled", 0.0)
	# Otherwise COMPOSE two layers, never replacing the working one:
	#   - room-mesh punch  = static occlusion (behind walls/furniture)
	#   - live-depth punch = dynamic occlusion (a moving hand) where a depth
	#     sensor is granted. They subtract-blend together.
	for bridge in get_tree().get_nodes_in_group("webxr_mesh_bridge"):
		bridge.set_occlusion(true)
	var depth_bridges := get_tree().get_nodes_in_group("webxr_depth_bridge")
	if not depth_bridges.is_empty() and _session_has_depth():
		_depth_occluding = true
		depth_bridges[0].set_occlude(true)

func _has_sensor_depth() -> bool:
	return _webxr and _webxr.is_initialized() and _webxr.get_system_info().has("webxr_depth_texture_rd")

## Did the session grant depth-sensing? (Enables the live-depth punch layer.)
func _session_has_depth() -> bool:
	return _webxr and _webxr.is_initialized() and str(_webxr.get("enabled_features")).contains("depth-sensing")

func get_status() -> String:
	if not _webxr or not _webxr.is_initialized():
		return "Occlusion: enter an immersive session first."
	var info := _webxr.get_system_info()
	if not info.has("webxr_depth_texture_rd"):
		var bridges := get_tree().get_nodes_in_group("webxr_mesh_bridge")
		var mesh_count: int = bridges[0].get_surface_count() if not bridges.is_empty() else 0
		var state := "ON" if occlusion_enabled else "OFF"
		if _depth_occluding:
			# Composed: static room-mesh punch + dynamic live-depth punch.
			return "Occlusion %s: room mesh (%d surfaces, static) + live depth (dynamic - occludes a moving hand, coarse)." % [state, mesh_count]
		var why := _no_sensor_reason(info)
		if mesh_count > 0:
			return "Occlusion %s via room mesh (%d surfaces, static). %s" % [state, mesh_count, why]
		return "Occlusion unavailable: no room scan either. %s" % why
	var size: Vector2 = info.get("webxr_depth_size", Vector2.ZERO)
	return "Occlusion %s via depth sensor (%dx%d, real-time)." % ["ON" if occlusion_enabled else "OFF", int(size.x), int(size.y)]

func _no_sensor_reason(info: Dictionary) -> String:
	match str(info.get("webxr_depth_status", "")):
		"unsupported_by_browser":
			return "Sensor occlusion is an UPCOMING WebGPU browser feature: this browser's XRGPUBinding has no getDepthInformation() yet. Re-toggle after a browser update ships it and this switches to the live sensor."
		"webgl_session":
			return "Depth sensor detected, but the WebGL rendering path does not consume it yet (sensor occlusion on WebGL is a planned feature)."
		"no_depth_data":
			return "No depth sensor: the session did not grant depth-sensing."
		"no_session":
			return "No depth sensor: no active session."
		_:
			return "No depth sensor on this platform."


## webxr_feature_provider contract: the occluder's sensor path probes
## getDepthInformation, which needs the depth-sensing grant even when no
## depth bridge is in the scene.
func get_webxr_required_features(_session_mode: String) -> PackedStringArray:
	return PackedStringArray()

func get_webxr_optional_features(session_mode: String) -> PackedStringArray:
	if session_mode == "immersive-ar":
		return PackedStringArray(["depth-sensing"])
	return PackedStringArray()
