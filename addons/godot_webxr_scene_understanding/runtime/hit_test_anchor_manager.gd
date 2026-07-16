@tool
@icon("res://addons/godot_webxr_scene_understanding/icons/hit_test_anchor_manager.svg")
class_name HitTestAnchorManager
extends Node3D

## Drop-in surface placement + spatial anchors (mirrors ARFoundation's
## ARRaycastManager / ARAnchorManager).
##
## Add this node anywhere in your scene and, in AR, a reticle tracks real
## surfaces along the viewer ray; a pinch/select places a spatial anchor there
## - and if [member placed_scene] is set, your scene is instanced at the anchor
## automatically. Content stays world-locked by the platform (anchors are
## standard XRAnchor3D trackers, updated across tracking corrections).
##
## Zero wiring: the reticle is auto-built (or bring your own via
## [member reticle_scene]), placement is one property, and the node requests
## the 'hit-test' + 'anchors' session features by itself. [method get_status]
## reports per-device availability honestly. Inert outside a web export.
##
## NOTE on place_on_select: the browser's select event fires for EVERY pinch,
## including ones aimed at UI panels or grabbables - in scenes with heavy
## interaction, prefer place_on_select = false and call [method place_anchor]
## from your own gesture/button.

## The live surface hit under the viewer ray moved (world transform, Y = the
## surface normal).
signal hit_updated(hit_transform: Transform3D)
## No surface under the viewer ray this frame.
signal hit_lost
## An anchor was created and its XRAnchor3D node exists (placed_scene, if any,
## is already instanced under it).
signal anchor_placed(anchor_id: int, anchor_node: XRAnchor3D)
## The platform dropped an anchor (or clear_anchors() removed it).
signal anchor_removed(anchor_id: int)
## Anchor creation failed (limit reached, platform refusal...).
signal anchor_failed(message: String)

const _BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd"
## Pre-baked reticle material (WebGPU-export safe).
const _RETICLE_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/hit_reticle_material.tres")

## Show a reticle on the surface under the viewer ray.
@export var show_reticle := true

## Your own reticle scene (a Node3D; its origin sits on the surface, +Y along
## the surface normal). Leave empty for the built-in ring.
@export var reticle_scene: PackedScene:
	set(value):
		reticle_scene = value
		update_configuration_warnings()

## Place an anchor at the reticle on pinch/select. See the class note about
## select firing for UI pinches too.
@export var place_on_select := true

## Scene instanced under every placed anchor - drop your content here and
## placement is fully zero-code. Leave empty to handle [signal anchor_placed]
## yourself.
@export var placed_scene: PackedScene

## Most platforms cap live anchors; oldest requests fail past the limit.
@export_range(1, 64, 1) var maximum_anchors := 16

var _bridge: Node
var _reticle: Node3D
var _anchor_root: Node3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if not OS.has_feature("web"):
		return  # WebXR-only feature; harmless no-op on desktop preview / OpenXR.
	# Anchored content is world-space; never let this manager's own transform
	# offset it, wherever the user parked the node.
	_anchor_root = Node3D.new()
	_anchor_root.name = "Anchors"
	add_child(_anchor_root)
	_anchor_root.top_level = true
	_anchor_root.global_transform = Transform3D.IDENTITY

	var script := load(_BRIDGE_SCRIPT)
	_bridge = Node.new()
	_bridge.name = "HitTestAnchorBridge"
	_bridge.set_script(script)
	_bridge.maximum_anchors = maximum_anchors
	add_child(_bridge)
	_bridge.anchor_node_root = _bridge.get_path_to(_anchor_root)
	_bridge.hit_pose_updated.connect(_on_hit_pose_updated)
	_bridge.hit_lost.connect(_on_hit_lost)
	_bridge.anchor_node_added.connect(_on_anchor_node_added)
	_bridge.anchor_removed.connect(func(anchor_id: int) -> void: anchor_removed.emit(anchor_id))
	_bridge.anchor_failed.connect(func(message: String) -> void: anchor_failed.emit(message))

	if show_reticle:
		_build_reticle()

	if place_on_select:
		var webxr := XRServer.find_interface("WebXR")
		if webxr and webxr.has_signal("select"):
			webxr.select.connect(_on_select)


## Place an anchor at the current surface hit. False when nothing is hit (or
## off-web); the result arrives via [signal anchor_placed] / [signal anchor_failed].
func place_anchor() -> bool:
	if _bridge == null or not _bridge.has_hit():
		return false
	return _bridge.request_anchor()


## Remove every anchor this manager placed.
func clear_anchors() -> void:
	if _bridge:
		_bridge.clear_anchors()


## True while a real surface sits under the viewer ray.
func has_hit() -> bool:
	return _bridge.has_hit() if _bridge else false


## World transform of the current surface hit (origin on the surface, +Y along
## the normal).
func get_hit_transform() -> Transform3D:
	return _bridge.get_hit_transform() if _bridge else Transform3D.IDENTITY


func get_anchor_count() -> int:
	return _bridge.get_anchor_count() if _bridge else 0


## The bridge's honest per-device availability line, for status displays.
func get_status() -> String:
	return str(_bridge.get_status()) if _bridge else "Hit test / anchors: web export required."


## Human label for what is aiming the hit ray ("your gaze", a hand...), for
## instruction text.
func get_hit_aim_label() -> String:
	return str(_bridge.get_hit_aim_label()) if _bridge else "your gaze"


func _on_hit_pose_updated(hit_transform: Transform3D) -> void:
	if _reticle:
		_reticle.visible = true
		_reticle.global_transform = hit_transform
	hit_updated.emit(hit_transform)


func _on_hit_lost() -> void:
	if _reticle:
		_reticle.visible = false
	hit_lost.emit()


func _on_anchor_node_added(anchor_id: int, anchor_node: XRAnchor3D) -> void:
	if placed_scene:
		var content := placed_scene.instantiate()
		anchor_node.add_child(content)
	anchor_placed.emit(anchor_id, anchor_node)


func _on_select(_input_source_id: int) -> void:
	place_anchor()


func _build_reticle() -> void:
	if reticle_scene:
		_reticle = reticle_scene.instantiate() as Node3D
	else:
		# Built-in ring: a flat torus on the surface (torus lies in XZ, matching
		# the hit pose's +Y-normal convention). Material from a pre-baked .tres.
		_reticle = Node3D.new()
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.055
		torus.outer_radius = 0.075
		torus.rings = 24
		torus.ring_segments = 12
		ring.mesh = torus
		ring.material_override = _RETICLE_MATERIAL
		_reticle.add_child(ring)
	_reticle.name = "HitReticle"
	_reticle.visible = false
	add_child(_reticle)
	_reticle.top_level = true
	_reticle.global_transform = Transform3D.IDENTITY


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if reticle_scene and not show_reticle:
		warnings.append("A reticle scene is set but Show Reticle is off - it will never appear.")
	return warnings
