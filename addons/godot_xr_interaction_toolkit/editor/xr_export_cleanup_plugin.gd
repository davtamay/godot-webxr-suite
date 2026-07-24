@tool
extends EditorExportPlugin

## Export-time package cleanup for every XR Suite build. The active Godot
## export platform is the source of truth: Web drops native tooling/providers,
## Android drops browser tooling/providers, and both drop editor-only files.
## Optional capabilities use Auto/Force Include/Strip from XR Suite Validator.

const _Packages := preload(
	"res://addons/godot_xr_interaction_toolkit/editor/xr_package_resolver.gd"
)
const _FEATURE_MODES_SETTING := "xr_suite/authoring/feature_modes"

const _WEB_ONLY_PREFIXES := [
	"res://web/",
	"res://addons/godot_webxr_kit/web/",
	"res://addons/godot_webgpu/",
	"res://addons/godot_webxr_scene_understanding/providers/",
]
const _WEB_ONLY_FILES := [
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd.uid",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd.uid",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd.uid",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd.uid",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_capability_manifest.gd",
	"res://addons/godot_webxr_scene_understanding/runtime/webxr_capability_manifest.gd.uid",
]
const _NATIVE_ONLY_PREFIXES := [
	"res://addons/godotopenxrvendors/",
	"res://addons/godot_universal_xr_apk/",
	"res://addons/godot_xr_scene_understanding/providers/openxr_meta/",
	"res://addons/godot_xr_scene_understanding/providers/openxr_android_xr/",
	"res://addons/godot_xr_scene_understanding/providers/openxr_common/",
]
const _HANDS_PREFIX := "res://addons/godot_xr_hands/"
const _PERCEPTION_PREFIXES := [
	"res://addons/godot_xr_scene_understanding/",
	"res://addons/godot_webxr_scene_understanding/",
]

var _platform_name := ""
var _strip_hands := false
var _strip_perception := false


func _get_name() -> String:
	return "XR Suite automatic package cleanup"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	if platform == null:
		return false
	return platform.get_os_name() in ["Web", "Android"]


func _export_begin(
	features: PackedStringArray,
	is_debug: bool,
	path: String,
	flags: int
) -> void:
	var platform := get_export_platform()
	_platform_name = "" if platform == null else platform.get_os_name()
	var usage := _Packages.detect_optional_capability_usage()
	var modes: Dictionary = ProjectSettings.get_setting(
		_FEATURE_MODES_SETTING,
		{}
	)
	_strip_hands = _should_strip_optional("hands", modes, usage)
	_strip_perception = _should_strip_optional("perception", modes, usage)
	print(
		"XR Suite export cleanup: %s; hands=%s; perception=%s"
		% [
			_platform_name,
			"strip" if _strip_hands else "include",
			"strip" if _strip_perception else "include",
		]
	)


func _export_file(
	path: String,
	type: String,
	features: PackedStringArray
) -> void:
	var strip_file := should_strip_path(
		path,
		_platform_name,
		_strip_hands,
		_strip_perception
	)
	if strip_file:
		skip()


func _export_end() -> void:
	_platform_name = ""
	_strip_hands = false
	_strip_perception = false


static func should_strip_path(
	path: String,
	platform_name: String,
	strip_hands: bool,
	strip_perception: bool
) -> bool:
	if platform_name != "Web" and platform_name != "Android":
		return false
	if _is_editor_only(path):
		return true
	if platform_name == "Web" and _has_prefix(path, _NATIVE_ONLY_PREFIXES):
		return true
	if platform_name == "Android":
		if _has_prefix(path, _WEB_ONLY_PREFIXES) or _WEB_ONLY_FILES.has(path):
			return true
		# The Universal XR APK addon participates in the editor export process,
		# but none of its scripts belong in the APK resource pack.
		if path.begins_with("res://addons/godot_universal_xr_apk/"):
			return true
	if strip_hands and path.begins_with(_HANDS_PREFIX):
		return true
	if strip_perception and _has_prefix(path, _PERCEPTION_PREFIXES):
		return true
	return false


static func _should_strip_optional(
	capability_id: String,
	modes: Dictionary,
	usage: Dictionary
) -> bool:
	var mode := str(modes.get(capability_id, "auto"))
	if mode == "include":
		return false
	if mode == "strip":
		return true
	var references: PackedStringArray = usage.get(
		capability_id,
		PackedStringArray()
	)
	return references.is_empty()


static func _is_editor_only(path: String) -> bool:
	if not path.begins_with("res://addons/"):
		return false
	var file_name := path.get_file()
	return (
		path.contains("/editor/")
		or path.contains("/tests/")
		or file_name == "plugin.cfg"
		or file_name == "plugin.gd"
		or file_name == "plugin.gd.uid"
		or file_name == "README.md"
		or file_name == "xr_package.cfg"
	)


static func _has_prefix(path: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if path.begins_with(prefix):
			return true
	return false
