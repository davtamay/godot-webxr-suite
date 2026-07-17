extends Node3D
# Internal per-hand debug panel for XRGestureRecognizer (no class_name; the
# recognizer preloads it). Five curl BARS + a pinch dot above the wrist,
# camera-facing. Bars turn GREEN when inside the nearest gesture's condition
# band and RED when they are what blocks it - tuning by color, not numbers.

const _LINE_MATERIAL := preload("res://addons/godot_xr_hands/runtime/gesture_studio/gesture_ghost_material.tres")

const _FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
const _BAR_HEIGHT := 0.05
const _BAR_WIDTH := 0.008
const _BAR_SPACING := 0.016
const _NEUTRAL := Color(0.55, 0.65, 0.85, 0.85)
const _IN_BAND := Color(0.25, 1.0, 0.5, 0.95)
const _BLOCKING := Color(1.0, 0.3, 0.25, 0.95)
const _BG := Color(0.1, 0.12, 0.16, 0.5)

var _fills := {}
var _pinch_dot: MeshInstance3D
var _title: Label3D


func _ready() -> void:
	top_level = true
	for i in _FINGERS.size():
		var x := (i - 2) * _BAR_SPACING
		_make_quad("bg_%s" % _FINGERS[i], x, _BAR_HEIGHT, _BG, -0.001)
		_fills[_FINGERS[i]] = _make_quad(_FINGERS[i], x, _BAR_HEIGHT, _NEUTRAL, 0.0)
	_pinch_dot = MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.006
	dot.height = 0.012
	_pinch_dot.mesh = dot
	_pinch_dot.material_override = _tinted(_NEUTRAL)
	_pinch_dot.position = Vector3(3 * _BAR_SPACING, 0.0, 0.0)
	add_child(_pinch_dot)
	_title = Label3D.new()
	_title.pixel_size = 0.0005
	_title.font_size = 26
	_title.outline_size = 8
	_title.no_depth_test = true
	_title.position = Vector3(0.0, _BAR_HEIGHT + 0.02, 0.0)
	add_child(_title)


func update_panel(anchor: Transform3D, camera: Camera3D, features: Dictionary, active_names: Array, nearest: Dictionary) -> void:
	visible = not features.is_empty()
	if not visible:
		return
	global_position = anchor.origin + Vector3(0.0, 0.09, 0.0)
	if camera:
		var to_camera := camera.global_position - global_position
		if to_camera.length_squared() > 0.0001:
			global_basis = Basis.looking_at(-to_camera.normalized(), Vector3.UP)

	var nearest_conditions: Dictionary = nearest.get("conditions", {})
	var failing: PackedStringArray = nearest.get("failing", PackedStringArray())
	for finger in _FINGERS:
		var feature := "curl_%s" % finger
		var value: float = clampf(features.get(feature, 0.0), 0.0, 1.0)
		var fill: MeshInstance3D = _fills[finger]
		fill.scale = Vector3(1.0, maxf(value, 0.02), 1.0)
		fill.position.y = (_BAR_HEIGHT * maxf(value, 0.02) - _BAR_HEIGHT) * 0.5
		var color := _NEUTRAL
		if nearest_conditions.has(feature):
			color = _BLOCKING if feature in failing else _IN_BAND
		(fill.material_override as StandardMaterial3D).albedo_color = color

	var pinch: float = clampf(features.get("pinch_index", 0.0), 0.0, 1.0)
	_pinch_dot.scale = Vector3.ONE * (0.6 + pinch * 1.6)
	(_pinch_dot.material_override as StandardMaterial3D).albedo_color = _IN_BAND if pinch > 0.75 else _NEUTRAL

	if not active_names.is_empty():
		_title.text = ", ".join(PackedStringArray(active_names))
		_title.modulate = _IN_BAND
	elif nearest.has("name"):
		_title.text = "%s?" % nearest["name"]
		_title.modulate = _BLOCKING if not failing.is_empty() else _NEUTRAL
	else:
		_title.text = ""


func _make_quad(quad_name: String, x: float, height: float, color: Color, z: float) -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = quad_name
	var mesh := QuadMesh.new()
	mesh.size = Vector2(_BAR_WIDTH, height)
	quad.mesh = mesh
	quad.material_override = _tinted(color)
	quad.position = Vector3(x, 0.0, z)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	return quad


func _tinted(color: Color) -> StandardMaterial3D:
	var material := _LINE_MATERIAL.duplicate() as StandardMaterial3D
	material.albedo_color = color
	return material
