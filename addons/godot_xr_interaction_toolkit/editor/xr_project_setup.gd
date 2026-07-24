@tool
extends RefCounted

## Project-level XR checks and fixes behind the dock's Project Validator.
## Encodes the settings a WORKING XR project
## carries that a fresh Godot project lacks - every one of these fails
## SILENTLY at runtime (actions read zero, sessions never start), which is
## why they are enforced here instead of documented.
##
## Project-level functions use only ProjectSettings/ConfigFile (no
## EditorInterface) so they are testable headless; scene-level checks take
## the scene root as a parameter.

const KIT_ACTION_MAP := "res://addons/godot_webxr_kit/openxr/default_action_map.tres"
const KIT_SHELL := "res://addons/godot_webxr_kit/web/adaptable_shell.html"
const KIT_PREFAB := "res://addons/godot_webxr_kit/xr_prefab.tscn"
const TOOLKIT_FLOOR := "res://addons/godot_xr_interaction_toolkit/xr_floor.tscn"
const TOOLKIT_GRABBABLE := "res://addons/godot_xr_interaction_toolkit/grabbable.tscn"
const PRESETS_PATH := "res://export_presets.cfg"

## Check ids (stable API for fix routing).
const CHECK_OPENXR := "openxr_enabled"
const CHECK_REFERENCE_SPACE := "openxr_reference_space"
const CHECK_ACTION_MAP := "action_map"
const CHECK_RENDERER := "renderer"
const CHECK_WEB_PRESET := "web_preset"
const CHECK_RIG := "scene_rig"
const CHECK_LIGHT := "scene_light"
const CHECK_FLOOR := "scene_floor"
const COMMON_EXPORT_EXCLUDES := [
	"addons/*/editor/*",
	"addons/*/editor/**/*",
	"addons/*/tests/*",
	"addons/*/tests/**/*",
	"addons/*/plugin.gd*",
	"addons/*/plugin.cfg",
	"addons/*/README.md",
	"addons/*/xr_package.cfg",
]
const WEB_PLATFORM_EXCLUDES := [
	"addons/godotopenxrvendors/*",
	"addons/godotopenxrvendors/**/*",
	"addons/godot_universal_xr_apk/*",
	"addons/godot_universal_xr_apk/**/*",
	"addons/godot_webgpu/webgpu_export_plugin.gd*",
	"addons/godot_xr_scene_understanding/providers/openxr_meta/*",
	"addons/godot_xr_scene_understanding/providers/openxr_meta/**/*",
	"addons/godot_xr_scene_understanding/providers/openxr_android_xr/*",
	"addons/godot_xr_scene_understanding/providers/openxr_android_xr/**/*",
	"addons/godot_xr_scene_understanding/providers/openxr_common/*",
	"addons/godot_xr_scene_understanding/providers/openxr_common/**/*",
]
const ANDROID_PLATFORM_EXCLUDES := [
	"web/*",
	"web/**/*",
	"addons/godot_webxr_kit/web/*",
	"addons/godot_webxr_kit/web/**/*",
	"addons/godot_webgpu/*",
	"addons/godot_webgpu/**/*",
	"addons/godot_universal_xr_apk/*",
	"addons/godot_universal_xr_apk/**/*",
	"addons/godot_webxr_scene_understanding/providers/*",
	"addons/godot_webxr_scene_understanding/providers/**/*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_capability_manifest.gd*",
]
const WEB_FILTERS_RESTORED_ON_ANDROID := [
	"addons/godotopenxrvendors/*",
	"addons/godotopenxrvendors/**/*",
	"addons/godot_xr_scene_understanding/providers/openxr_meta/*",
	"addons/godot_xr_scene_understanding/providers/openxr_meta/**/*",
	"addons/godot_xr_scene_understanding/providers/openxr_android_xr/*",
	"addons/godot_xr_scene_understanding/providers/openxr_android_xr/**/*",
	"addons/godot_xr_scene_understanding/providers/openxr_common/*",
	"addons/godot_xr_scene_understanding/providers/openxr_common/**/*",
]
const ANDROID_FILTERS_RESTORED_ON_WEB := [
	"web/*",
	"web/**/*",
	"addons/godot_webxr_kit/web/*",
	"addons/godot_webxr_kit/web/**/*",
	"addons/godot_webgpu/*",
	"addons/godot_webgpu/**/*",
	"addons/godot_webxr_scene_understanding/providers/*",
	"addons/godot_webxr_scene_understanding/providers/**/*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_depth_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_mesh_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_hit_test_anchor_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_light_estimation_bridge.gd*",
	"addons/godot_webxr_scene_understanding/runtime/webxr_capability_manifest.gd*",
]


## Returns [{id, label, ok, detail, fix}] - fix = "" means not auto-fixable.
static func run_project_checks(preset_name: String = "") -> Array:
	var checks := []
	var selected_profiles := detect_export_profiles(preset_name)

	var openxr_on := bool(ProjectSettings.get_setting("xr/openxr/enabled", false))
	checks.append({
		"id": CHECK_OPENXR, "ok": openxr_on,
		"label": "OpenXR enabled (headset Play via Link/SteamVR)",
		"detail": "Without it, pressing Play renders flat on the monitor - the headset is never asked.",
		"fix": "Enable OpenXR + hand tracking",
	})

	var local_floor := int(ProjectSettings.get_setting("xr/openxr/reference_space", 1)) == 2
	checks.append({
		"id": CHECK_REFERENCE_SPACE, "ok": local_floor,
		"label": "OpenXR uses Local Floor",
		"detail": "Matches WebXR local-floor. Stage can use an invalid or stale room boundary, changing user height and placing forward UI behind the startup view.",
		"fix": "Use Local Floor reference space",
	})

	if ResourceLoader.exists(KIT_ACTION_MAP):
		var map_ok: bool = str(ProjectSettings.get_setting("xr/openxr/default_action_map", "")) == KIT_ACTION_MAP
		checks.append({
			"id": CHECK_ACTION_MAP, "ok": map_ok,
			"label": "Kit action map assigned",
			"detail": "The suite reads actions named select/grab/thumbstick. Without the kit's map they silently return nothing on native - grab and teleport just never fire.",
			"fix": "Assign the kit action map",
		})

	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	var win_driver := str(ProjectSettings.get_setting("rendering/rendering_device/driver.windows",
			ProjectSettings.get_setting("rendering/rendering_device/driver", "vulkan")))
	var renderer_ok := method != "gl_compatibility" and win_driver == "vulkan"
	var renderer_label := "Renderer can drive OpenXR (Mobile + Vulkan)"
	var renderer_detail := (
		"Native OpenXR requires a RenderingDevice renderer and Vulkan on "
		+ "Windows. Otherwise headset Play can fail with "
		+ "GRAPHICS_DEVICE_INVALID."
	)
	if (
		bool(selected_profiles.get("webgpu", false))
		and not bool(selected_profiles.get("native", false))
	):
		renderer_label = "Editor can prepare WebGPU shaders (Mobile + Vulkan)"
		renderer_detail = (
			"WebGPU shader baking requires the editor to run Godot's Mobile "
			+ "renderer on a RenderingDevice. This check does not change the "
			+ "selected export preset's renderer or hosting settings."
		)
	checks.append({
		"id": CHECK_RENDERER, "ok": renderer_ok,
		"label": renderer_label,
		"detail": renderer_detail,
		"fix": "Set Mobile renderer + Vulkan on Windows",
	})

	var web_presets := _find_webxr_presets(preset_name)
	var preset_ok := not web_presets.is_empty()
	for preset in web_presets:
		if (
			str(
				preset["options"].get("html/custom_html_shell", "")
			).is_empty()
		):
			preset_ok = false
			break
	checks.append({
		"id": CHECK_WEB_PRESET, "ok": preset_ok,
		"label": "WebXR enabled and configured",
		"detail": "Each WebXR-enabled preset must use an XR-aware HTML shell; otherwise Enter XR cannot start a browser session. Ordinary non-XR Web presets are ignored. Renderer choice (WebGL or WebGPU) remains independent.",
		"fix": "Create/patch the Web preset",
	})

	return checks


static func run_scene_checks(root: Node) -> Array:
	var checks := []
	if root == null:
		return checks

	var has_rig := not root.find_children("*", "XROrigin3D", true, false).is_empty()
	checks.append({
		"id": CHECK_RIG, "ok": has_rig,
		"label": "XR rig in the scene",
		"detail": "Drop XR Prefab (shared rig + conditional WebXR/OpenXR sessions + hands) - the one required block.",
		"fix": "Add XR Prefab" if ResourceLoader.exists(KIT_PREFAB) else "",
	})

	var has_light := not root.find_children("*", "DirectionalLight3D", true, false).is_empty() \
			or not root.find_children("*", "WorldEnvironment", true, false).is_empty()
	checks.append({
		"id": CHECK_LIGHT, "ok": has_light,
		"label": "Scene has lighting",
		"detail": "A fresh scene has no light - default materials render nearly black in VR.",
		"fix": "Add a sun (DirectionalLight3D)",
	})

	if has_rig:
		var has_floor := false
		for body in root.find_children("*", "CollisionObject3D", true, false):
			if (body as CollisionObject3D).collision_layer & 1:
				has_floor = true
				break
		checks.append({
			"id": CHECK_FLOOR, "ok": has_floor,
			"label": "Teleport has ground to land on",
			"detail": "The teleport arc raycasts physics layer 1. No collision there = the arc never finds a valid target.",
			"fix": "Add Floor (teleportable)" if ResourceLoader.exists(TOOLKIT_FLOOR) else "",
		})

	# Grab interactables with no collider are silently un-grabbable (nothing
	# for the ray/direct queries to hit). Row appears only when grabbables
	# exist. Non-@tool scripts have placeholder instances in the editor:
	# identify by script class-name chain, read exports via get().
	var grabbables_missing := PackedStringArray()
	var grabbables_found := false
	for node in root.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		var is_grab := false
		while script:
			if script.get_global_name() == &"XRGrabInteractable":
				is_grab = true
				break
			script = script.get_base_script()
		if not is_grab:
			continue
		grabbables_found = true
		var target: Node = node
		var target_path: Variant = node.get("target_path")
		if target_path is NodePath and not (target_path as NodePath).is_empty():
			target = node.get_node_or_null(target_path)
		var has_collider: bool = target != null and (target is CollisionObject3D
				or not target.find_children("*", "CollisionObject3D", true, false).is_empty())
		if not has_collider:
			grabbables_missing.append(node.name)
	if grabbables_found:
		checks.append({
			"id": "scene_grab_colliders", "ok": grabbables_missing.is_empty(),
			"label": "Grabbables have colliders",
			"detail": "No CollisionObject3D under: %s - the interactor queries never hit them, so they cannot be hovered or grabbed." % ", ".join(grabbables_missing),
			"fix": "",
		})

	return checks


## Applies one project-level fix. Returns a human-readable summary line.
static func apply_project_fix(id: String, preset_name: String = "") -> String:
	match id:
		CHECK_OPENXR:
			ProjectSettings.set_setting("xr/openxr/enabled", true)
			ProjectSettings.set_setting("xr/openxr/extensions/hand_tracking", true)
			ProjectSettings.save()
			return "xr/openxr/enabled = true, hand tracking on."
		CHECK_REFERENCE_SPACE:
			ProjectSettings.set_setting("xr/openxr/reference_space", 2)
			ProjectSettings.save()
			return "OpenXR reference space -> Local Floor (matches WebXR)."
		CHECK_ACTION_MAP:
			ProjectSettings.set_setting("xr/openxr/default_action_map", KIT_ACTION_MAP)
			ProjectSettings.save()
			return "OpenXR action map -> the kit's (select/grab/thumbstick bindings)."
		CHECK_RENDERER:
			ProjectSettings.set_setting("rendering/renderer/rendering_method", "mobile")
			ProjectSettings.set_setting("rendering/rendering_device/driver.windows", "vulkan")
			var profiles := detect_export_profiles(preset_name)
			if bool(profiles.get("webgpu", false)):
				ProjectSettings.set_setting(
					"rendering/renderer/rendering_method.web",
					"mobile"
				)
				ProjectSettings.set_setting(
					"rendering/rendering_device/driver.web",
					"webgpu"
				)
			ProjectSettings.save()
			if bool(profiles.get("native", false)):
				return (
					"Native XR renderer -> Mobile + Vulkan. RESTART the "
					+ "editor to apply."
				)
			return (
				"WebGPU shader preparation -> Mobile + Vulkan. RESTART the "
				+ "editor to apply."
			)
		CHECK_WEB_PRESET:
			return _fix_web_preset(preset_name)
	return ""


## Applies every failing project-level fix; returns the summary lines.
static func setup_project() -> PackedStringArray:
	return setup_project_for_targets(true, true, false)


## Applies only the settings needed by the selected deployment. This keeps a
## Web-only project from being forced into native OpenXR configuration and a
## native-only project from receiving a Web preset. It is safe to call again
## after adding capabilities or changing deployment.
static func setup_project_for_targets(
	web: bool,
	native: bool,
	webgpu: bool = false,
	hands: bool = true,
	perception: bool = true,
	preset_name: String = ""
) -> PackedStringArray:
	var lines := PackedStringArray()
	for check in run_project_checks(preset_name):
		var check_id: String = check["id"]
		if check_id == CHECK_WEB_PRESET and not web:
			continue
		if check_id in [CHECK_OPENXR, CHECK_REFERENCE_SPACE, CHECK_ACTION_MAP] and not native:
			continue
		if check_id == CHECK_RENDERER and not native and not webgpu:
			continue
		if not check["ok"]:
			var line := apply_project_fix(check_id, preset_name)
			if not line.is_empty():
				lines.append(line)
	if web and webgpu:
		var webgpu_line := _configure_webgpu_project()
		if not webgpu_line.is_empty():
			lines.append(webgpu_line)
	if web or native:
		var footprint_line := _sync_export_filters(
			web,
			native,
			hands,
			perception,
			preset_name
		)
		if not footprint_line.is_empty():
			lines.append(footprint_line)
	if lines.is_empty():
		lines.append("Selected deployment is already configured - nothing to change.")
	return lines


## WebGPU remains a per-preset selection. These are only the shared project
## renderer prerequisites needed when at least one Web preset enables it.
static func _configure_webgpu_project() -> String:
	var changed := false
	var desired := {
		"rendering/renderer/rendering_method": "mobile",
		"rendering/renderer/rendering_method.web": "mobile",
		"rendering/rendering_device/driver.web": "webgpu",
		"xr/shaders/enabled": false,
	}
	for setting in desired:
		var value: Variant = desired[setting]
		if ProjectSettings.get_setting(setting, null) != value:
			ProjectSettings.set_setting(setting, value)
			changed = true
	if not changed:
		return ""
	ProjectSettings.save()
	return (
		"Configured shared WebGPU renderer prerequisites. WebGPU remains "
		+ "selected independently in each Web export preset; restart required."
	)


## XR-enabled export presets are the target source of truth. Ordinary Web or
## Android presets with their XR capability switched off are not active XR
## targets. The dock never mirrors these choices into ProjectSettings.
static func detect_export_profiles(preset_name: String = "") -> Dictionary:
	var web_presets := PackedStringArray()
	var android_presets := PackedStringArray()
	var result := {
		"ok": false,
		"web": false,
		"android": false,
		"native": false,
		"webgpu": false,
		"universal_apk": false,
		"web_presets": PackedStringArray(),
		"android_presets": PackedStringArray(),
	}
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return result
	result["ok"] = true
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var platform := str(config.get_value(section, "platform", ""))
		var name := str(config.get_value(section, "name", section))
		if not preset_name.is_empty() and name != preset_name:
			continue
		var options := section + ".options"
		if platform == "Web":
			if bool(config.get_value(options, "webxr/uses_webxr", false)):
				result["web"] = true
				web_presets.append(name)
				if bool(config.get_value(options, "webgpu/enabled", false)):
					result["webgpu"] = true
		elif platform == "Android":
			result["android"] = true
			if bool(
				config.get_value(options, "universal_xr_apk/enabled", false)
			):
				result["universal_apk"] = true
				result["native"] = true
				android_presets.append(name)
	result["web_presets"] = web_presets
	result["android_presets"] = android_presets
	return result


static func is_webgpu_enabled_in_web_presets() -> bool:
	return bool(detect_export_profiles().get("webgpu", false))


## Matches Godot's Export dialog when it has not been opened yet: the dialog's
## initial refresh selects the last configured preset.
static func get_default_export_preset_name() -> String:
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return ""
	var result := ""
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			result = str(config.get_value(section, "name", section))
	return result


## Read-only deployment guidance. These are user-owned choices, so Validator
## explains their hosting requirements but Repair Required never changes them.
static func get_web_environment(preset_name: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return {}
	for section in config.get_sections():
		if (
			not section.begins_with("preset.")
			or section.ends_with(".options")
			or str(config.get_value(section, "name", section)) != preset_name
			or str(config.get_value(section, "platform", "")) != "Web"
		):
			continue
		var options := section + ".options"
		var threads := bool(
			config.get_value(options, "variant/thread_support", false)
		)
		var webgpu := bool(
			config.get_value(options, "webgpu/enabled", false)
		)
		var detail := (
			"Threads ON: the host must provide HTTPS and COOP/COEP "
			+ "cross-origin-isolation headers."
			if threads
			else (
				"Threads OFF: no COOP/COEP isolation headers are required. "
				+ "WebXR still requires HTTPS (or localhost for testing)."
			)
		)
		detail += (
			" WebGPU ON: this export uses Godot's Mobile renderer, not "
			+ "Forward+. Support is detected at page load; browsers without "
			+ "WebGPU fall back to WebGL. Immersive WebXR currently prefers "
			+ "WebGL by default for broader feature support unless the user "
			+ "explicitly selects experimental WebGPU."
			if webgpu
			else " WebGPU OFF: this preset uses the WebGL renderer."
		)
		detail += " Validator will not change these environment choices."
		return {
			"threads": threads,
			"webgpu": webgpu,
			"detail": detail,
		}
	return {}


## Builds the starter playground the Scene Validator's checks describe: prefab
## (rig + sessions + hands + VR/AR entry UI), teleportable floor, sun + sky
## environment, and one grabbable in reach. Detached from any tree (no _ready
## runs) so it can be packed and saved headless.
static func build_starter_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "XRPlayground"
	if ResourceLoader.exists(KIT_PREFAB):
		# The rig's Hands node defaults to REALISTIC, so a fresh scene shows the
		# good hands out of the box - configure it under WebXRRig/XROrigin3D/Hands.
		root.add_child((load(KIT_PREFAB) as PackedScene).instantiate())
	if ResourceLoader.exists(TOOLKIT_FLOOR):
		root.add_child((load(TOOLKIT_FLOOR) as PackedScene).instantiate())

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	root.add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
	root.add_child(world_env)

	if ResourceLoader.exists(TOOLKIT_GRABBABLE):
		var grabbable := (load(TOOLKIT_GRABBABLE) as PackedScene).instantiate() as Node3D
		grabbable.name = "Grabbable"
		grabbable.position = Vector3(0.0, 0.9, -0.6)
		root.add_child(grabbable)

	const SIMULATOR := "res://addons/godot_webxr_kit/runtime/xr_simulator.gd"
	if ResourceLoader.exists(SIMULATOR):
		var simulator := Node.new()
		simulator.name = "XRSimulator"
		simulator.set_script(load(SIMULATOR))
		root.add_child(simulator)

	const DEBUG_PANEL := "res://addons/godot_xr_interaction_toolkit/runtime/xr_debug_panel.gd"
	if ResourceLoader.exists(DEBUG_PANEL):
		var debug_panel := Node3D.new()
		debug_panel.name = "XRDebugPanel"
		debug_panel.set_script(load(DEBUG_PANEL))
		debug_panel.position = Vector3(0.9, 1.5, -1.2)
		debug_panel.rotation_degrees = Vector3(0.0, -25.0, 0.0)
		root.add_child(debug_panel)
	return root


## Saves the starter scene to path. Returns "" on success, an error line
## otherwise.
static func save_starter_scene(path: String) -> String:
	var root := build_starter_scene()
	for child in root.get_children():
		child.owner = root
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		return "FAILED to save the starter scene (error %d)." % err
	return ""


static func _find_web_preset() -> Dictionary:
	var presets := _find_webxr_presets()
	return {} if presets.is_empty() else presets[0]


static func _find_webxr_presets(
	preset_name: String = ""
) -> Array[Dictionary]:
	var presets: Array[Dictionary] = []
	for preset in _find_web_presets():
		if (
			bool(preset["options"].get("webxr/uses_webxr", false))
			and (
				preset_name.is_empty()
				or str(preset.get("name", "")) == preset_name
			)
		):
			presets.append(preset)
	return presets


static func _find_web_presets() -> Array[Dictionary]:
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return []
	var presets: Array[Dictionary] = []
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and str(config.get_value(section, "platform", "")) == "Web":
			var options := {}
			var options_section := section + ".options"
			if config.has_section(options_section):
				for key in config.get_section_keys(options_section):
					options[key] = config.get_value(options_section, key)
			presets.append({
				"section": section,
				"name": config.get_value(section, "name", ""),
				"options": options,
			})
	return presets


static func _fix_web_preset(preset_name: String = "") -> String:
	var config := ConfigFile.new()
	config.load(PRESETS_PATH)  # missing file is fine - we create preset.0
	var preset_sections := PackedStringArray()
	for section in config.get_sections():
		if (
			section.begins_with("preset.")
			and not section.ends_with(".options")
			and str(config.get_value(section, "platform", "")) == "Web"
			and (
				preset_name.is_empty()
				or str(config.get_value(section, "name", section)) == preset_name
			)
			and bool(
				config.get_value(
					section + ".options",
					"webxr/uses_webxr",
					false
				)
			)
		):
			preset_sections.append(section)
	var created := preset_sections.is_empty() and preset_name.is_empty()
	if preset_sections.is_empty() and not preset_name.is_empty():
		return "FAILED: selected preset is not an enabled WebXR preset."
	if created:
		var index := 0
		while config.has_section("preset.%d" % index):
			index += 1
		var section := "preset.%d" % index
		preset_sections.append(section)
		config.set_value(section, "name", "Web (XR)")
		config.set_value(section, "platform", "Web")
		config.set_value(section, "runnable", true)
		config.set_value(section, "export_filter", "all_resources")
		config.set_value(section, "export_path", "build/web/index.html")
		# Thread Support is an environment/deployment choice. Repair never
		# changes it or assumes the user's server can provide COOP/COEP.
	for section in preset_sections:
		var filters := PackedStringArray()
		for raw_filter in str(
			config.get_value(section, "exclude_filter", "")
		).split(",", false):
			var filter := raw_filter.strip_edges()
			if not filter.is_empty() and not filters.has(filter):
				filters.append(filter)
		_set_managed_filters(
			filters,
			PackedStringArray(COMMON_EXPORT_EXCLUDES),
			true
		)
		config.set_value(section, "exclude_filter", ",".join(filters))
		config.set_value(section + ".options", "webxr/uses_webxr", true)
		var shell := str(
			config.get_value(
				section + ".options",
				"html/custom_html_shell",
				""
			)
		)
		if shell.is_empty() and FileAccess.file_exists(KIT_SHELL):
			config.set_value(
				section + ".options",
				"html/custom_html_shell",
				KIT_SHELL
			)
	var err := config.save(PRESETS_PATH)
	if err != OK:
		return "FAILED to write export_presets.cfg (error %d)." % err
	return (
		"Web preset%s %s: uses_webxr ON + XR shell. If the Export dialog "
		+ "was already open, close and reopen it."
	) % [
		"s" if preset_sections.size() != 1 else "",
		"created" if created else "patched",
	]


## Reports the automatic export-time cleanup owned by the neutral toolkit.
## Preset exclude_filter entries are only a readable fallback now; missing
## entries never block export because EditorExportPlugin filters every file.
static func get_export_filter_health(
	web: bool,
	native: bool,
	hands: bool,
	perception: bool,
	preset_name: String = ""
) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return {
			"ok": false,
			"detail": "export_presets.cfg could not be read.",
		}
	var checked_platform := ""
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var current_name := str(config.get_value(section, "name", section))
		if not preset_name.is_empty() and current_name != preset_name:
			continue
		var platform := str(config.get_value(section, "platform", ""))
		if (platform == "Web" and not web) or (platform == "Android" and not native):
			continue
		if platform != "Web" and platform != "Android":
			continue
		checked_platform = platform
		break
	if checked_platform.is_empty():
		return {
			"ok": false,
			"detail": "No active WebXR or Universal XR APK presets were found.",
		}
	var optional_summary := "Enhanced Hands %s; Scene Understanding %s." % [
		"included" if hands else "stripped",
		"included" if perception else "stripped",
	]
	return {
		"ok": true,
		"label": (
			"Automatic APK package cleanup"
			if checked_platform == "Android"
			else "Automatic Web package cleanup"
		),
		"detail": (
			"Runs automatically before every APK export. Browser-only and "
			+ "editor-only files are stripped; optional XR features follow "
			+ "Auto/Force Include/Strip. "
			+ optional_summary
			if checked_platform == "Android"
			else (
				"Runs automatically before every Web export. Native APK and "
				+ "editor-only files are stripped; optional XR features "
				+ "follow Auto/Force Include/Strip. "
				+ optional_summary
			)
		),
	}


## Applies explicit, reversible export exclusions. Opposite-platform code is
## always stripped; optional feature folders follow Auto/Force Include/Strip.
## Unrelated user-authored filters are preserved.
static func _sync_export_filters(
	web: bool,
	native: bool,
	hands: bool,
	perception: bool,
	preset_name: String = ""
) -> String:
	var config := ConfigFile.new()
	var load_error := config.load(PRESETS_PATH)
	if load_error != OK:
		return "FAILED to synchronize optional feature export filters (error %d)." % load_error

	var hands_tokens := PackedStringArray([
		"addons/godot_xr_hands/*",
		"addons/godot_xr_hands/**/*",
	])
	var perception_tokens := PackedStringArray([
		"addons/godot_xr_scene_understanding/*",
		"addons/godot_xr_scene_understanding/**/*",
		"addons/godot_webxr_scene_understanding/*",
		"addons/godot_webxr_scene_understanding/**/*",
	])
	var changed_presets := PackedStringArray()
	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var current_name := str(config.get_value(section, "name", section))
		if not preset_name.is_empty() and current_name != preset_name:
			continue
		var platform := str(config.get_value(section, "platform", ""))
		if (platform == "Web" and not web) or (platform == "Android" and not native):
			continue
		if platform != "Web" and platform != "Android":
			continue
		var filters := PackedStringArray()
		for raw_filter in str(config.get_value(section, "exclude_filter", "")).split(
			",",
			false
		):
			var filter := raw_filter.strip_edges()
			if not filter.is_empty() and not filters.has(filter):
				filters.append(filter)
		var before := filters.duplicate()
		_set_managed_filters(filters, hands_tokens, not hands)
		_set_managed_filters(filters, perception_tokens, not perception)
		_set_managed_filters(
			filters,
			PackedStringArray(COMMON_EXPORT_EXCLUDES),
			true
		)
		# Platform exclusions are applied last so an included optional feature
		# cannot accidentally restore the opposite platform's provider.
		if platform == "Web":
			_set_managed_filters(
				filters,
				PackedStringArray(WEB_PLATFORM_EXCLUDES),
				true
			)
			_set_managed_filters(
				filters,
				PackedStringArray(ANDROID_FILTERS_RESTORED_ON_WEB),
				false
			)
		else:
			_set_managed_filters(
				filters,
				PackedStringArray(ANDROID_PLATFORM_EXCLUDES),
				true
			)
			_set_managed_filters(
				filters,
				PackedStringArray(WEB_FILTERS_RESTORED_ON_ANDROID),
				false
			)
		if filters != before:
			config.set_value(section, "exclude_filter", ",".join(filters))
			changed_presets.append(current_name)

	if changed_presets.is_empty():
		return ""
	var save_error := config.save(PRESETS_PATH)
	if save_error != OK:
		return "FAILED to save optional feature export filters (error %d)." % save_error
	if native and not web:
		return (
			"Applied APK package cleanup to: %s. Only this preset's "
			+ "file-inclusion rules changed."
		) % ", ".join(changed_presets)
	if web and not native:
		return (
			"Applied Web package cleanup to: %s. Only this preset's "
			+ "file-inclusion rules changed; its Threads, WebGPU, and hosting "
			+ "choices were preserved."
		) % ", ".join(changed_presets)
	return (
		"Applied export package cleanup to: %s. Only file-inclusion rules "
		+ "changed."
	) % ", ".join(changed_presets)


static func _set_managed_filters(
	filters: PackedStringArray,
	managed_tokens: PackedStringArray,
	strip_feature: bool
) -> void:
	for token in managed_tokens:
		if strip_feature and not filters.has(token):
			filters.append(token)
		elif not strip_feature and filters.has(token):
			filters.remove_at(filters.find(token))
