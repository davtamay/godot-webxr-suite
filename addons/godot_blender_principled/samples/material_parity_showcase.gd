extends Node3D

## Renders the imported Blender material collection under the strict-parity
## environment for a measurable 1:1 comparison, plus a row of PrincipledMaterial
## spheres and a Blender-reference comparison overlay.
##
## Controls:
##   SPACE - toggle strict-parity (Linear tonemap = Blender Standard view) vs
##           nice-look (AgX).
##   R     - toggle the Blender reference image overlay for an A/B against the
##           live Godot render (only if the reference PNG is present).

const COLLECTION := "res://addons/godot_blender_principled/samples/assets/MaterialCollection.glb"
## User-supplied Blender Standard-view render (Pipeline -> Match Unity Preview),
## dropped in beside the GLB. Absent by default; the overlay handles that.
const REFERENCE := "res://addons/godot_blender_principled/samples/assets/blender_reference_standardview.png"

var _world_env: WorldEnvironment
var _orbit: Node3D
var _nice := false
var _mode_label: Label
var _reference_rect: TextureRect
var _has_reference := false

func _ready() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.environment = StrictParityEnvironment.parity_environment()
	add_child(_world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.5
	add_child(sun)

	_orbit = Node3D.new()
	add_child(_orbit)
	var cam := Camera3D.new()
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 4.0))
	cam.current = true
	_orbit.add_child(cam)

	var collection := (load(COLLECTION) as PackedScene).instantiate()
	add_child(collection)

	_build_principled_row()
	_build_overlay()

func _build_principled_row() -> void:
	var sphere := SphereMesh.new()
	for i in range(5):
		var metallic := float(i) / 4.0
		var roughness := 1.0 - float(i) / 4.0
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.position = Vector3(-2.0 + i * 1.0, 0.0, 1.5)
		var mat := PrincipledMaterial.new()
		mat.base_color = Color(0.8, 0.3, 0.2)
		mat.metallic = metallic
		mat.roughness = roughness
		mi.material_override = mat
		add_child(mi)

		# Per-material label so the parity comparison is legible.
		var label := Label3D.new()
		label.text = "M %.2f\nR %.2f" % [metallic, roughness]
		label.font_size = 32
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = mi.position + Vector3(0, 0.7, 0)
		add_child(label)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Blender reference image overlay (hidden until toggled). Only usable if the
	# user has dropped in a Standard-view render next to the GLB.
	_has_reference = ResourceLoader.exists(REFERENCE)
	_reference_rect = TextureRect.new()
	_reference_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reference_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reference_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reference_rect.visible = false
	if _has_reference:
		_reference_rect.texture = load(REFERENCE)
	layer.add_child(_reference_rect)

	_mode_label = Label.new()
	_mode_label.position = Vector2(16, 16)
	layer.add_child(_mode_label)
	_refresh_mode_label()

	# On-screen buttons so the toggles work on devices without a keyboard
	# (e.g. Quest Browser, where SPACE/R are unavailable but pointer/pinch works).
	var buttons := VBoxContainer.new()
	buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buttons.position = Vector2(-220, 16)
	buttons.add_theme_constant_override("separation", 8)
	layer.add_child(buttons)

	var tonemap_btn := Button.new()
	tonemap_btn.text = "Toggle tonemap (parity / AgX)"
	tonemap_btn.custom_minimum_size = Vector2(200, 48)
	tonemap_btn.pressed.connect(_toggle_tonemap)
	buttons.add_child(tonemap_btn)

	if _has_reference:
		var ref_btn := Button.new()
		ref_btn.text = "Toggle Blender reference"
		ref_btn.custom_minimum_size = Vector2(200, 48)
		ref_btn.pressed.connect(_toggle_reference)
		buttons.add_child(ref_btn)

func _toggle_tonemap() -> void:
	_nice = not _nice
	_world_env.environment = StrictParityEnvironment.nice_environment() if _nice else StrictParityEnvironment.parity_environment()
	_refresh_mode_label()

func _toggle_reference() -> void:
	if not _has_reference:
		return
	_reference_rect.visible = not _reference_rect.visible
	_refresh_mode_label()

func _refresh_mode_label() -> void:
	var mode := "NICE LOOK (AgX)" if _nice else "STRICT PARITY (Linear = Blender Standard view)"
	var ref_hint := ""
	if not _has_reference:
		ref_hint = "\n[R] Blender reference: drop 'blender_reference_standardview.png' next to the GLB to enable A/B"
	elif _reference_rect.visible:
		ref_hint = "\n[R] showing Blender reference overlay (A/B vs live render)"
	else:
		ref_hint = "\n[R] toggle Blender reference overlay"
	_mode_label.text = "%s\n[SPACE] toggle tonemap%s" % [mode, ref_hint]

func _process(delta: float) -> void:
	_orbit.rotate_y(delta * 0.2)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_toggle_tonemap()
		elif event.keycode == KEY_R:
			_toggle_reference()
