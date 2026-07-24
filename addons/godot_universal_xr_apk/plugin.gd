@tool
extends EditorPlugin

## Editor/export tooling for the suite's portable native OpenXR baseline.
##
## The runtime stays in godot_webxr_kit. This addon owns only:
##   - the optional Android XR manifest declarations needed by a universal APK;
##   - a repeatable UniversalXRAPK export preset;
##   - validation before export.

const _EXPORT_PLUGIN := preload("res://addons/godot_universal_xr_apk/universal_xr_apk_export_plugin.gd")
const _PROJECT_SETUP := preload("res://addons/godot_universal_xr_apk/universal_xr_apk_project_setup.gd")

var _export_plugin: EditorExportPlugin
var _result_dialog: AcceptDialog


func _enter_tree() -> void:
	_export_plugin = _EXPORT_PLUGIN.new()
	add_export_plugin(_export_plugin)
	add_tool_menu_item("Set Up Universal XR APK Export", _setup_project)


func _exit_tree() -> void:
	remove_tool_menu_item("Set Up Universal XR APK Export")
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _result_dialog != null:
		_result_dialog.queue_free()
		_result_dialog = null


func _setup_project() -> void:
	var result := _PROJECT_SETUP.apply()
	if _result_dialog == null:
		_result_dialog = AcceptDialog.new()
		_result_dialog.title = "Universal XR APK Setup"
		EditorInterface.get_base_control().add_child(_result_dialog)

	var lines: PackedStringArray = result.get("changes", PackedStringArray())
	if result.get("ok", false):
		if lines.is_empty():
			_result_dialog.dialog_text = "Already configured. UniversalXRAPK is ready."
		else:
			_result_dialog.dialog_text = "Configured UniversalXRAPK:\n\n- " + "\n- ".join(lines)
	else:
		_result_dialog.dialog_text = "Setup failed:\n\n" + str(result.get("error", "Unknown error"))
	_result_dialog.popup_centered(Vector2i(620, 360))
