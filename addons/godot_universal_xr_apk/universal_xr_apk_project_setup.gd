@tool
extends RefCounted

## Idempotent project setup used by the editor menu and headless tests.

const PRESET_NAME := "UniversalXRAPK"
const LEGACY_PRESET_NAME := "UniversalAndroidXR"
const PRESET_PATH := "res://export_presets.cfg"
const DEFAULT_EXPORT_PATH := "build/android/universal/GodotXR-universal-debug.apk"
const DEFAULT_ACTION_MAP := "res://addons/godot_webxr_kit/openxr/default_action_map.tres"


static func apply() -> Dictionary:
	var changes := PackedStringArray()

	_set_project_setting("xr/openxr/enabled", true, changes)
	# Request alpha-blended composition before OpenXR initializes. Android XR
	# exposes it directly; the Meta vendors extension emulates it with
	# XR_FB_passthrough on Quest.
	_set_project_setting("xr/openxr/environment_blend_mode", 2, changes)
	# Match WebXR's local-floor space. Godot defaults to Stage, whose room
	# forward is arbitrary and whose floor may be invalid when no valid
	# boundary is configured, placing fixed UI behind/above the user.
	_set_project_setting("xr/openxr/reference_space", 2, changes)
	_set_project_setting("xr/openxr/extensions/hand_tracking", true, changes)
	# Request both perception families as optional OpenXR extensions. The
	# runtime exposes only the family it implements, and the provider router
	# selects it by capability (the same pattern as the proven Unreal APK).
	_set_project_setting("xr/openxr/extensions/meta/passthrough", true, changes)
	_set_project_setting("xr/openxr/extensions/meta/scene_api", true, changes)
	_set_project_setting("xr/openxr/extensions/meta/environment_depth", true, changes)
	_set_project_setting("xr/openxr/extensions/androidxr/scene_meshing", true, changes)
	_set_project_setting("xr/openxr/extensions/androidxr/environment_depth", true, changes)
	# Let each runtime perform its stable hands/controllers transition. Meta's
	# simultaneous mode is useful for opt-in multimodal scenes, but on Quest it
	# can expose a controller-like aim source while a bare hand points.
	_set_project_setting("xr/openxr/extensions/meta/simultaneous_hands_and_controllers", false, changes)
	# Godot recommends Compatibility/OpenGL on standalone Android headsets.
	# This is only the mobile-platform override, so a project's explicit
	# renderer.web override (for example Mobile/WebGPU) remains untouched.
	_set_project_setting("rendering/renderer/rendering_method.mobile", "gl_compatibility", changes)
	_set_project_setting("textures/vram_compression/import_etc2_astc", true, changes)
	if ResourceLoader.exists(DEFAULT_ACTION_MAP):
		_set_project_setting("xr/openxr/default_action_map", DEFAULT_ACTION_MAP, changes)

	var save_project_error := ProjectSettings.save()
	if save_project_error != OK:
		return {
			"ok": false,
			"error": "Could not save project.godot (error %d)." % save_project_error,
			"changes": changes,
		}

	var config := ConfigFile.new()
	var load_error := config.load(PRESET_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return {
			"ok": false,
			"error": "Could not read export_presets.cfg (error %d)." % load_error,
			"changes": changes,
		}

	var preset_index := _find_preset(config, PRESET_NAME)
	if preset_index < 0:
		preset_index = _find_preset(config, LEGACY_PRESET_NAME)
		if preset_index >= 0:
			changes.append("Renamed %s to %s" % [LEGACY_PRESET_NAME, PRESET_NAME])
		else:
			preset_index = _next_preset_index(config)
			changes.append("Created the %s export preset" % PRESET_NAME)

	var section := "preset.%d" % preset_index
	var options := "%s.options" % section

	_set_config(config, section, "name", PRESET_NAME, changes)
	_set_config(config, section, "platform", "Android", changes)
	_set_config(config, section, "dedicated_server", false, changes)
	_set_config(config, section, "custom_features", "universal_xr_apk", changes)
	_set_config(config, section, "export_filter", "exclude", changes)
	_set_config(config, section, "export_files", PackedStringArray(), changes)
	_set_config(config, section, "include_filter", "", changes)
	_set_config(
		config,
		section,
		"exclude_filter",
		"tests/*,build/**/*,web/**/*,addons/godot_webxr_kit/web/**/*,addons/godot_webgpu/**/*,addons/godot_xr_scene_understanding/providers/webxr/*,addons/godot_xr_scene_understanding/providers/webxr/**/*,addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd*,addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd*,addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd*,addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd*,addons/godotopenxrvendors/.bin/windows/**/*,addons/godotopenxrvendors/.bin/linux/**/*,addons/godotopenxrvendors/.bin/macos/**/*,addons/godotopenxrvendors/.bin/android/debug/*,addons/godotopenxrvendors/.bin/android/debug/**/*,addons/godotopenxrvendors/.bin/android/release/*,addons/godotopenxrvendors/.bin/android/release/**/*,addons/godotopenxrvendors/.bin/android/template_debug/x86_64/*,addons/godotopenxrvendors/.bin/android/template_release/x86_64/*,addons/godot_universal_xr_apk/**/*,addons/*/editor/**/*,addons/godot_blender_principled/samples/assets/MaterialCollection.glb",
		changes
	)
	_set_config(config, section, "export_path", DEFAULT_EXPORT_PATH, changes)
	_set_config(config, section, "patches", PackedStringArray(), changes)
	_set_config(config, section, "encryption_include_filters", "", changes)
	_set_config(config, section, "encryption_exclude_filters", "", changes)
	_set_config(config, section, "seed", 0, changes)
	_set_config(config, section, "encrypt_pck", false, changes)
	_set_config(config, section, "encrypt_directory", false, changes)
	_set_config(config, section, "script_export_mode", 2, changes)

	# A Gradle build is required by Godot's built-in Android OpenXR loader.
	_set_config(config, options, "gradle_build/use_gradle_build", true, changes)
	_set_config(config, options, "gradle_build/export_format", 0, changes)
	_set_config(config, options, "gradle_build/min_sdk", "34", changes)
	_set_config(config, options, "gradle_build/target_sdk", "35", changes)

	# One binary ABI shared by Quest 3 and Galaxy XR.
	_set_config(config, options, "architectures/armeabi-v7a", false, changes)
	_set_config(config, options, "architectures/arm64-v8a", true, changes)
	_set_config(config, options, "architectures/x86", false, changes)
	_set_config(config, options, "architectures/x86_64", false, changes)

	_set_config(config, options, "xr_features/xr_mode", 1, changes)
	_set_config(config, options, "universal_xr_apk/enabled", true, changes)
	if config.has_section_key(options, "universal_android_xr/enabled"):
		config.erase_section_key(options, "universal_android_xr/enabled")
		changes.append("Removed the legacy universal_android_xr option")
	if config.has_section_key(options, "universal_android_xr/status"):
		config.erase_section_key(options, "universal_android_xr/status")

	# UniversalDev deliberately uses Godot's Khronos loader only. Enabling the
	# Android XR vendor exporter currently marks libopenxr.google.so required,
	# which makes the same APK impossible to install on a Quest.
	_set_config(config, options, "xr_features/enable_khronos_plugin", false, changes)
	_set_config(config, options, "xr_features/enable_androidxr_plugin", false, changes)
	_set_config(config, options, "xr_features/enable_meta_plugin", false, changes)
	_set_config(config, options, "xr_features/enable_pico_plugin", false, changes)
	_set_config(config, options, "xr_features/enable_magicleap_plugin", false, changes)

	var save_preset_error := config.save(PRESET_PATH)
	if save_preset_error != OK:
		return {
			"ok": false,
			"error": "Could not save export_presets.cfg (error %d)." % save_preset_error,
			"changes": changes,
		}

	return {"ok": true, "changes": changes, "preset_index": preset_index}


static func _set_project_setting(key: String, value: Variant, changes: PackedStringArray) -> void:
	if ProjectSettings.get_setting(key, null) == value:
		return
	ProjectSettings.set_setting(key, value)
	changes.append("Set Project Settings > %s" % key)


static func _set_config(
	config: ConfigFile,
	section: String,
	key: String,
	value: Variant,
	changes: PackedStringArray
) -> void:
	if config.has_section_key(section, key) and config.get_value(section, key) == value:
		return
	config.set_value(section, key, value)
	changes.append("Set %s/%s" % [section, key])


static func _find_preset(config: ConfigFile, preset_name: String) -> int:
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		if str(config.get_value(section, "name", "")) == preset_name:
			return int(section.trim_prefix("preset."))
	return -1


static func _next_preset_index(config: ConfigFile) -> int:
	var highest := -1
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		highest = maxi(highest, int(section.trim_prefix("preset.")))
	return highest + 1
