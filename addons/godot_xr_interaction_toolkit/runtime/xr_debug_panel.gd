@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_ui_canvas_interactable.svg")
class_name XRDebugPanel
extends Node3D

## In-headset debug HUD: the one panel that stays visible INSIDE a session.
## Status/status-bar UI is 2D and auto-hidden during immersive sessions, and
## print() goes to consoles a standalone headset can't show - on-device
## iteration was blind. Drop this block where you can see it and it shows:
##
## - a live status line: FPS, session state, per-hand modality
## - an event log auto-wired to the suite's signals (session lifecycle,
##   teleports, grabs/throws, sockets, gestures, modality switches)
## - your own lines: get_tree().call_group("xr_debug_panel", "log_line", msg)
##
## Self-building (no scene deps), bake-safe materials. Label3D on WebGPU
## exports needs a FontBakeAnchor (godot_webgpu addon); WebGL needs nothing.

const GROUP := "xr_debug_panel"
## OPAQUE on purpose: a transparent backdrop sorts against the (transparent)
## Label3D text at near-identical depth and can draw over it - the panel
## then reads as a solid black quad. Opaque writes depth; text always wins.
const _BACKDROP_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/xr_debug_panel_material.tres")

@export_range(3, 24, 1) var max_log_lines := 9
## Auto-connect to every suite signal source found in the scene at start.
@export var follow_signals := true
## Panel width; HEIGHT is automatic - compact when idle, grows downward from
## the node origin (the anchored top edge) as log lines accumulate.
@export var panel_width := 0.45

const _LINE_HEIGHT := 0.0145
const _TOP_PAD := 0.015
const _STATUS_TO_LOG := 0.03

var _backdrop: MeshInstance3D
var _status_label: Label3D
var _log_label: Label3D
var _log_lines: PackedStringArray = []
var _elapsed := 1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	_build_panel()
	if follow_signals:
		_wire_signals.call_deferred()


func log_line(text: String) -> void:
	_log_lines.append("%6.1f  %s" % [Time.get_ticks_msec() / 1000.0, text])
	while _log_lines.size() > max_log_lines:
		_log_lines.remove_at(0)
	if _log_label:
		_log_label.text = "\n".join(_log_lines)
		_update_layout()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0.0
	if _status_label == null:
		return
	var session := "flat"
	if get_viewport().use_xr:
		session = "XR"
	var modality := ""
	var manager := get_tree().get_first_node_in_group("xr_input_modality_manager")
	if manager and manager.has_method("get_modality"):
		var names := ["-", "CTRL", "HAND"]
		modality = "  L:%s R:%s" % [names[manager.get_modality(0)], names[manager.get_modality(1)]]
	_status_label.text = "FPS %d  |  %s%s" % [Engine.get_frames_per_second(), session, modality]


func _build_panel() -> void:
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = QuadMesh.new()
	_backdrop.material_override = _BACKDROP_MATERIAL
	add_child(_backdrop)

	_status_label = _make_label(Vector3(0.0, -_TOP_PAD, 0.002))
	_status_label.text = "XR Debug Panel"
	_log_label = _make_label(Vector3(0.0, -_TOP_PAD - _STATUS_TO_LOG, 0.002))
	_update_layout()


## Height fits the content: the node origin is the panel's TOP edge and the
## backdrop extends down as the log grows.
func _update_layout() -> void:
	var height := _TOP_PAD + _STATUS_TO_LOG + maxf(_log_lines.size(), 1) * _LINE_HEIGHT + _TOP_PAD
	(_backdrop.mesh as QuadMesh).size = Vector2(panel_width, height)
	_backdrop.position = Vector3(0.0, -height * 0.5, 0.0)


func _make_label(at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.pixel_size = 0.0004
	label.font_size = 30
	label.modulate = Color(0.85, 0.95, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.width = (panel_width - 0.02) / 0.0004
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.position = at
	add_child(label)
	return label


## Auto-wire every signal source the suite ships. Nodes added later are not
## picked up (call log_line yourself, or re-add the panel).
func _wire_signals() -> void:
	var count := 0
	for node in _walk(get_tree().current_scene if get_tree().current_scene else get_tree().root):
		count += _try_connect(node)
	log_line("debug panel wired to %d signal sources" % count)


func _walk(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _try_connect(node: Node) -> int:
	var wired := 0
	var hooks := {
		"session_started": func(mode): log_line("session started: %s" % mode),
		"session_ended": func(): log_line("session ended"),
		"session_failed": func(message): log_line("SESSION FAILED: %s" % message),
		"teleported": func(_from, to): log_line("teleported -> %s" % (to as Vector3).snapped(Vector3(0.1, 0.1, 0.1))),
		"teleport_cancelled": func(hand): log_line("teleport aim cancelled (hand %d)" % hand),
		"snap_turned": func(degrees): log_line("snap turn %+.0f deg" % degrees),
		"grabbed": func(_interactor): log_line("grabbed: %s" % node.name),
		"released": func(_interactor): log_line("released: %s" % node.name),
		"thrown": func(linear, _angular): log_line("thrown: %s at %.1f m/s" % [node.name, (linear as Vector3).length()]),
		"object_socketed": func(interactable): log_line("socketed: %s" % interactable.name),
		"object_released": func(interactable): log_line("socket released: %s" % interactable.name),
		"modality_changed": func(hand, modality): log_line("hand %d -> %s" % [hand, ["NONE", "CONTROLLER", "HAND"][modality]]),
		"gesture_started": func(gesture_name, hand): log_line("gesture %s (hand %d)" % [gesture_name, hand]),
	}
	for signal_name in hooks:
		if node.has_signal(signal_name):
			node.connect(signal_name, hooks[signal_name])
			wired += 1
	return wired
