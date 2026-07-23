@tool
@icon("res://addons/godot_webxr_scene_understanding/icons/environment_depth_manager.svg")
class_name EnvironmentDepthManager
extends Node3D

## Drop-in occlusion + depth manager (mirrors Meta's EnvironmentDepthManager).
##
## Add this node anywhere in your scene and pick an occlusion mode - real-world
## surfaces (including moving hands) hide your virtual objects. No wiring, no
## hand-authored materials:
##
## - HARD: everything is occluded by an invisible live depth mesh. Crisp edges,
##   zero per-object setup.
## - SOFT: listed objects fade behind real surfaces with feathered edges (the
##   Meta/Unity per-object technique). Choose the objects by dragging them into
##   [member occludees], by adding them to the 'webxr_occludable' group, or at
##   runtime via [method add_occludee] - their occlusion materials are generated
##   automatically from the addon's pre-baked shader (WebGPU-export safe).
##
## The manager reports one stable API while a capability router selects WebXR,
## Meta OpenXR, or Android XR depth at runtime.

## Meta-parity occlusion modes (their HARD_OCCLUSION / SOFT_OCCLUSION keywords).
enum OcclusionMode { NONE, HARD, SOFT }
const DEPTH_RESOLUTION_LABELS := [
	"Low 96x72",
	"Medium 128x96",
	"High 160x120",
	"Ultra 224x168",
	"Max 320x240",
]

const _ROUTER_SCRIPT := preload(
	"res://addons/godot_xr_scene_understanding/runtime/xr_scene_provider_router.gd"
)
## Pre-baked occlusion material template (occlusion_object.gdshader). Duplicated
## per occludee with the object's own colour/roughness copied into uniforms -
## uniform changes reuse the baked shader, so this stays WebGPU-export safe.
const _OCC_TEMPLATE := preload("res://addons/godot_webxr_scene_understanding/runtime/grab_cube_material.tres")

## What hides virtual objects behind the real world. HARD = depth-mesh punch
## (everything, crisp). SOFT = per-object feathered fade (occludees only).
@export var occlusion_mode: OcclusionMode = OcclusionMode.NONE:
	set(value):
		occlusion_mode = value
		update_configuration_warnings()
		_apply_occlusion()

## The objects SOFT occlusion applies to - drag them here from the scene tree.
## Each entry should be (or contain) a MeshInstance3D.
@export var occludees: Array[NodePath] = []:
	set(value):
		occludees = value
		update_configuration_warnings()
		_apply_occlusion()

## Edge feather for SOFT occlusion: 0 = crisp silhouette, 1 = very soft fade.
@export_range(0.0, 1.0, 0.01) var edge_softness := 0.0:
	set(value):
		edge_softness = value
		if _provider:
			_provider.set_occ_softness(edge_softness)

@export_group("Depth Debug")
## Render the live depth scan so you can SEE what the sensor sees.
@export var debug_depth_visualization := false:
	set(value):
		debug_depth_visualization = value
		if _provider:
			_provider.set_debug_visualization(debug_depth_visualization)

## Sensor sampling resolution. Higher = sharper occlusion, more per-frame cost.
@export_enum("Low 96x72", "Medium 128x96", "High 160x120", "Ultra 224x168", "Max 320x240")
var depth_resolution := 1:
	set(value):
		depth_resolution = value
		if _provider:
			_provider.set_resolution_level(depth_resolution)

var _provider: XRSceneProviderRouter


func _enter_tree() -> void:
	add_to_group("xr_environment_depth_manager")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_provider = _ROUTER_SCRIPT.new()
	_provider.name = "EnvironmentDepthProvider"
	_provider.configure("environment_depth", {
		"occlude": occlusion_mode == OcclusionMode.HARD,
		"soft_occlusion": occlusion_mode == OcclusionMode.SOFT,
		"edge_softness": edge_softness,
		"debug_depth_visualization": debug_depth_visualization,
		"depth_resolution": depth_resolution,
	})
	add_child(_provider)
	_provider.set_resolution_level(depth_resolution)
	_provider.set_debug_visualization(debug_depth_visualization)
	# Prep the occludees regardless of the current mode: cheap and idempotent
	# (group membership + occ_material metadata; materials only swap when SOFT
	# engages), and it lets external UIs (e.g. the feature panel) drive the
	# bridge's Hard/Soft toggles directly with the objects already prepared.
	for mesh in _resolve_occludee_meshes():
		_prepare_occludee(mesh)
	_apply_occlusion()


## Add an object to SOFT occlusion at runtime (e.g. spawned content).
func add_occludee(node: Node) -> void:
	for mesh in _meshes_under(node):
		_prepare_occludee(mesh)
	_refresh_soft()


## Remove an object from SOFT occlusion at runtime.
func remove_occludee(node: Node) -> void:
	for mesh in _meshes_under(node):
		if mesh.is_in_group("webxr_occludable"):
			if mesh.has_meta("opaque_material"):
				mesh.set_surface_override_material(0, mesh.get_meta("opaque_material"))
			mesh.remove_from_group("webxr_occludable")
	_refresh_soft()


## The bridge's honest per-device availability line, for status displays.
func get_status() -> String:
	return str(_provider.get_status()) if _provider else "Environment depth: provider not started."


## Stable UI/control API shared by WebXR, Meta OpenXR, and Android XR.
func set_visualize(enabled: bool) -> void:
	debug_depth_visualization = enabled


func set_occlude(enabled: bool) -> void:
	if enabled:
		occlusion_mode = OcclusionMode.HARD
	elif occlusion_mode == OcclusionMode.HARD:
		occlusion_mode = OcclusionMode.NONE


func set_ext_harvest(enabled: bool) -> void:
	if enabled:
		occlusion_mode = OcclusionMode.SOFT
	elif occlusion_mode == OcclusionMode.SOFT:
		occlusion_mode = OcclusionMode.NONE


func set_occ_softness(value: float) -> void:
	edge_softness = clampf(value, 0.0, 1.0)


func is_visualizing() -> bool:
	return debug_depth_visualization


func is_occluding() -> bool:
	return occlusion_mode == OcclusionMode.HARD


func is_soft_occluding() -> bool:
	return occlusion_mode == OcclusionMode.SOFT


func resolution_level_count() -> int:
	return DEPTH_RESOLUTION_LABELS.size()


func get_resolution_level() -> int:
	return depth_resolution


func set_resolution_level(level: int) -> void:
	depth_resolution = clampi(level, 0, DEPTH_RESOLUTION_LABELS.size() - 1)


func resolution_label() -> String:
	return DEPTH_RESOLUTION_LABELS[clampi(depth_resolution, 0, DEPTH_RESOLUTION_LABELS.size() - 1)]


func _apply_occlusion() -> void:
	if _provider == null:
		return
	match occlusion_mode:
		OcclusionMode.NONE:
			_provider.set_ext_harvest(false)
			_provider.set_occlude(false)
		OcclusionMode.HARD:
			_provider.set_ext_harvest(false)
			_provider.set_occlude(true)
		OcclusionMode.SOFT:
			_provider.set_occlude(false)
			for mesh in _resolve_occludee_meshes():
				_prepare_occludee(mesh)
			_provider.set_occ_softness(edge_softness)
			_provider.set_ext_harvest(true)


## Re-sync SOFT state after membership changes (the bridge swaps materials for
## the whole group on the harvest toggle, so cycle it).
func _refresh_soft() -> void:
	if _provider and occlusion_mode == OcclusionMode.SOFT:
		_provider.set_ext_harvest(false)
		_provider.set_ext_harvest(true)


## Give a mesh everything the bridge's occlusion contract needs: membership in
## 'webxr_occludable' + an occ_material generated from the baked template with
## the object's own look copied in.
func _prepare_occludee(mesh: MeshInstance3D) -> void:
	if not mesh.has_meta("occ_material"):
		var occ := _OCC_TEMPLATE.duplicate() as ShaderMaterial
		var source := mesh.get_active_material(0)
		if source is StandardMaterial3D:
			occ.set_shader_parameter("albedo", source.albedo_color)
			occ.set_shader_parameter("metallic", source.metallic)
			occ.set_shader_parameter("roughness", source.roughness)
		mesh.set_meta("occ_material", occ)
	if not mesh.is_in_group("webxr_occludable"):
		mesh.add_to_group("webxr_occludable")


func _resolve_occludee_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for path in occludees:
		var node := get_node_or_null(path)
		if node:
			for mesh in _meshes_under(node):
				if not meshes.has(mesh):
					meshes.append(mesh)
	return meshes


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node)
	else:
		for found in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append(found)
	return meshes


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for path in occludees:
		var node := get_node_or_null(path)
		if node == null:
			warnings.append("Occludee path '%s' does not resolve to a node." % path)
		elif _meshes_under(node).is_empty():
			warnings.append("Occludee '%s' has no MeshInstance3D - nothing to occlude." % node.name)
	if occlusion_mode == OcclusionMode.SOFT and occludees.is_empty():
		warnings.append("SOFT occlusion with an empty Occludees list only affects objects already in the 'webxr_occludable' group - drag your objects into Occludees.")
	return warnings
