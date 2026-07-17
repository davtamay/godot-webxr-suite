@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_highlight_affordance.svg")
extends XRGrabInteractable

## Root of grabbable.tscn - a ready-made grabbable object. Instance the scene,
## swap the Mesh (and material), done: collision auto-fits the mesh and the
## highlight affordance rides along.

func _ready() -> void:
	super()
	# Auto-fit the collision to whatever mesh the user swapped in, so the
	# prefab needs zero manual shape sizing. An explicitly authored shape is
	# respected.
	var collision := get_node_or_null("InteractableBody/CollisionShape3D") as CollisionShape3D
	var mesh_instance := get_node_or_null("Mesh") as MeshInstance3D
	if collision and collision.shape == null and mesh_instance and mesh_instance.mesh:
		var aabb := mesh_instance.mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size * mesh_instance.scale
		collision.shape = box
		collision.position = mesh_instance.position + (aabb.get_center() * mesh_instance.scale)
