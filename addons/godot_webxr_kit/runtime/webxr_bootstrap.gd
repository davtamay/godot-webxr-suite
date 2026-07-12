extends Node3D

## Minimal WebXR startup flow.
## Attach to a Node3D in the demo scene and wire VR/AR Buttons plus optional status Label.
## This intentionally uses Godot's WebXRInterface, not custom WebGPU rendering.

## Legacy single-button path. If enter_vr_button_path is empty, this is used as the VR button.
@export var enter_xr_button_path: NodePath
@export var enter_vr_button_path: NodePath
@export var enter_ar_button_path: NodePath
@export var status_label_path: NodePath
@export var inspect_object_path: NodePath
@export var world_environment_path: NodePath
@export var enable_legacy_select_visuals := false
## When true, "hand-tracking" is a REQUIRED session feature and browsers or
## devices without it refuse the whole session (controller-only headsets,
## hands disabled in system settings). Off by default: hand tracking is then
## requested as an optional feature and still granted where available.
@export var require_hand_tracking := false
@export var ar_hide_group := "ar_passthrough_hidden"
## Nodes in this group are hidden during ANY immersive session (VR or AR)
## and restored on exit. Put screen-space UI (CanvasLayer HUDs) here:
## Godot composites the 2D canvas into each eye's view otherwise.
@export var session_hide_group := "xr_session_hidden"

## Preloaded so the shader baker can precompile it for web/WebGPU exports.
const HIGHLIGHT_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/highlight_material.tres")

var _webxr: XRInterface
var _vr_supported := false
var _ar_supported := false
var _vr_support_checked := false
var _ar_support_checked := false
var _vr_button: Button
var _ar_button: Button
var _status_label: Label
var _inspect_object: MeshInstance3D
var _world_environment: WorldEnvironment
var _select_count := 0
var _base_scale := Vector3.ONE
var _base_material: Material
var _highlight_material: StandardMaterial3D
var _last_session_failed := false
var _requested_session_mode := ""
var _active_session_mode := ""
var _base_transparent_bg := false
var _base_clear_color := Color.BLACK
var _base_environment_background_mode := -1
var _base_environment_background_color := Color.BLACK
var _ar_hidden_node_visibility := {}
var _session_hidden_node_visibility := {}

func _ready() -> void:
    _vr_button = get_node_or_null(enter_vr_button_path) as Button
    if _vr_button == null:
        _vr_button = get_node_or_null(enter_xr_button_path) as Button
    _ar_button = get_node_or_null(enter_ar_button_path) as Button
    _status_label = get_node_or_null(status_label_path) as Label
    _inspect_object = get_node_or_null(inspect_object_path) as MeshInstance3D
    _world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
    _base_transparent_bg = get_viewport().transparent_bg
    _base_clear_color = RenderingServer.get_default_clear_color()
    if _world_environment and _world_environment.environment:
        _base_environment_background_mode = _world_environment.environment.background_mode
        _base_environment_background_color = _world_environment.environment.background_color

    if _vr_button:
        _vr_button.pressed.connect(_on_enter_vr_pressed)
        _vr_button.disabled = true
    else:
        _set_status("Enter VR button path is not assigned or does not point to a Button.")

    if _ar_button:
        _ar_button.pressed.connect(_on_enter_ar_pressed)
        _ar_button.disabled = true
    else:
        _set_status("Enter AR button path is not assigned or does not point to a Button.")

    if _inspect_object:
        _base_scale = _inspect_object.scale
        _base_material = _inspect_object.get_active_material(0)
        # Duplicate of a baked .tres; colors/energy are uniforms, so the
        # baked shader hash is kept.
        _highlight_material = HIGHLIGHT_MATERIAL.duplicate() as StandardMaterial3D
        _highlight_material.albedo_color = Color(0.25, 0.95, 0.68, 1.0)
        _highlight_material.emission = Color(0.25, 0.95, 0.68, 1.0)
        _highlight_material.emission_energy_multiplier = 1.2
    else:
        _set_status("Inspect object path is not assigned or does not point to a MeshInstance3D.")

    if not OS.has_feature("web"):
        _set_status("Not a web export. WebXRInterface is available only in web builds.")
        return

    _webxr = XRServer.find_interface("WebXR")
    if not _webxr:
        _set_status("WebXR interface not found.")
        return

    _webxr.session_supported.connect(_on_session_supported)
    _webxr.session_started.connect(_on_session_started)
    _webxr.session_ended.connect(_on_session_ended)
    _webxr.session_failed.connect(_on_session_failed)
    _connect_webxr_input_signal("select", _on_webxr_select)
    _connect_webxr_input_signal("selectstart", _on_webxr_select_start)
    _connect_webxr_input_signal("selectend", _on_webxr_select_end)

    _set_status("Checking WebXR VR/AR support...")
    _webxr.is_session_supported("immersive-vr")
    _webxr.is_session_supported("immersive-ar")

func _on_session_supported(session_mode: String, supported: bool) -> void:
    match session_mode:
        "immersive-vr":
            _vr_supported = supported
            _vr_support_checked = true
            if _vr_button:
                _vr_button.disabled = not supported
        "immersive-ar":
            _ar_supported = supported
            _ar_support_checked = true
            if _ar_button:
                _ar_button.disabled = not supported
        _:
            return

    _set_status("WebXR support: VR %s, AR %s." % [_support_text(_vr_support_checked, _vr_supported), _support_text(_ar_support_checked, _ar_supported)])

func _on_enter_vr_pressed() -> void:
    _start_xr_session("immersive-vr")

func _on_enter_ar_pressed() -> void:
    _start_xr_session("immersive-ar")

func _start_xr_session(session_mode: String) -> void:
    if not _webxr:
        _set_status("WebXR interface missing.")
        return

    if session_mode == "immersive-vr" and not _vr_supported:
        _set_status("immersive-vr not supported.")
        return
    if session_mode == "immersive-ar" and not _ar_supported:
        _set_status("immersive-ar not supported.")
        return

    _requested_session_mode = session_mode
    _webxr.session_mode = session_mode
    _webxr.requested_reference_space_types = _reference_space_types_for(session_mode)
    _webxr.required_features = _required_features_for(session_mode)
    _webxr.optional_features = _optional_features_for(session_mode)

    _set_status("Requesting %s session..." % _session_label(session_mode))
    if not _webxr.initialize():
        _requested_session_mode = ""
        _set_status("WebXR initialize() returned false. Session was not requested.")

func _on_session_started() -> void:
    _last_session_failed = false
    _active_session_mode = _requested_session_mode
    if _active_session_mode.is_empty():
        _active_session_mode = _webxr.session_mode
    _apply_ar_scene_mode(_active_session_mode == "immersive-ar")
    _apply_session_hidden(true)
    get_viewport().use_xr = true
    _set_status("%s session started. Reference space: %s. Enabled features: %s." % [_session_label(_active_session_mode), _webxr.reference_space_type, _webxr.enabled_features])

func _on_session_ended() -> void:
    get_viewport().use_xr = false
    # The root viewport only re-derives its size from the window inside
    # Window's private update, which runs on resize notifications - and on
    # web the window doesn't resize after session exit, so the viewport
    # stays stuck at the XR per-eye size (2D draws shrunken while input
    # maps to the real layout). Nudging the content scale factor forces
    # that update to run against the (correct) window size.
    var win := get_window()
    var scale_factor := win.content_scale_factor
    win.content_scale_factor = scale_factor * 1.000001 + 0.000001
    win.content_scale_factor = scale_factor
    _apply_ar_scene_mode(false)
    _apply_session_hidden(false)
    _requested_session_mode = ""
    _active_session_mode = ""
    if _last_session_failed:
        return
    _set_status("WebXR session ended.")

func _on_session_failed(message: String) -> void:
    _last_session_failed = true
    get_viewport().use_xr = false
    _apply_ar_scene_mode(false)
    _apply_session_hidden(false)
    _requested_session_mode = ""
    _active_session_mode = ""
    _set_status("WEBXR FAILED: " + message)
    _show_browser_failure("WEBXR FAILED: " + message)

func _connect_webxr_input_signal(signal_name: StringName, callback: Callable) -> void:
    if not _webxr.has_signal(signal_name):
        _set_status("WebXR signal unavailable in this Godot build: " + str(signal_name))
        return

    if not _webxr.is_connected(signal_name, callback):
        _webxr.connect(signal_name, callback)

func _on_webxr_select(input_source_id: int) -> void:
    _select_count += 1
    if enable_legacy_select_visuals:
        _apply_select_visual_state()
        _set_status("XR select received: %d (input source %d)" % [_select_count, input_source_id])
    else:
        print("XR select received: %d (input source %d)" % [_select_count, input_source_id])

func _on_webxr_select_start(input_source_id: int) -> void:
    print("XR select started (input source %d)" % input_source_id)

func _on_webxr_select_end(input_source_id: int) -> void:
    print("XR select ended (input source %d)" % input_source_id)

func _apply_select_visual_state() -> void:
    if not _inspect_object:
        _set_status("XR select received but inspect object is unavailable.")
        return

    var highlighted := _select_count % 2 == 1
    _inspect_object.scale = _base_scale * (1.25 if highlighted else 1.0)
    _inspect_object.set_surface_override_material(0, _highlight_material if highlighted else _base_material)

func _set_status(message: String) -> void:
    if _status_label:
        _status_label.text = message
    print(message)

func _support_text(checked: bool, supported: bool) -> String:
    if not checked:
        return "checking"
    return "yes" if supported else "no"

func _session_label(session_mode: String) -> String:
    return "AR" if session_mode == "immersive-ar" else "VR"

func _reference_space_types_for(session_mode: String) -> String:
    if session_mode == "immersive-ar":
        return "local-floor, local"
    # local-floor first: its forward is where the user faces at session
    # start, so the scene spawns in front of them. bounded-floor anchors to
    # the room's calibrated (arbitrary) forward instead.
    return "local-floor, bounded-floor, local"

func _required_features_for(session_mode: String) -> String:
    # Deliberately NOT declaring the 'layers' feature: Godot only ever uses
    # a single projection layer, which Chromium serves without the
    # declaration - while DECLARING it makes Android XR spin up its full
    # multi-layer compositor at session start (a 2-3s head-locked system
    # transition; found by feature-set bisection on a Galaxy XR). Verified
    # working without it on Quest 3 (WebGL+WebGPU paths) and Galaxy XR.
    # Re-add (conditionally) only if quad/cylinder layers are ever used.
    var features: Array[String] = []
    if require_hand_tracking:
        features.append("hand-tracking")
    _merge_provider_features(features, &"get_webxr_required_features", session_mode)
    return ", ".join(features)

func _optional_features_for(session_mode: String) -> String:
    var features: Array[String] = ["local-floor"]
    if session_mode == "immersive-vr":
        features.append("bounded-floor")
    if not require_hand_tracking:
        features.append("hand-tracking")
    # Feature-provider contract: nodes in the 'webxr_feature_provider' group
    # declare the session features they need (mesh bridge -> mesh-detection,
    # depth bridge/occluder -> depth-sensing), so a scene only requests what
    # it actually contains. Leaner requests enter immersive mode faster
    # (Android XR charges startup ceremony per feature family).
    _merge_provider_features(features, &"get_webxr_optional_features", session_mode)
    return ", ".join(features)

func _merge_provider_features(features: Array[String], method: StringName, session_mode: String) -> void:
    for node in get_tree().get_nodes_in_group("webxr_feature_provider"):
        if not node.has_method(method):
            continue
        for f in node.call(method, session_mode):
            var feature := str(f)
            if not feature.is_empty() and not features.has(feature):
                features.append(feature)

func _apply_ar_scene_mode(enabled: bool) -> void:
    get_viewport().transparent_bg = enabled if enabled else _base_transparent_bg
    RenderingServer.set_default_clear_color(Color(0, 0, 0, 0) if enabled else _base_clear_color)

    if _world_environment and _world_environment.environment:
        if enabled:
            _world_environment.environment.background_mode = Environment.BG_CLEAR_COLOR
            _world_environment.environment.background_color = Color(0, 0, 0, 0)
        elif _base_environment_background_mode >= 0:
            _world_environment.environment.background_mode = _base_environment_background_mode
            _world_environment.environment.background_color = _base_environment_background_color

    for node in get_tree().get_nodes_in_group(ar_hide_group):
        if not (node is Node3D):
            continue

        var node_3d := node as Node3D
        if enabled:
            if not _ar_hidden_node_visibility.has(node_3d):
                _ar_hidden_node_visibility[node_3d] = node_3d.visible
            node_3d.visible = false
        elif _ar_hidden_node_visibility.has(node_3d):
            node_3d.visible = bool(_ar_hidden_node_visibility[node_3d])

    if not enabled:
        _ar_hidden_node_visibility.clear()

func _apply_session_hidden(enabled: bool) -> void:
    for node in get_tree().get_nodes_in_group(session_hide_group):
        if not (node is CanvasItem or node is Node3D or node is CanvasLayer):
            continue
        if enabled:
            if not _session_hidden_node_visibility.has(node):
                _session_hidden_node_visibility[node] = node.visible
            node.visible = false
        elif _session_hidden_node_visibility.has(node):
            node.visible = bool(_session_hidden_node_visibility[node])

    if not enabled:
        _session_hidden_node_visibility.clear()

func _show_browser_failure(message: String) -> void:
    if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
        return

    var js_bridge = Engine.get_singleton("JavaScriptBridge")
    var encoded_message := JSON.stringify(message)
    js_bridge.eval("window.CompanyWebXRFailure = %s; console.error(%s);" % [encoded_message, encoded_message], true)
