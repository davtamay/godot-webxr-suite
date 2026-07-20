@icon("res://addons/godot_webxr_kit/icons/openxr_input_adapter.svg")
class_name OpenXRInputAdapter
extends "res://addons/godot_xr_interaction_toolkit/runtime/input/xr_controller_hand_adapter.gd"

## Native (OpenXR) select source - the platform twin of WebXRInputAdapter for
## editor-time / native testing via Meta Quest Link, SteamVR, or Android XR.
##
## Wires the controllers' action-map button signals (grip -> select/grab, trigger
## -> activate/use) into the shared controller + hand adapter base - the VR
## standard: hold with the grip, act with the trigger, so grabbing and using
## (e.g. a blaster's fire) are distinct buttons. Poses, hand ray, and
## bare-hand pinch all live in the base (XRControllerHandAdapter), so the exact
## same interaction runs natively as on WebXR - this file only adds where
## select/activate come from. Inert on web exports (the WebXR adapter owns that).
##
## Requires an OpenXR action map exposing an "aim" pose action plus the boolean
## actions named below; godot_webxr_kit ships one at openxr/default_action_map.tres.

@export_group("Actions")
## Boolean action name (from the OpenXR action map) that fires select (grab).
## "grab" is bound to the GRIP/squeeze, so you hold objects with the grip.
@export var select_action := "grab"
## Boolean action name that fires activate (use / trigger-while-held). "select"
## is bound to the TRIGGER, so trigger = fire/use - distinct from grab.
@export var activate_action := "select"


func _ready() -> void:
	_resolve_rig()
	if OS.has_feature("web"):
		# WebXR adapter owns the browser path. Also stop the base's _process,
		# or BOTH adapters run the synthetic pinch detector in parallel
		# (duplicate events/compute - tap showed every pinch printed twice).
		set_process(false)
		return

	_connect_controller(Hand.LEFT)
	_connect_controller(Hand.RIGHT)


func _connect_controller(hand_id: int) -> void:
	var controller := _controllers.get(hand_id) as XRController3D
	if controller == null:
		return
	controller.button_pressed.connect(_on_button_pressed.bind(hand_id))
	controller.button_released.connect(_on_button_released.bind(hand_id))


func _on_button_pressed(action_name: String, hand_id: int) -> void:
	if action_name == select_action:
		_emit_select_started(hand_id, HARDWARE_SELECT)
	elif action_name == activate_action:
		_emit_activate_started(hand_id, HARDWARE_SELECT)


func _on_button_released(action_name: String, hand_id: int) -> void:
	if action_name == select_action:
		_emit_select_ended(hand_id, HARDWARE_SELECT)
	elif action_name == activate_action:
		_emit_activate_ended(hand_id, HARDWARE_SELECT)
