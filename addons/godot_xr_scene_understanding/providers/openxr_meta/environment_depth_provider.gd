extends XRSceneProvider

const _EXTENSION := "OpenXRMetaEnvironmentDepthExtension"
const _DEPTH_NODE := "OpenXRMetaEnvironmentDepth"
const _DEBUG_SHADER := preload(
	"res://addons/godot_xr_scene_understanding/runtime/meta_depth_debug.gdshader"
)

var _extension: Object
var _depth_node: Node3D
var _debug_mesh: MeshInstance3D
var _started_here := false
var _occlusion_enabled := false
var _debug_enabled := false


func _init() -> void:
	provider_id = "openxr_meta"
	provider_label = "Meta OpenXR environment depth"


func start() -> bool:
	if OS.has_feature("web") or not ClassDB.class_exists(_DEPTH_NODE):
		return false
	_extension = Engine.get_singleton(_EXTENSION)
	if _extension == null or not bool(_extension.call("is_environment_depth_supported")):
		return false
	var camera := _find_xr_camera()
	if camera == null:
		return false
	_depth_node = ClassDB.instantiate(_DEPTH_NODE) as Node3D
	if _depth_node == null:
		return false
	_depth_node.name = "OpenXRMetaEnvironmentDepth"
	camera.add_child(_depth_node)
	_debug_mesh = _create_debug_mesh()
	camera.add_child(_debug_mesh)
	enable_native_passthrough()
	_occlusion_enabled = bool(options.get("occlude", false))
	_debug_enabled = bool(options.get("debug_depth_visualization", false))
	_apply_enabled()
	return true


func stop() -> void:
	if _started_here and _extension and bool(_extension.call("is_environment_depth_started")):
		_extension.call("stop_environment_depth")
	_started_here = false
	if _debug_mesh and is_instance_valid(_debug_mesh):
		_debug_mesh.queue_free()
	_debug_mesh = null


func get_status() -> String:
	if _extension == null:
		return "Meta environment depth: extension unavailable."
	if bool(_extension.call("is_environment_depth_started")):
		if _debug_enabled:
			return "Depth Scan: Meta live sensor map visible."
		if _occlusion_enabled:
			return "Depth occlusion: Meta live environment depth active."
		return "Environment depth: Meta stream ready."
	return "Environment depth: Meta OpenXR available; Show or Occlude to start."


func set_occlusion(enabled: bool) -> void:
	_occlusion_enabled = enabled
	_apply_enabled()


func set_visualize(enabled: bool) -> void:
	_debug_enabled = enabled
	_apply_enabled()


func set_debug_visualization(enabled: bool) -> void:
	set_visualize(enabled)


func set_ext_harvest(enabled: bool) -> void:
	# Native compositor depth is already feathered/reprojected. Treat SOFT as
	# enabling the native depth provider instead of swapping WebXR materials.
	if enabled:
		set_occlusion(true)


func _apply_enabled() -> void:
	if _extension == null or _depth_node == null:
		return
	var enabled := _occlusion_enabled or _debug_enabled
	# The vendors node is an invisible depth-buffer punch. Keep it exclusive
	# to Occlude; Show uses the colored reprojection mesh below.
	_depth_node.visible = _occlusion_enabled
	if _debug_mesh:
		_debug_mesh.visible = _debug_enabled
	if enabled and not bool(_extension.call("is_environment_depth_started")):
		_extension.call("start_environment_depth")
		_started_here = true
	elif not enabled and _started_here and bool(_extension.call("is_environment_depth_started")):
		_extension.call("stop_environment_depth")
		_started_here = false


func _create_debug_mesh() -> MeshInstance3D:
	var vertices := PackedVector3Array([
		Vector3(-1.0, -1.0, 1.0),
		Vector3(3.0, -1.0, 1.0),
		Vector3(-1.0, 3.0, 1.0),
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(
		Vector3(-1000, -1000, -1000),
		Vector3(2000, 2000, 2000)
	)
	var material := ShaderMaterial.new()
	material.shader = _DEBUG_SHADER
	material.render_priority = 1
	var instance := MeshInstance3D.new()
	instance.name = "MetaDepthDebugVisualization"
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = false
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _find_xr_camera() -> XRCamera3D:
	var scene := _own_scene_root()
	var cameras := scene.find_children("*", "XRCamera3D", true, false)
	if cameras.is_empty():
		return null
	return cameras[0] as XRCamera3D


func _own_scene_root() -> Node:
	var node: Node = self
	var tree_root := get_tree().root
	while node.get_parent() != null and node.get_parent() != tree_root:
		node = node.get_parent()
	return node
