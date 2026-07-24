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
## automatically. Anchors are standard XRAnchor3D trackers: browser anchors are
## platform-tracked; native room-surface anchors are world-locked for the
## current OpenXR session.
##
## Zero wiring: the reticle is auto-built (or bring your own via
## [member reticle_scene]), placement is one property, and the node requests
## the 'hit-test' + 'anchors' session features by itself. [method get_status]
## reports per-device availability honestly. WebXR uses the browser hit-test
## provider; native OpenXR raycasts the neutral Quest/Android XR room mesh.
##
## NOTE on place_on_select: UI-canvas pinches are filtered automatically. For
## more specialized gameplay arbitration, set place_on_select = false and call
## [method place_anchor] from your own gesture/button.

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

const _WEB_BRIDGE_SCRIPT := "res://addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd"
const _NATIVE_BRIDGE_SCRIPT := "res://addons/godot_xr_scene_understanding/providers/openxr_common/native_hit_test_anchor_provider.gd"
## Pre-baked reticle material (WebGPU-export safe).
const _RETICLE_MATERIAL := preload("res://addons/godot_webxr_scene_understanding/runtime/hit_reticle_material.tres")

## Master switch for targeting and placement. Keep this off until the user
## explicitly enters placement mode so ordinary UI pinches never create
## anchors unexpectedly.
@export var enabled := false:
	set(value):
		var was_enabled := enabled
		enabled = value
		if enabled and not was_enabled:
			_enabled_at_msec = Time.get_ticks_msec()
		_sync_enabled_state()

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
var _enabled_at_msec := 0


func _enter_tree() -> void:
	add_to_group("xr_hit_test_anchor_manager")


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Anchored content is world-space; never let this manager's own transform
	# offset it, wherever the user parked the node.
	_anchor_root = Node3D.new()
	_anchor_root.name = "Anchors"
	add_child(_anchor_root)
	_anchor_root.top_level = true
	_anchor_root.global_transform = Transform3D.IDENTITY

	var bridge_path := _WEB_BRIDGE_SCRIPT if OS.has_feature("web") else _NATIVE_BRIDGE_SCRIPT
	if not ResourceLoader.exists(bridge_path):
		push_warning("Hit Test + Anchors provider missing: %s" % bridge_path)
		return
	var script := load(bridge_path)
	_bridge = script.new()
	_bridge.name = "HitTestAnchorBridge"
	_bridge.maximum_anchors = maximum_anchors
	add_child(_bridge)
	_bridge.anchor_node_root = _bridge.get_path_to(_anchor_root)
	_bridge.hit_pose_updated.connect(_on_hit_pose_updated)
	_bridge.hit_lost.connect(_on_hit_lost)
	_bridge.anchor_node_added.connect(_on_anchor_node_added)
	_bridge.anchor_removed.connect(func(anchor_id: int) -> void: anchor_removed.emit(anchor_id))
	_bridge.anchor_failed.connect(func(message: String) -> void: anchor_failed.emit(message))
	if _bridge.has_signal("select_pressed"):
		_bridge.select_pressed.connect(_on_native_select)

	if show_reticle:
		_build_reticle()

	if place_on_select:
		var webxr := XRServer.find_interface("WebXR")
		if webxr and webxr.has_signal("select"):
			webxr.select.connect(_on_select)
	_sync_enabled_state()


## Enable or disable visible targeting and pinch/select placement.
func set_enabled(value: bool) -> void:
	enabled = value


func is_enabled() -> bool:
	return enabled


## Place an anchor at the current surface hit. False when nothing is hit; the
## result arrives via [signal anchor_placed] / [signal anchor_failed].
func place_anchor() -> bool:
	if not enabled or _bridge == null or not _bridge.has_hit():
		return false
	return _bridge.request_anchor()


## Remove every anchor this manager placed.
func clear_anchors() -> void:
	if _bridge:
		_bridge.clear_anchors()


## True while a real surface sits under the viewer ray.
func has_hit() -> bool:
	return enabled and _bridge != null and _bridge.has_hit()


## World transform of the current surface hit (origin on the surface, +Y along
## the normal).
func get_hit_transform() -> Transform3D:
	return _bridge.get_hit_transform() if _bridge else Transform3D.IDENTITY


func get_anchor_count() -> int:
	return _bridge.get_anchor_count() if _bridge else 0


## The bridge's honest per-device availability line, for status displays.
func get_status() -> String:
	if not enabled:
		return "Hit Test + Anchors: off. Enable to show a surface target and pinch to place."
	return str(_bridge.get_status()) if _bridge else "Hit Test + Anchors: provider unavailable."


## Human label for what is aiming the hit ray ("your gaze", a hand...), for
## instruction text.
func get_hit_aim_label() -> String:
	return str(_bridge.get_hit_aim_label()) if _bridge else "your gaze"


func _on_hit_pose_updated(hit_transform: Transform3D) -> void:
	if not enabled:
		if _reticle:
			_reticle.visible = false
		return
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
	if not enabled:
		return
	# The select event that toggles placement on can arrive after the Button's
	# toggled signal. Ignore that gesture, and any later gesture currently
	# targeting an XR UI canvas, so controls never spawn anchors.
	if Time.get_ticks_msec() - _enabled_at_msec < 350:
		return
	if _pointer_over_ui():
		return
	place_anchor()


func _on_native_select(hand: int) -> void:
	if _bridge and _bridge.has_method("set_preferred_hand"):
		_bridge.set_preferred_hand(hand)
	_on_select(hand)


func _sync_enabled_state() -> void:
	if _bridge and _bridge.has_method("set_enabled"):
		_bridge.set_enabled(enabled)
	if not enabled and _reticle:
		_reticle.visible = false


func _pointer_over_ui() -> bool:
	for node in get_tree().get_nodes_in_group("xr_ui_canvas"):
		if (
			(node.has_method("is_hovered") and bool(node.call("is_hovered")))
			or (node.has_method("is_selected") and bool(node.call("is_selected")))
		):
			return true
	return false


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
