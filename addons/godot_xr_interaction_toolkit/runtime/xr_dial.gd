@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRDial
extends XRConstrainedInteractable

## A dial / rotary knob: grab it and move your hand in an ORBIT around it to
## sweep a value 0..1 (Unity XRI's Dial). The knob follows your hand's orbit
## around its spin axis 1:1 - the same whether you grabbed it near or with the
## far ray (it tracks the hand, not the reeled ray point). Optional detents
## snap to steps; wire value_changed to volume, brightness, anything.

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

const _MIN_RADIUS := 0.02

var _zero_basis := Basis.IDENTITY
var _prev_dir := Vector3.ZERO
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
	_prev_dir = _orbit_dir()
	_accum_degrees = 0.0
	_grab_value = value


func _on_update(_hand: Vector3) -> void:
	if range_degrees < 0.001:
		return
	var cur := _orbit_dir()
	# Accumulate the angle the hand sweeps around the dial axis this frame. Only
	# when there's enough lever arm for a stable angle (skips the degenerate
	# case of the hand right at the dial centre); per-frame steps let the dial
	# turn past 180 deg across one grab.
	if _prev_dir.length() > _MIN_RADIUS and cur.length() > _MIN_RADIUS:
		_accum_degrees += rad_to_deg(_signed_angle_around(_prev_dir, cur, _axis_world()))
	_prev_dir = cur
	var new_value := _grab_value + _accum_degrees / range_degrees
	if snap_steps > 0:
		new_value = roundf(clampf(new_value, 0.0, 1.0) * snap_steps) / float(snap_steps)
	set_value(new_value)


## The hand's position relative to the dial, in the plane perpendicular to the
## spin axis - i.e. where the hand sits on its orbit around the dial. Uses the
## hand ORIGIN (reel-safe), so far-ray orbiting works the same as near.
func _orbit_dir() -> Vector3:
	var v := _hand_world() - target().global_position
	var n := _axis_world()
	return v - n * v.dot(n)


func _axis() -> Vector3:
	var axis := spin_axis if spin_axis.length_squared() > 1e-8 else Vector3.UP
	return -axis if invert else axis


func _axis_world() -> Vector3:
	return (target().global_transform.basis * _axis()).normalized()
