@tool
extends EditorExportPlugin

## Adds a clear "WebGPU" toggle to the Web export preset, plus an in-panel status
## line right under it - so setup + verification live in the export settings, not
## a disconnected menu. When WebGPU is ON:
##   - shader baking is turned on AUTOMATICALLY and the raw "Shader Baker" toggle
##     is hidden (nobody should need to know what it is - WebGPU implies it);
##   - a read-only "WebGPU / Status" line shows "✓ Configured" once the project
##     actually runs a RenderingDevice renderer (so the baker will run); until
##     then a warning shows and ticking WebGPU pops a one-click setup dialog;
##   - the web build is pointed at WebGPU at export time.
##
## "Uses WebXR" stays Godot's own separate, visible toggle - WebGPU and WebXR are
## independent and compose (WebGPU alone, WebXR alone, or WebXR-on-WebGPU).

const OPT := "webgpu/enabled"
const STATUS := "webgpu/status"
const SHADER_BAKER := "shader_baker/enabled"

var editor_plugin: EditorPlugin  # set by plugin.gd, used to pop the setup dialog
var _last_on := false


func _get_name() -> String:
	return "WebGPU"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform != null and platform.get_os_name() == "Web"


func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	return [
		# update_visibility: true so toggling it repaints the panel immediately
		# (shows/hides the status line + warning) - editor_export_preset.cpp:44.
		{"option": {"name": OPT, "type": TYPE_BOOL},
			"default_value": false, "update_visibility": true},
		# In-panel status line. NOT overridden - Godot DROPS overridden options from
		# the panel (editor_export_preset.cpp _get_property_list). Instead it's made
		# READ_ONLY via the usage flag and shown only when configured (visibility
		# below), so its static value only ever appears in the configured state.
		{"option": {"name": STATUS, "type": TYPE_STRING,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY},
			"default_value": "✓ Configured - ready to export"},
	]


func _should_update_export_options(platform: EditorExportPlatform) -> bool:
	var now := _is_on(OPT)
	if now == _last_on:
		return false
	_last_on = now
	# On ENABLING WebGPU with an unconfigured project, pop the one-click setup.
	if now and not _base_ok() and editor_plugin != null:
		editor_plugin.call_deferred("show_setup_popup")
	return true


func _get_export_option_visibility(platform: EditorExportPlatform, option: String) -> bool:
	# WebGPU owns shader baking (forced on), so hide the raw toggle entirely.
	if option == SHADER_BAKER:
		return false
	# Show the "✓ Configured" status only when WebGPU is on AND actually set up;
	# when it's not set up, the warning below carries the message instead.
	if option == STATUS:
		return _is_on(OPT) and _base_ok()
	return true


func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
	# Only force the hidden Shader Baker plumbing. NEVER override STATUS - Godot
	# drops overridden options from the panel, which is what hid the line before.
	if _is_on(OPT):
		return {SHADER_BAKER: true}
	return {}


func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if option == OPT and _is_on(OPT) and not _base_ok():
		return "Not set up for WebGPU rendering. Re-tick WebGPU to open the one-click setup (or set Project Settings > Rendering > Renderer > Mobile and restart)."
	return ""


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if not _is_on(OPT):
		return
	ProjectSettings.set_setting("rendering/renderer/rendering_method.web", "mobile")
	ProjectSettings.set_setting("rendering/rendering_device/driver.web", "webgpu")
	ProjectSettings.set_setting("xr/shaders/enabled", false)


func _base_ok() -> bool:
	# "Configured" = the editor is ACTUALLY running a RenderingDevice renderer, so
	# the shader baker will run. Checking the saved setting alone lies when it's
	# been changed but not yet applied (a renderer change needs an editor restart).
	return RenderingServer.get_rendering_device() != null


func _is_on(option: String) -> bool:
	# get_option() errors when there is no active preset (e.g. _should_update_
	# export_options fires at editor startup before one exists), so guard it.
	if get_export_preset() == null:
		return false
	var v: Variant = get_option(option)
	return v != null and bool(v)
