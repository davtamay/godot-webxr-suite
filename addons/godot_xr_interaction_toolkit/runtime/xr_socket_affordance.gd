@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_socket_affordance.svg")
class_name XRSocketAffordance
extends Node

## Drop-in visual state for an XRSocketInteractor: tints a pad mesh by socket
## state (ready / hovering / occupied / disabled).
##
## Parent this node inside the socket (like a CollisionShape3D inside a body)
## and it wires itself: the socket is found by walking up the ancestors, the
## pad mesh is found automatically under it. Zero NodePaths; the affordance
## travels with the socket prefab.

## State changes, for UIs: state is ready/hovering/occupied/disabled; selected
## and candidate are the involved interactables (may be null).
signal socket_state_changed(state: StringName, selected: Node, candidate: Node)

const _SOCKET_MATERIAL := preload("res://addons/godot_xr_interaction_toolkit/runtime/socket_affordance_material.tres")

## The pad mesh to tint. Leave empty to use the first MeshInstance3D found
## under the socket.
@export var pad_mesh_path: NodePath:
    set(value):
        pad_mesh_path = value
        update_configuration_warnings()

var _socket: Node
var _pad_mesh: MeshInstance3D
var _materials := {}
var _last_key := ""


func _ready() -> void:
    if Engine.is_editor_hint():
        set_process(false)
        return
    _socket = _find_socket()
    _pad_mesh = _find_pad_mesh()
    if _socket == null or _pad_mesh == null:
        push_warning("%s: needs an XRSocketInteractor ancestor and a pad MeshInstance3D." % name)
        set_process(false)
        return
    _materials[&"ready"] = _make_material(Color(0.14, 0.82, 0.95, 0.55))
    _materials[&"hovering"] = _make_material(Color(1.0, 0.9, 0.25, 0.78))
    _materials[&"occupied"] = _make_material(Color(0.28, 1.0, 0.55, 0.82))
    _materials[&"disabled"] = _make_material(Color(0.22, 0.24, 0.26, 0.36))


func _process(_delta: float) -> void:
    var state: Dictionary = _socket.get_socket_state()
    var state_name: StringName = state.get("state", &"ready")
    var selected = state.get("selected")
    var candidate = state.get("candidate")
    var key := "%s:%s:%s" % [state_name, _node_name(selected), _node_name(candidate)]
    if key == _last_key:
        return
    _last_key = key
    _pad_mesh.set_surface_override_material(0, _materials.get(state_name, _materials[&"ready"]))
    socket_state_changed.emit(state_name, selected if selected is Node else null, candidate if candidate is Node else null)


func _find_socket() -> Node:
    var node := get_parent()
    while node:
        if node.has_method("get_socket_state"):
            return node
        node = node.get_parent()
    return null


func _find_pad_mesh() -> MeshInstance3D:
    if not pad_mesh_path.is_empty():
        return get_node_or_null(pad_mesh_path) as MeshInstance3D
    if _socket == null:
        return null
    for found in _socket.find_children("*", "MeshInstance3D", true, false):
        return found
    return null


func _make_material(color: Color) -> StandardMaterial3D:
    # Duplicate of a baked .tres; colour/emission/roughness are uniforms, so
    # the baked shader hash is kept (WebGPU-export safe).
    var material := _SOCKET_MATERIAL.duplicate() as StandardMaterial3D
    material.albedo_color = color
    material.emission = color
    material.emission_energy_multiplier = 0.55
    material.roughness = 0.42
    return material


func _node_name(node) -> String:
    if node is Node:
        return str((node as Node).name)
    return ""


func _get_configuration_warnings() -> PackedStringArray:
    var warnings := PackedStringArray()
    if _find_socket() == null:
        warnings.append("No XRSocketInteractor ancestor - parent this node inside a socket.")
    return warnings
