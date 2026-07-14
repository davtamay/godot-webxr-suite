class_name XRHandFeatureExtractor
extends RefCounted

## Deterministic shared feature extraction. Distances are normalized by palm
## width so authored thresholds transfer across users and runtimes.

const MIN_PALM_WIDTH := 0.025

const FINGER_CHAINS := [
    [XRHandTracker.HAND_JOINT_THUMB_METACARPAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_THUMB_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_THUMB_TIP],
    [XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP],
    [XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_MIDDLE_FINGER_TIP],
    [XRHandTracker.HAND_JOINT_RING_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_RING_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_RING_FINGER_TIP],
    [XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_PROXIMAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_INTERMEDIATE, XRHandTracker.HAND_JOINT_PINKY_FINGER_PHALANX_DISTAL, XRHandTracker.HAND_JOINT_PINKY_FINGER_TIP],
]

func extract(frame: XRHandFrame, previous: XRHandFrame = null, target: XRHandFeatures = null) -> XRHandFeatures:
    var output := target if target != null else XRHandFeatures.new()
    output.reset()
    output.hand = frame.hand
    output.timestamp_usec = frame.timestamp_usec
    output.tracking_quality = float(frame.valid_joint_count) / float(XRHandFrame.JOINT_COUNT)
    if not frame.tracking_valid:
        return output

    var index_base := XRHandTracker.HAND_JOINT_INDEX_FINGER_METACARPAL
    var pinky_base := XRHandTracker.HAND_JOINT_PINKY_FINGER_METACARPAL
    var middle_base := XRHandTracker.HAND_JOINT_MIDDLE_FINGER_METACARPAL
    var wrist := XRHandTracker.HAND_JOINT_WRIST
    if not _has_all(frame, [index_base, pinky_base, middle_base, wrist]):
        return output

    var index_position := frame.joint_position(index_base)
    var pinky_position := frame.joint_position(pinky_base)
    var middle_position := frame.joint_position(middle_base)
    var wrist_position := frame.joint_position(wrist)
    output.palm_width = index_position.distance_to(pinky_position)
    if output.palm_width < MIN_PALM_WIDTH:
        return output

    var x_axis := (index_position - pinky_position).normalized()
    var z_axis := (middle_position - wrist_position).normalized()
    var y_axis := z_axis.cross(x_axis).normalized()
    if y_axis.length_squared() < 0.5:
        return output
    x_axis = y_axis.cross(z_axis).normalized()
    output.palm_transform = Transform3D(Basis(x_axis, y_axis, z_axis).orthonormalized(), (index_position + pinky_position) * 0.5)

    var thumb_tip := XRHandTracker.HAND_JOINT_THUMB_TIP
    var index_tip := XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP
    if _has_all(frame, [thumb_tip, index_tip]):
        var thumb_position := frame.joint_position(thumb_tip)
        var index_tip_position := frame.joint_position(index_tip)
        output.pinch_distance = thumb_position.distance_to(index_tip_position) / output.palm_width
        output.thumb_tip_local = output.to_palm_local(thumb_position) / output.palm_width
        output.index_tip_local = output.to_palm_local(index_tip_position) / output.palm_width

        var thumb_proximal := XRHandTracker.HAND_JOINT_THUMB_PHALANX_PROXIMAL
        if frame.has_joint(thumb_proximal):
            var thumb_direction := thumb_position - frame.joint_position(thumb_proximal)
            if thumb_direction.length_squared() > 0.0000001:
                output.thumb_direction_origin = thumb_direction.normalized()
                output.thumb_direction_local = (output.palm_transform.basis.inverse() * thumb_direction).normalized()

        var index_proximal := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_PROXIMAL
        var index_intermediate := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_INTERMEDIATE
        var index_distal := XRHandTracker.HAND_JOINT_INDEX_FINGER_PHALANX_DISTAL
        if _has_all(frame, [index_proximal, index_intermediate, index_distal, index_tip]):
            var index_surface := _closest_point_on_polyline(thumb_position, [
                frame.joint_position(index_proximal),
                frame.joint_position(index_intermediate),
                frame.joint_position(index_distal),
                index_tip_position,
            ])
            output.thumb_index_side_distance = float(index_surface["distance"]) / output.palm_width
            output.thumb_index_contact_position = float(index_surface["position"])

    for finger in range(FINGER_CHAINS.size()):
        output.finger_curls[finger] = _finger_curl(frame, FINGER_CHAINS[finger])

    if previous != null and previous.tracking_valid and previous.has_joint(middle_base):
        var elapsed := float(frame.timestamp_usec - previous.timestamp_usec) / 1000000.0
        if elapsed > 0.0001:
            output.palm_linear_velocity = (middle_position - previous.joint_position(middle_base)) / elapsed

    output.valid = true
    return output

func _finger_curl(frame: XRHandFrame, chain: Array) -> float:
    if not _has_all(frame, chain):
        return 0.0
    var total_angle := 0.0
    var angle_count := 0
    for index in range(1, chain.size() - 1):
        var previous_direction := frame.joint_position(chain[index]) - frame.joint_position(chain[index - 1])
        var next_direction := frame.joint_position(chain[index + 1]) - frame.joint_position(chain[index])
        if previous_direction.length_squared() > 0.0000001 and next_direction.length_squared() > 0.0000001:
            total_angle += previous_direction.angle_to(next_direction)
            angle_count += 1
    if angle_count == 0:
        return 0.0
    return clampf(total_angle / (float(angle_count) * PI * 0.5), 0.0, 1.0)

func _has_all(frame: XRHandFrame, joints: Array) -> bool:
    for joint in joints:
        if not frame.has_joint(joint):
            return false
    return true

func _closest_point_on_polyline(point: Vector3, points: Array) -> Dictionary:
    var total_length := 0.0
    for index in range(points.size() - 1):
        total_length += (Vector3(points[index + 1]) - Vector3(points[index])).length()
    if total_length <= 0.0001:
        return {"distance": INF, "position": 0.5}

    var best_distance := INF
    var best_path_distance := 0.0
    var path_distance := 0.0
    for index in range(points.size() - 1):
        var start := Vector3(points[index])
        var segment := Vector3(points[index + 1]) - start
        var segment_length := segment.length()
        if segment_length <= 0.0001:
            continue
        var t := clampf((point - start).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
        var distance := point.distance_to(start + segment * t)
        if distance < best_distance:
            best_distance = distance
            best_path_distance = path_distance + segment_length * t
        path_distance += segment_length
    return {
        "distance": best_distance,
        "position": clampf(best_path_distance / total_length, 0.0, 1.0),
    }
