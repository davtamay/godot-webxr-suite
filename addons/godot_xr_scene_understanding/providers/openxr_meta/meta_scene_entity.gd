extends Node3D

var mesh_instance: MeshInstance3D
var semantic_labels := PackedStringArray()


## Called by OpenXRFbSceneManager. The argument stays dynamically typed so the
## script also parses in web exports where the vendor GDExtension is absent.
func setup_scene(entity: Object) -> void:
	if entity == null:
		return
	if entity.has_method("get_semantic_labels"):
		semantic_labels = entity.call("get_semantic_labels")
	var arrays: Array = entity.call("get_triangle_mesh") if entity.has_method("get_triangle_mesh") else []
	if arrays.is_empty():
		if entity.has_method("create_mesh_instance"):
			mesh_instance = entity.call("create_mesh_instance") as MeshInstance3D
	else:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = mesh
	if mesh_instance:
		mesh_instance.name = "RoomMesh"
		add_child(mesh_instance)


func apply_display(
	visualize: bool,
	occlude: bool,
	show_labels: bool,
	mesh_color: Color,
	occlusion_material: Material
) -> void:
	if mesh_instance:
		mesh_instance.visible = visualize or occlude
		if visualize:
			var material := StandardMaterial3D.new()
			material.albedo_color = mesh_color
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.material_override = material
		elif occlude:
			mesh_instance.material_override = occlusion_material
	var label := get_node_or_null("SemanticLabel") as Label3D
	if show_labels and not semantic_labels.is_empty():
		if label == null:
			label = Label3D.new()
			label.name = "SemanticLabel"
			label.font_size = 28
			label.outline_size = 6
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(label)
		label.text = ", ".join(semantic_labels)
		label.visible = true
	elif label:
		label.visible = false
