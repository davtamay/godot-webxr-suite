@tool
@icon("res://addons/godot_webgpu/icons/font_bake_anchor.svg")
class_name FontBakeAnchor
extends Label3D

## One-node text bake for WebGPU exports: add this anywhere in an exported
## scene and Label3D text renders on the WebGPU driver.
##
## Label3D builds its material INTERNALLY at runtime, invisible to the shader
## baker - so the first 3D text in a scene appears as white boxes on WebGPU.
## This node is a hidden Label3D carrying the flag-twin baked material and the
## full glyph set, forcing the exporter to bake the text shader. Zero runtime
## cost (invisible; nothing processes). Sibling of BakeAnchor, which does the
## same for runtime-built MATERIALS.

const _BAKE_MATERIAL := preload("res://addons/godot_webgpu/font_bake_material.tres")


func _init() -> void:
	visible = false
	material_override = _BAKE_MATERIAL
	pixel_size = 0.001
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 +-:/()."
	font_size = 48
	outline_size = 8
