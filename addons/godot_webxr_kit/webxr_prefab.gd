extends Node3D

## WebXRPrefab - the one-drop-in XR setup. Instance this scene under any scene's
## root and you get WebXR (browser) AND OpenXR (Quest Link / SteamVR / Android XR):
## controllers, hands, grab, and an auto-built VR/AR entry UI, with zero wiring.
##
## Drops into EXISTING scenes without fighting your camera - if the scene already
## has a Camera3D it stays the flat view, and the XR camera takes over only
## in-session. To make an object grabbable, add an XRGrabInteractable (with a
## CollisionObject3D child) anywhere in your scene.

const HAND_VISUALIZER := "res://addons/godot_xr_hands/runtime/hand_visualizer.gd"

var _xr_cam: XRCamera3D
var _flat_cam: Camera3D
var _was_xr := false


func _ready() -> void:
	var origin := get_node_or_null("WebXRRig/XROrigin3D") as XROrigin3D

	# Procedural tracked hands on both WebXR and OpenXR (soft dependency on
	# godot_xr_hands; skipped cleanly if that addon isn't installed).
	if origin and ResourceLoader.exists(HAND_VISUALIZER):
		var hands: Node3D = load(HAND_VISUALIZER).new()
		hands.prefer_browser_hand_bridge = false
		origin.add_child(hands)

	# Existing-scene camera: keep the scene's own camera for the flat view; the XR
	# camera drives only in-session (toggled in _process). A bare scene with no
	# camera keeps the rig's camera as its flat view.
	_xr_cam = get_node_or_null("WebXRRig/XROrigin3D/XRCamera3D") as XRCamera3D
	_flat_cam = _find_scene_camera(_xr_cam)
	if _flat_cam and _xr_cam:
		_xr_cam.current = false
		var flat_ctrl := get_node_or_null("WebXRRig/FlatscreenCamera")
		if flat_ctrl:
			flat_ctrl.set("enabled", false)  # let the scene's own camera drive flat


func _process(_delta: float) -> void:
	# Only relevant when we deferred to a scene camera: hand the view to the XR
	# camera when a session starts, and back to the scene camera on exit.
	if _flat_cam == null or _xr_cam == null:
		return
	var xr := get_viewport().use_xr
	if xr and not _was_xr:
		_xr_cam.current = true
	elif not xr and _was_xr:
		_flat_cam.current = true
	_was_xr = xr


func _find_scene_camera(exclude: Camera3D) -> Camera3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for cam in scene.find_children("*", "Camera3D", true, false):
		if cam != exclude:
			return cam as Camera3D
	return null
