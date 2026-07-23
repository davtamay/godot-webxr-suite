extends XRSceneProvider

const _EXTENSION := "OpenXRAndroidSceneMeshingExtension"
const _MESH_CLASS := "OpenXRAndroidSceneMeshing"
const _OCCLUSION_MATERIAL := preload(
	"res://addons/godot_xr_scene_understanding/runtime/native_mesh_occlusion_material.tres"
)
const _QUERY_INTERVAL := 0.25
const _STATE_UNCHANGED := 1
const _STATE_DELETED := 3

var _extension: Object
var _scene_meshing: Object
var _entries: Dictionary = {}
var _elapsed := 0.0
var _status := "Android XR scene mesh: waiting for reconstruction."


func _init() -> void:
	provider_id = "openxr_android_xr"
	provider_label = "Android XR live scene mesh"


func start() -> bool:
	if OS.has_feature("web") or not ClassDB.class_exists(_MESH_CLASS):
		return false
	_extension = Engine.get_singleton(_EXTENSION)
	if _extension == null:
		return false
	var label_sets: Array = _extension.call("get_supported_semantic_label_sets")
	if label_sets.is_empty():
		return false
	var label_set := 1 if label_sets.has(1) else int(label_sets[0])
	_scene_meshing = ClassDB.instantiate(_MESH_CLASS)
	if _scene_meshing == null or not bool(_scene_meshing.call("initialize", label_set, true)):
		if OS.has_feature("android"):
			OS.request_permissions()
		return false
	enable_native_passthrough()
	set_process(true)
	return true


func stop() -> void:
	set_process(false)
	for entry: Dictionary in _entries.values():
		var node: Node = entry.get("node")
		if node and is_instance_valid(node):
			node.queue_free()
	_entries.clear()
	_scene_meshing = null


func get_status() -> String:
	return _status


func is_live_reconstruction() -> bool:
	return true


func set_visualize(enabled: bool) -> void:
	options["visualize"] = enabled
	_refresh_display()


func set_occlusion(enabled: bool) -> void:
	options["occlude"] = enabled
	_refresh_display()


func set_labels(enabled: bool) -> void:
	options["scene_labels"] = enabled
	_refresh_display()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _QUERY_INTERVAL or _scene_meshing == null:
		return
	_elapsed = 0.0
	var camera := _find_xr_camera()
	if camera == null:
		return
	var pose := camera.get_camera_transform().translated_local(Vector3.FORWARD * 2.0)
	var submeshes: Dictionary = _scene_meshing.call(
		"get_submesh_data", pose, Vector3(8.0, 5.0, 8.0)
	)
	for uuid: Variant in submeshes:
		var data: Object = submeshes[uuid]
		var state := int(data.call("get_update_state"))
		if state == _STATE_DELETED:
			_remove_entry(uuid)
			continue
		if not _entries.has(uuid):
			_entries[uuid] = _create_entry()
		var entry: Dictionary = _entries[uuid]
		var node := entry["node"] as Node3D
		node.transform = data.call("get_transform")
		if state != _STATE_UNCHANGED:
			_update_entry_geometry(entry, data)
	_status = "Scene mesh: Android XR live reconstruction (%d chunks)." % _entries.size()
	status_changed.emit()


func _create_entry() -> Dictionary:
	var root := Node3D.new()
	root.name = "AndroidXRSceneChunk"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "RoomMesh"
	root.add_child(mesh_instance)
	add_child(root)
	return {"node": root, "mesh": mesh_instance, "body": null, "label": null}


func _update_entry_geometry(entry: Dictionary, data: Object) -> void:
	var arrays: Array = data.call("get_indexed_arrays")
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance := entry["mesh"] as MeshInstance3D
	mesh_instance.mesh = mesh
	if bool(options.get("generate_collision", false)):
		var old_body := entry.get("body") as StaticBody3D
		if old_body:
			old_body.queue_free()
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		entry["node"].add_child(body)
		entry["body"] = body
	_update_entry_label(entry, data)
	_apply_entry_display(entry)


func _update_entry_label(entry: Dictionary, data: Object) -> void:
	if not bool(options.get("scene_labels", false)) or not data.has_method("get_indexed_vertex_semantics"):
		return
	var semantics: Array = data.call("get_indexed_vertex_semantics")
	if semantics.is_empty():
		return
	var counts := {}
	for semantic: int in semantics:
		counts[semantic] = int(counts.get(semantic, 0)) + 1
	var best := 0
	for semantic: int in counts:
		if int(counts[semantic]) > int(counts.get(best, 0)):
			best = semantic
	var names := ["other", "floor", "ceiling", "wall", "table"]
	var label := entry.get("label") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "SemanticLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		entry["node"].add_child(label)
		entry["label"] = label
	label.text = names[best] if best >= 0 and best < names.size() else "surface"


func _refresh_display() -> void:
	for entry: Dictionary in _entries.values():
		_apply_entry_display(entry)


func _apply_entry_display(entry: Dictionary) -> void:
	var mesh_instance := entry["mesh"] as MeshInstance3D
	var visualize := bool(options.get("visualize", false))
	var occlude := bool(options.get("occlude", false))
	mesh_instance.visible = visualize or occlude
	if visualize:
		var material := StandardMaterial3D.new()
		material.albedo_color = options.get("mesh_color", Color(0.08, 0.72, 1.0, 0.5))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = material
	elif occlude:
		mesh_instance.material_override = _OCCLUSION_MATERIAL
	var label := entry.get("label") as Label3D
	if label:
		label.visible = bool(options.get("scene_labels", false))


func _remove_entry(uuid: Variant) -> void:
	if not _entries.has(uuid):
		return
	var entry: Dictionary = _entries[uuid]
	var node := entry["node"] as Node
	if node:
		node.queue_free()
	_entries.erase(uuid)


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
