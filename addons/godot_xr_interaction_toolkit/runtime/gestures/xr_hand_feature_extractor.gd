extends Object
# NOTE: deliberately NO class_name - godot_xr_hands claims XRHandFeatureExtractor
# globally; consumers preload this script (the toolkit's usual pattern).

## The single math home of the gesture system: raw XRHandTracker joints in,
## the NAMED NORMALIZED FEATURE dictionary out (see docs/gesture-authoring-
## design.md). Everything downstream - recognizer, recorder, debug HUD -
## consumes only this vocabulary, never joints, so gestures stay agnostic to
## the runtime (WebXR / OpenXR / future) that produced the hand.
##
## Palm orientation is computed GEOMETRICALLY (palm->index x palm->ring,
## chirality-corrected per hand), not from any runtime's joint axis
## conventions - the same gesture resource matches on every platform and on
## both hands.

const FINGERS := {
	"thumb": [XRHandTracker.HAND_JOINT_THUMB_METACARPAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_THUMB_TIP],
	"index": [XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
	"middle": [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP],
	"ring": [XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP],
	"pinky": [XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
}
const SPREAD_PAIRS := [["index", "middle"], ["middle", "ring"], ["ring", "pinky"]]

## Curl: total inter-segment bend mapped 0 (straight) .. 1 (fist).
const _CURL_MAX_RADIANS := 3.6
const _THUMB_CURL_MAX_RADIANS := 1.7
## Pinch: tip-to-thumb-tip distance mapped 1 (touching) .. 0 (far).
const _PINCH_NEAR := 0.02
const _PINCH_FAR := 0.09
## Spread: neighbour angle mapped 0 (together) .. 1 (wide).
const _SPREAD_MAX_RADIANS := 0.55


## Extract the full feature dictionary for a tracked hand. `hand` is 0 = left,
## 1 = right (chirality for the palm normal). `head` (optional camera/head
## global transform) enables the palm_toward_head feature. Origin transform
## maps tracker-local joints into world space for the world-up feature; pass
## the XROrigin3D global transform (or IDENTITY - palm_up then reads
## tracker-local up, fine while the origin is unrotated).
static func extract(tracker: XRHandTracker, hand: int, origin: Transform3D = Transform3D.IDENTITY, head: Variant = null) -> Dictionary:
	var features := {}
	if tracker == null or not tracker.has_tracking_data:
		return features

	# Per-finger curls.
	for finger in FINGERS:
		var joints: Array = FINGERS[finger]
		var total := 0.0
		var previous_direction := Vector3.ZERO
		for i in range(joints.size() - 1):
			var a := tracker.get_hand_joint_transform(joints[i]).origin
			var b := tracker.get_hand_joint_transform(joints[i + 1]).origin
			var direction := (b - a)
			if direction.length_squared() < 0.000001:
				continue
			direction = direction.normalized()
			if previous_direction != Vector3.ZERO:
				total += previous_direction.angle_to(direction)
			previous_direction = direction
		var max_radians := _THUMB_CURL_MAX_RADIANS if finger == "thumb" else _CURL_MAX_RADIANS
		features["curl_%s" % finger] = clampf(total / max_radians, 0.0, 1.0)

	# Pinches (vs the thumb tip).
	var thumb_tip := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_THUMB_TIP).origin
	for finger in FINGERS:
		if finger == "thumb":
			continue
		var tip: Vector3 = tracker.get_hand_joint_transform(FINGERS[finger][-1]).origin
		var distance := tip.distance_to(thumb_tip)
		features["pinch_%s" % finger] = clampf(1.0 - (distance - _PINCH_NEAR) / (_PINCH_FAR - _PINCH_NEAR), 0.0, 1.0)

	# Neighbour spreads (angle between proximal segment directions).
	for pair in SPREAD_PAIRS:
		var direction_a := _segment_direction(tracker, FINGERS[pair[0]][1], FINGERS[pair[0]][-2])
		var direction_b := _segment_direction(tracker, FINGERS[pair[1]][1], FINGERS[pair[1]][-2])
		var spread := 0.0
		if direction_a != Vector3.ZERO and direction_b != Vector3.ZERO:
			spread = clampf(direction_a.angle_to(direction_b) / _SPREAD_MAX_RADIANS, 0.0, 1.0)
		features["spread_%s_%s" % [pair[0], pair[1]]] = spread

	# Palm normal, geometric + chirality-corrected: the same physical pose
	# yields the same values on both hands and every runtime.
	var palm := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_PALM).origin
	var to_index := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL).origin - palm
	var to_ring := tracker.get_hand_joint_transform(XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL).origin - palm
	var palm_normal := to_index.cross(to_ring)
	if hand == 1:
		palm_normal = -palm_normal
	if palm_normal.length_squared() > 0.000001:
		palm_normal = (origin.basis * palm_normal).normalized()
		features["palm_up"] = palm_normal.dot(Vector3.UP)
		if head is Transform3D:
			var to_head := ((head as Transform3D).origin - (origin * palm)).normalized()
			features["palm_toward_head"] = palm_normal.dot(to_head)
	return features


static func _segment_direction(tracker: XRHandTracker, from_joint: int, to_joint: int) -> Vector3:
	var a := tracker.get_hand_joint_transform(from_joint).origin
	var b := tracker.get_hand_joint_transform(to_joint).origin
	var direction := b - a
	return direction.normalized() if direction.length_squared() > 0.000001 else Vector3.ZERO
