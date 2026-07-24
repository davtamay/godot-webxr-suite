@tool
@icon("res://addons/godot_xr_scene_understanding/icons/scene_mesh_manager.svg")
class_name SceneMeshManager
extends Node3D

## Drop-in scene meshing manager (mirrors Unity's ARMeshManager / Meta's Scene
## Mesh).
##
## Add this node anywhere in your scene to consume the device's room geometry -
## the stored Space-Setup mesh on Quest, the live streaming reconstruction on
## Android XR. One node, device-adaptive; [method get_status] reports which one
## this headset serves.
##
## - [member visualize]: render the room geometry (classic blue scan look).
## - [member occlude]: punch the room geometry into the depth buffer so virtual
##   objects hide behind real walls/furniture (static surfaces; pair with
##   EnvironmentDepthManager for moving things like hands).
## - [member scene_labels]: floating semantic labels (wall/floor/table...) where
##   the platform provides them.
##
## The same API selects WebXR meshes, Meta's stored Scene Model, or Android
## XR's live reconstruction from capabilities exposed by the active runtime.

const _ROUTER_SCRIPT := preload(
	"res://addons/godot_xr_scene_understanding/runtime/xr_scene_provider_router.gd"
)

## Render the room mesh so you can see what the device knows about the room.
@export var visualize := false:
	set(value):
		visualize = value
		if _provider:
			_provider.set_visualize(visualize)

## Hide virtual objects behind real walls/furniture (invisible depth punch).
@export var occlude := false:
	set(value):
		occlude = value
		if _provider:
			_provider.set_occlusion(occlude)

## Floating semantic labels (wall/floor/table...) where the platform names
## surfaces - Android XR labels mesh chunks, Quest labels planes.
@export var scene_labels := false:
	set(value):
		scene_labels = value
		if _provider:
			_provider.set_labels(scene_labels)

## Build static trimesh colliders from the room geometry so physics objects
## collide with the real room. Set before the session starts.
@export var generate_collision := false

## Meta only: ask the system to open Space Setup when no stored Scene Model is
## available. Off by default so entering a scene never surprises the user with
## an operating-system modal.
@export var request_scene_capture_if_missing := false

## Tint for the visualized room mesh.
@export var mesh_color := Color(0.08, 0.72, 1.0, 0.5)

var _provider: XRSceneProviderRouter


func _enter_tree() -> void:
	add_to_group("xr_scene_mesh_manager")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# A surface-placement manager needs real-room physics even when visualization
	# and occlusion are off. Resolve this automatically so adding the block is
	# enough; authors do not need to discover a second collision checkbox.
	if not get_tree().get_nodes_in_group("xr_hit_test_anchor_manager").is_empty():
		generate_collision = true
	_provider = _ROUTER_SCRIPT.new()
	_provider.name = "SceneMeshProvider"
	_provider.configure("scene_mesh", {
		"visualize": visualize,
		"occlude": occlude,
		"scene_labels": scene_labels,
		"generate_collision": generate_collision,
		"request_scene_capture_if_missing": request_scene_capture_if_missing,
		"mesh_color": mesh_color,
	})
	add_child(_provider)
	_provider.set_visualize(visualize)
	_provider.set_occlusion(occlude)
	_provider.set_labels(scene_labels)


## The bridge's honest per-device availability line, for status displays
## (stored room mesh vs live reconstruction, surface counts, flag hints).
func get_status() -> String:
	return str(_provider.get_status()) if _provider else "Scene mesh: provider not started."


## True when this device reconstructs the room LIVE (Android XR) rather than
## serving a stored Space-Setup mesh (Quest).
func is_live_reconstruction() -> bool:
	return _provider.is_live_reconstruction() if _provider else false


## Stable UI/control API shared by WebXR, Meta OpenXR, and Android XR.
func set_visualize(enabled: bool) -> void:
	visualize = enabled


func set_occlusion(enabled: bool) -> void:
	occlude = enabled


func set_labels(enabled: bool) -> void:
	scene_labels = enabled


func is_visualizing() -> bool:
	return visualize


func is_occluding() -> bool:
	return occlude


func is_showing_labels() -> bool:
	return scene_labels


## Compatibility name used by the original WebXR feature panel.
func is_dynamic_mesh_platform() -> bool:
	return is_live_reconstruction()
