extends Node3D

## WebXRPrefab - the one-drop-in XR setup. Instance this scene under any scene's
## root and you get WebXR (browser) AND OpenXR (Quest Link / SteamVR / Android XR):
## controllers, hands, grab, and an auto-built VR/AR entry UI, with zero wiring.
##
## Drops into EXISTING scenes without fighting your camera - if the scene already
## has a Camera3D it stays the flat view, and the XR camera takes over only
## in-session. To make an object grabbable, add an XRGrabInteractable (with a
## CollisionObject3D child) anywhere in your scene.

## Show the virtual hand meshes during AR passthrough. Off by default: in AR you
## see your REAL hands, and the virtual meshes would cover them (e.g. hiding that
## your own hand is doing the occluding). Hands stay visible in VR either way,
## and hand INPUT (pinch, grab, rays) works in AR regardless.
@export var virtual_hands_in_ar := false

## Virtual hand look: PROCEDURAL joints/bones, or the REALISTIC rigged hand
## mesh (godot_xr_hands' bundled WebXR Input Profiles asset). Forwarded to the
## hands mount. The XR Simulator's simulated hands render with the same choice.
##
## NOTE: the hands mount is BUILT AT RUNTIME (it is not a node in this scene),
## so configure hands HERE on the prefab root - these exports are forwarded to
## it. To wire a mount by hand instead, use the WebXR Rig block and add an
## XRHandsMount node yourself.
@export var hand_style := XRHandsMount.HandStyle.PROCEDURAL

## Custom hand meshes for REALISTIC style: drop in your own rigged glb whose
## bones use the standard WebXR joint names. Empty = the bundled generic hand.
@export var left_hand_model: PackedScene
@export var right_hand_model: PackedScene

var _xr_cam: XRCamera3D
var _flat_cam: Camera3D
var _was_xr := false


func _ready() -> void:
	var origin := get_node_or_null("WebXRRig/XROrigin3D") as XROrigin3D

	# Procedural tracked hands on both WebXR and OpenXR, with the real-hands-in-
	# AR rule built in - one shared module (XRHandsMount), not a per-scene copy.
	if origin:
		var hand_mount := XRHandsMount.new()
		hand_mount.name = "HandVisualizerMount"
		hand_mount.virtual_hands_in_ar = virtual_hands_in_ar
		hand_mount.hand_style = hand_style
		hand_mount.left_hand_model = left_hand_model
		hand_mount.right_hand_model = right_hand_model
		var bootstrap := get_node_or_null("WebXRBootstrap")
		if bootstrap and "ar_hide_group" in bootstrap:
			hand_mount.ar_hide_group = str(bootstrap.ar_hide_group)
		origin.add_child(hand_mount)

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
