extends Control
## In-world control panel: a per-source occlusion/visualization matrix. Each
## data SOURCE (Room Mesh, Live Recon, Depth Scan) has two INDEPENDENT toggles:
##   Show    = draw the source's geometry (visible blue mesh / scan)
##   Occlude = draw it as an invisible passthrough punch (hide virtual content
##             behind the real world - the AR occlusion effect)
## Room Mesh and Live Recon are the SAME mesh-detection stream with opposite
## device semantics (stored scan vs live reconstruction); the static/dynamic
## classifier enables whichever applies here and greys the other. Scene Labels
## is its own system (semantic words from plane/mesh detection). Every toggle
## reports its honest per-device status to the label.

@onready var _state_label: Label = %StateLabel
@onready var _rows: VBoxContainer = %Rows

const ON_COLOR := Color(0.45, 1.0, 0.55)
const OFF_COLOR := Color(0.74, 0.76, 0.80)
const NA_COLOR := Color(0.48, 0.50, 0.54)

# The mesh source drives ONE bridge from either the Room Mesh or Live Recon row
# (only the device-applicable one is enabled).
var _mesh_lbl: Label
var _mesh_show: Button
var _mesh_occ: Button
var _live_lbl: Label
var _live_show: Button
var _live_occ: Button
var _depth_show: Button
var _depth_occ: Button
var _res_btn: Button
var _occ_mode_btn: Button
var _edge_row: HBoxContainer
var _edge_slider: HSlider
var _edge_value_lbl: Label
var _labels_btn: Button
## Depth-occlude technique: false = working hard mesh punch, true = experimental
## per-pixel soft (feathered) occlusion.
var _depth_soft := false

func _ready() -> void:
	_build_ui()
	_sync.call_deferred()

## ---- UI construction (built in code so the matrix layout lives in one place) ----

func _build_ui() -> void:
	var mesh_row := _make_row("Room Mesh")
	_mesh_lbl = mesh_row[0]
	_mesh_show = mesh_row[1]
	_mesh_occ = mesh_row[2]
	var live_row := _make_row("Live Recon")
	_live_lbl = live_row[0]
	_live_show = live_row[1]
	_live_occ = live_row[2]
	var depth_row := _make_row("Depth Scan")
	_depth_show = depth_row[1]
	_depth_occ = depth_row[2]

	# Resolution is a sub-control of Depth Scan (the sensor grid it harvests).
	_res_btn = Button.new()
	_res_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_res_btn.custom_minimum_size = Vector2(0, 48)
	_res_btn.add_theme_font_size_override("font_size", 22)
	_res_btn.text = "      Resolution: -"
	_rows.add_child(_res_btn)

	# Depth-occlude technique: the working hard-edged mesh punch, or the
	# experimental per-pixel soft (feathered) version.
	_occ_mode_btn = Button.new()
	_occ_mode_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_occ_mode_btn.custom_minimum_size = Vector2(0, 48)
	_occ_mode_btn.add_theme_font_size_override("font_size", 22)
	_occ_mode_btn.text = "      Occlude: Hard"
	_rows.add_child(_occ_mode_btn)

	# Soft-occlusion edge softness slider (shown only in Soft mode). crispest 0
	# .. softest 1, live value shown.
	_edge_row = HBoxContainer.new()
	_edge_row.add_theme_constant_override("separation", 10)
	var edge_name := Label.new()
	edge_name.text = "   Edge"
	edge_name.add_theme_font_size_override("font_size", 22)
	_edge_slider = HSlider.new()
	_edge_slider.min_value = 0.0
	_edge_slider.max_value = 1.0
	_edge_slider.step = 0.01
	_edge_slider.value = 0.0
	_edge_slider.custom_minimum_size = Vector2(240, 44)
	_edge_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edge_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edge_value_lbl = Label.new()
	_edge_value_lbl.text = "0.00"
	_edge_value_lbl.custom_minimum_size = Vector2(70, 0)
	_edge_value_lbl.add_theme_font_size_override("font_size", 22)
	_edge_row.add_child(edge_name)
	_edge_row.add_child(_edge_slider)
	_edge_row.add_child(_edge_value_lbl)
	_edge_row.visible = false
	_rows.add_child(_edge_row)

	_rows.add_child(HSeparator.new())

	# Scene Labels is its own system (semantic words), not part of the matrix.
	var lab_row := HBoxContainer.new()
	lab_row.add_theme_constant_override("separation", 8)
	var lab_name := Label.new()
	lab_name.text = "Scene Labels"
	lab_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab_name.add_theme_font_size_override("font_size", 26)
	_labels_btn = _toggle("Show")
	lab_row.add_child(lab_name)
	lab_row.add_child(_labels_btn)
	_rows.add_child(lab_row)

	# Wiring. Room Mesh and Live Recon drive the SAME mesh bridge; only the
	# enabled row can fire, so both point at the same handlers.
	_mesh_show.toggled.connect(_on_mesh_show)
	_mesh_occ.toggled.connect(_on_mesh_occlude)
	_live_show.toggled.connect(_on_mesh_show)
	_live_occ.toggled.connect(_on_mesh_occlude)
	_depth_show.toggled.connect(_on_depth_show)
	_depth_occ.toggled.connect(_on_depth_occlude)
	_res_btn.pressed.connect(_on_res_pressed)
	_occ_mode_btn.pressed.connect(_on_occ_mode_pressed)
	_edge_slider.value_changed.connect(_on_edge_changed)
	_labels_btn.toggled.connect(_on_labels_toggled)

## Live soft-occlusion edge softness (0 = crispest .. 1 = softest).
func _on_edge_changed(v: float) -> void:
	var b = _depth_bridge()
	if b != null:
		b.set_occ_softness(v)
	_edge_value_lbl.text = "%.2f" % v

func _toggle(text: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = text
	b.custom_minimum_size = Vector2(120, 52)
	b.add_theme_font_size_override("font_size", 24)
	return b

## Returns [label, show_button, occlude_button].
func _make_row(source_name: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = source_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 26)
	var show_b := _toggle("Show")
	var occ_b := _toggle("Occlude")
	row.add_child(lbl)
	row.add_child(show_b)
	row.add_child(occ_b)
	_rows.add_child(row)
	return [lbl, show_b, occ_b]

## ---- handlers ----

# Per source, Show and Occlude are mutually exclusive (either one, or both off):
# turning one on turns the other off.
func _on_mesh_show(pressed: bool) -> void:
	var b = _mesh_bridge()
	if b == null:
		_state_label.text = "Room mesh bridge missing."
		return
	if pressed:
		b.set_occlusion(false)
	b.set_visualize(pressed)
	_state_label.text = b.get_status()
	_sync()

func _on_mesh_occlude(pressed: bool) -> void:
	var b = _mesh_bridge()
	if b == null:
		_state_label.text = "Room mesh bridge missing."
		return
	if pressed:
		b.set_visualize(false)
	b.set_occlusion(pressed)
	_state_label.text = b.get_status()
	_sync()

func _on_depth_show(pressed: bool) -> void:
	var b = _depth_bridge()
	if b == null:
		_state_label.text = "Depth bridge missing."
		return
	if pressed:
		_set_depth_occlude(false)  # Show and Occlude are exclusive.
	b.set_visualize(pressed)
	_state_label.text = b.get_status()
	_sync()

# Depth occlusion = the live depth-mesh punch (dynamic, occludes a moving hand).
# Hard-edged but reliable; the per-pixel soft version is a separate experiment.
func _on_depth_occlude(pressed: bool) -> void:
	var b = _depth_bridge()
	if b == null:
		_state_label.text = "Depth bridge missing."
		return
	if pressed:
		b.set_visualize(false)  # exclusive with Show
	_set_depth_occlude(pressed)
	_state_label.text = b.get_status()
	_sync()

# Hard = the depth-mesh punch (crisp). Soft = per-object occlusion: the depth
# bridge feeds the env-depth globals and each occludable object fades to
# passthrough where the real world is in front, with a feathered edge.
func _set_depth_occlude(on: bool) -> void:
	var b = _depth_bridge()
	if b == null:
		return
	if _depth_soft:
		b.set_occlude(false)
		b.set_ext_harvest(on)
	else:
		b.set_ext_harvest(false)
		b.set_occlude(on)

## Toggle Hard/Soft; re-apply live if occlusion is on.
func _on_occ_mode_pressed() -> void:
	var was_on := _depth_occ.button_pressed
	if was_on:
		_set_depth_occlude(false)
	_depth_soft = not _depth_soft
	if was_on:
		_set_depth_occlude(true)
	_state_label.text = "Depth occlude: %s." % ("SOFT per-object (feathered edges)" if _depth_soft else "HARD mesh punch (crisp)")
	_sync()

func _on_labels_toggled(pressed: bool) -> void:
	var b = _mesh_bridge()
	if b == null:
		_state_label.text = "Room mesh bridge missing."
		return
	b.set_labels(pressed)
	_state_label.text = b.get_status()
	_sync()

## Cycle the depth sensor grid Low -> ... -> Max -> Low. Higher = sharper
## Depth Scan/occlusion up to the sensor's own resolution, but heavier.
func _on_res_pressed() -> void:
	var b = _depth_bridge()
	if b == null:
		return
	var count: int = b.RES_LEVELS.size()
	b.set_resolution_level((b.res_level + 1) % count)
	_state_label.text = "Depth resolution: %s. Higher = sharper but heavier (esp. the CPU-depth path)." % b.resolution_label()
	_sync()

## ---- helpers ----

func _mesh_bridge():
	var nodes := get_tree().get_nodes_in_group("webxr_mesh_bridge")
	return null if nodes.is_empty() else nodes[0]

func _depth_bridge():
	var nodes := get_tree().get_nodes_in_group("webxr_depth_bridge")
	return null if nodes.is_empty() else nodes[0]

func _occluder():
	var nodes := get_tree().get_nodes_in_group("webxr_occluder")
	return null if nodes.is_empty() else nodes[0]

func _is_dynamic(bridge) -> bool:
	return bridge != null and bridge.has_method("is_dynamic_mesh_platform") and bridge.is_dynamic_mesh_platform()

## The active session's granted feature list ('' outside a session).
func _session_features() -> String:
	var webxr := XRServer.find_interface("WebXR")
	if webxr == null or not webxr.is_initialized():
		return ""
	return str(webxr.get("enabled_features"))

# The behavioural static/dynamic classifier can transiently flip (Quest's
# re-localization bursts read as dynamic for a moment), which would flap the
# active mesh row. Latch the verdict once per session so Room Mesh / Live Recon
# assignment is STABLE - the greyed row never becomes live mid-session.
var _dyn_latched := false
var _dyn_value := false
func _device_is_dynamic(mb) -> bool:
	if _session_features().is_empty():
		_dyn_latched = false
		return _is_dynamic(mb)
	if not _dyn_latched:
		_dyn_value = _is_dynamic(mb)
		_dyn_latched = true
	return _dyn_value

## Availability can change mid-session (streams warm up, services stall) -
## keep the per-button device readouts fresh without any toggling.
var _refresh_accum := 0.0
func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 2.0:
		_refresh_accum = 0.0
		if not _session_features().is_empty():
			_sync()

## Reflect one toggle button: pressed state + a strong colour (the theme's
## pressed shading is too subtle in-headset).
func _reflect(btn: Button, on: bool) -> void:
	btn.set_pressed_no_signal(on)
	btn.disabled = false
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.self_modulate = ON_COLOR if on else OFF_COLOR

## Grey out a source row that doesn't apply on this device. MOUSE_FILTER_IGNORE
## is essential: in XR the ray interactor pushes input straight at the control,
## bypassing Button.disabled - only ignoring input truly stops a faded toggle
## from firing.
func _disable_row(lbl: Label, base_name: String, show_b: Button, occ_b: Button) -> void:
	lbl.text = "%s (n/a here)" % base_name
	for b in [show_b, occ_b]:
		b.set_pressed_no_signal(false)
		b.disabled = true
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.self_modulate = NA_COLOR

func _sync() -> void:
	var feats := _session_features()
	var in_session := not feats.is_empty()
	var mb = _mesh_bridge()
	var dynamic := _device_is_dynamic(mb)
	# Room Mesh applies on stored-scan (static) devices; Live Recon on live
	# (dynamic) reconstruction devices. The other is greyed.
	if mb == null:
		_disable_row(_mesh_lbl, "Room Mesh", _mesh_show, _mesh_occ)
		_disable_row(_live_lbl, "Live Recon", _live_show, _live_occ)
	elif dynamic:
		_disable_row(_mesh_lbl, "Room Mesh", _mesh_show, _mesh_occ)
		_live_lbl.text = "Live Recon"
		_reflect(_live_show, mb.auto_visualize)
		_reflect(_live_occ, mb.occlusion_enabled)
	else:
		_disable_row(_live_lbl, "Live Recon", _live_show, _live_occ)
		_mesh_lbl.text = "Room Mesh"
		_reflect(_mesh_show, mb.auto_visualize)
		_reflect(_mesh_occ, mb.occlusion_enabled)

	var db = _depth_bridge()
	if db == null:
		for b in [_depth_show, _depth_occ]:
			b.disabled = true
			b.self_modulate = NA_COLOR
		_res_btn.text = "      Resolution: -"
	else:
		_reflect(_depth_show, db.auto_visualize)
		_reflect(_depth_occ, db.is_soft_occluding() if _depth_soft else db.occlude_enabled)
		_occ_mode_btn.text = "      Occlude: %s" % ("Soft" if _depth_soft else "Hard")
		# The edge-softness slider only makes sense in Soft mode.
		_edge_row.visible = _depth_soft
		var res_note := ""
		if in_session and not feats.contains("depth-sensing"):
			res_note = " (depth n/a)"
		_res_btn.text = "      Resolution: %s%s" % [db.resolution_label(), res_note]

	if mb != null:
		_reflect(_labels_btn, mb.show_labels)
