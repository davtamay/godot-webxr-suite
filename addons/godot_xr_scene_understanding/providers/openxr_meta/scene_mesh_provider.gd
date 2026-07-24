extends XRSceneProvider

const _MANAGER_CLASS := "OpenXRFbSceneManager"
const _SCENE_EXTENSION := "OpenXRFbSceneExtension"
const _ENTITY_SCENE := preload(
	"res://addons/godot_xr_scene_understanding/providers/openxr_meta/meta_scene_entity.tscn"
)
const _OCCLUSION_MATERIAL := preload(
	"res://addons/godot_xr_scene_understanding/runtime/native_mesh_occlusion_material.tres"
)
const _SURFACE_COLLISION_LAYER := 1 << 30

var _manager: Node
var _entities: Array[Node] = []
var _status := "Meta Scene Model: waiting for room data."


func _init() -> void:
	provider_id = "openxr_meta"
	provider_label = "Meta OpenXR Scene Model"


func start() -> bool:
	if OS.has_feature("web") or not ClassDB.class_exists(_MANAGER_CLASS):
		return false
	var interface := XRServer.find_interface("OpenXR")
	if interface == null or not interface.is_initialized():
		return false
	var scene_extension := Engine.get_singleton(_SCENE_EXTENSION)
	if (
		scene_extension == null
		or not scene_extension.has_method("is_scene_supported")
		or not bool(scene_extension.call("is_scene_supported"))
	):
		return false
	_manager = ClassDB.instantiate(_MANAGER_CLASS) as Node
	if _manager == null:
		return false
	var origin := _find_xr_origin()
	_manager.name = "OpenXRFbSceneManager"
	_manager.set("default_scene", _ENTITY_SCENE)
	_manager.set("scenes/global_mesh", _ENTITY_SCENE)
	# Configure and connect before entering the tree. The vendors manager
	# defaults auto_create on; adding it first raced its initial query against
	# our scene resources and signal connections.
	_manager.set("auto_create", false)
	_manager.connect("openxr_fb_scene_anchor_created", _on_scene_anchor_created)
	_manager.connect("openxr_fb_scene_data_missing", _on_scene_data_missing)
	_manager.connect("openxr_fb_scene_capture_completed", _on_scene_capture_completed)
	origin.add_child(_manager)
	enable_native_passthrough()
	_create_scene_anchors.call_deferred()
	return true


func stop() -> void:
	if _manager and is_instance_valid(_manager):
		_manager.queue_free()
	_manager = null
	_entities.clear()


func get_status() -> String:
	return _status


func set_visualize(enabled: bool) -> void:
	options["visualize"] = enabled
	_refresh_entities()


func set_occlusion(enabled: bool) -> void:
	options["occlude"] = enabled
	_refresh_entities()


func set_labels(enabled: bool) -> void:
	options["scene_labels"] = enabled
	_refresh_entities()


func _on_scene_anchor_created(scene_node: Object, spatial_entity: Object) -> void:
	if scene_node is Node:
		var node := scene_node as Node
		_entities.append(node)
		if bool(options.get("generate_collision", false)) and spatial_entity.has_method("create_collision_shape"):
			var shape := spatial_entity.call("create_collision_shape") as CollisionShape3D
			if shape:
				var body := StaticBody3D.new()
				body.name = "RoomCollision"
				body.collision_layer = _SURFACE_COLLISION_LAYER
				body.collision_mask = 0
				body.add_child(shape)
				node.add_child(body)
		_configure_entity(node)
	_status = "Scene mesh: Meta stored Scene Model (%d anchors)." % _entities.size()
	print(_status)
	status_changed.emit()


func _on_scene_data_missing() -> void:
	_status = "Meta Scene Model: room data missing."
	print(_status)
	status_changed.emit()
	if (
		bool(options.get("request_scene_capture_if_missing", false))
		and bool(_manager.call("is_scene_capture_supported"))
	):
		_manager.call("request_scene_capture")


func _on_scene_capture_completed(success: bool) -> void:
	_status = "Meta Scene Model: capture complete; loading." if success else "Meta Scene Model: capture failed."
	if success:
		_manager.call("remove_scene_anchors")
		_manager.call("create_scene_anchors")
	status_changed.emit()


func _create_scene_anchors() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	var error := int(_manager.call("create_scene_anchors"))
	if error != OK:
		_status = "Meta Scene Model: room query failed (error %d)." % error
		push_warning(_status)
		status_changed.emit()


func _refresh_entities() -> void:
	for entity in _entities:
		if is_instance_valid(entity):
			_configure_entity(entity)


func _configure_entity(entity: Node) -> void:
	if entity.has_method("apply_display"):
		entity.call(
			"apply_display",
			bool(options.get("visualize", false)),
			bool(options.get("occlude", false)),
			bool(options.get("scene_labels", false)),
			options.get("mesh_color", Color(0.08, 0.72, 1.0, 0.5)),
			_OCCLUSION_MATERIAL
		)


func _find_xr_origin() -> Node:
	var scene := _own_scene_root()
	var origins := scene.find_children("*", "XROrigin3D", true, false)
	if not origins.is_empty():
		return origins[0]
	return self


func _own_scene_root() -> Node:
	var node: Node = self
	var tree_root := get_tree().root
	while node.get_parent() != null and node.get_parent() != tree_root:
		node = node.get_parent()
	return node
