extends Node3D

## WebXRPrefab - the one-drop-in XR setup. Instance this scene under any scene's
## root and you get WebXR (browser) AND OpenXR (Quest Link / SteamVR / Android XR):
## controllers, hands, grab, and an auto-built VR/AR entry UI, with zero wiring.
##
## Drops into EXISTING scenes without fighting your camera - if the scene already
## has a Camera3D it stays the flat view, and the XR camera takes over only
## in-session. To make an object grabbable, add an XRGrabInteractable (with a
## CollisionObject3D child) anywhere in your scene.

## Hands and controllers are configured on VISIBLE NODES inside the rig, so
## the fields live where you'd look for them: expand WebXRRig/XROrigin3D and
## select the "Hands" node (show mode, procedural/realistic, custom models),
## or the "XRInputModalityManager" node (controller models). This prefab just
## instances that rig and handles the camera hand-off.

var _xr_cam: XRCamera3D
var _flat_cam: Camera3D
var _was_xr := false


func _ready() -> void:
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
