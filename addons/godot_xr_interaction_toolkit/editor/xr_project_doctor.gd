@tool
extends AcceptDialog

## Preset-driven project validation. Opening the dialog always performs a fresh
## export-preset, addon, and optional-feature scan. Repair Required handles
## project configuration; package cleanup runs automatically during export.

const _Setup := preload(
	"res://addons/godot_xr_interaction_toolkit/editor/xr_project_setup.gd"
)
const _Packages := preload(
	"res://addons/godot_xr_interaction_toolkit/editor/xr_package_resolver.gd"
)
const _UNIVERSAL_SETUP := \
		"res://addons/godot_universal_xr_apk/universal_xr_apk_project_setup.gd"
const _FEATURE_MODES_SETTING := "xr_suite/authoring/feature_modes"
const _AUTO_FEATURE_IDS := ["hands", "perception"]
const _MODE_AUTO := "auto"
const _MODE_INCLUDE := "include"
const _MODE_STRIP := "strip"

var _rows: VBoxContainer
var _status: Label
var _scope_hint: Label
var _repair_button: Button
var _copy_button: Button
var _advanced_controls: VBoxContainer
var _advanced_summary: Label
var _mode_selects := {}
var _profiles := {}
var _resolution := {}
var _feature_usage := {}
var _export_preset_name := ""
var _repair_required := false


func _init() -> void:
	title = "XR Suite Validator — Project"
	ok_button_text = "Close"
	min_size = Vector2i(480, 320)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(460, 270)
	add_child(root)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	root.add_child(_status)

	_scope_hint = Label.new()
	_scope_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scope_hint.add_theme_font_size_override("font_size", 11)
	_scope_hint.add_theme_color_override(
		"font_color",
		Color(0.62, 0.66, 0.72)
	)
	root.add_child(_scope_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var actions := HBoxContainer.new()
	root.add_child(actions)
	_repair_button = Button.new()
	_repair_button.text = "Repair Required"
	_repair_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_button.pressed.connect(_repair_all)
	actions.add_child(_repair_button)
	_copy_button = Button.new()
	_copy_button.text = "Copy Missing Addons"
	_copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_button.pressed.connect(_copy_missing)
	actions.add_child(_copy_button)

	about_to_popup.connect(refresh)


func open_for_export_preset(preset_name: String) -> void:
	_export_preset_name = preset_name
	var editor_size := EditorInterface.get_base_control().size
	var target_size := Vector2i(
		mini(720, maxi(480, int(editor_size.x) - 100)),
		mini(600, maxi(360, int(editor_size.y) - 120))
	)
	max_size = target_size
	popup_centered_clamped(target_size, 0.85)


func refresh() -> void:
	# This is the former Recheck Addons operation. It intentionally runs on
	# every open and after every repair so the report cannot be stale.
	_profiles = _Setup.detect_export_profiles(_export_preset_name)
	_repair_button.tooltip_text = (
		"Repairs missing native XR project configuration. APK package cleanup "
		+ "runs automatically during export."
		if bool(_profiles.get("native", false))
		else (
			"Repairs missing WebXR project configuration. Web package cleanup "
			+ "runs automatically during export; Threads, WebGPU, and hosting "
			+ "choices remain unchanged."
		)
	)
	_feature_usage = _Packages.detect_optional_capability_usage()
	_resolution = _resolve_packages()
	_repair_required = false
	_scope_hint.text = (
		"Report scope: Export preset “%s”. Only settings and addons required "
		+ "by this preset are shown."
	) % (
		_export_preset_name
		if not _export_preset_name.is_empty()
		else "not selected"
	)
	for child in _rows.get_children():
		child.queue_free()

	_add_header("Export Presets")
	_add_export_rows()
	_add_header("Required Addons")
	_add_addon_rows()
	_add_header("Project Configuration")
	_add_configuration_rows()
	_add_advanced_footprint()

	var missing: Array = _resolution.get("missing", [])
	_copy_button.visible = not missing.is_empty()
	if not _has_active_target():
		_repair_button.text = "No Repair Available"
		_repair_button.disabled = true
		_set_status(
			"Enable WebXR or Universal XR APK in the selected export preset.",
			false
		)
	elif not missing.is_empty():
		_repair_button.text = "Repair Blocked — Addons Missing"
		_repair_button.disabled = true
		_set_status(
			"%d required addon%s missing. Install them before repair."
			% [missing.size(), "" if missing.size() == 1 else "s"],
			false
		)
	elif _repair_required:
		_repair_button.text = "Repair Required"
		_repair_button.disabled = false
		_set_status(
			"Selected preset needs safe XR project configuration.",
			false
		)
	else:
		_repair_button.text = "No Repair Required"
		_repair_button.disabled = true
		_set_status(
			"Selected preset is ready. No repair required.",
			true
		)


func _add_export_rows() -> void:
	var web_names: PackedStringArray = _profiles.get(
		"web_presets",
		PackedStringArray()
	)
	if not web_names.is_empty():
		_add_row(
			true,
			"WebXR: %s" % ", ".join(web_names),
			(
				"WebGPU enabled in at least one preset."
				if bool(_profiles.get("webgpu", false))
				else "WebGL renderer; WebGPU remains available per preset."
			)
		)
		var environment := _Setup.get_web_environment(_export_preset_name)
		if not environment.is_empty():
			_add_row(
				true,
				"Web hosting environment",
				str(environment.get("detail", ""))
			)

	var android_names: PackedStringArray = _profiles.get(
		"android_presets",
		PackedStringArray()
	)
	if not android_names.is_empty():
		_add_row(
			true,
			"Universal XR APK: %s" % ", ".join(android_names),
			"Portable Quest 3 + Android XR target enabled."
		)

	if web_names.is_empty() and android_names.is_empty():
		_add_row(
			false,
			"No XR export profile enabled",
			"Enable WebXR on a Web preset or Universal XR APK on an "
			+ "Android preset in Project > Export."
		)


func _add_addon_rows() -> void:
	var packages: Array = _resolution.get("packages", [])
	if packages.is_empty():
		_add_row(false, "No active XR export target", "Configure an export preset first.")
		return
	for package in packages:
		var installed := bool(package.get("installed", false))
		var reasons: PackedStringArray = package.get("reasons", PackedStringArray())
		_add_row(
			installed,
			"%s  [%s]" % [
				package.get("display_name", package.get("id", "")),
				package.get("layer", "addon"),
			],
			"Why: %s\nFootprint: %s%s" % [
				", ".join(reasons),
				package.get("runtime_footprint", "unspecified"),
				"" if installed else "\nInstall: " + str(package.get("install_hint", "")),
			]
		)
	var installed_unused: Array = _resolution.get("installed_unused", [])
	for package in installed_unused:
		_add_row(
			true,
			"Available, not required: %s"
			% package.get("display_name", package.get("id", "")),
			"Kept locally for fast target switching; active export filters "
			+ "control what ships."
		)


func _add_configuration_rows() -> void:
	if not _has_active_target():
		_add_row(false, "Configuration not evaluated", "No active XR export target.")
		return
	var web := bool(_profiles.get("web", false))
	var native := bool(_profiles.get("native", false))
	var webgpu := bool(_profiles.get("webgpu", false))
	for check in _Setup.run_project_checks(_export_preset_name):
		var check_id: String = check["id"]
		if check_id == _Setup.CHECK_WEB_PRESET and not web:
			continue
		if (
			check_id in [
				_Setup.CHECK_OPENXR,
				_Setup.CHECK_REFERENCE_SPACE,
				_Setup.CHECK_ACTION_MAP,
			]
			and not native
		):
			continue
		if check_id == _Setup.CHECK_RENDERER and not native and not webgpu:
			continue
		var check_ok := bool(check["ok"])
		if not check_ok and not str(check.get("fix", "")).is_empty():
			_repair_required = true
		_add_row(check_ok, str(check["label"]), str(check["detail"]))

	var filter_health := _Setup.get_export_filter_health(
		web,
		native,
		_effective_feature("hands"),
		_effective_feature("perception"),
		_export_preset_name
	)
	var filters_ok := bool(filter_health.get("ok", false))
	if not filters_ok:
		_repair_required = true
	_add_row(
		filters_ok,
		(
			str(filter_health.get("label", "Export package cleanup"))
			if filters_ok
			else "Action required: %s" % str(
				filter_health.get("label", "Export package cleanup")
			)
		),
		str(filter_health.get("detail", "Not evaluated."))
	)


func _add_advanced_footprint() -> void:
	_add_header("Advanced Build Footprint")
	var explanation := Label.new()
	explanation.text = (
		"Automatic by default: features used by your project are included; "
		+ "unused optional features are stripped at export. No action needed."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_font_size_override("font_size", 11)
	explanation.add_theme_color_override(
		"font_color",
		Color(0.62, 0.66, 0.72)
	)
	_rows.add_child(explanation)

	var disclosure := Button.new()
	disclosure.text = "Show Optional Feature Overrides"
	disclosure.toggle_mode = true
	disclosure.tooltip_text = (
		"Advanced escape hatch for dynamically loaded features that Auto "
		+ "cannot detect, or deliberately minimal builds."
	)
	_rows.add_child(disclosure)
	_advanced_controls = VBoxContainer.new()
	_advanced_controls.visible = false
	_rows.add_child(_advanced_controls)
	disclosure.toggled.connect(
		func(expanded: bool):
			_advanced_controls.visible = expanded
			disclosure.text = (
				"Hide Optional Feature Overrides"
				if expanded
				else "Show Optional Feature Overrides"
			)
	)

	var saved_modes: Dictionary = ProjectSettings.get_setting(
		_FEATURE_MODES_SETTING,
		{}
	)
	_mode_selects.clear()
	for capability_id in _AUTO_FEATURE_IDS:
		var row := HBoxContainer.new()
		_advanced_controls.add_child(row)
		var label := Label.new()
		label.text = _display_name(capability_id)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var select := OptionButton.new()
		for mode in [_MODE_AUTO, _MODE_INCLUDE, _MODE_STRIP]:
			var index := select.item_count
			select.add_item(_mode_name(mode))
			select.set_item_metadata(index, mode)
		var saved_mode := str(saved_modes.get(capability_id, _MODE_AUTO))
		for index in select.item_count:
			if str(select.get_item_metadata(index)) == saved_mode:
				select.select(index)
				break
		select.item_selected.connect(_on_mode_changed.bind(capability_id))
		row.add_child(select)
		_mode_selects[capability_id] = select

	_advanced_summary = Label.new()
	_advanced_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advanced_summary.add_theme_font_size_override("font_size", 11)
	_advanced_controls.add_child(_advanced_summary)
	_refresh_advanced_summary()


func _resolve_packages() -> Dictionary:
	if not _has_active_target():
		return {
			"packages": [],
			"missing": [],
			"targets": PackedStringArray(),
		}
	var deployment := (
		"both"
		if bool(_profiles.get("web", false))
			and bool(_profiles.get("native", false))
		else ("native" if bool(_profiles.get("native", false)) else "web")
	)
	var enabled := {
		"interactions": true,
		"hands": _effective_feature("hands"),
		"perception": _effective_feature("perception"),
		"webgpu": bool(_profiles.get("webgpu", false)),
	}
	return _Packages.resolve(deployment, enabled)


func _repair_all() -> void:
	# Recheck immediately before mutation, not only when the dialog opened.
	_profiles = _Setup.detect_export_profiles(_export_preset_name)
	_feature_usage = _Packages.detect_optional_capability_usage()
	_resolution = _resolve_packages()
	if not _resolution.get("missing", []).is_empty():
		refresh()
		_set_status("Repair paused because required addons are missing.", false)
		return
	var save_error := _save_modes()
	var lines := PackedStringArray()
	var targets: PackedStringArray = _resolution.get(
		"targets",
		PackedStringArray()
	)
	if targets.has("native") and ResourceLoader.exists(_UNIVERSAL_SETUP):
		var native_setup: Variant = load(_UNIVERSAL_SETUP)
		var result: Dictionary = native_setup.apply()
		if not bool(result.get("ok", false)):
			lines.append("FAILED: " + str(result.get("error", "Native setup failed.")))
		else:
			for line in result.get("changes", PackedStringArray()):
				if not lines.has(line):
					lines.append(line)
	var setup_lines := _Setup.setup_project_for_targets(
		targets.has("web"),
		targets.has("native"),
		bool(_profiles.get("webgpu", false)),
		_effective_feature("hands"),
		_effective_feature("perception"),
		_export_preset_name
	)
	for line in setup_lines:
		if not lines.has(line):
			lines.append(line)
	for package in _resolution.get("packages", []):
		var plugin := str(package.get("editor_plugin", ""))
		if not plugin.is_empty() and not EditorInterface.is_plugin_enabled(plugin):
			EditorInterface.set_plugin_enabled(plugin, true)
			lines.append(
				"Enabled editor plugin: %s"
				% package.get("display_name", package.get("id", ""))
			)
	if save_error != OK:
		lines.append("FAILED to save optional footprint modes (error %d)." % save_error)
	for line in lines:
		print("XR Suite Project Validator: ", line)
	refresh()
	var failed := false
	for line in lines:
		if str(line).begins_with("FAILED"):
			failed = true
			break
	_set_status(
		"Repair report:\n%s" % "\n".join(lines),
		not failed
	)


func _on_mode_changed(_index: int, _capability_id: String) -> void:
	_save_modes()
	_refresh_advanced_summary()
	_resolution = _resolve_packages()
	_set_status(
		"Optional footprint changed. It will apply automatically on the next export.",
		true
	)


func _refresh_advanced_summary() -> void:
	if not is_instance_valid(_advanced_summary):
		return
	var lines := PackedStringArray([
		"Auto is recommended. It includes features used by project-owned "
		+ "scenes/scripts and strips unused features. Installed addons alone "
		+ "do not count as usage.",
	])
	var warning := false
	for capability_id in _AUTO_FEATURE_IDS:
		var mode := _mode(capability_id)
		var refs: PackedStringArray = _feature_usage.get(
			capability_id,
			PackedStringArray()
		)
		var line := "%s: %s" % [_display_name(capability_id), _mode_name(mode)]
		if mode == _MODE_AUTO:
			line += (
				" — included; used by %s" % ", ".join(refs)
				if not refs.is_empty()
				else " — stripped; no project usage found"
			)
		elif mode == _MODE_STRIP and not refs.is_empty():
			line += " — WARNING: referenced by %s" % ", ".join(refs)
			warning = true
		lines.append(line)
	_advanced_summary.text = "\n".join(lines)
	_advanced_summary.add_theme_color_override(
		"font_color",
		Color(1.0, 0.62, 0.32) if warning else Color(0.62, 0.66, 0.72)
	)


func _effective_feature(capability_id: String) -> bool:
	var mode := _mode(capability_id)
	if mode == _MODE_INCLUDE:
		return true
	if mode == _MODE_STRIP:
		return false
	var refs: PackedStringArray = _feature_usage.get(
		capability_id,
		PackedStringArray()
	)
	return not refs.is_empty()


func _mode(capability_id: String) -> String:
	if _mode_selects.has(capability_id):
		var select: OptionButton = _mode_selects[capability_id]
		return str(select.get_item_metadata(select.selected))
	var saved_modes: Dictionary = ProjectSettings.get_setting(
		_FEATURE_MODES_SETTING,
		{}
	)
	return str(saved_modes.get(capability_id, _MODE_AUTO))


func _save_modes() -> Error:
	var modes := {}
	for capability_id in _AUTO_FEATURE_IDS:
		modes[capability_id] = _mode(capability_id)
	ProjectSettings.set_setting(_FEATURE_MODES_SETTING, modes)
	return ProjectSettings.save()


func _has_active_target() -> bool:
	return (
		bool(_profiles.get("web", false))
		or bool(_profiles.get("native", false))
	)


func _copy_missing() -> void:
	DisplayServer.clipboard_set(_Packages.missing_install_text(_resolution))
	_set_status("Missing-addon installation steps copied.", true)


func _add_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.62, 0.78, 1.0))
	_rows.add_child(header)


func _add_row(ok: bool, label_text: String, detail: String) -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)
	var icon := Label.new()
	icon.text = "  ✓" if ok else "  !"
	icon.custom_minimum_size = Vector2(32, 0)
	icon.add_theme_color_override(
		"font_color",
		Color(0.35, 0.85, 0.45) if ok else Color(0.95, 0.5, 0.35)
	)
	row.add_child(icon)
	var text := Label.new()
	text.text = (
		label_text
		if detail.is_empty()
		else "%s\n%s" % [label_text, detail]
	)
	text.tooltip_text = detail
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)


func _set_status(message: String, ok: bool) -> void:
	_status.text = message
	_status.add_theme_color_override(
		"font_color",
		Color(0.55, 0.9, 0.68) if ok else Color(1.0, 0.72, 0.32)
	)


func _display_name(capability_id: String) -> String:
	return "Enhanced Hands" if capability_id == "hands" else "Scene Understanding"


func _mode_name(mode: String) -> String:
	match mode:
		_MODE_INCLUDE:
			return "Force Include"
		_MODE_STRIP:
			return "Force Strip"
		_:
			return "Auto (Recommended)"
