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
## Total sweep from value 0 to value 1, in degrees.
@export_range(15.0, 1440.0, 5.0) var range_degrees := 270.0
## 0 = smooth. >0 = snap to this many detents (e.g. 10 = eleven positions).
@export_range(0, 64, 1) var snap_steps := 0

var _zero_basis := Basis.IDENTITY
var _ref_axis := 1          # which hand-basis axis we measure the twist from
var _prev_ref := Vector3.ZERO
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
	# Track the hand-basis axis most perpendicular to the spin axis (its
	# projection carries the cleanest twist signal). That choice is invariant
	# under twisting, so it stays valid for the whole grab.
	_ref_axis = _best_ref_axis()
	_prev_ref = _hand_ref()
	_accum_degrees = 0.0
	_grab_value = value


func _on_update(_hand: Vector3) -> void:
	if range_degrees < 0.001:
		return
	var cur_ref := _hand_ref()
	# Accumulate per-frame twist (each frame is well under 180 deg, so no wrap
	# glitch) - lets the knob turn past 180 deg across a grab.
	_accum_degrees += rad_to_deg(_signed_angle_around(_prev_ref, cur_ref, _axis_world()))
	_prev_ref = cur_ref
	var new_value := _grab_value + _accum_degrees / range_degrees
	if snap_steps > 0:
		new_value = roundf(clampf(new_value, 0.0, 1.0) * snap_steps) / float(snap_steps)
	set_value(new_value)


func _axis() -> Vector3:
	return spin_axis if spin_axis.length_squared() > 1e-8 else Vector3.UP


func _axis_world() -> Vector3:
	return (target().global_transform.basis * _axis()).normalized()


## The grabbing hand's orientation (reel-safe: rotation isn't touched by the
## ray's distance manipulation).
func _hand_basis() -> Basis:
	if _grabber and _grabber.has_method("get_attach_pose"):
		return (_grabber.get_attach_pose() as Transform3D).basis.orthonormalized()
	return (_grabber as Node3D).global_basis if _grabber is Node3D else Basis.IDENTITY


func _hand_ref() -> Vector3:
	var basis := _hand_basis()
	return basis.x if _ref_axis == 0 else (basis.y if _ref_axis == 1 else basis.z)


func _best_ref_axis() -> int:
	var basis := _hand_basis()
	var n := _axis_world()
	var dx := absf(basis.x.dot(n))
	var dy := absf(basis.y.dot(n))
	var dz := absf(basis.z.dot(n))
	if dx <= dy and dx <= dz:
		return 0
	return 1 if dy <= dz else 2
