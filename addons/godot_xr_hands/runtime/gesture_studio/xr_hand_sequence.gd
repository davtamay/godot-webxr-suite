@icon("res://addons/godot_xr_hands/icons/xr_gesture_recognizer.svg")
class_name XRHandSequence
extends Resource

## A MOTION gesture as data: ordered stages over the same agnostic feature
## vocabulary as XRHandGesture, each stage holding conditions and optionally
## a required MOTION (a signed feature delta within a time window). Thumb
## swipes and taps - Meta-style microgestures - are just sequence resources.
##
## Stage dictionary keys (all optional except conditions):
##   "conditions":       {feature: Vector2(target, tolerance)} - must hold
##                       throughout the stage.
##   "motion_feature":   feature whose CHANGE advances the stage.
##   "motion_min_delta": signed delta (from the stage-entry value) that
##                       completes the stage.
##   "max_seconds":      the stage fails (sequence resets) after this long.
## A stage without motion completes the moment its conditions hold.

@export var sequence_name := ""

@export var stages: Array[Dictionary] = []

## Refractory period after firing, so one motion cannot double-trigger.
@export_range(0.0, 2.0, 0.05) var cooldown_seconds := 0.35


func stage_conditions_hold(stage_index: int, features: Dictionary) -> bool:
	if stage_index < 0 or stage_index >= stages.size() or features.is_empty():
		return false
	var conditions: Dictionary = stages[stage_index].get("conditions", {})
	for feature in conditions:
		if not features.has(feature):
			return false
		var target_tolerance: Vector2 = conditions[feature]
		if absf((features[feature] as float) - target_tolerance.x) > target_tolerance.y:
			return false
	return true
