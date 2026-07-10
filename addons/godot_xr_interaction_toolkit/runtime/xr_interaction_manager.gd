class_name XRInteractionManager
extends Node

## Collider registry + select arbitration. One per scene, found via group.
## Rules: an interactor selects at most one interactable; each interactable
## decides whether it accepts one or multiple selecting interactors.

const GROUP_NAME := &"xr_interaction_manager"

static var _last_manager: Node

var _collider_map := {} # collider instance_id (int) -> interactable
var _selections := {} # interactor -> interactable
var _activations := {} # interactor -> interactable

static func find(from: Node):
    var fallback := _get_valid_last_manager()
    if from == null or not from.is_inside_tree():
        return fallback
    var manager := from.get_tree().get_first_node_in_group(GROUP_NAME)
    return manager if manager else fallback

static func _get_valid_last_manager() -> Node:
    if _last_manager != null and not is_instance_valid(_last_manager):
        _last_manager = null
    return _last_manager

func _init() -> void:
    _last_manager = self

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and _last_manager == self:
        _last_manager = null

func _enter_tree() -> void:
    add_to_group(GROUP_NAME)
    _last_manager = self

func _exit_tree() -> void:
    if _last_manager == self:
        _last_manager = null

func register_interactable(interactable) -> void:
    if interactable == null:
        return
    for collider in interactable.get_colliders():
        _collider_map[collider.get_instance_id()] = interactable

func unregister_interactable(interactable) -> void:
    if interactable == null:
        return
    for id in _collider_map.keys():
        if _collider_map[id] == interactable:
            _collider_map.erase(id)

    var selecting_interactors := []
    for interactor in _selections.keys():
        if _selections[interactor] == interactable:
            selecting_interactors.append(interactor)
    var activating_interactors := []
    for interactor in _activations.keys():
        if _activations[interactor] == interactable:
            activating_interactors.append(interactor)
    for interactor in activating_interactors:
        request_deactivate(interactor)
    for interactor in selecting_interactors:
        request_deselect(interactor)

## Re-syncs an interactable's collider registrations without touching its
## selections/activations (unlike unregister_interactable).
func refresh_interactable_colliders(interactable) -> void:
    if interactable == null:
        return
    for id in _collider_map.keys():
        if _collider_map[id] == interactable:
            _collider_map.erase(id)
    register_interactable(interactable)

func get_interactable_for_collider(collider: Object):
    if collider == null:
        return null
    var registered = _collider_map.get(collider.get_instance_id())
    if registered != null and is_instance_valid(registered):
        return registered

    var node := collider as Node
    while node:
        if node.is_inside_tree() and node.has_method("can_hover") and node.has_method("get_colliders"):
            register_interactable(node)
            return node
        node = node.get_parent()
    return null

func request_select(interactor, interactable) -> bool:
    if interactor == null or interactable == null:
        return false
    if _selections.has(interactor):
        return false
    if not interactable.can_select(interactor):
        if not _try_yield_selection(interactor, interactable):
            return false
        if not interactable.can_select(interactor):
            return false

    _selections[interactor] = interactable
    interactable._notify_select_entered(interactor)
    if _selections.get(interactor) != interactable:
        # A select_entered handler deselected synchronously; do not grant.
        return false
    interactor._notify_select_granted(interactable)
    return true

func request_deselect(interactor) -> bool:
    if not _selections.has(interactor):
        return false

    var interactable = _selections[interactor]
    if _activations.get(interactor) == interactable:
        request_deactivate(interactor)
    _selections.erase(interactor)
    interactable._notify_select_exited(interactor)
    interactor._notify_select_released(interactable)
    return true

func request_activate(interactor, interactable) -> bool:
    if interactor == null or interactable == null:
        return false
    if _activations.has(interactor):
        return false
    if not interactable.can_activate(interactor):
        return false

    _activations[interactor] = interactable
    interactable._notify_activate_entered(interactor)
    if _activations.get(interactor) != interactable:
        # An activate handler deactivated synchronously; do not grant.
        return false
    interactor._notify_activate_granted(interactable)
    return true

func request_deactivate(interactor) -> bool:
    if not _activations.has(interactor):
        return false

    var interactable = _activations[interactor]
    _activations.erase(interactor)
    interactable._notify_activate_exited(interactor)
    interactor._notify_activate_released(interactable)
    return true

func _try_yield_selection(requesting_interactor, interactable) -> bool:
    if not interactable.has_method("get_selecting_interactors"):
        return false

    var yielded := false
    for selecting_interactor in interactable.get_selecting_interactors():
        if selecting_interactor == requesting_interactor:
            continue
        if selecting_interactor == null or not is_instance_valid(selecting_interactor):
            continue
        if not selecting_interactor.has_method("should_yield_selection_to"):
            continue
        if selecting_interactor.should_yield_selection_to(requesting_interactor, interactable):
            yielded = request_deselect(selecting_interactor) or yielded
    return yielded
