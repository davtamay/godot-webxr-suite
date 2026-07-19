@icon("res://addons/godot_xr_interaction_toolkit/icons/xr_grab_interactable.svg")
class_name XRDial
extends XRConstrainedInteractable

## A dial / rotary knob: grab and turn it around its spin axis to sweep a value
## 0..1 (Unity XRI's Dial). Grab the knob and move your hand around it; optional
## detents snap to steps. Wire value_changed to volume, brightness, etc.

## Spin axis in the knob's LOCAL space (default: its up axis).
@export var spin_axis := Vector3(0.0, 1.0, 0.0)
## Total sweep from value 0 to value 1, in degrees.
@export_range(15.0, 1440.0, 5.0) var range_degrees := 270.0
## 0 = smooth. >0 = snap to this many detents (e.g. 10 = eleven positions).
@export_range(0, 64, 1) var snap_steps := 0

var _zero_basis := Basis.IDENTITY
var _grab_hand_dir := Vector3.ZERO
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
	_grab_hand_dir = _hand_world() - target().global_position
	_grab_value = value


func _on_update(hand: Vector3) -> void:
	if range_degrees < 0.001:
		return
	var delta := _signed_angle_around(_grab_hand_dir, hand - target().global_position, _axis_world())
	var new_value := _grab_value + rad_to_deg(delta) / range_degrees
	if snap_steps > 0:
		new_value = roundf(clampf(new_value, 0.0, 1.0) * snap_steps) / float(snap_steps)
	set_value(new_value)


func _axis() -> Vector3:
	return spin_axis if spin_axis.length_squared() > 1e-8 else Vector3.UP


func _axis_world() -> Vector3:
	return (target().global_transform.basis * _axis()).normalized()
