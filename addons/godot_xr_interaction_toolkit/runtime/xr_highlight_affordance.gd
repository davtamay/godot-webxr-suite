@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_highlight_affordance.svg")
class_name XRHighlightAffordance
extends Node

## Drop-in hover/select/activate highlighting for any interactable.
##
## Parent this node ANYWHERE inside an interactable (like a CollisionShape3D
## inside a body) and it wires itself: it finds the interactable by walking up
## its ancestors, finds the mesh to tint automatically, and swaps highlight
## materials as interactors hover / grab / use the object. Zero NodePaths, and
## the highlight travels with the object into any scene.
##
## The highlight materials duplicate a pre-baked .tres with colour/emission as
## uniforms, so they render on WebGPU exports without extra bake steps.
## Priority when states overlap: activate > select > hover > base.

## Every raw interaction event, for UIs (status labels, sounds, haptics):
## event is one of hover_entered/hover_exited/select_entered/select_exited/
## activate_entered/activate_exited.
signal interaction_event(event: StringName, interactor: Node)

const _HIGHLIGHT_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/highlight_affordance_material.tres")

## Tint while an interactor points at / touches the object.
@export var hover_color := Color(1.0, 0.9, 0.25)
## Tint while grabbed.
@export var select_color := Color(0.28, 1.0, 0.55)
## Tint while activated (used/triggered while held).
@export var activate_color := Color(0.18, 0.92, 1.0)
## Highlight glow strength.
@export_range(0.0, 4.0, 0.05) var emission_energy := 0.65
## The mesh to tint. Leave empty to use the first MeshInstance3D found under
## the interactable.
@export var mesh_path: NodePath:
    set(value):
        mesh_path = value
        update_configuration_warnings()
## Optional display name for UIs consuming [signal interaction_event]; empty =
## the interactable's node name.
@export var display_name := ""

var _interactable: Node
var _mesh: MeshInstance3D
var _base_material: Material
var _hover_material: StandardMaterial3D
var _select_material: StandardMaterial3D
var _activate_material: StandardMaterial3D


func _ready() -> void:
    if Engine.is_editor_hint():
        return
    _interactable = _find_interactable()
    _mesh = _find_mesh()
    if _interactable == null or _mesh == null:
        push_warning("%s: needs an interactable ancestor and a MeshInstance3D to tint." % name)
        return

    _base_material = _mesh.get_surface_override_material(0)
    if _base_material == null:
        _base_material = _mesh.get_active_material(0)
    _hover_material = _make_material(hover_color)
    _select_material = _make_material(select_color)
    _activate_material = _make_material(activate_color)

    _interactable.hover_entered.connect(_on_event.bind(&"hover_entered"))
    _interactable.hover_exited.connect(_on_event.bind(&"hover_exited"))
    _interactable.select_entered.connect(_on_event.bind(&"select_entered"))
    _interactable.select_exited.connect(_on_event.bind(&"select_exited"))
    if _interactable.has_signal("activate_entered"):
        _interactable.activate_entered.connect(_on_event.bind(&"activate_entered"))
    if _interactable.has_signal("activate_exited"):
        _interactable.activate_exited.connect(_on_event.bind(&"activate_exited"))


## The name UIs should show for this object.
func get_display_name() -> String:
    if not display_name.is_empty():
        return display_name
    return str(_interactable.name) if _interactable else name


func _find_interactable() -> Node:
    var node := get_parent()
    while node:
        if node.has_signal("hover_entered") and node.has_signal("select_entered"):
            return node
        node = node.get_parent()
    return null


func _find_mesh() -> MeshInstance3D:
    if not mesh_path.is_empty():
        return get_node_or_null(mesh_path) as MeshInstance3D
    if _interactable == null:
        return null
    if _interactable is MeshInstance3D:
        return _interactable
    for found in _interactable.find_children("*", "MeshInstance3D", true, false):
        return found
    return null


func _make_material(color: Color) -> StandardMaterial3D:
    # Duplicate of a baked .tres; colour/emission are uniforms, so the baked
    # shader hash is kept (WebGPU-export safe).
    var material := _HIGHLIGHT_MATERIAL.duplicate() as StandardMaterial3D
    material.albedo_color = color
    material.emission = color
    material.emission_energy_multiplier = emission_energy
    return material


func _on_event(interactor: Node, event: StringName) -> void:
    _apply_state_material()
    interaction_event.emit(event, interactor)


func _apply_state_material() -> void:
    if _interactable.has_method("is_activated") and _interactable.is_activated():
        _mesh.set_surface_override_material(0, _activate_material)
    elif _interactable.has_method("is_selected") and _interactable.is_selected():
        _mesh.set_surface_override_material(0, _select_material)
    elif _interactable.has_method("is_hovered") and _interactable.is_hovered():
        _mesh.set_surface_override_material(0, _hover_material)
    else:
        _mesh.set_surface_override_material(0, _base_material)


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()
    var interactable := _find_interactable()
    if interactable == null:
        warnings.append("No interactable ancestor - parent this node inside an XRGrabInteractable (or any interactable).")
    elif _find_mesh_for_warning(interactable) == null:
        warnings.append("No MeshInstance3D found to tint - add one under the interactable or set Mesh Path.")
    return warnings


func _find_mesh_for_warning(interactable: Node) -> MeshInstance3D:
    if not mesh_path.is_empty():
        return get_node_or_null(mesh_path) as MeshInstance3D
    if interactable is MeshInstance3D:
        return interactable
    for found in interactable.find_children("*", "MeshInstance3D", true, false):
        return found
    return null
