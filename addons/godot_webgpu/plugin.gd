@tool
extends EditorPlugin

## Standalone WebGPU-for-web tooling. No dependencies. Adds a clear "WebGPU"
## toggle to the Web export preset (webgpu_export_plugin.gd) with an in-panel
## status line. Turning it on bakes shaders automatically (the raw "Shader Baker"
## toggle is hidden) and, if the project isn't set up yet, pops up a one-click
## "Set up WebGPU rendering" dialog. Everything lives in the export panel - no
## menu items. The BakeAnchor node (bake_anchor.gd) is available whenever this
## addon is on.

const _WEBGPU_EXPORT := preload("res://addons/godot_webgpu/webgpu_export_plugin.gd")

var _export_plugin: EditorExportPlugin
var _dialog: ConfirmationDialog


func _enter_tree() -> void:
	_export_plugin = _WEBGPU_EXPORT.new()
	_export_plugin.editor_plugin = self
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
	if _dialog != null:
		_dialog.queue_free()
		_dialog = null


## Called (deferred) by the export plugin when WebGPU is enabled on an
## unconfigured project. No-op if the project is already set up.
func show_setup_popup() -> void:
	if _base_ok():
		return
	if _dialog == null:
		_dialog = ConfirmationDialog.new()
		_dialog.title = "Set up WebGPU rendering"
		_dialog.ok_button_text = "Configure + restart"
		_dialog.confirmed.connect(_apply)
		EditorInterface.get_base_control().add_child(_dialog)
	_dialog.dialog_text = ("Set this project up for the WebGPU backend?\n\n"
		+ "• Renderer → Mobile, so shaders can bake\n"
		+ "• Web build → WebGPU (falls back to WebGL where unsupported)\n"
		+ "• Restarts the editor to apply the renderer\n\n"
		+ "One-time setup. After the restart, tick WebGPU again in the export "
		+ "preset - it will stick, and the status line will read Configured ✓.")
	_dialog.popup_centered()


func _apply() -> void:
	if _base_ok():
		return
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "mobile")
	ProjectSettings.set_setting("rendering/renderer/rendering_method.web", "mobile")
	ProjectSettings.set_setting("rendering/rendering_device/driver.web", "webgpu")
	# Mono XR shaders: the per-view WebGPU path doesn't use multiview, and
	# multiview variants don't bake to WGSL. No-op for non-XR projects.
	ProjectSettings.set_setting("xr/shaders/enabled", false)
	ProjectSettings.save()
	EditorInterface.restart_editor(true)


func _base_ok() -> bool:
	# "Configured" = the editor is actually running a RenderingDevice renderer (so
	# the shader baker runs), not merely that the saved setting says so.
	return RenderingServer.get_rendering_device() != null
