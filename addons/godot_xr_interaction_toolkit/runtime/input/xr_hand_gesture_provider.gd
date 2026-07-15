class_name XRHandGestureProvider
extends RefCounted

## XRHandTracker geometry helpers. Returned transforms are XROrigin3D-local,
## matching XRHandTracker joint data; callers convert to global space.
## Hand ray, Meta/Unity-style: the ORIGIN sits at the pinch point (between the
## index + thumb tips) so the ray emerges from your fingers, but the DIRECTION is
## STABLE (index knuckle -> wrist), so pinching does not swing the aim. Only the
## origin tracks the fingers; for a far target the direction dominates, so it holds.

const XRHandTrackerResolver := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_tracker_resolver.gd")

const RAY_ORIGIN_FORWARD_OFFSET := 0.025
## Downward pitch applied to the stable aim so the ray points where you point,
## not up at the knuckles (Meta/Unity apply a similar tilt). Tune to taste.
const HAND_RAY_PITCH_DOWN_DEGREES := 35.0

static func joint_position_valid(tracker: XRHandTracker, joint: int) -> bool:
    return XRHandTrackerResolver.joint_position_valid(tracker, joint)

static func get_hand_ray_pose(tracker: XRHandTracker) -> Dictionary:
    if tracker == null:
        return {}

    # STABLE aim: the index knuckle (proximal) and wrist hold still when you pinch,
    # so the ray does not swing. But knuckles sit ABOVE the wrist, so wrist->knuckle
    # aims high - pitch it DOWN so it points where you point (Meta/Unity do the same).
    var wrist := XRHandTracker.HAND_JOINT_WRIST
    var palm := XRHandTracker.HAND_JOINT_PALM
    var knuckle := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
    if not joint_position_valid(tracker, knuckle):
        knuckle = XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL
    if not joint_position_valid(tracker, knuckle):
        return {}
    var back := wrist
    if not joint_position_valid(tracker, back):
        back = palm
    if not joint_position_valid(tracker, back):
        return {}

    var knuckle_pos := tracker.get_hand_joint_transform(knuckle).origin
    var fwd := knuckle_pos - tracker.get_hand_joint_transform(back).origin
    if fwd.length_squared() < 0.000001:
        return {}
    fwd = fwd.normalized()

    # Pitch axis = across the knuckles (index -> pinky); it mirrors between hands,
    # so flip the tilt sign by the tracker's handedness.
    var pinky := XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL
    var across := fwd.cross(Vector3.UP)
    if joint_position_valid(tracker, pinky):
        across = tracker.get_hand_joint_transform(pinky).origin - knuckle_pos
    if across.length_squared() < 0.000001:
        across = fwd.cross(Vector3.UP)
    across = across.normalized()
    var pitch := deg_to_rad(HAND_RAY_PITCH_DOWN_DEGREES)
    if tracker.hand == XRPositionalTracker.TRACKER_HAND_RIGHT:
        pitch = -pitch
    var direction := fwd.rotated(across, pitch).normalized()

    # ORIGIN at the pinch point (between index + thumb tips), Meta/Unity-style, so
    # the ray emerges from your fingers; falls back to the knuckle if not tracked.
    var origin_point := knuckle_pos
    var index_tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
    var thumb_tip := XRHandTracker.HAND_JOINT_THUMB_TIP
    if joint_position_valid(tracker, index_tip):
        origin_point = tracker.get_hand_joint_transform(index_tip).origin
        if joint_position_valid(tracker, thumb_tip):
            origin_point = (origin_point + tracker.get_hand_joint_transform(thumb_tip).origin) * 0.5

    return {
        "origin": origin_point + direction * RAY_ORIGIN_FORWARD_OFFSET,
        "direction": direction,
    }

static func basis_from_forward(direction: Vector3) -> Basis:
    var forward := direction.normalized()
    if forward.length_squared() < 0.000001:
        return Basis.IDENTITY

    var up := Vector3.UP
    if absf(forward.dot(up)) > 0.95:
        up = Vector3.FORWARD

    return Basis.looking_at(forward, up)
