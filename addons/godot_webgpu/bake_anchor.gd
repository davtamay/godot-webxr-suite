@tool
@icon("res://addons/godot_webgpu/icons/bake_anchor.svg")
class_name BakeAnchor
extends Node3D

## Declare materials you build or duplicate at RUNTIME so the WebGPU shader
## baker includes their shaders at export time.
##
## WebGPU has no in-browser shader translation: shaders are baked SPIR-V -> WGSL
## ahead of time (the same model as Unity's shader variant collections). A
## material whose SHADER is first seen at runtime therefore has no baked shader
## and fails on WebGPU ("missing from the baked shader cache"). Add each such
## material - saved as a .tres with its codegen flags frozen - to `materials`.
## This node references them on hidden meshes so the exporter bakes them;
## the references are invisible and freed at runtime, so there is no cost in game.
##
## When you DON'T need this: uniform-only changes at runtime (albedo colour,
## roughness, a texture swap, energy) reuse an already-baked shader - only a NEW
## shader needs an anchor. A "new shader" means either a StandardMaterial3D whose
## FEATURE FLAGS differ from anything an exported scene already renders
## (emission_enabled, transparency, a different cull/blend mode...) or a
## ShaderMaterial with code no exported scene already uses.
##
## Usage: drop a BakeAnchor into any scene that is reachable from your exported
## main scene, and fill `materials` with the .tres materials your scripts will
## construct/duplicate. That's it.

const _META := "_bake_anchor_child"

@export var materials: Array[Material] = []:
    set(value):
        materials = value
        if Engine.is_editor_hint():
            _sync_anchor_children()

func _ready() -> void:
    if not Engine.is_editor_hint():
        # In game the anchors have already done their job at export time.
        visible = false
        for child in get_children():
            if child.has_meta(_META):
                child.queue_free()
        return
    # In the editor: only (re)build when out of sync, so merely opening the
    # scene never marks it modified.
    if not _anchor_children_match():
        _sync_anchor_children()

func _anchor_children_match() -> bool:
    var anchors: Array[Node] = []
    for child in get_children():
        if child.has_meta(_META):
            anchors.append(child)
    var mats := materials.filter(func(m): return m != null)
    if anchors.size() != mats.size():
        return false
    for i in mats.size():
        if (anchors[i] as MeshInstance3D).material_override != mats[i]:
            return false
    return true

func _sync_anchor_children() -> void:
    if not is_inside_tree() or get_tree() == null:
        return
    var scene_root: Node = get_tree().edited_scene_root
    if scene_root == null:
        return
    for child in get_children():
        if child.has_meta(_META):
            child.free()
    # One tiny hidden mesh per material carries it as material_override, which is
    # what makes the exporter's shader baker include that material's shader.
    var marker_mesh := BoxMesh.new()
    marker_mesh.size = Vector3(0.001, 0.001, 0.001)
    for mat in materials:
        if mat == null:
            continue
        var mi := MeshInstance3D.new()
        mi.set_meta(_META, true)
        mi.mesh = marker_mesh
        mi.material_override = mat
        mi.visible = false
        add_child(mi)
        mi.owner = scene_root
