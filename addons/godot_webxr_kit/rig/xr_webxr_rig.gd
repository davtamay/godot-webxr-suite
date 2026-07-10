extends Node3D

## Root of the drop-in WebXR interaction rig. Keeps integration resilient: when an
## immersive session starts, it resets the XR origin to a clean floor pose so the
## user faces forward (-Z) at floor height, regardless of any desktop-preview
## camera transform left on the origin. Without this, projects hit the classic
## "I spawn facing backward / under the floor" bug on entering VR/AR.

## Reset the origin to start_position/start_yaw when a session begins.
@export var reset_origin_on_session_start := true
## Where the user stands when the session starts, in rig-local space. Place your
## content in front of -Z from here.
@export var start_position := Vector3.ZERO
@export_range(-180.0, 180.0, 1.0) var start_yaw_degrees := 0.0

@onready var _origin: XROrigin3D = $XROrigin3D

var _was_xr := false

func _process(_delta: float) -> void:
	var now := get_viewport().use_xr
	if now and not _was_xr and reset_origin_on_session_start and _origin:
		_origin.transform = Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(start_yaw_degrees), 0.0)),
			start_position)
	_was_xr = now
