class_name XRSceneProvider
extends Node3D

## Minimal contract implemented by every scene-understanding provider.
##
## Deliberately uses only built-in Godot types. Native provider scripts call
## vendor classes dynamically so web exports and projects without the native
## dependency still parse and run.

signal status_changed

var provider_id := "unavailable"
var provider_label := "Unavailable"
var options: Dictionary = {}
var _passthrough_claimed := false


func configure(p_options: Dictionary) -> void:
	options = p_options.duplicate(true)


func start() -> bool:
	return false


func stop() -> void:
	pass


func get_status() -> String:
	return "%s: unavailable." % provider_label


func is_live_reconstruction() -> bool:
	return false


func set_visualize(_enabled: bool) -> void:
	pass


func set_occlusion(_enabled: bool) -> void:
	pass


func set_labels(_enabled: bool) -> void:
	pass


func set_resolution_level(_level: int) -> void:
	pass


func set_occ_softness(_softness: float) -> void:
	pass


func set_ext_harvest(_enabled: bool) -> void:
	pass


func set_occlude(enabled: bool) -> void:
	set_occlusion(enabled)


func set_debug_visualization(enabled: bool) -> void:
	set_visualize(enabled)


func enable_native_passthrough() -> void:
	if OS.has_feature("web") or _passthrough_claimed:
		return
	var interface := XRServer.find_interface("OpenXR")
	if interface == null:
		return
	var modes: Array = interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND not in modes:
		return
	interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	get_viewport().transparent_bg = true
	add_to_group(&"xr_native_passthrough_provider")
	_passthrough_claimed = true


func _release_native_passthrough() -> void:
	if not _passthrough_claimed:
		return
	remove_from_group(&"xr_native_passthrough_provider")
	if get_tree() and get_tree().get_nodes_in_group(&"xr_native_passthrough_provider").is_empty():
		var interface := XRServer.find_interface("OpenXR")
		if interface:
			var modes: Array = interface.get_supported_environment_blend_modes()
			if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
				interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		if get_viewport():
			get_viewport().transparent_bg = false
	_passthrough_claimed = false


func _exit_tree() -> void:
	stop()
	_release_native_passthrough()
