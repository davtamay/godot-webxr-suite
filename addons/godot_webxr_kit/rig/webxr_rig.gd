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

func _ready() -> void:
	# The rig ships both input adapters (WebXR + OpenXR); each is inert off its own
	# platform. On web the interactors already point at WebXRInputAdapter; on native
	# (OpenXR - Quest Link / SteamVR / Android XR) route them to the OpenXR source so
	# the exact same scene gets controllers + hands in the editor. Runs after the
	# interactors' own _ready (children resolve first), so this re-point wins.
	if OS.has_feature("web"):
		return
	var openxr := get_node_or_null("OpenXRInputAdapter")
	if openxr == null:
		return
	for interactor in _adapter_interactors(self):
		interactor.set_input_adapter(openxr)


func _adapter_interactors(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child.has_method("set_input_adapter"):
			var path: Variant = child.get("input_adapter_path")
			if path is NodePath and not (path as NodePath).is_empty():
				out.append(child)
		out.append_array(_adapter_interactors(child))
	return out


func _process(_delta: float) -> void:
	var now := get_viewport().use_xr
	if now and not _was_xr and reset_origin_on_session_start and _origin:
		_origin.transform = Transform3D(
			Basis.from_euler(Vector3(0.0, deg_to_rad(start_yaw_degrees), 0.0)),
			start_position)
	_was_xr = now
