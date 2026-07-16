@icon("res://addons/godot_webxr_kit/icons/openxr_bootstrap.svg")
class_name OpenXRBootstrap
extends Node

## Drop-in sibling of WebXRBootstrap for EDITOR-TIME / NATIVE testing on a real
## headset via Meta Quest Link, SteamVR, or Android XR's OpenXR runtime.
##
## Press Play and the SAME scene renders to the headset - no export, no browser.
## It just starts the OpenXR session and turns on XR rendering; the standard XR
## nodes (XROrigin3D / XRController3D / XRHandModifier3D) do the rest, so hands,
## controllers, and the interaction toolkit all work exactly as they do on WebXR.
##
## Inert on web exports (the WebXR bootstrap owns the browser path), so you can
## leave both bootstraps in every scene and each activates on its own platform.
##
## One-time project setup: Project Settings > XR > OpenXR > Enabled = on, then
## restart the editor. Have a runtime running (Quest Link / SteamVR) before Play.

## Hide nodes in this group while the session is active (mirrors the WebXR
## bootstrap so 2D HUDs don't composite into both eyes).
@export var session_hide_group := "xr_session_hidden"

var _xr: XRInterface


func _ready() -> void:
	if OS.has_feature("web"):
		return  # WebXR bootstrap handles the browser path.

	_xr = XRServer.find_interface("OpenXR")
	if _xr == null:
		push_warning("OpenXRBootstrap: no OpenXR interface. Enable Project Settings > XR > OpenXR and restart the editor.")
		return
	if not _xr.is_initialized():
		push_warning("OpenXRBootstrap: OpenXR is not initialized. Start a runtime (Quest Link / SteamVR) before pressing Play.")
		_xr = null
		return

	_set_group_hidden(true)
	get_viewport().use_xr = true


func _exit_tree() -> void:
	if _xr != null and get_viewport() != null:
		get_viewport().use_xr = false
		_set_group_hidden(false)


func _set_group_hidden(hidden: bool) -> void:
	if session_hide_group.is_empty():
		return
	for node in get_tree().get_nodes_in_group(session_hide_group):
		if node is CanvasItem:
			node.visible = not hidden
