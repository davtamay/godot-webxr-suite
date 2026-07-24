@tool
@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_font_bake_anchor.svg")
class_name XRFontBakeAnchor
extends Label3D

## Cross-export marker that makes Label3D's internally-created material visible
## to ahead-of-time shader bakers. It is safe in every target: the marker is
## invisible, does not process, and exists only so shared scenes can export
## without depending on a renderer-specific deployment addon.

const _BAKE_MATERIAL := preload(
	"res://addons/godot_xr_interaction_toolkit/runtime/xr_font_bake_material.tres"
)


func _init() -> void:
	visible = false
	material_override = _BAKE_MATERIAL
	pixel_size = 0.001
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789 +-:/()."
	font_size = 48
	outline_size = 8
