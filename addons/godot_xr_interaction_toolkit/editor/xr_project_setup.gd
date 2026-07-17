@tool
extends RefCounted

## Project-level XR checks and fixes behind the dock's "Set Up XR Project"
## button and the Scene Doctor. Encodes the settings a WORKING XR project
## carries that a fresh Godot project lacks - every one of these fails
## SILENTLY at runtime (actions read zero, sessions never start), which is
## why they are enforced here instead of documented.
##
## Project-level functions use only ProjectSettings/ConfigFile (no
## EditorInterface) so they are testable headless; scene-level checks take
## the scene root as a parameter.

const KIT_ACTION_MAP := "res://addons/godot_webxr_kit/openxr/default_action_map.tres"
const KIT_SHELL := "res://addons/godot_webxr_kit/web/adaptable_shell.html"
const KIT_PREFAB := "res://addons/godot_webxr_kit/webxr_prefab.tscn"
const TOOLKIT_FLOOR := "res://addons/godot_xr_interaction_toolkit/xr_floor.tscn"
const TOOLKIT_GRABBABLE := "res://addons/godot_xr_interaction_toolkit/grabbable.tscn"
const PRESETS_PATH := "res://export_presets.cfg"

## Check ids (stable API for fix routing).
const CHECK_OPENXR := "openxr_enabled"
const CHECK_ACTION_MAP := "action_map"
const CHECK_RENDERER := "renderer"
const CHECK_WEB_PRESET := "web_preset"
const CHECK_RIG := "scene_rig"
const CHECK_LIGHT := "scene_light"
const CHECK_FLOOR := "scene_floor"


## Returns [{id, label, ok, detail, fix}] - fix = "" means not auto-fixable.
static func run_project_checks() -> Array:
	var checks := []

	var openxr_on := bool(ProjectSettings.get_setting("xr/openxr/enabled", false))
	checks.append({
		"id": CHECK_OPENXR, "ok": openxr_on,
		"label": "OpenXR enabled (headset Play via Link/SteamVR)",
		"detail": "Without it, pressing Play renders flat on the monitor - the headset is never asked.",
		"fix": "Enable OpenXR + hand tracking",
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
	checks.append({
		"id": CHECK_RENDERER, "ok": renderer_ok,
		"label": "Renderer can drive OpenXR (Mobile + Vulkan)",
		"detail": "OpenXR runtimes reject GL and D3D12-defaulted editors reject Vulkan sessions - headset Play fails with GRAPHICS_DEVICE_INVALID. Web exports stay GL Compatibility via the .web override.",
		"fix": "Set Mobile renderer + Vulkan on Windows",
	})

	var preset := _find_web_preset()
	var preset_ok: bool = not preset.is_empty() \
			and bool(preset["options"].get("webxr/uses_webxr", false)) \
			and not str(preset["options"].get("html/custom_html_shell", "")).is_empty()
	checks.append({
		"id": CHECK_WEB_PRESET, "ok": preset_ok,
		"label": "Web export preset is XR-ready",
		"detail": "Needs webxr/uses_webxr ON (else no WebXR interface ships - Enter VR never appears) and an XR-aware HTML shell. The kit ships one.",
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
		"detail": "Drop WebXR Prefab (rig + sessions + hands + VR/AR entry UI) - the one required block.",
		"fix": "Add WebXR Prefab" if ResourceLoader.exists(KIT_PREFAB) else "",
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
static func apply_project_fix(id: String) -> String:
	match id:
		CHECK_OPENXR:
			ProjectSettings.set_setting("xr/openxr/enabled", true)
			ProjectSettings.set_setting("xr/openxr/extensions/hand_tracking", true)
			ProjectSettings.save()
			return "xr/openxr/enabled = true, hand tracking on."
		CHECK_ACTION_MAP:
			ProjectSettings.set_setting("xr/openxr/default_action_map", KIT_ACTION_MAP)
			ProjectSettings.save()
			return "OpenXR action map -> the kit's (select/grab/thumbstick bindings)."
		CHECK_RENDERER:
			ProjectSettings.set_setting("rendering/renderer/rendering_method", "mobile")
			ProjectSettings.set_setting("rendering/rendering_device/driver.windows", "vulkan")
			ProjectSettings.set_setting("rendering/renderer/rendering_method.web", "gl_compatibility")
			ProjectSettings.save()
			return "Renderer -> Mobile (Vulkan on Windows); web exports stay GL Compatibility. RESTART the editor to apply."
		CHECK_WEB_PRESET:
			return _fix_web_preset()
	return ""


## Applies every failing project-level fix; returns the summary lines.
static func setup_project() -> PackedStringArray:
	var lines := PackedStringArray()
	for check in run_project_checks():
		if not check["ok"]:
			var line := apply_project_fix(check["id"])
			if not line.is_empty():
				lines.append(line)
	if lines.is_empty():
		lines.append("Everything already configured - nothing to change.")
	return lines


## Builds the starter playground the Scene Doctor's checks describe: prefab
## (rig + sessions + hands + VR/AR entry UI), teleportable floor, sun + sky
## environment, and one grabbable in reach. Detached from any tree (no _ready
## runs) so it can be packed and saved headless.
static func build_starter_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "XRPlayground"
	if ResourceLoader.exists(KIT_PREFAB):
		var prefab := (load(KIT_PREFAB) as PackedScene).instantiate()
		# Default to the realistic (registry-model) hands - they're bundled and
		# work well in the toolkit sample, so the starter shows them off too.
		# 1 = XRHandsMount.HandStyle.REALISTIC (avoid a hard class dep here).
		if "hand_style" in prefab:
			prefab.hand_style = 1
		root.add_child(prefab)
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
	var config := ConfigFile.new()
	if config.load(PRESETS_PATH) != OK:
		return {}
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and str(config.get_value(section, "platform", "")) == "Web":
			var options := {}
			var options_section := section + ".options"
			if config.has_section(options_section):
				for key in config.get_section_keys(options_section):
					options[key] = config.get_value(options_section, key)
			return {"section": section, "name": config.get_value(section, "name", ""), "options": options}
	return {}


static func _fix_web_preset() -> String:
	var config := ConfigFile.new()
	config.load(PRESETS_PATH)  # missing file is fine - we create preset.0
	var preset := _find_web_preset()
	var section: String
	if preset.is_empty():
		var index := 0
		while config.has_section("preset.%d" % index):
			index += 1
		section = "preset.%d" % index
		config.set_value(section, "name", "Web (XR)")
		config.set_value(section, "platform", "Web")
		config.set_value(section, "runnable", true)
		config.set_value(section, "export_filter", "all_resources")
		config.set_value(section, "export_path", "build/web/index.html")
		config.set_value(section + ".options", "variant/thread_support", false)
	else:
		section = preset["section"]
	# Editor-only addon scripts (dock, doctor, this file) never run in a build -
	# keep them out of the pck.
	var exclude := str(config.get_value(section, "exclude_filter", ""))
	if not exclude.contains("addons/*/editor/*"):
		exclude = "addons/*/editor/*" if exclude.is_empty() else exclude + ",addons/*/editor/*"
		config.set_value(section, "exclude_filter", exclude)
	config.set_value(section + ".options", "webxr/uses_webxr", true)
	var shell := str(config.get_value(section + ".options", "html/custom_html_shell", ""))
	# FileAccess, not ResourceLoader - .html is not a Godot resource type.
	if shell.is_empty() and FileAccess.file_exists(KIT_SHELL):
		config.set_value(section + ".options", "html/custom_html_shell", KIT_SHELL)
	var err := config.save(PRESETS_PATH)
	if err != OK:
		return "FAILED to write export_presets.cfg (error %d)." % err
	return "Web preset %s: uses_webxr ON + XR shell. If the Export dialog was already open, close and reopen it." % \
			("patched" if not preset.is_empty() else "created")
