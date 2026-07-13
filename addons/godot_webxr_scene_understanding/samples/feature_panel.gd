extends Control
## In-world control panel for the scene-understanding demo: one toggle per
## DATA SOURCE, each reporting its node's honest per-device status to the
## label. Quest and Android XR both expose 'mesh-detection', but with
## opposite semantics (stored room scan vs live reconstruction) - the
## static/dynamic classifier decides which of the two mesh toggles is live
## on this device; the other refuses with a pointer. Depth Scan is the raw
## depth-sensing API on every device, honestly labeled as our own
## triangulation of single-frame sensor readings.

@onready var _state_label: Label = %StateLabel
@onready var _mesh_button: Button = %RoomMeshButton
@onready var _live_button: Button = %LiveReconButton
@onready var _labels_button: Button = %LabelsButton
@onready var _occlusion_button: Button = %OcclusionButton
@onready var _depth_button: Button = %DepthSensingButton

func _ready() -> void:
	_mesh_button.toggled.connect(_on_mesh_toggled)
	_live_button.toggled.connect(_on_live_toggled)
	_labels_button.toggled.connect(_on_labels_toggled)
	_occlusion_button.toggled.connect(_on_occlusion_toggled)
	_depth_button.toggled.connect(_on_depth_toggled)
	_sync_toggle_states.call_deferred()

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

## Availability can change mid-session (streams warm up, services stall) -
## keep the per-button device readouts fresh without any toggling.
var _refresh_accum := 0.0
func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= 2.0:
		_refresh_accum = 0.0
		if not _session_features().is_empty():
			_sync_toggle_states()

## Room Mesh (stored) = mesh-detection serving a STATIC captured space
## (Quest Space Setup). Live-reconstruction devices have no such thing.
func _on_mesh_toggled(pressed: bool) -> void:
	var bridge = _mesh_bridge()
	if bridge == null:
		_state_label.text = "Room mesh bridge missing."
		return
	if pressed and _is_dynamic(bridge):
		_mesh_button.set_pressed_no_signal(false)
		_state_label.text = "No stored room scan on this device - it reconstructs live. Use Live Reconstruction."
		return
	bridge.set_visualize(pressed)
	_state_label.text = bridge.get_status()
	_sync_toggle_states()

## Live Reconstruction = mesh-detection serving the OS's continuously
## updated environment mesh (Android XR). Stored-scan devices don't stream.
func _on_live_toggled(pressed: bool) -> void:
	var bridge = _mesh_bridge()
	if bridge == null:
		_state_label.text = "Room mesh bridge missing."
		return
	if pressed and not _is_dynamic(bridge):
		_live_button.set_pressed_no_signal(false)
		_state_label.text = "This device serves a stored room scan, not a live stream. Use Room Mesh (stored)."
		return
	bridge.set_visualize(pressed)
	_state_label.text = bridge.get_status()
	_sync_toggle_states()

func _on_labels_toggled(pressed: bool) -> void:
	var bridge = _mesh_bridge()
	if bridge == null:
		_state_label.text = "Room mesh bridge missing."
		return
	bridge.set_labels(pressed)
	_state_label.text = bridge.get_status()
	_sync_toggle_states()

func _on_occlusion_toggled(pressed: bool) -> void:
	var occluder = _occluder()
	if occluder == null:
		_state_label.text = "Occluder missing."
		return
	occluder.set_occlusion(pressed)
	_state_label.text = occluder.get_status()
	_sync_toggle_states()

func _on_depth_toggled(pressed: bool) -> void:
	var bridge = _depth_bridge()
	if bridge == null:
		_state_label.text = "Depth bridge missing."
		return
	bridge.set_visualize(pressed)
	_state_label.text = bridge.get_status()
	_sync_toggle_states()

## Mesh visualize and occlusion exclude each other in the bridge; mirror the
## true state on every toggle without re-firing signals. The theme's pressed
## shading is too subtle in-headset, so the text says On/Off explicitly.
func _sync_toggle_states() -> void:
	# Device-availability readouts live in the button text itself, so users
	# see what THIS device serves without toggling anything. Outside a
	# session grants are unknown - the suffixes stay quiet.
	var feats := _session_features()
	var in_session := not feats.is_empty()
	var mesh_bridge = _mesh_bridge()
	if mesh_bridge != null:
		# One mesh-detection visualization, two device semantics: the
		# classifier picks which button owns it here; the other reads n/a.
		var dynamic_platform := _is_dynamic(mesh_bridge)
		var mesh_on: bool = mesh_bridge.auto_visualize
		var mesh_granted := feats.contains("mesh-detection")
		var served: int = mesh_bridge.get_served_count() if in_session else -1
		_mesh_button.set_pressed_no_signal(mesh_on and not dynamic_platform)
		_live_button.set_pressed_no_signal(mesh_on and dynamic_platform)
		var mesh_state := "On" if mesh_on else "Off"
		if in_session and not mesh_granted:
			_mesh_button.text = "Room Mesh (stored): not granted"
			_live_button.text = "Live Reconstruction: not granted"
		else:
			_mesh_button.text = "Room Mesh (stored): %s" % ("n/a on this device" if dynamic_platform else mesh_state)
			if not dynamic_platform:
				_live_button.text = "Live Reconstruction: n/a on this device"
			elif served >= 0:
				_live_button.text = "Live Reconstruction: %s - %d meshes live" % [mesh_state, served]
			else:
				_live_button.text = "Live Reconstruction: %s" % mesh_state
		_labels_button.set_pressed_no_signal(mesh_bridge.show_labels)
		var labels_state := "On" if mesh_bridge.show_labels else "Off"
		if in_session and feats.contains("plane-detection"):
			labels_state += " - planes served"
		_labels_button.text = "Scene Labels: %s" % labels_state
	var occluder = _occluder()
	if occluder != null:
		_occlusion_button.set_pressed_no_signal(occluder.occlusion_enabled)
		_occlusion_button.text = "Occlusion: %s" % ("On" if occluder.occlusion_enabled else "Off")
	var depth_bridge = _depth_bridge()
	if depth_bridge != null:
		_depth_button.set_pressed_no_signal(depth_bridge.auto_visualize)
		var depth_state := "On" if depth_bridge.auto_visualize else "Off"
		if in_session:
			if not feats.contains("depth-sensing"):
				depth_state = "not granted"
			else:
				var usage := str(depth_bridge.get_usage())
				if usage == "cpu-optimized":
					depth_state += " - cpu depth served"
				elif usage == "gpu-optimized":
					depth_state += " - gpu-only depth"
		_depth_button.text = "Depth Scan (raw): %s" % depth_state
