@tool
extends EditorPlugin

## All runtime classes are plain class_name scripts, so the toolkit works even
## when this plugin is disabled. Enabling it adds the "XR Blocks" dock - the
## suite's block catalog with one-click add (blocks from addons that are not
## installed hide themselves).

const _DOCK := preload("res://addons/godot_xr_interaction_toolkit/editor/xr_blocks_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = _DOCK.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
