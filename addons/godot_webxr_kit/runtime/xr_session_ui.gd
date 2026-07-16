@icon("res://addons/godot_webxr_kit/icons/xr_session_ui.svg")
class_name XRSessionUI
extends CanvasLayer

## The drop-in session HUD block: Enter VR / Enter AR buttons, a status line,
## and a browser-capabilities readout. Instance xr_session_ui.tscn anywhere in
## a scene that has a WebXRBootstrap and the bootstrap adopts it automatically
## (no NodePath wiring). Hides itself during immersive sessions.
##
## Scene-specific controls (extra buttons, labels) can be added as children of
## Panel/Margin/VBox in the host scene - the block is a start, not a cage.

@export var title_text := "WebXR"
@export var description_text := ""

@onready var _title: Label = $Panel/Margin/VBox/Title
@onready var _description: Label = $Panel/Margin/VBox/Description


func _enter_tree() -> void:
	# Groups join in _enter_tree so the bootstrap's _ready (which may run
	# first) already finds this HUD when it looks for one to adopt.
	add_to_group(WebXRBootstrap.GROUP_SESSION_HIDDEN)
	add_to_group(WebXRBootstrap.GROUP_SESSION_UI)


func _ready() -> void:
	_title.text = title_text
	_description.text = description_text
	_description.visible = not description_text.is_empty()


## Adoption points for WebXRBootstrap.
func get_vr_button() -> Button:
	return $Panel/Margin/VBox/SessionButtons/EnterVRButton


func get_ar_button() -> Button:
	return $Panel/Margin/VBox/SessionButtons/EnterARButton


func get_status_label() -> Label:
	return $Panel/Margin/VBox/BootstrapStatus
