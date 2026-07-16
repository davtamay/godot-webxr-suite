@tool
@icon("res://addons/godot_webxr_scene_understanding/icons/scene_mesh_manager.svg")
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
## Requests the 'mesh-detection' / 'plane-detection' session features by itself.
## Inert outside a web export (WebXR-only feature).

const _BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd"

## Render the room mesh so you can see what the device knows about the room.
@export var visualize := false:
	set(value):
		visualize = value
		if _bridge:
			_bridge.set_visualize(visualize)

## Hide virtual objects behind real walls/furniture (invisible depth punch).
@export var occlude := false:
	set(value):
		occlude = value
		if _bridge:
			_bridge.set_occlusion(occlude)

## Floating semantic labels (wall/floor/table...) where the platform names
## surfaces - Android XR labels mesh chunks, Quest labels planes.
@export var scene_labels := false:
	set(value):
		scene_labels = value
		if _bridge:
			_bridge.set_labels(scene_labels)

## Build static trimesh colliders from the room geometry so physics objects
## collide with the real room. Set before the session starts.
@export var generate_collision := false

## Tint for the visualized room mesh.
@export var mesh_color := Color(0.08, 0.72, 1.0, 0.5)

var _bridge: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not OS.has_feature("web"):
		return  # WebXR-only feature; harmless no-op on desktop preview / OpenXR.
	var script := load(_BRIDGE_SCRIPT)
	_bridge = Node3D.new()
	_bridge.name = "MeshBridge"
	_bridge.set_script(script)
	_bridge.mesh_color = mesh_color
	_bridge.generate_collision = generate_collision
	add_child(_bridge)
	# Room geometry is world-space; never let this manager's own transform
	# offset it, wherever the user parked the node.
	_bridge.top_level = true
	_bridge.global_transform = Transform3D.IDENTITY
	_bridge.set_visualize(visualize)
	_bridge.set_occlusion(occlude)
	_bridge.set_labels(scene_labels)


## The bridge's honest per-device availability line, for status displays
## (stored room mesh vs live reconstruction, surface counts, flag hints).
func get_status() -> String:
	return str(_bridge.get_status()) if _bridge else "Scene mesh: web export required."


## True when this device reconstructs the room LIVE (Android XR) rather than
## serving a stored Space-Setup mesh (Quest).
func is_live_reconstruction() -> bool:
	return _bridge.is_dynamic_mesh_platform() if _bridge else false
