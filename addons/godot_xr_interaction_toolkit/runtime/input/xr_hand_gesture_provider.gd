class_name XRHandGestureProvider
extends RefCounted

## XRHandTracker geometry helpers. Returned transforms are XROrigin3D-local,
## matching XRHandTracker joint data; callers convert to global space.
## Ray recipe validated on Quest 3 Browser: cursor = midpoint(thumb tip,
## index tip), falling back to index tip alone if thumb is invalid; direction =
## normalize(cursor - palm), falling back to wrist if palm is invalid; origin =
## cursor nudged forward 2.5 cm.

const XRHandTrackerResolver := preload("res://addons/godot_xr_interaction_toolkit/runtime/input/xr_hand_tracker_resolver.gd")

const RAY_ORIGIN_FORWARD_OFFSET := 0.025

static func joint_position_valid(tracker: XRHandTracker, joint: int) -> bool:
    return XRHandTrackerResolver.joint_position_valid(tracker, joint)

static func get_hand_ray_pose(tracker: XRHandTracker) -> Dictionary:
    if tracker == null:
        return {}

    var wrist := XRHandTracker.HAND_JOINT_WRIST
    var palm := XRHandTracker.HAND_JOINT_PALM
    var index_tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
    var thumb_tip := XRHandTracker.HAND_JOINT_THUMB_TIP
    if not joint_position_valid(tracker, index_tip):
        return {}
    if not joint_position_valid(tracker, palm) and not joint_position_valid(tracker, wrist):
        return {}

    var cursor := tracker.get_hand_joint_transform(index_tip).origin
    if joint_position_valid(tracker, thumb_tip):
        cursor = (tracker.get_hand_joint_transform(thumb_tip).origin + cursor) * 0.5

    var direction_seed := tracker.get_hand_joint_transform(palm).origin
    if not joint_position_valid(tracker, palm):
        direction_seed = tracker.get_hand_joint_transform(wrist).origin

    var direction := cursor - direction_seed
    if direction.length_squared() < 0.000001:
        return {}

    direction = direction.normalized()
    return {
        "origin": cursor + direction * RAY_ORIGIN_FORWARD_OFFSET,
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
