@tool
extends AcceptDialog

## The Scene Doctor: validates the open scene + project against everything an
## XR scene needs to actually work on a headset, with one-click fixes. Every
## row here is a failure that is otherwise SILENT at runtime - the whole point
## is turning headset-debugging roundtrips into editor-time checkmarks.

const _Setup := preload("res://addons/godot_xr_interaction_toolkit/editor/xr_project_setup.gd")

const _PROJECT_IDS := ["openxr_enabled", "action_map", "renderer", "web_preset"]

var _rows: VBoxContainer


func _init() -> void:
	title = "XR Scene Doctor"
	ok_button_text = "Close"
	min_size = Vector2i(560, 380)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 330)
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	about_to_popup.connect(refresh)


func refresh() -> void:
	for child in _rows.get_children():
		child.queue_free()

	_add_header("Project")
	for check in _Setup.run_project_checks():
		_add_row(check, true)

	_add_header("Scene")
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		var none := Label.new()
		none.text = "  (no scene open)"
		_rows.add_child(none)
		return
	for check in _Setup.run_scene_checks(root):
		_add_row(check, false)


func _add_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	header.add_theme_font_size_override("font_size", 15)
	_rows.add_child(header)


func _add_row(check: Dictionary, is_project: bool) -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)

	var status := Label.new()
	status.text = "  ✔" if check["ok"] else "  ✘"
	status.add_theme_color_override("font_color",
			Color(0.35, 0.85, 0.45) if check["ok"] else Color(0.95, 0.4, 0.35))
	status.custom_minimum_size = Vector2(30, 0)
	row.add_child(status)

	var text := Label.new()
	text.text = check["label"] if check["ok"] else "%s\n%s" % [check["label"], check["detail"]]
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	if not check["ok"] and not str(check.get("fix", "")).is_empty():
		var fix := Button.new()
		fix.text = check["fix"]
		fix.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fix.pressed.connect(_apply_fix.bind(check["id"], is_project))
		row.add_child(fix)


func _apply_fix(id: String, is_project: bool) -> void:
	if is_project:
		print("XR Scene Doctor: ", _Setup.apply_project_fix(id))
	else:
		_apply_scene_fix(id)
	refresh()


func _apply_scene_fix(id: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	match id:
		_Setup.CHECK_RIG:
			_add_scene_node((load(_Setup.KIT_PREFAB) as PackedScene).instantiate(), root, "Add WebXR Prefab")
		_Setup.CHECK_LIGHT:
			var sun := DirectionalLight3D.new()
			sun.name = "Sun"
			sun.shadow_enabled = true
			sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
			_add_scene_node(sun, root, "Add Sun")
		_Setup.CHECK_FLOOR:
			_add_scene_node((load(_Setup.TOOLKIT_FLOOR) as PackedScene).instantiate(), root, "Add Floor")


func _add_scene_node(node: Node, root: Node, action: String) -> void:
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("XR Scene Doctor: %s" % action)
	undo.add_do_method(root, "add_child", node, true)
	undo.add_do_method(node, "set_owner", root)
	undo.add_do_reference(node)
	undo.add_undo_method(root, "remove_child", node)
	undo.commit_action()
