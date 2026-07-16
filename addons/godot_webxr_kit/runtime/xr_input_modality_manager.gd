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
## Controller models are PROFILE-MATCHED: the WebXR Input Profiles registry
## models bundled in controller_models/ (MIT) are picked by the profile ids
## the runtime reports (browser input-source profiles on WebXR, interaction
## profile paths on OpenXR), attached at the GRIP pose like the web's own
## controller-model factory. Unknown controllers fall back to the generic
## registry model, then to built-in stylized primitives. Bundled = imported =
## the materials bake for WebGPU exports like any scene asset.
##
## Built into WebXRRig, so every rig/prefab scene has it BY DEFAULT - turn it
## off with [member enabled], or pin a modality with [member forced_modality].

## A hand's modality changed. hand: 0 = left, 1 = right.
signal modality_changed(hand: int, modality: Modality)

enum Modality { NONE, CONTROLLER, HAND }
enum ForcedModality { AUTO, CONTROLLER, HAND }

const _MODEL_MATERIAL := preload("res://addons/godot_webxr_kit/runtime/controller_model_material.tres")
const _MODELS_DIR := "res://addons/godot_webxr_kit/controller_models"
const _GENERIC_PROFILE := "generic-trigger-squeeze-thumbstick"
## OpenXR interaction-profile paths -> registry profile ids (extend as needed).
const _OPENXR_PROFILE_MAP := {
	"/interaction_profiles/oculus/touch_controller": "oculus-touch-v3",
	"/interaction_profiles/meta/touch_controller_plus": "oculus-touch-v3",
	"/interaction_profiles/meta/touch_pro_controller": "oculus-touch-v3",
	"/interaction_profiles/khr/simple_controller": _GENERIC_PROFILE,
}
## A reading must hold this long before the modality switches (transitions
## flicker while the platform hands over between sources).
const _DEBOUNCE_SECONDS := 0.25

## Master switch. Off = no detection, no signals, controller models hidden
## (hand visuals then behave exactly as before this block existed).
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_set_controller_visuals(0, false)
			_set_controller_visuals(1, false)

## AUTO follows the live trackers per hand. CONTROLLER / HAND pins BOTH hands
## to one modality (visuals only show when that source actually tracks).
@export var forced_modality: ForcedModality = ForcedModality.AUTO

## Show controller models while a hand is in CONTROLLER modality.
@export var show_controller_models := true

## Match the model to the reported controller profile (registry models in
## controller_models/). Off = always the built-in stylized primitives.
@export var use_profile_models := true

## The rig's XRController3D nodes (aim pose), used for the primitive fallback
## models and to locate the XROrigin3D for grip attachment.
@export var left_controller_path: NodePath
@export var right_controller_path: NodePath

var _modality := [Modality.NONE, Modality.NONE]
var _pending := [Modality.NONE, Modality.NONE]
var _pending_time := [0.0, 0.0]
var _fallback_models: Array[Node3D] = [null, null]
var _profile_models: Array[Node3D] = [null, null]
var _grip_nodes: Array[XRController3D] = [null, null]
var _resolved_profile := ["", ""]


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	var controllers := [get_node_or_null(left_controller_path), get_node_or_null(right_controller_path)]
	if show_controller_models:
		for hand in 2:
			_fallback_models[hand] = _build_fallback_model(controllers[hand])
			_grip_nodes[hand] = _build_grip_node(controllers[hand], hand)
	_install_webxr_profiles_hook()


## The hand's current modality (0 = left, 1 = right).
func get_modality(hand: int) -> Modality:
	return _modality[hand] if hand >= 0 and hand < 2 else Modality.NONE


## The registry profile id whose model this hand is showing ("" = fallback).
func get_resolved_profile(hand: int) -> String:
	return _resolved_profile[hand] if hand >= 0 and hand < 2 else ""


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
		if detected == Modality.CONTROLLER and _profile_models[hand] == null:
			_try_resolve_profile_model(hand)
		_set_controller_visuals(hand, detected == Modality.CONTROLLER)
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


## ---- profile-matched models -------------------------------------------------

func _try_resolve_profile_model(hand: int) -> void:
	if not use_profile_models or _grip_nodes[hand] == null:
		return
	for profile in _candidate_profiles(hand):
		var path := "%s/%s/%s.glb" % [_MODELS_DIR, profile, "left" if hand == 0 else "right"]
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			continue
		var model := scene.instantiate() as Node3D
		model.name = "ProfileControllerModel"
		_grip_nodes[hand].add_child(model)
		_profile_models[hand] = model
		_resolved_profile[hand] = profile
		return


func _candidate_profiles(hand: int) -> PackedStringArray:
	var candidates := PackedStringArray()
	# WebXR: the browser reports an ordered list per input source (specific ->
	# generic), captured by the JS hook below.
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js := Engine.get_singleton("JavaScriptBridge")
		var side := "left" if hand == 0 else "right"
		var raw := str(js.eval("JSON.stringify((window.GodotXRProfiles && window.GodotXRProfiles.%s) || [])" % side, true))
		var parsed = JSON.parse_string(raw)
		if parsed is Array:
			for entry in parsed:
				candidates.append(str(entry))
	# OpenXR: the tracker carries the bound interaction profile path.
	var tracker := XRServer.get_tracker(&"left_hand" if hand == 0 else &"right_hand") as XRPositionalTracker
	if tracker and not tracker.profile.is_empty():
		var mapped: String = _OPENXR_PROFILE_MAP.get(tracker.profile, "")
		if not mapped.is_empty():
			candidates.append(mapped)
	candidates.append(_GENERIC_PROFILE)
	return candidates


func _install_webxr_profiles_hook() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	Engine.get_singleton("JavaScriptBridge").eval("""
(function () {
	if (window.GodotXRProfiles) { return; }
	window.GodotXRProfiles = { left: [], right: [] };
	if (typeof XRSession === 'undefined') { return; }
	const originalRAF = XRSession.prototype.requestAnimationFrame;
	XRSession.prototype.requestAnimationFrame = function (callback) {
		return originalRAF.call(this, function (time, frame) {
			try {
				for (const source of frame.session.inputSources) {
					if (source.handedness === 'left' || source.handedness === 'right') {
						const store = window.GodotXRProfiles[source.handedness];
						if (source.profiles && source.profiles.length && store[0] !== source.profiles[0]) {
							window.GodotXRProfiles[source.handedness] = Array.from(source.profiles);
						}
					}
				}
			} catch (e) { /* never break the frame loop */ }
			callback(time, frame);
		});
	};
}())
""", true)


func _build_grip_node(controller: Node3D, hand: int) -> XRController3D:
	if controller == null or controller.get_parent() == null:
		return null
	# Registry models are authored for the GRIP space (the web's controller-
	# model factory attaches them there); the rig's controllers sit at the AIM
	# pose, so the model rides its own grip-pose node.
	var grip := XRController3D.new()
	grip.name = "GripModelAnchor%s" % ("Left" if hand == 0 else "Right")
	grip.tracker = &"left_hand" if hand == 0 else &"right_hand"
	grip.pose = &"grip"
	controller.get_parent().add_child(grip)
	return grip


## ---- fallback primitives ----------------------------------------------------

func _build_fallback_model(controller: Node3D) -> Node3D:
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
	model.visible = false
	return model


func _set_controller_visuals(hand: int, on: bool) -> void:
	# Profile model preferred; primitives only when no profile model resolved.
	if _profile_models[hand]:
		_profile_models[hand].visible = on
		if _fallback_models[hand]:
			_fallback_models[hand].visible = false
	elif _fallback_models[hand]:
		_fallback_models[hand].visible = on


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if show_controller_models and (left_controller_path.is_empty() or right_controller_path.is_empty()):
		warnings.append("Point Left/Right Controller Path at the rig's XRController3D nodes for controller models.")
	return warnings
