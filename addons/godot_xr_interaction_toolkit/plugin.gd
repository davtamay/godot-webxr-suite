@tool
extends EditorPlugin

## All runtime classes are plain class_name scripts, so the toolkit works even
## when this plugin is disabled. Enabling it adds the "XR Suite" dock: project
## preset-driven Project Validator/addon resolution plus the Scene Blocks catalog.

const _DOCK := preload("res://addons/godot_xr_interaction_toolkit/editor/xr_blocks_dock.gd")
const _EXPORT_CLEANUP := preload(
	"res://addons/godot_xr_interaction_toolkit/editor/xr_export_cleanup_plugin.gd"
)

var _dock: Control
var _export_cleanup: EditorExportPlugin


func _enter_tree() -> void:
	_export_cleanup = _EXPORT_CLEANUP.new()
	add_export_plugin(_export_cleanup)
	_dock = _DOCK.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _export_cleanup:
		remove_export_plugin(_export_cleanup)
		_export_cleanup = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
