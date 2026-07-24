@tool
extends RefCounted

## Resolves deployment targets + author-selected capabilities into concrete
## addon packages. Installed addons override the embedded fallback catalog
## with their own xr_package.cfg, while the fallback keeps missing packages
## visible and installable later.

const CATALOG_PATH := "res://addons/godot_xr_interaction_toolkit/editor/xr_suite_catalog.cfg"
const PACKAGE_PREFIX := "packages."
const DEPLOYMENT_PREFIX := "deployments."
const CAPABILITY_PREFIX := "capabilities."
const OPTIONAL_USAGE_PATTERNS := {
	"hands": [
		"res://addons/godot_xr_hands/",
		"res://addons/godot_webxr_kit/xr_prefab.tscn",
		"res://addons/godot_webxr_kit/runtime/xr_hands_mount.gd",
		"XRHandMeshVisualizer",
		"XRGestureRecognizer",
		"XRGestureRecorder",
	],
	"perception": [
		"res://addons/godot_xr_scene_understanding/",
		"res://addons/godot_webxr_scene_understanding/",
		"EnvironmentDepthManager",
		"SceneMeshManager",
		"HitTestAnchorManager",
		"LightEstimationManager",
	],
}
const SCANNED_EXTENSIONS := ["gd", "godot", "tscn", "tres"]
const IGNORED_SCAN_FOLDERS := [
	"res://.godot",
	"res://addons",
	"res://build",
	"res://tests",
]


static func get_deployments() -> Array[Dictionary]:
	return _entries(DEPLOYMENT_PREFIX)


static func get_capabilities() -> Array[Dictionary]:
	return _entries(CAPABILITY_PREFIX)


static func default_capabilities() -> Dictionary:
	var enabled := {}
	for capability in get_capabilities():
		enabled[capability["id"]] = bool(capability.get("default_enabled", false))
	return enabled


## Finds explicit optional-feature references in project-owned text resources.
## Addons and generated output are excluded so merely installing a package does
## not count as using it. The result maps capability IDs to referring files.
static func detect_optional_capability_usage() -> Dictionary:
	var usage := {}
	for capability_id in OPTIONAL_USAGE_PATTERNS:
		usage[capability_id] = PackedStringArray()
	_scan_usage_directory("res://", usage)
	return usage


static func _scan_usage_directory(path: String, usage: Dictionary) -> void:
	if path != "res://" and _scan_path_ignored(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with(".") and entry != "project.godot":
			continue
		var child := path.path_join(entry)
		if directory.current_is_dir():
			_scan_usage_directory(child, usage)
			continue
		if not SCANNED_EXTENSIONS.has(entry.get_extension().to_lower()):
			continue
		var file := FileAccess.open(child, FileAccess.READ)
		if file == null or file.get_length() > 2 * 1024 * 1024:
			continue
		var text := file.get_as_text()
		for capability_id in OPTIONAL_USAGE_PATTERNS:
			for pattern in OPTIONAL_USAGE_PATTERNS[capability_id]:
				if text.contains(pattern):
					var matches: PackedStringArray = usage[capability_id]
					matches.append(child)
					usage[capability_id] = matches
					break
	directory.list_dir_end()


static func _scan_path_ignored(path: String) -> bool:
	for ignored in IGNORED_SCAN_FOLDERS:
		if path == ignored or path.begins_with(ignored + "/"):
			return true
	return false


static func deployment_supports_capability(deployment_id: String, capability_id: String) -> bool:
	var deployment := _entry(DEPLOYMENT_PREFIX + deployment_id)
	var capability := _entry(CAPABILITY_PREFIX + capability_id)
	if deployment.is_empty() or capability.is_empty():
		return false
	return _targets_overlap(
		_as_strings(deployment.get("targets", PackedStringArray())),
		_as_strings(capability.get("targets", PackedStringArray()))
	)


static func resolve(deployment_id: String, enabled_capabilities: Dictionary) -> Dictionary:
	var deployment := _entry(DEPLOYMENT_PREFIX + deployment_id)
	if deployment.is_empty():
		return {
			"ok": false,
			"errors": PackedStringArray(["Unknown deployment '%s'." % deployment_id]),
			"packages": [],
			"missing": [],
			"installed_unused": [],
			"targets": PackedStringArray(),
		}

	var targets := _as_strings(deployment.get("targets", PackedStringArray()))
	var package_ids := PackedStringArray()
	var reasons := {}
	for package_id in _as_strings(deployment.get("base_packages", PackedStringArray())):
		_add_requested(package_ids, reasons, package_id, str(deployment.get("display_name", deployment_id)))

	for capability in get_capabilities():
		var capability_id: String = capability["id"]
		var required := bool(capability.get("required", false))
		var selected := required or bool(enabled_capabilities.get(capability_id, false))
		if not selected or not _targets_overlap(
			targets,
			_as_strings(capability.get("targets", PackedStringArray()))
		):
			continue
		var reason := str(capability.get("display_name", capability_id))
		for package_id in _as_strings(capability.get("packages", PackedStringArray())):
			_add_requested(package_ids, reasons, package_id, reason)
		if targets.has("web"):
			for package_id in _as_strings(capability.get("packages_web", PackedStringArray())):
				_add_requested(package_ids, reasons, package_id, reason + " (Web)")
		if targets.has("native"):
			for package_id in _as_strings(capability.get("packages_native", PackedStringArray())):
				_add_requested(package_ids, reasons, package_id, reason + " (Native)")

	var errors := PackedStringArray()
	var cursor := 0
	while cursor < package_ids.size():
		var package_id := package_ids[cursor]
		cursor += 1
		var package := get_package(package_id)
		if package.is_empty():
			errors.append("Package '%s' is not present in the suite catalog." % package_id)
			continue
		var dependencies := _as_strings(package.get("requires", PackedStringArray()))
		if targets.has("web"):
			dependencies.append_array(_as_strings(package.get("requires_web", PackedStringArray())))
		if targets.has("native"):
			dependencies.append_array(_as_strings(package.get("requires_native", PackedStringArray())))
		for dependency_id in dependencies:
			_add_requested(
				package_ids,
				reasons,
				dependency_id,
				"Required by %s" % package.get("display_name", package_id)
			)

	var packages: Array[Dictionary] = []
	var missing: Array[Dictionary] = []
	for package_id in package_ids:
		var package := get_package(package_id)
		if package.is_empty():
			continue
		package["installed"] = _is_installed(package)
		package["reasons"] = reasons.get(package_id, PackedStringArray())
		package["install_hint"] = _install_hint(package)
		packages.append(package)
		if not package["installed"]:
			missing.append(package)

	var installed_unused: Array[Dictionary] = []
	for section in _sections(PACKAGE_PREFIX):
		var package_id := section.trim_prefix(PACKAGE_PREFIX)
		if package_ids.has(package_id):
			continue
		var package := get_package(package_id)
		if package.is_empty() or not _is_installed(package):
			continue
		package["installed"] = true
		installed_unused.append(package)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"deployment": deployment,
		"targets": targets,
		"packages": packages,
		"missing": missing,
		"installed_unused": installed_unused,
	}


static func get_package(package_id: String) -> Dictionary:
	var package := _entry(PACKAGE_PREFIX + package_id)
	if package.is_empty():
		return {}
	var manifest_path := str(package.get("manifest", ""))
	if not manifest_path.is_empty() and FileAccess.file_exists(manifest_path):
		var manifest := ConfigFile.new()
		if manifest.load(manifest_path) == OK and manifest.has_section("package"):
			for key in manifest.get_section_keys("package"):
				package[key] = manifest.get_value("package", key)
	package["id"] = package_id
	return package


static func validate_installed_manifests() -> PackedStringArray:
	var errors := PackedStringArray()
	for section in _sections(PACKAGE_PREFIX):
		var package_id := section.trim_prefix(PACKAGE_PREFIX)
		var package := _entry(section)
		var manifest_path := str(package.get("manifest", ""))
		if manifest_path.is_empty() or not FileAccess.file_exists(manifest_path):
			continue
		var manifest := ConfigFile.new()
		var load_error := manifest.load(manifest_path)
		if load_error != OK:
			errors.append("%s cannot be read (error %d)." % [manifest_path, load_error])
			continue
		if int(manifest.get_value("package", "schema", 0)) != 1:
			errors.append("%s does not use package schema 1." % manifest_path)
		if str(manifest.get_value("package", "id", "")) != package_id:
			errors.append("%s id does not match catalog id %s." % [manifest_path, package_id])
		for key in [
			"display_name",
			"summary",
			"layer",
			"folder",
			"targets",
			"requires",
			"requires_web",
			"requires_native",
			"runtime_footprint",
			"editor_plugin",
		]:
			if (
				manifest.has_section_key("package", key)
				and package.has(key)
				and manifest.get_value("package", key) != package[key]
			):
				errors.append("%s/%s differs from the fallback catalog." % [manifest_path, key])
	return errors


static func missing_install_text(resolution: Dictionary) -> String:
	var missing: Array = resolution.get("missing", [])
	if missing.is_empty():
		return "All required addons are installed."
	var lines := PackedStringArray([
		"Add these folders under your project's addons/ directory, then click Recheck Addons:",
	])
	for package in missing:
		lines.append("- %s: %s" % [package.get("display_name", package.get("id", "")), package["install_hint"]])
	lines.append("")
	lines.append("Easiest from a godot-xr-suite checkout:")
	lines.append(
		'.\\setup.ps1 -Project "%s"'
		% ProjectSettings.globalize_path("res://").trim_suffix("/")
	)
	return "\n".join(lines)


static func _add_requested(
	package_ids: PackedStringArray,
	reasons: Dictionary,
	package_id: String,
	reason: String
) -> void:
	if package_id.is_empty():
		return
	if not package_ids.has(package_id):
		package_ids.append(package_id)
	if not reasons.has(package_id):
		reasons[package_id] = PackedStringArray()
	var package_reasons: PackedStringArray = reasons[package_id]
	if not package_reasons.has(reason):
		package_reasons.append(reason)
	reasons[package_id] = package_reasons


static func _is_installed(package: Dictionary) -> bool:
	var probe := str(package.get("probe", ""))
	return not probe.is_empty() and FileAccess.file_exists(probe)


static func _install_hint(package: Dictionary) -> String:
	var source_url := str(package.get("source_url", ""))
	if not source_url.is_empty():
		return source_url
	var folder := str(package.get("folder", ""))
	var catalog := _catalog()
	var repository := str(catalog.get_value("catalog", "repository", ""))
	if repository.is_empty():
		return "addons/%s" % folder
	return "%s/tree/master/addons/%s" % [repository, folder]


static func _entries(prefix: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for section in _sections(prefix):
		var entry := _entry(section)
		entry["id"] = section.trim_prefix(prefix)
		entries.append(entry)
	return entries


static func _entry(section: String) -> Dictionary:
	var config := _catalog()
	if not config.has_section(section):
		return {}
	var entry := {}
	for key in config.get_section_keys(section):
		entry[key] = config.get_value(section, key)
	return entry


static func _sections(prefix: String) -> PackedStringArray:
	var matches := PackedStringArray()
	for section in _catalog().get_sections():
		if section.begins_with(prefix):
			matches.append(section)
	return matches


static func _catalog() -> ConfigFile:
	var config := ConfigFile.new()
	var error := config.load(CATALOG_PATH)
	if error != OK:
		push_error("XR package catalog could not be loaded (error %d)." % error)
	return config


static func _as_strings(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var strings := PackedStringArray()
	if value is Array:
		for item in value:
			strings.append(str(item))
	return strings


static func _targets_overlap(a: PackedStringArray, b: PackedStringArray) -> bool:
	for target in a:
		if b.has(target):
			return true
	return false
