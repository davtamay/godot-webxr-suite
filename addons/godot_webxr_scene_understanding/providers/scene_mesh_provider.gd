extends XRSceneProvider

const _BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd"

var _bridge: Node3D


func _init() -> void:
	provider_id = "webxr"
	provider_label = "WebXR scene mesh"


func start() -> bool:
	if not OS.has_feature("web"):
		return false
	if not ResourceLoader.exists(_BRIDGE_SCRIPT, "Script"):
		return false
	var script := load(_BRIDGE_SCRIPT) as Script
	if script == null:
		return false
	_bridge = Node3D.new()
	_bridge.name = "WebXRMeshBridge"
	_bridge.set_script(script)
	_bridge.mesh_color = options.get("mesh_color", Color(0.08, 0.72, 1.0, 0.5))
	_bridge.generate_collision = bool(options.get("generate_collision", false))
	add_child(_bridge)
	set_visualize(bool(options.get("visualize", false)))
	set_occlusion(bool(options.get("occlude", false)))
	set_labels(bool(options.get("scene_labels", false)))
	return true


func get_status() -> String:
	return str(_bridge.get_status()) if _bridge else "Scene mesh: waiting for WebXR."


func is_live_reconstruction() -> bool:
	return _bridge.is_dynamic_mesh_platform() if _bridge else false


func set_visualize(enabled: bool) -> void:
	if _bridge:
		_bridge.set_visualize(enabled)


func set_occlusion(enabled: bool) -> void:
	if _bridge:
		_bridge.set_occlusion(enabled)


func set_labels(enabled: bool) -> void:
	if _bridge:
		_bridge.set_labels(enabled)
