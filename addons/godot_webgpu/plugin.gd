@tool
extends EditorPlugin

## Standalone WebGPU-for-web tooling. No dependencies. While enabled it
## registers the WebGPU adaptive-build export plugin, which adds a one-checkbox
## "WebGPU (adaptive) build" toggle to the Web export preset
## (see webgpu_export_plugin.gd). The BakeAnchor node (bake_anchor.gd) is a
## plain class_name script, available whenever this addon is present.

const _WEBGPU_EXPORT := preload("res://addons/godot_webgpu/webgpu_export_plugin.gd")

var _webgpu_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_webgpu_export_plugin = _WEBGPU_EXPORT.new()
	add_export_plugin(_webgpu_export_plugin)


func _exit_tree() -> void:
	if _webgpu_export_plugin != null:
		remove_export_plugin(_webgpu_export_plugin)
		_webgpu_export_plugin = null
