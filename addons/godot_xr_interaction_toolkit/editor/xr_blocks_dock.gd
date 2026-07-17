@tool
extends VBoxContainer

## The "XR Blocks" dock: every drop-in block across the suite's addons, with
## its icon and a one-line description - double-click (or Add) to drop it into
## the edited scene, undo-aware. Blocks from addons that are not installed are
## hidden automatically, so the catalog always matches the project.

## kind "scene" = instantiate a .tscn; "node" = create the script's node type
## with the script attached. Paths are existence-checked at refresh.
const BLOCKS := [
	{"name": "WebXR Prefab", "desc": "Everything XR in one drop: rig + sessions (WebXR + OpenXR) + hands + auto UI.", "kind": "scene", "path": "res://addons/godot_webxr_kit/webxr_prefab.tscn", "icon": "res://addons/godot_webxr_kit/icons/webxr_bootstrap.svg"},
	{"name": "WebXR Rig", "desc": "The pre-wired XR rig alone (origin, camera, controllers, interactors) - for custom-HUD scenes.", "kind": "scene", "path": "res://addons/godot_webxr_kit/rig/webxr_rig.tscn", "icon": "res://addons/godot_webxr_kit/icons/openxr_input_adapter.svg"},
	{"name": "Session UI", "desc": "Enter VR/AR buttons + status HUD; the WebXR bootstrap adopts it automatically.", "kind": "scene", "path": "res://addons/godot_webxr_kit/xr_session_ui.tscn", "icon": "res://addons/godot_webxr_kit/icons/xr_session_ui.svg"},
	{"name": "WebXR Bootstrap", "desc": "Browser session lifecycle (VR/AR entry, passthrough, feature requests).", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_kit/runtime/webxr_bootstrap.gd", "icon": "res://addons/godot_webxr_kit/icons/webxr_bootstrap.svg"},
	{"name": "OpenXR Bootstrap", "desc": "Play straight to a headset from the editor (Quest Link / SteamVR). Inert on web.", "kind": "node", "base": "Node", "path": "res://addons/godot_webxr_kit/runtime/openxr_bootstrap.gd", "icon": "res://addons/godot_webxr_kit/icons/openxr_bootstrap.svg"},
	{"name": "Hands Mount", "desc": "Procedural tracked hands; virtual meshes hide in AR so you see your real hands. Parent under XROrigin3D.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_kit/runtime/xr_hands_mount.gd", "icon": "res://addons/godot_webxr_kit/icons/xr_hands_mount.svg"},
	{"name": "Locomotion", "desc": "Teleport arc + snap turn (thumbsticks). Drop anywhere - finds the rig itself. Rig-default.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_locomotion.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg"},
	{"name": "Microgesture Locomotion", "desc": "Thumb swipes drive the SAME teleport arc + snap turn (needs godot_xr_hands; inert without). Rig-default.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_microgesture_locomotion_driver.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg"},
	{"name": "Input Modality", "desc": "Per-hand controller/hands switching + profile-matched models. Drop anywhere - finds the rig itself. Rig-default.", "kind": "node", "base": "Node", "path": "res://addons/godot_webxr_kit/runtime/xr_input_modality_manager.gd", "icon": "res://addons/godot_webxr_kit/icons/xr_input_modality_manager.svg"},
	{"name": "Realistic Hands", "desc": "Rigged hand meshes (WebXR Input Profiles, MIT) skinned live to the tracked joints. Or set hand_style=REALISTIC on a Hands Mount.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_xr_hands/runtime/xr_hand_mesh_visualizer.gd", "icon": "res://addons/godot_xr_hands/icons/xr_hand_mesh_visualizer.svg"},
	{"name": "Gesture Recognizer", "desc": "Hand gestures as data (.tres) - presets included, tune live with show_debug. Per-hand start/end signals.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_recognizer.gd", "icon": "res://addons/godot_xr_hands/icons/xr_gesture_recognizer.svg"},
	{"name": "Gesture Recorder", "desc": "Hold a pose, get a gesture (.tres, tolerances from your own jitter). Browser saves = that browser only; record via Link/native for real files.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_hands/runtime/gesture_studio/xr_gesture_recorder.gd", "icon": "res://addons/godot_xr_hands/icons/xr_gesture_recognizer.svg"},
	{"name": "Floor (teleportable)", "desc": "Ground in one drop: visible floor + teleport collision; the visual hides in AR passthrough (your real floor takes over).", "kind": "scene", "path": "res://addons/godot_xr_interaction_toolkit/xr_floor.tscn", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg"},
	{"name": "Grabbable", "desc": "Ready grabbable object: swap the mesh, collision auto-fits, highlight included.", "kind": "scene", "path": "res://addons/godot_xr_interaction_toolkit/grabbable.tscn", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg"},
	{"name": "Grab Point", "desc": "Authored grip: parent INSIDE a grabbable where the hand should hold it - grabbing snaps the object into the palm (pos+rot). Per-hand filter, multiple points OK.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_grab_point.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg"},
	{"name": "UI Panel (3D)", "desc": "In-world interactive UI panel; build your Control tree under Viewport/Root.", "kind": "scene", "path": "res://addons/godot_xr_interaction_toolkit/xr_ui_panel.tscn", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_ui_canvas_interactable.svg"},
	{"name": "Keyboard (XR)", "desc": "In-world keyboard: open(initial, prompt) -> text_submitted/cancelled. Letters, digits, space, underscore.", "kind": "scene", "path": "res://addons/godot_xr_interaction_toolkit/xr_keyboard.tscn", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_ui_canvas_interactable.svg"},
	{"name": "Highlight Affordance", "desc": "Hover/grab/use tinting for any interactable. Parent it INSIDE the object - it wires itself.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_highlight_affordance.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_highlight_affordance.svg"},
	{"name": "Socket Affordance", "desc": "Ready/hover/occupied tinting for a socket pad. Parent inside the socket.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_socket_affordance.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_socket_affordance.svg"},
	{"name": "Socket Interactor", "desc": "Snap-zone that grabs and holds interactables placed into it.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_socket_interactor.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_socket_interactor.svg"},
	{"name": "Poke Interactor", "desc": "Fingertip touch: press panels, drag sliders, push 3D buttons. Drop anywhere - finds the rig itself. Rig-default.", "kind": "node", "base": "Node", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_poke_interactor.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg"},
	{"name": "Poke Button (3D)", "desc": "Physical push-button: the cap depresses under your fingertip and fires with hysteresis.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_xr_interaction_toolkit/runtime/xr_poke_button.gd", "icon": "res://addons/godot_xr_interaction_toolkit/icons/xr_poke_interactor.svg"},
	{"name": "Occlusion / Depth", "desc": "Real-world occlusion (hard/soft) + depth debug. Occludees are a drag-in list.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_scene_understanding/runtime/environment_depth_manager.gd", "icon": "res://addons/godot_webxr_scene_understanding/icons/environment_depth_manager.svg"},
	{"name": "Scene Mesh", "desc": "The device's room geometry: visualize, occlude, labels, collision.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_scene_understanding/runtime/scene_mesh_manager.gd", "icon": "res://addons/godot_webxr_scene_understanding/icons/scene_mesh_manager.svg"},
	{"name": "Light Estimation", "desc": "Objects lit by (and reflecting) the real room. Android XR / ARCore.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_scene_understanding/runtime/light_estimation_manager.gd", "icon": "res://addons/godot_webxr_scene_understanding/icons/light_estimation_manager.svg"},
	{"name": "Hit Test + Anchors", "desc": "Surface reticle + pinch-to-place spatial anchors with your scene instanced at them.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webxr_scene_understanding/runtime/hit_test_anchor_manager.gd", "icon": "res://addons/godot_webxr_scene_understanding/icons/hit_test_anchor_manager.svg"},
	{"name": "Bake Anchor", "desc": "Declare runtime-built materials so their shaders bake for WebGPU exports.", "kind": "node", "base": "Node3D", "path": "res://addons/godot_webgpu/bake_anchor.gd", "icon": "res://addons/godot_webgpu/icons/bake_anchor.svg"},
	{"name": "Font Bake Anchor", "desc": "Makes 3D text render on WebGPU exports (bakes the Label3D shader).", "kind": "node", "base": "Label3D", "path": "res://addons/godot_webgpu/font_bake_anchor.gd", "icon": "res://addons/godot_webgpu/icons/font_bake_anchor.svg"},
]

const _Setup := preload("res://addons/godot_xr_interaction_toolkit/editor/xr_project_setup.gd")
const _DoctorScript := preload("res://addons/godot_xr_interaction_toolkit/editor/xr_scene_doctor.gd")

var _list: ItemList
var _desc: Label
var _add_button: Button
var _visible_blocks := []
var _doctor: AcceptDialog


func _ready() -> void:
	name = "XR Blocks"
	var project_row := HBoxContainer.new()
	add_child(project_row)
	var setup_button := Button.new()
	setup_button.text = "Set Up XR Project"
	setup_button.tooltip_text = "Writes the project settings and Web export preset an XR project needs (OpenXR + action map + renderer + WebXR export). Reports every change."
	setup_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_button.pressed.connect(_on_setup_project)
	project_row.add_child(setup_button)
	var doctor_button := Button.new()
	doctor_button.text = "Scene Doctor"
	doctor_button.tooltip_text = "Checks the open scene + project for everything that fails silently on a headset, with one-click fixes."
	doctor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doctor_button.pressed.connect(_on_open_doctor)
	project_row.add_child(doctor_button)

	var hint := Label.new()
	hint.text = "Double-click a block to add it to the scene."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_i): _add_selected())
	add_child(_list)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(0, 56)
	add_child(_desc)
	_add_button = Button.new()
	_add_button.text = "Add to Scene"
	_add_button.pressed.connect(_add_selected)
	add_child(_add_button)
	refresh()


func _on_setup_project() -> void:
	var lines := _Setup.setup_project()
	for line in lines:
		print("XR Setup: ", line)
	_desc.text = "\n".join(lines)


func _on_open_doctor() -> void:
	if _doctor == null:
		_doctor = _DoctorScript.new()
		add_child(_doctor)
	_doctor.popup_centered()


func refresh() -> void:
	_list.clear()
	_visible_blocks.clear()
	for block in BLOCKS:
		if not ResourceLoader.exists(block["path"]):
			continue  # that addon isn't installed in this project
		var icon: Texture2D = load(block["icon"]) if ResourceLoader.exists(block["icon"]) else null
		_list.add_item(block["name"], icon)
		_visible_blocks.append(block)


func _on_selected(index: int) -> void:
	_desc.text = _visible_blocks[index]["desc"]


func _add_selected() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	var block: Dictionary = _visible_blocks[selected[0]]
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_desc.text = "Open a scene first."
		return
	# Add under the current selection when there is one, else the scene root.
	var parent: Node = root
	var editor_selection := EditorInterface.get_selection().get_selected_nodes()
	if not editor_selection.is_empty():
		parent = editor_selection[0]

	var node: Node
	if block["kind"] == "scene":
		node = (load(block["path"]) as PackedScene).instantiate()
	else:
		node = ClassDB.instantiate(block["base"])
		node.set_script(load(block["path"]))
		node.name = block["name"].replace(" ", "").replace("/", "").replace("+", "").replace("(", "").replace(")", "")

	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Add XR Block: %s" % block["name"])
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_method(node, "set_owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()
	_desc.text = "%s added under %s." % [block["name"], parent.name]
