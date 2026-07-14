@tool
extends EditorExportPlugin

## Adds a one-checkbox "WebGPU (adaptive) build" toggle to the Web export preset
## so the whole WebGPU setup is a toggle instead of several settings.
##
## webgpu/adaptive_build ON:
##   - forces shader_baker/enabled (option override), so the SPIR-V -> WGSL bake
##     runs;
##   - at export start sets rendering_method.web = mobile, driver.web = webgpu,
##     and disables multiview XR shaders.
##   OFF = a normal WebGL build, with none of the WebGPU cost.
##
## webgpu/xr_compatible ON (only meaningful for immersive WebXR apps):
##   - forces webxr/uses_webxr, which makes the loader request an XR-compatible
##     WebGPU adapter (required for XRGPUBinding / entering VR-AR on WebGPU).
##   Leave it OFF for a non-XR web game: uses_webxr would make the loader keep
##   WebGL on any browser that exposes navigator.xr (e.g. desktop Chrome).
##
## The one thing this can't flip is the editor's BASE Rendering Method - the
## shader baker only runs when the editor itself uses a RenderingDevice renderer,
## fixed at editor startup. When adaptive_build is on but the base is not
## Mobile/Forward+, the export dialog warns with the exact setting to change.
##
## Runtime-built materials whose SHADER is new need a BakeAnchor - see README.

const OPT := "webgpu/adaptive_build"
const OPT_XR := "webgpu/xr_compatible"


func _get_name() -> String:
	return "WebGPU Adaptive Build"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform != null and platform.get_os_name() == "Web"


func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		{
			"option": {"name": OPT, "type": TYPE_BOOL},
			"default_value": false,
		},
		{
			"option": {"name": OPT_XR, "type": TYPE_BOOL},
			"default_value": false,
		},
	]


func _should_update_export_options(platform: EditorExportPlatform) -> bool:
	return true


func _get_export_option_visibility(platform: EditorExportPlatform, option: String) -> bool:
	# The XR-compatible sub-option only applies when building for WebGPU.
	if option == OPT_XR:
		return _is_on(OPT)
	return true


func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
	var overrides: Dictionary = {}
	if _is_on(OPT):
		overrides["shader_baker/enabled"] = true
	if _is_on(OPT) and _is_on(OPT_XR):
		overrides["webxr/uses_webxr"] = true
	return overrides


func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if option != OPT or not _is_on(OPT):
		return ""
	var rm := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	if rm != "mobile" and rm != "forward_plus":
		return ("WebGPU export needs the shader baker, which only runs when the editor uses a "
			+ "RenderingDevice renderer. Set Project Settings → Rendering → Renderer → "
			+ "Rendering Method to \"Mobile\" (or \"Forward+\") and restart the editor. "
			+ "Current: \"%s\"." % rm)
	return ""


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if not _is_on(OPT):
		return
	# Point the web build at the adaptive WebGPU renderer, and use mono XR shaders
	# (multiview variants aren't produced by the non-XR host bake; harmless off
	# for non-XR too). The base renderer is validated by the warning above.
	ProjectSettings.set_setting("rendering/renderer/rendering_method.web", "mobile")
	ProjectSettings.set_setting("rendering/rendering_device/driver.web", "webgpu")
	ProjectSettings.set_setting("xr/shaders/enabled", false)


func _is_on(option: String) -> bool:
	var v: Variant = get_option(option)
	return v != null and bool(v)
