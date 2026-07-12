extends Control
## In-world control panel for the scene-understanding demo: one toggle per
## feature, each reporting its node's honest per-device status to the label.

@onready var _state_label: Label = %StateLabel
@onready var _mesh_button: Button = %RoomMeshButton
@onready var _labels_button: Button = %LabelsButton
@onready var _occlusion_button: Button = %OcclusionButton
@onready var _depth_button: Button = %DepthSensingButton

func _ready() -> void:
	_mesh_button.toggled.connect(_on_mesh_toggled)
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

func _on_mesh_toggled(pressed: bool) -> void:
	var bridge = _mesh_bridge()
	if bridge == null:
		_state_label.text = "Room mesh bridge missing."
		return
	# Room Mesh = the STATIC stored space. Devices that stream their
	# reconstruction live have no such thing - that experience lives under
	# Depth Sensing (dynamic).
	if pressed and bridge.has_method("is_dynamic_mesh_platform") and bridge.is_dynamic_mesh_platform():
		_mesh_button.set_pressed_no_signal(false)
		_state_label.text = "No stored room mesh on this device - it reconstructs live. Use Depth Sensing (dynamic)."
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
	var mesh_bridge = _mesh_bridge()
	if mesh_bridge != null:
		# Static vs dynamic is the core distinction - keep it on the buttons.
		var dynamic_platform: bool = mesh_bridge.has_method("is_dynamic_mesh_platform") and mesh_bridge.is_dynamic_mesh_platform()
		var mesh_on: bool = mesh_bridge.auto_visualize and not dynamic_platform
		_mesh_button.set_pressed_no_signal(mesh_on)
		_labels_button.set_pressed_no_signal(mesh_bridge.show_labels)
		_mesh_button.text = "Room Mesh (static): %s" % ("n/a" if dynamic_platform else ("On" if mesh_on else "Off"))
		_labels_button.text = "Scene Labels: %s" % ("On" if mesh_bridge.show_labels else "Off")
	var occluder = _occluder()
	if occluder != null:
		_occlusion_button.set_pressed_no_signal(occluder.occlusion_enabled)
		_occlusion_button.text = "Occlusion: %s" % ("On" if occluder.occlusion_enabled else "Off")
	var depth_bridge = _depth_bridge()
	if depth_bridge != null:
		_depth_button.set_pressed_no_signal(depth_bridge.auto_visualize)
		_depth_button.text = "Depth Sensing (dynamic): %s" % ("On" if depth_bridge.auto_visualize else "Off")
