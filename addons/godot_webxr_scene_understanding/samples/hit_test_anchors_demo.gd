extends Node3D

const ANCHOR_MARKER := preload("res://addons/godot_webxr_scene_understanding/samples/anchor_marker.tscn")

@onready var _bridge: Node = $XROrigin3D/HitTestAnchorBridge
@onready var _reticle: Node3D = $XROrigin3D/HitReticle
@onready var _anchor_container: Node3D = $XROrigin3D/AnchoredObjects
@onready var _world_status: Label3D = $XROrigin3D/GuidePanel/Status
@onready var _screen_status: Label = %DemoStatus
@onready var _clear_button: Button = %ClearButton

var _webxr: XRInterface
var _markers := {}
var _status_accum := 0.0
var _transient_message := ""
var _transient_time := 0.0


func _ready() -> void:
	const MENU_BUTTON := "res://scripts/back_to_menu_button.gd"
	if ResourceLoader.exists(MENU_BUTTON):
		var menu_button = load(MENU_BUTTON)
		if menu_button:
			add_child(menu_button.new())

	_bridge.hit_pose_updated.connect(_on_hit_pose_updated)
	_bridge.hit_lost.connect(_on_hit_lost)
	_bridge.anchor_added.connect(_on_anchor_added)
	_bridge.anchor_updated.connect(_on_anchor_updated)
	_bridge.anchor_removed.connect(_on_anchor_removed)
	_bridge.anchor_failed.connect(_on_anchor_failed)
	_clear_button.pressed.connect(_clear_anchors)
	_reticle.visible = false

	if OS.has_feature("web"):
		_webxr = XRServer.find_interface("WebXR")
		if _webxr and _webxr.has_signal("select"):
			_webxr.select.connect(_on_webxr_select)


func _process(delta: float) -> void:
	_status_accum += delta
	_transient_time = maxf(0.0, _transient_time - delta)
	var now := Time.get_ticks_msec() * 0.001
	if _reticle.visible:
		var pulse := 1.0 + sin(now * 8.0) * 0.08
		_reticle.scale = Vector3.ONE * pulse
	for marker_value in _markers.values():
		if marker_value is Node3D and marker_value.visible:
			var marker := marker_value as Node3D
			var orbit := marker.get_node_or_null("Orbit") as Node3D
			var orbit_tilt := marker.get_node_or_null("OrbitTilt") as Node3D
			var beacon := marker.get_node_or_null("Beacon") as Node3D
			if orbit:
				orbit.rotate_y(delta * 2.2)
			if orbit_tilt:
				orbit_tilt.rotate_z(-delta * 1.6)
			if beacon:
				beacon.scale = Vector3.ONE * (1.0 + sin(now * 4.5 + marker.get_instance_id()) * 0.1)
	if _status_accum < 0.2:
		return
	_status_accum = 0.0
	var status := _transient_message if _transient_time > 0.0 else str(_bridge.get_status())
	status += "\nAim with %s. Pinch or press trigger/select when the cyan reticle is visible." % _bridge.get_hit_aim_label()
	_world_status.text = status
	_screen_status.text = status


func _on_webxr_select(_input_source_id: int) -> void:
	if _bridge.request_anchor():
		_show_transient("Creating a stable WebXR anchor at the selected surface...", 1.4)
	else:
		_show_transient("No surface hit yet. Move your head and aim at a floor, table, or wall.", 1.8)


func _on_hit_pose_updated(hit_transform: Transform3D) -> void:
	_reticle.transform = hit_transform
	_reticle.visible = true


func _on_hit_lost() -> void:
	_reticle.visible = false


func _on_anchor_added(anchor_id: int, anchor_transform: Transform3D) -> void:
	var marker := ANCHOR_MARKER.instantiate() as Node3D
	marker.name = "Anchor_%d" % anchor_id
	marker.transform = anchor_transform
	var label := marker.get_node_or_null("AnchorLabel") as Label3D
	if label:
		label.text = "ANCHOR %02d" % anchor_id
	_anchor_container.add_child(marker)
	_markers[anchor_id] = marker
	marker.scale = Vector3.ONE * 0.04
	var reveal := create_tween()
	reveal.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(marker, "scale", Vector3.ONE * 1.12, 0.24)
	reveal.tween_property(marker, "scale", Vector3.ONE, 0.12)
	_show_transient("Anchor %d created. It now follows the runtime's stable anchor pose." % anchor_id, 1.8)


func _on_anchor_updated(anchor_id: int, anchor_transform: Transform3D, tracked: bool) -> void:
	var marker = _markers.get(anchor_id)
	if marker is Node3D:
		marker.transform = anchor_transform
		marker.visible = tracked


func _on_anchor_removed(anchor_id: int) -> void:
	var marker = _markers.get(anchor_id)
	if marker is Node:
		marker.queue_free()
	_markers.erase(anchor_id)


func _on_anchor_failed(message: String) -> void:
	_show_transient("Anchor creation failed: %s" % message, 2.5)


func _clear_anchors() -> void:
	_bridge.clear_anchors()
	_show_transient("All demo anchors cleared.", 1.4)


func _show_transient(message: String, duration: float) -> void:
	_transient_message = message
	_transient_time = duration
