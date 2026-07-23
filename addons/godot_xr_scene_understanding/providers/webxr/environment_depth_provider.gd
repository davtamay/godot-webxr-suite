extends XRSceneProvider

const _BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd"

var _bridge: Node3D


func _init() -> void:
	provider_id = "webxr"
	provider_label = "WebXR depth sensing"


func start() -> bool:
	if not OS.has_feature("web"):
		return false
	var script := load(_BRIDGE_SCRIPT) as Script
	if script == null:
		return false
	_bridge = Node3D.new()
	_bridge.name = "WebXRDepthBridge"
	_bridge.set_script(script)
	add_child(_bridge)
	_apply_options()
	return true


func get_status() -> String:
	return str(_bridge.get_status()) if _bridge else "Depth sensing: waiting for WebXR."


func set_resolution_level(level: int) -> void:
	if _bridge:
		_bridge.set_resolution_level(level)


func set_visualize(enabled: bool) -> void:
	if _bridge:
		_bridge.set_visualize(enabled)


func set_debug_visualization(enabled: bool) -> void:
	set_visualize(enabled)


func set_occlusion(enabled: bool) -> void:
	if _bridge:
		_bridge.set_occlude(enabled)


func set_occ_softness(softness: float) -> void:
	if _bridge:
		_bridge.set_occ_softness(softness)


func set_ext_harvest(enabled: bool) -> void:
	if _bridge:
		_bridge.set_ext_harvest(enabled)


func _apply_options() -> void:
	set_resolution_level(int(options.get("depth_resolution", 1)))
	set_visualize(bool(options.get("debug_depth_visualization", false)))
	set_occ_softness(float(options.get("edge_softness", 0.0)))
	set_occlusion(bool(options.get("occlude", false)))
	set_ext_harvest(bool(options.get("soft_occlusion", false)))
