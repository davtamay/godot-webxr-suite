extends Node3D

## Perception showcase: room mesh + depth occlusion + light estimation + hit-test
## anchors, all via the drop-in manager blocks. Adds the back-to-menu button when
## opened from the sample launcher (soft-loaded, so the addon stays standalone).
##
## The managers do the work; this script only drives the little light-readout
## station (swatch + arrow) from the LightEstimationManager's estimate signal so
## you can SEE the estimated room light, not just be lit by it.


func _ready() -> void:
	if ResourceLoader.exists("res://scripts/back_to_menu_button.gd"):
		add_child((load("res://scripts/back_to_menu_button.gd") as GDScript).new())

	var light_mgr := get_node_or_null("LightEstimationManager")
	if light_mgr and light_mgr.has_signal("estimate_applied"):
		light_mgr.estimate_applied.connect(_on_light_estimate)


func _on_light_estimate(direction_to_light: Vector3, primary_intensity: Vector3, _sh: PackedVector3Array) -> void:
	# Tint the swatch to the estimated room-light color.
	var swatch := get_node_or_null("LightReadout/Swatch") as MeshInstance3D
	if swatch:
		var mat := swatch.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			var c := primary_intensity
			var peak: float = maxf(maxf(c.x, c.y), maxf(c.z, 0.001))
			mat.albedo_color = Color(c.x / peak, c.y / peak, c.z / peak, 1.0)

	# Point the arrow toward the estimated light source.
	var arrow := get_node_or_null("LightReadout/DirectionArrow") as Node3D
	if arrow and direction_to_light.length() > 0.01:
		var up := Vector3.UP if absf(direction_to_light.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		arrow.global_basis = Basis.looking_at(direction_to_light.normalized(), up)
