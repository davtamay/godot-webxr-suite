@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRDial
extends XRConstrainedInteractable

## A dial / rotary knob: grab it and TWIST your wrist to sweep a value 0..1
## (Unity XRI's Dial). The knob follows your hand's rotation around its spin
## axis 1:1 - hold and turn, like a real knob - so it never fights you.
## Twist more than one grab allows? Release and re-grab, like a physical knob.
## Optional detents snap to steps; wire value_changed to volume, brightness...

## Spin axis in the knob's LOCAL space (default: its up axis).
@export var spin_axis := Vector3(0.0, 1.0, 0.0)
## Flip which twist direction raises the value (the knob still follows your
## wrist either way; this only swaps increase/decrease). Turn this on if
## "clockwise = more" feels backwards for how the knob is mounted.
@export var invert := false
## Total sweep from value 0 to value 1, in degrees.
@export_range(15.0, 1440.0, 5.0) var range_degrees := 270.0
## 0 = smooth. >0 = snap to this many detents (e.g. 10 = eleven positions).
@export_range(0, 64, 1) var snap_steps := 0

var _zero_basis := Basis.IDENTITY
var _prev_quat := Quaternion.IDENTITY
var _accum_degrees := 0.0
var _grab_value := 0.0


func _capture_rest() -> void:
	var moved := target()
	if moved:
		_zero_basis = moved.transform.basis * Basis(_axis(), -deg_to_rad(default_value * range_degrees))


func _apply_value() -> void:
	var moved := target()
	if moved:
		moved.transform.basis = _zero_basis * Basis(_axis(), deg_to_rad(value * range_degrees))


func _on_grab() -> void:
	_prev_quat = _hand_quat()
	_accum_degrees = 0.0
	_grab_value = value


func _on_update(_hand: Vector3) -> void:
	if range_degrees < 0.001:
		return
	var cur := _hand_quat()
	# The hand's rotation SINCE last frame, decomposed to just the part around
	# the spin axis (swing-twist) - so off-axis wrist motion is ignored and the
	# turn is symmetric regardless of how the knob is held. Small per-frame
	# deltas accumulate, so the knob can turn past 180 deg across a grab.
	var delta := cur * _prev_quat.inverse()
	_prev_quat = cur
	_accum_degrees += rad_to_deg(_twist_angle(delta, _axis_world()))
	var new_value := _grab_value + _accum_degrees / range_degrees
	if snap_steps > 0:
		new_value = roundf(clampf(new_value, 0.0, 1.0) * snap_steps) / float(snap_steps)
	set_value(new_value)


func _axis() -> Vector3:
	var axis := spin_axis if spin_axis.length_squared() > 1e-8 else Vector3.UP
	return -axis if invert else axis


func _axis_world() -> Vector3:
	return (target().global_transform.basis * _axis()).normalized()


## The grabbing hand's orientation (reel-safe: rotation isn't touched by the
## ray's distance manipulation).
func _hand_quat() -> Quaternion:
	if _grabber and _grabber.has_method("get_attach_pose"):
		return (_grabber.get_attach_pose() as Transform3D).basis.orthonormalized().get_rotation_quaternion()
	if _grabber is Node3D:
		return _grabber.global_basis.orthonormalized().get_rotation_quaternion()
	return Quaternion.IDENTITY


## Signed rotation of `q` around `axis` (swing-twist decomposition). For the
## small per-frame deltas we feed it, this is the exact twist component.
func _twist_angle(q: Quaternion, axis: Vector3) -> float:
	var w := q.w
	var projected := Vector3(q.x, q.y, q.z).dot(axis)
	if w < 0.0:  # take the shortest arc
		w = -w
		projected = -projected
	return 2.0 * atan2(projected, w)
