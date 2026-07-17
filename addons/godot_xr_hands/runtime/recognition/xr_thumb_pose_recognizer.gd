class_name XRThumbPoseRecognizer
extends Node

## Recognizes deliberate thumbs-up/down poses while the four fingers remain
## curled. Direction is gravity-relative in XROrigin space, matching the
## physical meaning of thumbs up/down instead of depending on palm rotation.

enum Pose { UP, DOWN }

signal pose_candidate(pose: Pose, hand: int, progress: float)
signal pose_performed(pose: Pose, hand: int, confidence: float)
signal pose_ended(pose: Pose, hand: int)

@export var gesture_runtime_path: NodePath
@export_enum("Any:-1", "Left:0", "Right:1") var hand := -1
@export_range(0.0, 1.0, 0.01) var minimum_finger_curl := 0.26
@export_range(0.0, 1.0, 0.01) var maximum_thumb_curl := 0.84
@export_range(0.0, 1.0, 0.01) var direction_threshold := 0.28
@export_range(0.02, 1.0, 0.01) var activation_time := 0.06
@export_range(0.0, 0.3, 0.01) var candidate_dropout_grace := 0.12
@export_range(0.0, 1.0, 0.01) var release_direction_threshold := 0.14
@export_range(0.0, 1.0, 0.01) var maintenance_average_curl := 0.26
@export_range(0.0, 1.0, 0.01) var maintenance_finger_curl := 0.20
@export_range(1, 4, 1) var maintenance_curled_fingers := 3
@export_range(0.0, 2.0, 0.01) var cooldown := 0.20
@export_range(0.0, 1.0, 0.01) var minimum_tracking_quality := 0.36
@export_range(0.0, 1.0, 0.01) var direction_smoothing := 0.48

var _runtime: XRGestureRuntime
var _hands := {}

func _ready() -> void:
    _runtime = get_node_or_null(gesture_runtime_path) as XRGestureRuntime
    if _runtime != null:
        _runtime.hand_features_updated.connect(process_features)

func process_features(p_hand: int, features: XRHandFeatures) -> void:
    if hand >= 0 and p_hand != hand:
        return
    if not _hands.has(p_hand):
        _hands[p_hand] = _new_state()  # lazy: .get()'s default arg allocated every call
    var state: Dictionary = _hands[p_hand]
    if features == null or not features.valid or features.tracking_quality < minimum_tracking_quality:
        _end_active_pose(state, p_hand)
        _reset_state(state)
        return

    var timestamp := features.timestamp_usec
    var delta := 0.0
    if int(state["last_timestamp"]) > 0:
        delta = maxf(float(timestamp - int(state["last_timestamp"])) / 1000000.0, 0.0)
    state["last_timestamp"] = timestamp
    state["cooldown_left"] = maxf(float(state["cooldown_left"]) - delta, 0.0)

    var raw_direction := features.thumb_direction_origin
    var smoothed_direction: Vector3 = Vector3(state["smoothed_direction"])
    if smoothed_direction.is_zero_approx():
        smoothed_direction = raw_direction
    else:
        smoothed_direction = smoothed_direction.lerp(raw_direction, direction_smoothing)
    state["smoothed_direction"] = smoothed_direction
    var result := _evaluate_with_direction(features, smoothed_direction)
    if int(state["active_pose"]) >= 0:
        if _maintains_active_pose(features, smoothed_direction, int(state["active_pose"])):
            return
        _end_active_pose(state, p_hand)
    if not bool(state["armed"]):
        if float(state["cooldown_left"]) > 0.0:
            return
        var returned_to_neutral := result.is_empty() or absf(smoothed_direction.y) <= release_direction_threshold
        var changed_pose := not result.is_empty() and int(result["pose"]) != int(state["last_pose"])
        if not returned_to_neutral and not changed_pose:
            return
        state["armed"] = true
        if returned_to_neutral:
            return
    if result.is_empty():
        if int(state["candidate"]) >= 0 and float(state["candidate_dropout_left"]) > 0.0:
            state["candidate_dropout_left"] = maxf(float(state["candidate_dropout_left"]) - delta, 0.0)
            var held_progress := clampf(float(state["elapsed"]) / activation_time, 0.0, 1.0)
            pose_candidate.emit(int(state["candidate"]), p_hand, held_progress)
            return
        state["candidate"] = -1
        state["elapsed"] = 0.0
        state["candidate_dropout_left"] = 0.0
        return

    var pose := int(result["pose"])
    if int(state["candidate"]) != pose:
        state["candidate"] = pose
        state["elapsed"] = 0.0
    else:
        state["elapsed"] = float(state["elapsed"]) + delta
    state["candidate_dropout_left"] = candidate_dropout_grace
    var progress := clampf(float(state["elapsed"]) / activation_time, 0.0, 1.0)
    pose_candidate.emit(pose, p_hand, progress)
    if progress >= 1.0:
        pose_performed.emit(pose, p_hand, float(result["confidence"]))
        state["active_pose"] = pose
        state["armed"] = false
        state["last_pose"] = pose
        state["candidate"] = -1
        state["candidate_dropout_left"] = 0.0
        state["elapsed"] = 0.0
        state["cooldown_left"] = cooldown

func evaluate(features: XRHandFeatures) -> Dictionary:
    if features == null:
        return {}
    return _evaluate_with_direction(features, features.thumb_direction_origin)

func _evaluate_with_direction(features: XRHandFeatures, thumb_direction: Vector3) -> Dictionary:
    if features == null or not features.valid:
        return {}
    var curl_average := 0.0
    for finger in range(XRHandFeatures.Finger.INDEX, XRHandFeatures.Finger.PINKY + 1):
        curl_average += features.finger_curls[finger]
    curl_average /= 4.0
    var curl_score := clampf(curl_average / maxf(minimum_finger_curl, 0.001), 0.0, 1.0)
    var thumb_score := clampf(
        (maximum_thumb_curl - features.finger_curls[XRHandFeatures.Finger.THUMB]) / maxf(maximum_thumb_curl, 0.001),
        0.0,
        1.0
    )
    var direction := thumb_direction.y
    if absf(direction) < direction_threshold:
        return {}
    var direction_score := clampf((absf(direction) - direction_threshold) / maxf(1.0 - direction_threshold, 0.001), 0.0, 1.0)
    var confidence := minf(curl_score, minf(thumb_score, direction_score))
    if confidence <= 0.0:
        return {}
    return {
        "pose": Pose.UP if direction > 0.0 else Pose.DOWN,
        "confidence": confidence,
    }

func _maintains_active_pose(features: XRHandFeatures, thumb_direction: Vector3, active_pose: int) -> bool:
    # Once recognized, keep the pose active while its anatomical posture is
    # maintained. World-space hand rotation is then free to aim teleportation
    # without incorrectly releasing the thumbs-up gesture.
    var curl_average := 0.0
    var curled_fingers := 0
    for finger in range(XRHandFeatures.Finger.INDEX, XRHandFeatures.Finger.PINKY + 1):
        var curl := features.finger_curls[finger]
        curl_average += curl
        if curl >= maintenance_finger_curl:
            curled_fingers += 1
    curl_average /= 4.0
    if curl_average < maintenance_average_curl or curled_fingers < maintenance_curled_fingers:
        return false
    if features.finger_curls[XRHandFeatures.Finger.THUMB] > minf(maximum_thumb_curl + 0.10, 1.0):
        return false
    if active_pose == Pose.UP and thumb_direction.y <= -direction_threshold:
        return false
    if active_pose == Pose.DOWN and thumb_direction.y >= direction_threshold:
        return false
    return true

func pose_name(pose: Pose) -> String:
    return Pose.keys()[pose].to_lower()

func reset() -> void:
    for state in _hands.values():
        _reset_state(state)

func _new_state() -> Dictionary:
    return {
        "armed": true,
        "candidate": -1,
        "last_pose": -1,
        "active_pose": -1,
        "elapsed": 0.0,
        "candidate_dropout_left": 0.0,
        "cooldown_left": 0.0,
        "last_timestamp": 0,
        "smoothed_direction": Vector3.ZERO,
    }

func _reset_state(state: Dictionary) -> void:
    state["armed"] = true
    state["candidate"] = -1
    state["last_pose"] = -1
    state["active_pose"] = -1
    state["elapsed"] = 0.0
    state["candidate_dropout_left"] = 0.0
    state["cooldown_left"] = 0.0
    state["last_timestamp"] = 0
    state["smoothed_direction"] = Vector3.ZERO

func _end_active_pose(state: Dictionary, p_hand: int) -> void:
    var active_pose := int(state["active_pose"])
    if active_pose < 0:
        return
    state["active_pose"] = -1
    pose_ended.emit(active_pose, p_hand)
