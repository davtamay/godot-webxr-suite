class_name XRThumbMicrogestureRecognizer
extends XRMicrogestureSource

## Clean-room joint recognizer for thumb tap and index-surface swipes. The
## horizontal coordinate follows the curved index finger from its proximal
## joint (0) to fingertip (1), then maps either hand into the canonical,
## wearer-relative microgesture vocabulary.

# Compatibility enum and signals retained for existing scenes. New consumers
# should use XRMicrogestureSource.Gesture and gesture_* signals.
enum Direction { LEFT, RIGHT, UP, DOWN, TAP }
enum Phase { READY, TRACKING, WAITING_FOR_RELEASE }

signal microgesture_candidate(direction: Direction, hand: int, progress: float)
signal microgesture_performed(direction: Direction, hand: int, confidence: float)

@export var gesture_runtime_path: NodePath
@export_enum("Any:-1", "Left:0", "Right:1") var hand := -1
@export_range(0.05, 1.5, 0.01) var contact_threshold := 0.40
@export_range(0.05, 2.0, 0.01) var release_threshold := 0.46
@export_range(0.0, 1.0, 0.01) var minimum_finger_curl := 0.28
@export_range(0.0, 1.0, 0.01) var minimum_index_curl := 0.16
@export_range(0.0, 1.0, 0.01) var start_zone_minimum := 0.12
@export_range(0.0, 1.0, 0.01) var start_zone_maximum := 0.88
@export_range(0.02, 0.8, 0.01) var minimum_index_travel := 0.12
@export_range(0.02, 0.8, 0.01) var confident_commit_travel := 0.22
@export_range(0.0, 0.3, 0.01) var minimum_swipe_duration := 0.03
@export_range(0.05, 1.5, 0.01) var maximum_duration := 0.85
@export_range(0.0, 0.5, 0.01) var minimum_tap_duration := 0.04
@export_range(0.01, 0.5, 0.01) var maximum_tap_travel := 0.09
@export_range(0.0, 2.0, 0.01) var cooldown := 0.18
@export_range(0.0, 1.0, 0.01) var minimum_tracking_quality := 0.36
@export_range(0.0, 1.0, 0.01) var tracking_gate_release := 0.42
@export_range(0.0, 1.0, 0.01) var contact_position_smoothing := 0.48

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
        _reset_state(state)
        return

    var timestamp := features.timestamp_usec
    var delta := 0.0
    if int(state["last_timestamp"]) > 0:
        delta = maxf(float(timestamp - int(state["last_timestamp"])) / 1000000.0, 0.0)
    state["last_timestamp"] = timestamp
    state["cooldown_left"] = maxf(float(state["cooldown_left"]) - delta, 0.0)

    var posture_score := gate_score(features)
    match int(state["phase"]):
        Phase.READY:
            if float(state["cooldown_left"]) <= 0.0 and posture_score >= 0.999 and _can_start(features):
                _start_tracking(state, features)
        Phase.TRACKING:
            state["elapsed"] = float(state["elapsed"]) + delta
            if posture_score < tracking_gate_release or float(state["elapsed"]) > maximum_duration:
                state["phase"] = Phase.WAITING_FOR_RELEASE
                return
            _update_tracking(state, features, p_hand)
            if int(state["phase"]) != Phase.TRACKING:
                return
            if features.thumb_index_side_distance >= release_threshold:
                _finish_contact(state, p_hand)
        Phase.WAITING_FOR_RELEASE:
            if features.thumb_index_side_distance >= release_threshold and float(state["cooldown_left"]) <= 0.0:
                state["phase"] = Phase.READY

func gate_score(features: XRHandFeatures) -> float:
    if features == null or not features.valid:
        return 0.0
    var curl_average := 0.0
    for finger in range(XRHandFeatures.Finger.INDEX, XRHandFeatures.Finger.PINKY + 1):
        curl_average += features.finger_curls[finger]
    curl_average /= 4.0
    var average_score := clampf(curl_average / maxf(minimum_finger_curl, 0.001), 0.0, 1.0)
    var index_score := clampf(
        features.finger_curls[XRHandFeatures.Finger.INDEX] / maxf(minimum_index_curl, 0.001),
        0.0,
        1.0
    )
    return minf(average_score, index_score)

func direction_name(direction: int) -> String:
    return gesture_name(direction)

func reset() -> void:
    for state in _hands.values():
        _reset_state(state)

func _can_start(features: XRHandFeatures) -> bool:
    return features.thumb_index_side_distance <= contact_threshold \
        and features.thumb_index_contact_position >= start_zone_minimum \
        and features.thumb_index_contact_position <= start_zone_maximum

func _start_tracking(state: Dictionary, features: XRHandFeatures) -> void:
    state["phase"] = Phase.TRACKING
    state["elapsed"] = 0.0
    state["start_contact_position"] = features.thumb_index_contact_position
    state["smoothed_contact_position"] = features.thumb_index_contact_position
    state["peak_semantic_delta"] = 0.0

func _update_tracking(state: Dictionary, features: XRHandFeatures, p_hand: int) -> void:
    var smoothed := lerpf(
        float(state["smoothed_contact_position"]),
        features.thumb_index_contact_position,
        contact_position_smoothing
    )
    state["smoothed_contact_position"] = smoothed
    var surface_delta := smoothed - float(state["start_contact_position"])
    # Mirroring produces wearer-relative events: an equivalent physical
    # gesture has the same meaning regardless of which hand performs it.
    var semantic_delta := surface_delta if p_hand == 1 else -surface_delta
    if absf(semantic_delta) > absf(float(state["peak_semantic_delta"])):
        state["peak_semantic_delta"] = semantic_delta
    var peak := float(state["peak_semantic_delta"])
    var progress := clampf(absf(peak) / minimum_index_travel, 0.0, 1.0)
    if progress > 0.05:
        var direction := Gesture.LEFT if peak > 0.0 else Gesture.RIGHT
        gesture_candidate.emit(direction, p_hand, progress)
        microgesture_candidate.emit(direction, p_hand, progress)
    if float(state["elapsed"]) >= minimum_swipe_duration and absf(peak) >= confident_commit_travel:
        _perform_swipe(state, p_hand, peak, true)

func _finish_contact(state: Dictionary, p_hand: int) -> void:
    var peak := float(state["peak_semantic_delta"])
    var travel := absf(peak)
    var elapsed := float(state["elapsed"])
    if travel >= minimum_index_travel:
        _perform_swipe(state, p_hand, peak, false)
        return
    elif elapsed >= minimum_tap_duration and elapsed <= maximum_duration and travel <= maximum_tap_travel:
        var duration_score := 1.0 - clampf(elapsed / maximum_duration, 0.0, 1.0)
        var travel_score := 1.0 - clampf(travel / maximum_tap_travel, 0.0, 1.0)
        var confidence := 0.7 + 0.15 * duration_score + 0.15 * travel_score
        gesture_performed.emit(Gesture.TAP, p_hand, confidence)
        microgesture_performed.emit(Direction.TAP, p_hand, confidence)
        state["cooldown_left"] = cooldown
    state["phase"] = Phase.WAITING_FOR_RELEASE

func _perform_swipe(state: Dictionary, p_hand: int, peak: float, early_commit: bool) -> void:
    var travel := absf(peak)
    var direction := Gesture.LEFT if peak > 0.0 else Gesture.RIGHT
    var travel_score := clampf(travel / maxf(minimum_index_travel * 1.8, 0.001), 0.0, 1.0)
    var time_score := 1.0 - clampf(float(state["elapsed"]) / maximum_duration, 0.0, 1.0)
    var confidence := 0.65 + 0.25 * travel_score + 0.10 * time_score
    if early_commit:
        confidence = maxf(confidence, 0.86)
    gesture_performed.emit(direction, p_hand, confidence)
    microgesture_performed.emit(direction, p_hand, confidence)
    state["cooldown_left"] = cooldown
    state["phase"] = Phase.WAITING_FOR_RELEASE

func _new_state() -> Dictionary:
    return {
        "phase": Phase.READY,
        "elapsed": 0.0,
        "cooldown_left": 0.0,
        "last_timestamp": 0,
        "start_contact_position": 0.5,
        "smoothed_contact_position": 0.5,
        "peak_semantic_delta": 0.0,
    }

func _reset_state(state: Dictionary) -> void:
    state["phase"] = Phase.READY
    state["elapsed"] = 0.0
    state["cooldown_left"] = 0.0
    state["last_timestamp"] = 0
    state["start_contact_position"] = 0.5
    state["smoothed_contact_position"] = 0.5
    state["peak_semantic_delta"] = 0.0
