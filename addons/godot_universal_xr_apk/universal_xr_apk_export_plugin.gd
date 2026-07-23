@tool
extends EditorExportPlugin

## Adds only portable manifest declarations. Godot's built-in OpenXR export
## plugin supplies the Khronos loader, runtime broker queries, permissions, and
## IMMERSIVE_HMD intent category.

const ENABLED := "universal_xr_apk/enabled"
const STATUS := "universal_xr_apk/status"
const OPENXR_VENDORS_DESCRIPTOR := \
		"res://addons/godotopenxrvendors/plugin.gdextension"
const OPENXR_VENDORS_DEBUG_LIBRARY := \
		"res://addons/godotopenxrvendors/.bin/android/template_debug/arm64/libgodotopenxrvendors.so"
const OPENXR_VENDORS_RELEASE_LIBRARY := \
		"res://addons/godotopenxrvendors/.bin/android/template_release/arm64/libgodotopenxrvendors.so"


func _get_name() -> String:
	return "Universal XR APK"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform != null and platform.get_os_name() == "Android"


func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		{
			"option": {"name": ENABLED, "type": TYPE_BOOL},
			"default_value": false,
			"update_visibility": true,
		},
		{
			"option": {
				"name": STATUS,
				"type": TYPE_STRING,
				"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY,
			},
			"default_value": "Quest 3 + Android XR portable baseline",
		},
	]


func _get_export_option_visibility(platform: EditorExportPlatform, option: String) -> bool:
	if option == STATUS:
		return _is_enabled()
	return true


func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if option != ENABLED or not _is_enabled():
		return ""
	if int(get_option("xr_features/xr_mode")) != 1:
		return "Universal XR APK requires XR Mode = OpenXR."
	if not bool(get_option("gradle_build/use_gradle_build")):
		return "Universal XR APK requires Use Gradle Build."
	if not bool(get_option("architectures/arm64-v8a")):
		return "Universal XR APK requires the arm64-v8a architecture."
	if str(get_option("gradle_build/min_sdk")).to_int() < 34:
		return "Galaxy XR requires Min SDK 34 or newer."
	if _vendor_exporter_enabled():
		return "UniversalDev must keep Android XR and device-vendor exporters off; they add platform-required manifest entries. Use separate store presets for vendor extensions."
	return ""


func _get_android_manifest_element_contents(
	platform: EditorExportPlatform,
	debug: bool
) -> String:
	if not _is_enabled():
		return ""
	return """
    <!-- Godot Universal XR APK: portable, store-neutral features. -->
    <uses-feature android:name="android.software.xr.api.openxr" android:required="false" />
    <uses-feature android:name="android.hardware.xr.input.controller" android:required="false" />
    <uses-feature android:name="android.hardware.xr.input.hand_tracking" android:required="false" />
    <uses-feature android:name="oculus.software.handtracking" android:required="false" />
    <uses-feature android:name="com.oculus.feature.PASSTHROUGH" android:required="false" />
    <uses-permission android:name="android.permission.HAND_TRACKING" />
    <uses-permission android:name="horizonos.permission.HAND_TRACKING" />
    <uses-permission android:name="android.permission.SCENE_UNDERSTANDING_FINE" />
    <uses-permission android:name="android.permission.SCENE_UNDERSTANDING_COARSE" />
    <uses-permission android:name="com.oculus.permission.USE_SCENE" />
    <uses-permission android:name="horizonos.permission.USE_SCENE" />
    <uses-permission android:name="horizonos.permission.USE_ANCHOR_API" />
"""


func _get_android_manifest_application_element_contents(
	platform: EditorExportPlatform,
	debug: bool
) -> String:
	if not _is_enabled():
		return ""
	return """
        <!-- Optional keeps this exact APK installable when the Google loader is absent. -->
        <uses-native-library android:name="libopenxr.google.so" android:required="false" />
        <property
            android:name="android.window.PROPERTY_XR_BOUNDARY_TYPE_RECOMMENDED"
            android:value="XR_BOUNDARY_TYPE_NO_RECOMMENDATION" />
"""


func _get_android_manifest_activity_element_contents(
	platform: EditorExportPlatform,
	debug: bool
) -> String:
	if not _is_enabled():
		return ""
	return """
            <property
                android:name="android.window.PROPERTY_XR_ACTIVITY_START_MODE"
                android:value="XR_ACTIVITY_START_MODE_FULL_SPACE_UNMANAGED" />
"""


func _export_begin(
	features: PackedStringArray,
	is_debug: bool,
	path: String,
	flags: int
) -> void:
	if not _is_enabled():
		return
	var platform := get_export_platform()
	if platform == null:
		return
	var errors := PackedStringArray()
	if int(get_option("xr_features/xr_mode")) != 1:
		errors.append("XR Mode must be OpenXR.")
	if not bool(get_option("gradle_build/use_gradle_build")):
		errors.append("Use Gradle Build must be enabled.")
	if not bool(get_option("architectures/arm64-v8a")):
		errors.append("arm64-v8a must be enabled.")
	if str(get_option("gradle_build/min_sdk")).to_int() < 34:
		errors.append("Min SDK must be at least 34.")
	if _vendor_exporter_enabled():
		errors.append("Android XR/Meta/Pico/Magic Leap vendor exporters must be disabled.")
	if not FileAccess.file_exists(OPENXR_VENDORS_DESCRIPTOR):
		errors.append(
			"Godot OpenXR Vendors is missing; install the addon before exporting."
		)
	var vendor_library := (
		OPENXR_VENDORS_DEBUG_LIBRARY
		if is_debug
		else OPENXR_VENDORS_RELEASE_LIBRARY
	)
	if not FileAccess.file_exists(vendor_library):
		errors.append(
			"Godot OpenXR Vendors arm64 %s library is missing."
			% ("debug" if is_debug else "release")
		)
	for message in errors:
		platform.add_message(
			EditorExportPlatform.EXPORT_MESSAGE_ERROR,
			"Universal XR APK",
			message
		)
	if not errors.is_empty():
		return

	# The official vendor descriptor uses android_aar_plugin=true, which makes
	# Godot omit both the descriptor and library when no vendor AAR exporter is
	# selected. UniversalXRAPK deliberately keeps those exporters off so one
	# APK remains portable. Re-add the unchanged descriptor and its matching
	# arm64 library through Godot's normal export API; no vendor or engine fork
	# is required.
	add_file(
		OPENXR_VENDORS_DESCRIPTOR,
		FileAccess.get_file_as_bytes(OPENXR_VENDORS_DESCRIPTOR),
		false
	)
	add_shared_object(vendor_library, PackedStringArray(["arm64"]), "")


func _vendor_exporter_enabled() -> bool:
	for option in [
		"xr_features/enable_androidxr_plugin",
		"xr_features/enable_meta_plugin",
		"xr_features/enable_pico_plugin",
		"xr_features/enable_magicleap_plugin",
	]:
		var value: Variant = get_option(option)
		if value != null and bool(value):
			return true
	return false


func _is_enabled() -> bool:
	if get_export_preset() == null:
		return false
	var value: Variant = get_option(ENABLED)
	return value != null and bool(value)
