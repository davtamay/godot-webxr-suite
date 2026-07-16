@tool
@icon("res://addons/godot_webxr_kit/icons/xr_input_modality_manager.svg")
class_name XRInputModalityManager
extends Node

## Per-hand input modality (Unity XRI's XRInputModalityManager, as a block):
## each hand independently switches between CONTROLLER and tracked HAND, with
## the matching visuals - controller models appear when you pick controllers
## up, hand meshes return when you set them down (the hand visualizer already
## self-hides per hand without tracking data; this block adds the controller
## side and the explicit signal).
##
## Built into WebXRRig, so every rig/prefab scene has it BY DEFAULT - turn it
## off with [member enabled], or pin a modality with [member forced_modality].
## Input itself (poses, pinch, selects) already follows the active source in
## the adapters; this manager owns detection, visuals, and notification.

## A hand's modality changed. hand: 0 = left, 1 = right.
signal modality_changed(hand: int, modality: Modality)

enum Modality { NONE, CONTROLLER, HAND }
enum ForcedModality { AUTO, CONTROLLER, HAND }

const _MODEL_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/controller_model_material.tres")
## A reading must hold this long before the modality switches (transitions
## flicker while the platform hands over between sources).
const _DEBOUNCE_SECONDS := 0.25

## Master switch. Off = no detection, no signals, controller models hidden
## (hand visuals then behave exactly as before this block existed).
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_set_models_visible(false)

## AUTO follows the live trackers per hand. CONTROLLER / HAND pins BOTH hands
## to one modality (visuals only show when that source actually tracks).
@export var forced_modality: ForcedModality = ForcedModality.AUTO

## Show stylized controller models while a hand is in CONTROLLER modality.
@export var show_controller_models := true

## The rig's XRController3D nodes (aim pose) the models attach to.
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath

var _modality := [Modality.NONE, Modality.NONE]
var _pending := [Modality.NONE, Modality.NONE]
var _pending_time := [0.0, 0.0]
var _models: Array[Node3D] = [null, null]


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	if show_controller_models:
		_models[0] = _build_controller_model(get_node_or_null(left_controller_path))
		_models[1] = _build_controller_model(get_node_or_null(right_controller_path))
	_set_models_visible(false)


## The hand's current modality (0 = left, 1 = right).
func get_modality(hand: int) -> Modality:
	return _modality[hand] if hand >= 0 and hand < 2 else Modality.NONE


func _process(delta: float) -> void:
	if not enabled:
		return
	for hand in 2:
		var detected := _detect(hand)
		if detected == _modality[hand]:
			_pending[hand] = detected
			_pending_time[hand] = 0.0
			continue
		if detected != _pending[hand]:
			_pending[hand] = detected
			_pending_time[hand] = 0.0
			continue
		_pending_time[hand] += delta
		if _pending_time[hand] < _DEBOUNCE_SECONDS:
			continue
		_modality[hand] = detected
		if _models[hand]:
			_models[hand].visible = detected == Modality.CONTROLLER
		modality_changed.emit(hand, detected)


func _detect(hand: int) -> Modality:
	var side := "left" if hand == 0 else "right"
	var hand_tracker := XRServer.get_tracker("/user/hand_tracker/%s" % side) as XRHandTracker
	var hand_live := hand_tracker != null and hand_tracker.has_tracking_data
	# Controller-driven "hands" (emulated joints from a held controller) count
	# as CONTROLLER modality, matching Unity's rule.
	if hand_live and hand_tracker.hand_tracking_source == XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER:
		hand_live = false

	var controller_live := false
	var controller_tracker := XRServer.get_tracker(&"left_hand" if hand == 0 else &"right_hand") as XRPositionalTracker
	if controller_tracker:
		var pose := controller_tracker.get_pose(&"aim")
		if pose == null:
			pose = controller_tracker.get_pose(&"default")
		controller_live = pose != null and pose.has_tracking_data

	match forced_modality:
		ForcedModality.CONTROLLER:
			return Modality.CONTROLLER if controller_live else Modality.NONE
		ForcedModality.HAND:
			return Modality.HAND if hand_live else Modality.NONE
		_:
			# Real tracked hands win: on both WebXR and OpenXR the controller
			# tracker is ALSO populated while bare hands are tracked (that is
			# how the rig's aim poses work hands-only), so hand-presence is
			# the discriminator, not controller-tracker liveness.
			if hand_live:
				return Modality.HAND
			if controller_live:
				return Modality.CONTROLLER
			return Modality.NONE


func _build_controller_model(controller: Node3D) -> Node3D:
	if controller == null:
		return null
	var model := Node3D.new()
	model.name = "ControllerModel"
	# The controller node sits at the AIM pose (pointer tip, -Z forward); the
	# grip body sits behind and below it, pitched like a held controller.
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.021
	capsule.height = 0.115
	body.mesh = capsule
	body.material_override = _MODEL_MATERIAL
	body.position = Vector3(0, -0.03, 0.06)
	body.rotation_degrees = Vector3(-60, 0, 0)
	model.add_child(body)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.028
	torus.outer_radius = 0.036
	torus.rings = 24
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = _MODEL_MATERIAL
	ring.position = Vector3(0, -0.012, 0.035)
	ring.rotation_degrees = Vector3(25, 0, 0)
	model.add_child(ring)
	controller.add_child(model)
	return model


func _set_models_visible(visible_now: bool) -> void:
	for model in _models:
		if model:
			model.visible = visible_now


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if show_controller_models and (left_controller_path.is_empty() or right_controller_path.is_empty()):
		warnings.append("Point Left/Right Controller Path at the rig's XRController3D nodes for controller models.")
	return warnings
