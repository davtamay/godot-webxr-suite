@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_locomotion.svg")
class_name XRClimbInteractable
extends "res://addons/godot_xr_interaction_toolkit/runtime/xr_base_interactable.gd"

## A handhold you climb by (Unity XRI's Climb Interactable). Grab it and move
## your hand - the XRClimbProvider moves the rig the opposite way. Unlike a
## grabbable, the handhold itself does NOT move.
##
## Put this on a node with a collider (a rung, rock, ledge) - the base class
## auto-collects child colliders, so a StaticBody3D + CollisionShape3D under it
## is all you need. It registers with the interaction manager like any
## interactable, so the scene-wide feedback highlights it on hover for free.

var _provider: Node


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	select_entered.connect(_on_grabbed)
	select_exited.connect(_on_released)


func _on_grabbed(interactor) -> void:
	var provider := _find_provider()
	if provider:
		provider.begin_climb(interactor)


func _on_released(interactor) -> void:
	var provider := _find_provider()
	if provider:
		provider.end_climb(interactor)


func _find_provider() -> Node:
	if _provider == null or not is_instance_valid(_provider):
		_provider = get_tree().get_first_node_in_group("xr_climb_provider")
	return _provider
