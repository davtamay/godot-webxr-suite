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
const OCCLUSION_DEBUG_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/occlusion_debug_material.tres")
const OCCLUSION_SOFT_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/occlusion_soft_material.tres")

var occlusion_enabled := false
## EXPERIMENTAL per-pixel sensor occlusion. Off (default) = the working
## room-mesh + live-depth punch. On = the depth-texture occlusion shader
## (being brought up on the GL path; supersedes the mesh punch when engaged).
var use_sensor := false
## Bring-up: while true, the sensor path renders the full-FOV depth DIAGNOSTIC
## (three bands: raw texture / decoded metres / scene depth) instead of the
## occlusion punch, so we can see which stage of the per-pixel path is broken.
## Flip to false once the decode is verified to get real soft occlusion.
var debug_view := true

var _webxr: XRInterface
var _material: ShaderMaterial
var _debug_material: ShaderMaterial
var _soft_material: ShaderMaterial
var _depth_rd: Texture2DRD
var _sensor_active := false
## Whether we routed a depth bridge into live-depth punch occlusion (dynamic).
var _depth_occluding := false
## The mesh-punch fallback is running (used when no sensor depth texture binds).
var _fallback_active := false

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
	_debug_material = OCCLUSION_DEBUG_MATERIAL.duplicate() as ShaderMaterial
	_soft_material = OCCLUSION_SOFT_MATERIAL.duplicate() as ShaderMaterial
	material_override = _material

	_depth_rd = Texture2DRD.new()
	_material.set_shader_parameter("depth_map", _depth_rd)

	_webxr = XRServer.find_interface("WebXR")
	# The sensor quad must never survive the session, or it lingers over the 2D
	# page after exit.
	if _webxr:
		_webxr.session_ended.connect(_on_session_ended)
	# Per-frame work only happens while sensor occlusion is actually live.
	set_process(false)
	# Hidden unless sensor occlusion runs: the punch shader samples the scene
	# depth buffer (hint_depth_texture), which the WebGPU driver cannot bind
	# yet - an always-on quad would invalidate every frame there.
	visible = false

func _on_session_ended() -> void:
	set_process(false)
	visible = false
	_sensor_active = false
	var db = _depth_bridge()
	if db:
		db.set_ext_harvest(false)

# The occluder's fullscreen sensor path is retired - per-object soft occlusion
# (occlusion_object.gdshader on the grab meshes, fed by the depth bridge)
# replaced it because a fullscreen quad can't read scene depth in XR. This node
# stays inert; the mesh-punch API below is unused by the current panel.
func _process(_delta: float) -> void:
	return

func _depth_bridge():
	var nodes := get_tree().get_nodes_in_group("webxr_depth_bridge")
	return null if nodes.is_empty() else nodes[0]

## Static room-mesh punch + dynamic live-depth punch (subtract-blend together);
## used when no per-pixel sensor depth texture is available.
func _start_fallback() -> void:
	_fallback_active = true
	_material.set_shader_parameter("occlusion_enabled", 0.0)
	visible = false
	for bridge in get_tree().get_nodes_in_group("webxr_mesh_bridge"):
		bridge.set_occlusion(true)
	var depth_bridges := get_tree().get_nodes_in_group("webxr_depth_bridge")
	if not depth_bridges.is_empty() and _session_has_depth():
		_depth_occluding = true
		depth_bridges[0].set_occlude(true)

func _stop_fallback() -> void:
	_fallback_active = false
	if _depth_occluding:
		_depth_occluding = false
		for b in get_tree().get_nodes_in_group("webxr_depth_bridge"):
			b.set_occlude(false)
	for bridge in get_tree().get_nodes_in_group("webxr_mesh_bridge"):
		bridge.set_occlusion(false)

func set_occlusion(p_enabled: bool) -> void:
	occlusion_enabled = p_enabled
	_sensor_active = false
	visible = false
	_material.set_shader_parameter("occlusion_enabled", 0.0)
	if not p_enabled:
		set_process(false)
		var db = _depth_bridge()
		if db:
			db.set_ext_harvest(false)
		if _fallback_active:
			_stop_fallback()
		return
	_apply_mode()

## Pick the occlusion technique: the working mesh punch by default, or the
## experimental per-pixel SOFT sensor path when use_sensor is on.
func _apply_mode() -> void:
	if not occlusion_enabled:
		return
	var db = _depth_bridge()
	if use_sensor:
		# Per-pixel SOFT occlusion: stop the mesh punch and ask the depth bridge
		# to harvest + upload its depth texture; _process binds it into the soft
		# shader once it appears.
		_stop_fallback()
		_sensor_active = false
		visible = false
		if db:
			db.set_ext_harvest(true)
		set_process(true)
	else:
		# Working room-mesh + live-depth punch.
		set_process(false)
		_sensor_active = false
		visible = false
		if db:
			db.set_ext_harvest(false)
		if not _fallback_active:
			_start_fallback()

## Switch between the working mesh punch (off) and the experimental per-pixel
## sensor occlusion (on).
func set_use_sensor(p_on: bool) -> void:
	use_sensor = p_on
	_apply_mode()

## Did the session grant depth-sensing? (Enables the live-depth punch layer.)
func _session_has_depth() -> bool:
	return _webxr and _webxr.is_initialized() and str(_webxr.get("enabled_features")).contains("depth-sensing")

func get_status() -> String:
	if not _webxr or not _webxr.is_initialized():
		return "Occlusion: enter an immersive session first."
	var info := _webxr.get_system_info()
	var sensor_live := _sensor_active and (info.has("webxr_depth_texture_rd") or info.has("webxr_depth_texture_rs"))
	if not sensor_live:
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
