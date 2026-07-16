extends Node3D

## Hit-test + anchors demo. All the machinery - viewer-ray surface hits, the
## reticle, select-to-place, XRAnchor3D lifecycle, marker instancing - lives in
## the drop-in HitTestAnchorManager node (this scene just hands it a custom
## reticle and the beacon scene). This script owns only the demo dressing:
## the beacon animations, anchor labels, transient messages, and status lines.

@onready var _manager = $HitTestAnchorManager
@onready var _world_status: Label3D = $GuidePanel/Status
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

	_manager.anchor_placed.connect(_on_anchor_placed)
	_manager.anchor_removed.connect(_on_anchor_removed)
	_manager.anchor_failed.connect(_on_anchor_failed)
	_clear_button.pressed.connect(_clear_anchors)

	# Placement itself is the manager's (place_on_select); this handler only
	# adds the helpful "no surface yet" coaching message.
	if OS.has_feature("web"):
		_webxr = XRServer.find_interface("WebXR")
		if _webxr and _webxr.has_signal("select"):
			_webxr.select.connect(_on_webxr_select)


func _process(delta: float) -> void:
	_status_accum += delta
	_transient_time = maxf(0.0, _transient_time - delta)
	var now := Time.get_ticks_msec() * 0.001
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
	var status := _transient_message if _transient_time > 0.0 else str(_manager.get_status())
	status += "\nAim with %s. Pinch or press trigger/select when the cyan reticle is visible." % _manager.get_hit_aim_label()
	_world_status.text = status
	_screen_status.text = status


func _on_webxr_select(_input_source_id: int) -> void:
	if _manager.has_hit():
		_show_transient("Creating a stable WebXR anchor at the selected surface...", 1.4)
	else:
		_show_transient("No surface hit yet. Move your head and aim at a floor, table, or wall.", 1.8)


func _on_anchor_placed(anchor_id: int, anchor_node: XRAnchor3D) -> void:
	# The manager already instanced the beacon (placed_scene) under the
	# XRAnchor3D, which the platform keeps world-locked - no manual transform
	# tracking. This handler just dresses it up.
	var marker: Node3D = null
	if anchor_node.get_child_count() > 0:
		marker = anchor_node.get_child(0) as Node3D
	if marker == null:
		return
	marker.name = "Anchor_%d" % anchor_id
	var label := marker.get_node_or_null("AnchorLabel") as Label3D
	if label:
		label.text = "ANCHOR %02d" % anchor_id
	_markers[anchor_id] = marker
	marker.scale = Vector3.ONE * 0.04
	var reveal := create_tween()
	reveal.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(marker, "scale", Vector3.ONE * 1.12, 0.24)
	reveal.tween_property(marker, "scale", Vector3.ONE, 0.12)
	_show_transient("Anchor %d created. It now follows the runtime's stable anchor pose." % anchor_id, 1.8)


func _on_anchor_removed(anchor_id: int) -> void:
	_markers.erase(anchor_id)  # the bridge frees the anchor node (and beacon) itself


func _on_anchor_failed(message: String) -> void:
	_show_transient("Anchor creation failed: %s" % message, 2.5)


func _clear_anchors() -> void:
	_manager.clear_anchors()
	_show_transient("All demo anchors cleared.", 1.4)


func _show_transient(message: String, duration: float) -> void:
	_transient_message = message
	_transient_time = duration
