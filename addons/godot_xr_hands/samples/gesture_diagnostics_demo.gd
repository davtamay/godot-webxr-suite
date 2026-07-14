extends Node3D

## Pose-driven gesture laboratory. Runtime events are intentionally generic;
## this script demonstrates one possible gameplay binding with a visual reactor.

const WEBXR_BOOTSTRAP := "res://addons/godot_webxr_kit/runtime/webxr_bootstrap.gd"
const SHOWCASE_MATERIAL := preload("res://addons/godot_xr_hands/runtime/showcase_material.tres")

const POSE_COLORS := {
    &"pinch": Color(0.2, 0.95, 1.0, 1.0),
    &"fist": Color(1.0, 0.32, 0.18, 1.0),
    &"point": Color(1.0, 0.82, 0.16, 1.0),
    &"open_palm": Color(0.4, 1.0, 0.48, 1.0),
}
const POSE_TITLES := {
    &"pinch": "PINCH  •  charge the reactor",
    &"fist": "FIST  •  release a shockwave",
    &"point": "POINT  •  fire the energy beam",
    &"open_palm": "OPEN PALM  •  reset the system",
}
const SATELLITE_POSITIONS := {
    &"pinch": Vector3(-0.9, 1.15, -1.75),
    &"fist": Vector3(-0.3, 1.1, -1.9),
    &"point": Vector3(0.3, 1.1, -1.9),
    &"open_palm": Vector3(0.9, 1.15, -1.75),
}

@onready var _runtime: XRGestureRuntime = $GestureRuntime
@onready var _screen_status: Label = %StatusLabel
@onready var _world_status: Label3D = $WorldDiagnostics
@onready var _event_banner: Label3D = $EventBanner

var _event_line := "Make a pose to power the gesture reactor"
var _elapsed := 0.0
var _showcase_time := 0.0
var _showcase_root: Node3D
var _core: MeshInstance3D
var _target: MeshInstance3D
var _satellites := {}

func _ready() -> void:
    _build_showcase()
    _runtime.gesture_started.connect(_on_gesture_started)
    _runtime.gesture_performed.connect(_on_gesture_performed)
    _runtime.gesture_ended.connect(_on_gesture_ended)
    _install_optional_webxr_bootstrap()
    _update_diagnostics()
    const MENU_BUTTON := "res://scripts/back_to_menu_button.gd"
    if ResourceLoader.exists(MENU_BUTTON):
        var menu_button = load(MENU_BUTTON)
        if menu_button:
            add_child(menu_button.new())

func _process(delta: float) -> void:
    _elapsed += delta
    _showcase_time += delta
    _animate_showcase()
    if _elapsed >= 0.1:
        _elapsed = 0.0
        _update_diagnostics()

func _unhandled_key_input(event: InputEvent) -> void:
    var key_event := event as InputEventKey
    if key_event == null or get_viewport().use_xr or not key_event.pressed or key_event.echo:
        return
    var gesture_id: StringName
    match key_event.keycode:
        KEY_1:
            gesture_id = &"pinch"
        KEY_2:
            gesture_id = &"fist"
        KEY_3:
            gesture_id = &"point"
        KEY_4:
            gesture_id = &"open_palm"
        _:
            return
    _on_gesture_performed(gesture_id, 1, 1.0)

func _build_showcase() -> void:
    _showcase_root = Node3D.new()
    _showcase_root.name = "GestureReactor"
    add_child(_showcase_root)

    var core_mesh := SphereMesh.new()
    core_mesh.radius = 0.18
    core_mesh.height = 0.36
    core_mesh.radial_segments = 24
    core_mesh.rings = 12
    _core = _make_mesh("Core", core_mesh, Vector3(0, 1.55, -1.65), Color(0.25, 0.68, 1.0, 1.0))

    var target_mesh := TorusMesh.new()
    target_mesh.inner_radius = 0.16
    target_mesh.outer_radius = 0.23
    target_mesh.rings = 24
    target_mesh.ring_segments = 12
    _target = _make_mesh("BeamTarget", target_mesh, Vector3(0.95, 1.55, -2.25), POSE_COLORS[&"point"])
    _target.rotation_degrees.x = 90.0

    for gesture_id in SATELLITE_POSITIONS:
        var satellite_mesh := SphereMesh.new()
        satellite_mesh.radius = 0.075
        satellite_mesh.height = 0.15
        satellite_mesh.radial_segments = 16
        satellite_mesh.rings = 8
        var satellite := _make_mesh(
            "%sSatellite" % String(gesture_id).to_pascal_case(),
            satellite_mesh,
            SATELLITE_POSITIONS[gesture_id],
            POSE_COLORS[gesture_id])
        _satellites[gesture_id] = satellite
        _add_pose_label(gesture_id, SATELLITE_POSITIONS[gesture_id] + Vector3(0, -0.17, 0))

func _make_mesh(name: String, mesh: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    instance.set_surface_override_material(0, _make_material(color))
    _showcase_root.add_child(instance)
    return instance

func _make_material(color: Color) -> StandardMaterial3D:
    var material := SHOWCASE_MATERIAL.duplicate() as StandardMaterial3D
    material.albedo_color = color
    material.emission = color
    material.emission_energy_multiplier = 2.5
    return material

func _add_pose_label(gesture_id: StringName, position: Vector3) -> void:
    var label := Label3D.new()
    label.name = "%sLabel" % String(gesture_id).to_pascal_case()
    label.position = position
    label.pixel_size = 0.0012
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.font_size = 32
    label.outline_size = 7
    label.text = String(gesture_id).replace("_", " ").to_upper()
    _showcase_root.add_child(label)

func _animate_showcase() -> void:
    if _core == null:
        return
    _core.rotation.y += 0.012
    _target.rotation.z += 0.008
    var index := 0
    for gesture_id in SATELLITE_POSITIONS:
        var satellite := _satellites[gesture_id] as MeshInstance3D
        var base: Vector3 = SATELLITE_POSITIONS[gesture_id]
        satellite.position.y = base.y + sin(_showcase_time * 2.2 + float(index) * 0.8) * 0.035
        satellite.rotation.y += 0.018
        index += 1

func _install_optional_webxr_bootstrap() -> void:
    if not ResourceLoader.exists(WEBXR_BOOTSTRAP):
        %EnterVRButton.disabled = true
        %EnterARButton.disabled = true
        _event_line = "WebXR kit absent; start this scene from a native OpenXR project."
        return
    var bootstrap_script = load(WEBXR_BOOTSTRAP)
    if bootstrap_script == null:
        return
    var bootstrap = bootstrap_script.new()
    bootstrap.name = "WebXRBootstrap"
    bootstrap.enter_vr_button_path = NodePath("../CanvasLayer/Panel/Margin/VBox/SessionButtons/EnterVRButton")
    bootstrap.enter_ar_button_path = NodePath("../CanvasLayer/Panel/Margin/VBox/SessionButtons/EnterARButton")
    bootstrap.status_label_path = NodePath("../CanvasLayer/Panel/Margin/VBox/StatusLabel")
    bootstrap.world_environment_path = NodePath("../WorldEnvironment")
    add_child(bootstrap)

func _update_diagnostics() -> void:
    var lines: Array[String] = ["XR Gesture Reactor", _event_line]
    lines.append(_format_hand("Left", 0))
    lines.append(_format_hand("Right", 1))
    lines.append("Poses: pinch • fist • point • open palm  |  Desktop preview: keys 1–4")
    var text := "\n".join(lines)
    _screen_status.text = text
    _world_status.text = text

func _format_hand(label: String, hand: int) -> String:
    var features := _runtime.get_features(hand)
    if features == null or not features.valid:
        return "%s: tracking unavailable" % label
    return "%s: quality %.0f%%  pinch %.2f  curls %.2f %.2f %.2f %.2f %.2f" % [
        label,
        features.tracking_quality * 100.0,
        features.pinch_distance,
        features.finger_curls[0],
        features.finger_curls[1],
        features.finger_curls[2],
        features.finger_curls[3],
        features.finger_curls[4],
    ]

func _on_gesture_started(gesture_id: StringName, hand: int, score: float) -> void:
    _event_line = "%s %s candidate %.2f" % [_hand_name(hand), gesture_id, score]
    var satellite := _satellites.get(gesture_id) as MeshInstance3D
    if satellite != null:
        _tween_scale(satellite, Vector3.ONE * 1.35, 0.08)

func _on_gesture_performed(gesture_id: StringName, hand: int, score: float) -> void:
    _event_line = "%s invoked %s at %.0f%%" % [_hand_name(hand), gesture_id, score * 100.0]
    _event_banner.text = POSE_TITLES.get(gesture_id, String(gesture_id))
    _event_banner.modulate = POSE_COLORS.get(gesture_id, Color.WHITE)
    _trigger_showcase_event(gesture_id)

func _on_gesture_ended(gesture_id: StringName, hand: int, score: float) -> void:
    _event_line = "%s %s released %.2f" % [_hand_name(hand), gesture_id, score]
    var satellite := _satellites.get(gesture_id) as MeshInstance3D
    if satellite != null:
        _tween_scale(satellite, Vector3.ONE, 0.12)

func _trigger_showcase_event(gesture_id: StringName) -> void:
    match gesture_id:
        &"pinch":
            _pinch_charge()
        &"fist":
            _fist_shockwave()
        &"point":
            _point_beam()
        &"open_palm":
            _open_palm_reset()

func _pinch_charge() -> void:
    var tween := create_tween()
    tween.tween_property(_core, "scale", Vector3.ONE * 0.35, 0.12).set_trans(Tween.TRANS_BACK)
    tween.tween_property(_core, "scale", Vector3.ONE * 1.5, 0.18).set_trans(Tween.TRANS_ELASTIC)
    tween.tween_property(_core, "scale", Vector3.ONE, 0.22)

func _fist_shockwave() -> void:
    for index in range(3):
        var ring_mesh := TorusMesh.new()
        ring_mesh.inner_radius = 0.17
        ring_mesh.outer_radius = 0.205
        ring_mesh.rings = 24
        ring_mesh.ring_segments = 10
        var ring := _make_mesh("Shockwave", ring_mesh, _core.position, POSE_COLORS[&"fist"])
        ring.rotation_degrees.x = 90.0
        ring.scale = Vector3.ONE * (0.35 + float(index) * 0.12)
        var tween := create_tween()
        tween.tween_property(ring, "scale", Vector3.ONE * (2.3 + float(index) * 0.45), 0.45 + float(index) * 0.08).set_trans(Tween.TRANS_QUAD)
        tween.tween_callback(ring.queue_free)

func _point_beam() -> void:
    var origin := _core.position
    var destination := _target.position
    var beam_mesh := BoxMesh.new()
    beam_mesh.size = Vector3(0.035, 0.035, origin.distance_to(destination))
    var beam := _make_mesh("EnergyBeam", beam_mesh, (origin + destination) * 0.5, POSE_COLORS[&"point"])
    beam.look_at(destination, Vector3.UP)
    beam.scale = Vector3(1, 1, 0.05)
    var tween := create_tween()
    tween.tween_property(beam, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_EXPO)
    tween.parallel().tween_property(_target, "scale", Vector3.ONE * 1.55, 0.12)
    tween.tween_interval(0.18)
    tween.tween_property(beam, "scale", Vector3(0.05, 0.05, 1), 0.1)
    tween.parallel().tween_property(_target, "scale", Vector3.ONE, 0.16)
    tween.tween_callback(beam.queue_free)

func _open_palm_reset() -> void:
    var tween := create_tween().set_parallel(true)
    tween.tween_property(_core, "scale", Vector3.ONE * 1.8, 0.2).set_trans(Tween.TRANS_ELASTIC)
    for gesture_id in SATELLITE_POSITIONS:
        var satellite := _satellites[gesture_id] as MeshInstance3D
        tween.tween_property(satellite, "scale", Vector3.ONE, 0.18)
    tween.chain().tween_property(_core, "scale", Vector3.ONE, 0.24)

func _tween_scale(node: Node3D, target_scale: Vector3, duration: float) -> void:
    create_tween().tween_property(node, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK)

func _hand_name(hand: int) -> String:
    return "Left" if hand == 0 else "Right"
