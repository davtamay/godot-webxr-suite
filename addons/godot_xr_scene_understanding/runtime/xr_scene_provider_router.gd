class_name XRSceneProviderRouter
extends Node3D

## Capability-driven provider selection.
##
## Native providers are retried while OpenXR starts because extension support
## is only authoritative after the runtime has created its instance/session.

signal provider_changed(provider_id: String, provider_label: String)
signal status_changed

const _RETRY_SECONDS := 0.5

var feature := ""
var options: Dictionary = {}
var _active: XRSceneProvider
var _retry_left := 0.0
var _attempts := 0


func configure(p_feature: String, p_options: Dictionary) -> void:
	feature = p_feature
	options = p_options.duplicate(true)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_try_select()
	set_process(_active == null)


func _process(delta: float) -> void:
	if _active != null:
		set_process(false)
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_retry_left = _RETRY_SECONDS
		_try_select()


func _try_select() -> void:
	if _active != null:
		return
	_attempts += 1
	for path: String in _provider_paths():
		var script := load(path) as Script
		if script == null:
			continue
		var candidate := script.new() as XRSceneProvider
		if candidate == null:
			continue
		candidate.configure(options)
		add_child(candidate)
		if candidate.start():
			_active = candidate
			if not candidate.status_changed.is_connected(_on_provider_status_changed):
				candidate.status_changed.connect(_on_provider_status_changed)
			provider_changed.emit(candidate.provider_id, candidate.provider_label)
			set_process(false)
			return
		remove_child(candidate)
		candidate.queue_free()


func _provider_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	if feature == "environment_depth":
		if OS.has_feature("web"):
			paths.append(_optional_webxr_provider_path("environment_depth_provider.gd"))
		else:
			paths.append(_provider_path("openxr_meta", "environment_depth_provider.gd"))
			paths.append(_provider_path("openxr_android_xr", "environment_depth_provider.gd"))
	elif feature == "scene_mesh":
		if OS.has_feature("web"):
			paths.append(_optional_webxr_provider_path("scene_mesh_provider.gd"))
		else:
			# Android has an explicit support probe. Try it first, then Meta's
			# stored Scene Model.
			paths.append(_provider_path("openxr_android_xr", "scene_mesh_provider.gd"))
			paths.append(_provider_path("openxr_meta", "scene_mesh_provider.gd"))
	return paths


func _provider_path(provider: String, file_name: String) -> String:
	# Constructed at runtime so export filters can physically omit the opposite
	# platform's providers instead of Godot treating every path as a dependency.
	return (
		"res:"
		+ "//addons/godot_xr_scene_understanding/providers/"
		+ provider
		+ "/"
		+ file_name
	)


func _optional_webxr_provider_path(file_name: String) -> String:
	# The browser acquisition package depends on this neutral core, never the
	# other way around. Constructing the path keeps it a soft, strippable edge.
	return (
		"res:"
		+ "//addons/godot_webxr_scene_understanding/providers/"
		+ file_name
	)


func get_provider_id() -> String:
	return _active.provider_id if _active else "detecting"


func get_status() -> String:
	if _active:
		return _active.get_status()
	if OS.has_feature("web"):
		if not _has_webxr_provider():
			return "%s: WebXR provider is not installed." % _feature_label()
		return "%s: waiting for WebXR session." % _feature_label()
	if _attempts < 2:
		return "%s: waiting for OpenXR capabilities." % _feature_label()
	return "%s: no supported provider on the active OpenXR runtime." % _feature_label()


func is_live_reconstruction() -> bool:
	return _active.is_live_reconstruction() if _active else false


func set_visualize(enabled: bool) -> void:
	_set_option_and_forward("visualize", enabled, "set_visualize")


func set_occlusion(enabled: bool) -> void:
	_set_option_and_forward("occlude", enabled, "set_occlusion")


func set_occlude(enabled: bool) -> void:
	set_occlusion(enabled)


func set_labels(enabled: bool) -> void:
	_set_option_and_forward("scene_labels", enabled, "set_labels")


func set_resolution_level(level: int) -> void:
	_set_option_and_forward("depth_resolution", level, "set_resolution_level")


func set_occ_softness(softness: float) -> void:
	_set_option_and_forward("edge_softness", softness, "set_occ_softness")


func set_ext_harvest(enabled: bool) -> void:
	_set_option_and_forward("soft_occlusion", enabled, "set_ext_harvest")


func set_debug_visualization(enabled: bool) -> void:
	_set_option_and_forward("debug_depth_visualization", enabled, "set_debug_visualization")


func _set_option_and_forward(key: String, value: Variant, method: String) -> void:
	options[key] = value
	if _active and _active.has_method(method):
		_active.call(method, value)


func _feature_label() -> String:
	return "Environment depth" if feature == "environment_depth" else "Scene mesh"


func _has_webxr_provider() -> bool:
	var provider_file := (
		"environment_depth_provider.gd"
		if feature == "environment_depth"
		else "scene_mesh_provider.gd"
	)
	var bridge_file := (
		"webxr_depth_bridge.gd"
		if feature == "environment_depth"
		else "webxr_mesh_bridge.gd"
	)
	var provider_path := _optional_webxr_provider_path(provider_file)
	var bridge_path := (
		"res:"
		+ "//addons/godot_webxr_scene_understanding/runtime/"
		+ bridge_file
	)
	return (
		ResourceLoader.exists(provider_path, "Script")
		and ResourceLoader.exists(bridge_path, "Script")
	)


func _on_provider_status_changed() -> void:
	status_changed.emit()
